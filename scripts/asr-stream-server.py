#!/usr/bin/env python3
"""Warm sherpa-onnx streaming ASR server, so dictation types as you talk.

Protocol is raw TCP, one dictation per connection: the client writes 16kHz
mono s16le PCM for as long as the trigger is held and half-closes on release.
Back comes text as it is recognised, one fragment per line, each an append to
what came before - a greedy transducer never revises tokens it has emitted,
so nothing typed ever has to be taken back. push-to-talk.sh types each line.

The model has to be cache-aware (NeMo's nemotron-speech-streaming): the
buffered parakeet-unified streaming export re-encodes its left context every
chunk, which measured 3.5x slower than real time on the T500 even in fp16.
It also needs sherpa-onnx 1.13.5 or later: earlier NeMo streaming greedy search
fed the last token to the decoder twice at every chunk boundary, which dropped
word pieces there ("test this particularly" -> "testly").
"""

import argparse
import os
import pathlib
import socketserver
import sys
import threading
import time

import numpy as np
import sherpa_onnx

RATE = 16000
# Trailing silence fed after release. The encoder only emits a chunk once it
# has the lookahead behind it, so without this the last word is lost.
TAIL_SECONDS = 0.8


def pick(directory, kind):
    """First onnx file for this part of the model. Streaming exports ship one
    precision per directory, so there is nothing to choose between."""
    found = sorted(directory.glob(f"{kind}*.onnx"))
    if not found:
        sys.exit(f"no {kind} onnx in {directory}")
    return str(found[0])


def build(args):
    model = pathlib.Path(args.model)
    return sherpa_onnx.OnlineRecognizer.from_transducer(
        encoder=pick(model, "encoder"),
        decoder=pick(model, "decoder"),
        joiner=pick(model, "joiner"),
        tokens=str(model / "tokens.txt"),
        num_threads=args.threads,
        provider=args.provider,
    )


class Shaper:
    """Turns the recogniser's running transcript into what should be typed.

    The model writes prose - leading capital, closing full stop - but this is
    dictated into shells, prompts and tab names where neither is wanted. The
    capital is easy. The full stop cannot be un-typed once sent, so a trailing
    one is held back until more text proves it was mid-dictation."""

    def __init__(self):
        self.sent = ""

    def shape(self, text):
        text = text.strip()
        return text[:1].lower() + text[1:]

    def fragment(self, text, final):
        text = self.shape(text)
        text = text.rstrip(".") if final else text.rstrip(". ")
        if not text.startswith(self.sent):
            # Never expected from greedy search. Typed text cannot be pulled
            # back, so say so and carry on from wherever the two diverge.
            print(f"revision: {self.sent!r} -> {text!r}", file=sys.stderr, flush=True)
            self.sent = self.sent[:len(os.path.commonprefix([self.sent, text]))]
        new = text[len(self.sent):]
        self.sent = text
        return new


class Handler(socketserver.StreamRequestHandler):
    recognizer = None
    # Connections run concurrently (meet-bot opens one per speaker), but they
    # share one recognizer, so decoding takes turns.
    decoding = threading.Lock()

    def send(self, text):
        if text:
            self.wfile.write(text.replace("\n", " ").encode() + b"\n")
            self.wfile.flush()

    def handle(self):
        stream = self.recognizer.create_stream()
        shaper = Shaper()
        pending = b""
        samples = 0
        busy = 0.0

        def advance(final=False):
            nonlocal busy
            with self.decoding:
                started = time.monotonic()
                while self.recognizer.is_ready(stream):
                    self.recognizer.decode_stream(stream)
                busy += time.monotonic() - started
                text = self.recognizer.get_result(stream)
            self.send(shaper.fragment(text, final))

        # 100ms reads: the model only moves in whole chunks anyway, so this
        # just bounds how long a finished chunk waits to be decoded.
        while chunk := self.rfile.read1(3200):
            pending += chunk
            usable = len(pending) - len(pending) % 2
            audio = np.frombuffer(pending[:usable], dtype="<i2").astype(np.float32) / 32768.0
            pending = pending[usable:]
            samples += len(audio)
            stream.accept_waveform(RATE, audio)
            advance()

        stream.accept_waveform(RATE, np.zeros(int(TAIL_SECONDS * RATE), dtype=np.float32))
        stream.input_finished()
        advance(final=True)

        # Timings only. Everything dictated passes through here, and the
        # journal is the wrong place for it.
        seconds = samples / RATE
        rtf = f"{busy / seconds:.3f}" if seconds else "-"
        print(f"{seconds:.1f}s audio, {busy:.2f}s decoding (rtf {rtf})",
              file=sys.stderr, flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, help="directory of onnx files")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--provider", default="cuda", choices=["cpu", "cuda"])
    parser.add_argument("--threads", type=int, default=4)
    args = parser.parse_args()

    Handler.recognizer = build(args)
    # The first decode pays for CUDA kernel selection. Spend it now rather than
    # on the first thing dictated after a reboot.
    warm = Handler.recognizer.create_stream()
    warm.accept_waveform(RATE, np.zeros(2 * RATE, dtype=np.float32))
    warm.input_finished()
    while Handler.recognizer.is_ready(warm):
        Handler.recognizer.decode_stream(warm)
    print(f"ready on 127.0.0.1:{args.port} ({args.provider})", file=sys.stderr, flush=True)

    socketserver.ThreadingTCPServer.allow_reuse_address = True
    socketserver.ThreadingTCPServer.daemon_threads = True
    socketserver.ThreadingTCPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
