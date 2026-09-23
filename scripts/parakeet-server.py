#!/usr/bin/env python3
"""Warm sherpa-onnx ASR server wearing whisper-server's /inference contract.

push-to-talk.sh and scripts/eval-transcribe.py both POST a WAV as multipart
"file" and read plain text back, so answering the same shape makes swapping
engines a port number, and lets the two be scored against each other with
`eval-transcribe.py whisper:8378 parakeet:8379`.

Parakeet 0.6B transcribes better than whisper base.en, but its cost is
proportional to audio length where whisper's fixed 30s window is flat, so it
only becomes the faster engine once the encoder runs on a GPU. --provider cuda
is the reason this file exists; on CPU it measured 3x slower than real time.
"""

import argparse
import io
import pathlib
import sys
import time
import wave
from http.server import BaseHTTPRequestHandler, HTTPServer

import numpy as np
import sherpa_onnx


def pick(directory, kind):
    """Models name their onnx files inconsistently; prefer int8 where both exist."""
    found = sorted(directory.glob(f"*{kind}*.onnx"),
                   key=lambda p: ("int8" not in p.name, len(p.name)))
    if not found:
        sys.exit(f"no {kind} onnx in {directory}")
    return str(found[0])


def build(args):
    model = pathlib.Path(args.model)
    # model_type is given rather than left to auto-detection: that reads
    # "model_type" out of the encoder's onnx metadata, and its table has no
    # entry for NeMo's TDT exports.
    return sherpa_onnx.OfflineRecognizer.from_transducer(
        encoder=pick(model, "encoder"),
        decoder=pick(model, "decoder"),
        joiner=pick(model, "joiner"),
        tokens=str(model / "tokens.txt"),
        model_type=args.model_type,
        num_threads=args.threads,
        provider=args.provider,
    )


def upload(headers, body):
    """The file part of a multipart POST, split by hand rather than through
    email.parser, whose payload round-trip through str is not obviously
    byte-exact for binary. whisper-server's other form fields (audio_ctx,
    prompt, response_format) are whisper-specific, so they are ignored."""
    content_type = headers.get("Content-Type", "")
    if "boundary=" not in content_type:
        raise ValueError("expected a multipart body")
    boundary = content_type.split("boundary=")[1].strip('"').encode()
    for part in body.split(b"--" + boundary):
        head, blank, payload = part.partition(b"\r\n\r\n")
        if blank and b"filename=" in head:
            return payload[:-2]  # the CRLF that terminates the part
    raise ValueError("no file part in the request")


def samples(data):
    """Mono float32 in [-1, 1] plus its rate; sherpa resamples if it has to."""
    with wave.open(io.BytesIO(data), "rb") as f:
        if f.getsampwidth() != 2:
            raise ValueError(f"expected 16-bit PCM, got {8 * f.getsampwidth()}-bit")
        channels, rate = f.getnchannels(), f.getframerate()
        raw = f.readframes(f.getnframes())
    audio = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    return np.ascontiguousarray(audio[::channels]), rate


class Handler(BaseHTTPRequestHandler):
    recognizer = None

    # HTTP/1.1 so that curl's `Expect: 100-continue` - which it sends for any
    # body over 1KB, so every clip - is answered. Under 1.0 it goes unanswered
    # and curl gives up and sends anyway, a second of latency per utterance.
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        if self.path.split("?")[0] != "/inference":
            self.send_error(404, "only /inference")
            return
        try:
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            audio, rate = samples(upload(self.headers, body))
        except Exception as error:
            self.send_error(400, str(error))
            return

        started = time.monotonic()
        stream = self.recognizer.create_stream()
        stream.accept_waveform(rate, audio)
        self.recognizer.decode_stream(stream)
        text = stream.result.text.strip()
        elapsed = time.monotonic() - started

        # Timings only. Everything dictated passes through here, and the
        # journal is the wrong place for it.
        seconds = len(audio) / rate
        rtf = f"{elapsed / seconds:.3f}" if seconds else "-"
        print(f"{seconds:.1f}s audio in {elapsed:.2f}s (rtf {rtf})",
              file=sys.stderr, flush=True)

        payload = (text + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        # One connection per clip. Callers send one at a time and the server is
        # single-threaded, so keep-alive could only ever hold it hostage.
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass  # the line above says the useful part


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, help="directory of onnx files")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--provider", default="cuda", choices=["cpu", "cuda"])
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--model-type", default="nemo_transducer")
    args = parser.parse_args()

    Handler.recognizer = build(args)
    # The first decode pays for CUDA kernel selection. Spend it now rather than
    # on the first thing dictated after a reboot.
    warm = Handler.recognizer.create_stream()
    warm.accept_waveform(16000, np.zeros(16000, dtype=np.float32))
    Handler.recognizer.decode_stream(warm)
    print(f"ready on 127.0.0.1:{args.port} ({args.provider})", file=sys.stderr, flush=True)

    # Single-threaded on purpose: one recognizer, and both callers send one
    # clip at a time, so there is nothing to gain and thread-safety to lose.
    HTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
