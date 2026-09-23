#!/usr/bin/env python3
"""Score whisper-server variants against the push-to-talk eval corpus.

The corpus is whatever push-to-talk has banked in ~/.local/share/push-to-talk/eval
(a .wav and the .txt it produced). The stored .txt is not the reference: it was
produced by whatever settings were live at the time, so it moves. The first
variant given is the reference and everything else is scored against it.

A variant is LABEL:PORT[:CTX] - a running whisper-server, optionally asked for a
truncated audio context. So this compares models, thread counts and context
sizes with the same command:

  eval-transcribe.py fp16:8378 q5_1:19051 q8_0:19080
  eval-transcribe.py full:8378 ctx512:8378:512 ctx1024:8378:1024
"""

import argparse
import pathlib
import re
import statistics
import subprocess
import sys
import time

WORD = re.compile(r"[a-z0-9']+")


def normalise(text):
    return WORD.findall(text.lower())


def wer(reference, hypothesis):
    """Word error rate: edit distance over words, relative to the reference."""
    ref, hyp = normalise(reference), normalise(hypothesis)
    if not ref:
        return 0.0 if not hyp else 1.0
    # Row-wise Levenshtein; the corpus is short utterances so this is plenty.
    previous = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        current = [i]
        for j, h in enumerate(hyp, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1,
                               previous[j - 1] + (r != h)))
        previous = current
    return previous[-1] / len(ref)


def sized_ctx(wav):
    """Context just large enough for this clip: 50 units per second of 16kHz
    mono s16 audio, plus a margin, rounded up to 64. This is what chunked
    streaming would be able to use if a short chunk needs only a short context."""
    seconds = (wav.stat().st_size - 44) / 32000
    ctx = int(seconds * 50) + 150
    ctx = -(-ctx // 64) * 64
    return ctx if ctx < 1500 else 0


def transcribe(wav, port, ctx, prompt=None):
    """One request to a warm whisper-server. Returns (text, seconds)."""
    form = ["-F", f"file=@{wav}", "-F", "response_format=text"]
    if ctx == "sized":
        ctx = sized_ctx(wav)
    if ctx is not None:
        form += ["-F", f"audio_ctx={ctx}"]
    if prompt:
        form += ["-F", f"prompt={prompt}"]
    start = time.monotonic()
    result = subprocess.run(
        ["curl", "-sS", "--max-time", "120",
         f"http://127.0.0.1:{port}/inference", *form],
        capture_output=True, text=True, check=True,
    )
    return " ".join(result.stdout.split()), time.monotonic() - start


def parse_variant(spec):
    label, port, *rest = spec.split(":")
    if not rest:
        return label, port, None
    return label, port, rest[0] if rest[0] == "sized" else int(rest[0])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("variants", nargs="+", metavar="LABEL:PORT[:CTX]")
    parser.add_argument("--corpus", type=pathlib.Path,
                        default=pathlib.Path.home() / ".local/share/push-to-talk/eval")
    parser.add_argument("--repeats", type=int, default=2,
                        help="requests per clip; the fastest is kept")
    args = parser.parse_args()

    clips = sorted(args.corpus.glob("*.wav"))
    if not clips:
        sys.exit(f"no clips in {args.corpus}")
    variants = [parse_variant(v) for v in args.variants]

    print(f"{len(clips)} clips, reference = {variants[0][0]}\n")
    print(f"{'variant':>10}  {'mean WER':>9}  {'exact':>7}  {'mean s':>7}  worst clip")

    # A hand-corrected <clip>.ref beats any model output as a reference: without
    # one, a variant can only be scored on how far it moves from the first
    # variant, which measures change rather than accuracy. Correct a handful by
    # hand and this starts reporting real word error instead.
    corrected = {c: (c.with_suffix(".ref").read_text().strip())
                 for c in clips if c.with_suffix(".ref").exists()}
    if corrected:
        print(f"({len(corrected)} of {len(clips)} clips have a corrected .ref)")

    references = dict(corrected)
    for label, port, ctx in variants:
        errors, times, worst = [], [], (0.0, "")
        for clip in clips:
            best, text = None, ""
            for _ in range(args.repeats):
                candidate, seconds = transcribe(clip, port, ctx)
                if best is None or seconds < best:
                    best, text = seconds, candidate
            times.append(best)
            if clip not in references:
                references[clip] = text
                continue
            rate = wer(references[clip], text)
            errors.append(rate)
            if rate > worst[0]:
                worst = (rate, f"{clip.name[9:]}: {text[:40]}")
        if errors:
            exact = f"{sum(1 for e in errors if e == 0)}/{len(errors)}"
            print(f"{label:>10}  {statistics.mean(errors):>8.1%}  {exact:>7}  "
                  f"{statistics.mean(times):>6.2f}s  {worst[1]}")
        else:
            print(f"{label:>10}  {'-':>9}  {'-':>7}  "
                  f"{statistics.mean(times):>6.2f}s  (reference)")


if __name__ == "__main__":
    main()
