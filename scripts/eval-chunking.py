#!/usr/bin/env python3
"""Score VAD sentence-chunked transcription against whole-clip transcription.

The idea under test: split a long dictation at the silences between sentences,
transcribe each chunk as it completes while the trigger is still held, and at
release only transcribe the final chunk. If that concatenation matches what the
whole clip produces, long prompts stop costing their full length after release.

Each chunk gets whisper's full 30s window, so this is not the audio_ctx
truncation that scripts/eval-transcribe.py scores badly - the audio is short,
the context is not.

Two numbers matter. WER says whether chunking changes the text. "last chunk"
is the latency that would actually be felt on release, as against "whole" for
the current behaviour.

Run under: nix shell nixpkgs#whisper-cpp -c python3 scripts/eval-chunking.py
"""

import argparse
import pathlib
import re
import statistics
import subprocess
import sys
import tempfile
import time
import wave

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from importlib import import_module  # noqa: E402

_eval = import_module("eval-transcribe")
wer, transcribe = _eval.wer, _eval.transcribe

SEGMENT = re.compile(r"^Speech segment \d+: start = ([\d.]+), end = ([\d.]+)$", re.M)


def speech_segments(wav, vad_bin, vad_model):
    """Speech spans in seconds. The tool prints centiseconds."""
    result = subprocess.run([vad_bin, "-vm", str(vad_model), "-f", str(wav)],
                            capture_output=True, text=True)
    return [(float(a) / 100, float(b) / 100)
            for a, b in SEGMENT.findall(result.stdout)]


def chunk_spans(segments, min_gap, max_chunk):
    """Merge speech segments into sentence-sized chunks, splitting only where
    the speaker actually paused. A chunk is capped so it cannot outgrow the
    30s window that makes a single encode cheap."""
    chunks = []
    for start, end in segments:
        if chunks and start - chunks[-1][1] < min_gap and end - chunks[-1][0] <= max_chunk:
            chunks[-1][1] = end
        else:
            chunks.append([start, end])
    return chunks


def extract(wav, start, end, directory, index):
    """Write one chunk out as its own wav."""
    with wave.open(str(wav), "rb") as source:
        rate = source.getframerate()
        source.setpos(int(start * rate))
        frames = source.readframes(int((end - start) * rate))
        path = pathlib.Path(directory) / f"chunk{index}.wav"
        with wave.open(str(path), "wb") as sink:
            sink.setnchannels(source.getnchannels())
            sink.setsampwidth(source.getsampwidth())
            sink.setframerate(rate)
            sink.writeframes(frames)
    return path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=pathlib.Path,
                        default=pathlib.Path.home() / ".local/share/push-to-talk/eval")
    parser.add_argument("--port", default="8378")
    parser.add_argument("--vad-bin", default="whisper-vad-speech-segments")
    parser.add_argument("--vad-model", default=
                        "/nix/store/nasxhy568slvs3np3b1yqf352h4a2xx0-ggml-silero-v5.1.2.bin")
    parser.add_argument("--min-seconds", type=float, default=8.0,
                        help="only score clips at least this long")
    parser.add_argument("--min-gap", type=float, default=0.6,
                        help="silence that counts as a sentence boundary")
    parser.add_argument("--max-chunk", type=float, default=25.0)
    parser.add_argument("--prompt-context", action="store_true",
                        help="feed the previous chunk back as whisper prompt context")
    args = parser.parse_args()

    clips = [c for c in sorted(args.corpus.glob("*.wav"))
             if (c.stat().st_size - 44) / 32000 >= args.min_seconds]
    if not clips:
        sys.exit(f"no clips of at least {args.min_seconds}s in {args.corpus}")

    print(f"{len(clips)} clips of at least {args.min_seconds}s\n")
    print(f"{'clip':>10} {'secs':>6} {'chunks':>7} {'whole':>7} {'last':>7} "
          f"{'total':>7} {'WER':>6}")

    errors, wholes, lasts = [], [], []
    for clip in clips:
        seconds = (clip.stat().st_size - 44) / 32000
        reference, whole_time = transcribe(clip, args.port, None)
        spans = chunk_spans(speech_segments(clip, args.vad_bin, args.vad_model),
                            args.min_gap, args.max_chunk)
        if not spans:
            continue

        texts, times = [], []
        with tempfile.TemporaryDirectory() as directory:
            for index, (start, end) in enumerate(spans):
                piece = extract(clip, start, end, directory, index)
                # Whisper conditions on preceding text, which a chunk otherwise
                # loses. Feeding the last chunk back as the prompt is what a live
                # implementation would do, since it already has that text.
                prompt = " ".join(texts[-1:]) if args.prompt_context else None
                started = time.monotonic()
                text, _ = transcribe(piece, args.port, None, prompt)
                times.append(time.monotonic() - started)
                texts.append(text)

        joined = " ".join(t for t in texts if t)
        rate = wer(reference, joined)
        errors.append(rate)
        wholes.append(whole_time)
        lasts.append(times[-1])
        print(f"{clip.name[9:15]:>10} {seconds:>6.1f} {len(spans):>7} "
              f"{whole_time:>6.2f}s {times[-1]:>6.2f}s {sum(times):>6.2f}s {rate:>5.1%}")

    print(f"\nmean WER {statistics.mean(errors):.1%}  "
          f"exact {sum(1 for e in errors if e == 0)}/{len(errors)}")
    print(f"felt latency on release: {statistics.mean(lasts):.2f}s chunked "
          f"vs {statistics.mean(wholes):.2f}s whole")


if __name__ == "__main__":
    main()
