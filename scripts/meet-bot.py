#!/usr/bin/env python3
"""Join a Google Meet as a guest and write a live transcript, one line per turn.

Meet sends remote audio as a few virtual streams that carry whoever is loudest,
and tags every packet with the speaker's CSRC, which is fixed for as long as
they are in the call. So rather than guess speakers from voices, this wraps
RTCPeerConnection in the page, taps each incoming audio track at 16kHz, and
splits the audio by CSRC. Each speaker gets their own connection to
asr-stream-server.py for the whole call, keeping the encoder's context across
their turns.

The host has to admit the bot. Ctrl-C leaves the call and finishes the file.
"""

import argparse
import atexit
import base64
import datetime
import json
import math
import os
import pathlib
import random
import re
import socket
import subprocess
import sys
import threading
import time
import wave

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import sync_playwright
from playwright_stealth import Stealth

RATE = 16000
# A speaker's turn ends after this long without a fresh packet from them.
TURN_GAP = 1.2
# Silence sent when a turn ends. The encoder only emits a chunk once it has
# the lookahead behind it, so without this a turn's last words would wait for
# the speaker's next turn.
TAIL = bytes(2 * int(0.8 * RATE))
# How long after a turn ends before its line is written, so the words the
# tail flushed out have come back.
SETTLE = 1.5

# Runs before any of Meet's scripts. Remote audio reaches the page only through
# RTCPeerConnection's track event, so this is the one place to catch it.
TAP_JS = r"""
(() => {
  const Original = window.RTCPeerConnection;
  if (!Original) return;
  let ctx = null;
  let tracks = 0;
  const keep = [];

  function tap(receiver, track) {
    // The context resamples the track to 16kHz, which is what the server takes.
    ctx ??= new AudioContext({ sampleRate: 16000 });
    ctx.resume();
    const id = ++tracks;
    const source = ctx.createMediaStreamSource(new MediaStream([track]));
    // ScriptProcessor rather than an AudioWorklet: a worklet has to load a
    // module, which Meet's CSP and Trusted Types get in the way of.
    const proc = ctx.createScriptProcessor(2048, 1, 1);
    const seen = new Map();
    let owner = 0;
    proc.onaudioprocess = (event) => {
      // Meet tags packets with the speaker's CSRC. Anything else (the test
      // page, a one-to-one call) only has the stream's own SSRC.
      let sources = receiver.getContributingSources();
      if (!sources.length) sources = receiver.getSynchronizationSources();
      // A source is speaking now if a new packet arrived since the last
      // callback and it is not near-silence. Comparing timestamps with the
      // last seen ones sidesteps which clock they are on.
      let speaker = 0;
      let loudest = -1;
      for (const s of sources) {
        const moved = seen.get(s.source) !== s.timestamp;
        seen.set(s.source, s.timestamp);
        const level = s.audioLevel ?? 1;
        if (moved && level > 0.001 && level > loudest) {
          speaker = s.source;
          loudest = level;
        }
      }
      const fresh = speaker !== 0;
      if (fresh) owner = speaker;
      if (!owner) return;
      const samples = event.inputBuffer.getChannelData(0);
      const pcm = new Int16Array(samples.length);
      for (let i = 0; i < samples.length; i++) {
        pcm[i] = Math.max(-1, Math.min(1, samples[i])) * 32767;
      }
      const bytes = new Uint8Array(pcm.buffer);
      let binary = "";
      for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
      window.meetBotAudio(id, owner, fresh, btoa(binary));
    };
    source.connect(proc);
    // A ScriptProcessor only runs while connected to the destination. It
    // writes nothing to its output, so this plays silence.
    proc.connect(ctx.destination);
    keep.push(source, proc);
  }

  class Tapped extends Original {
    constructor(...args) {
      super(...args);
      this.addEventListener("track", (event) => {
        if (event.track.kind === "audio") tap(event.receiver, event.track);
      });
    }
  }
  window.RTCPeerConnection = Tapped;
})();
"""


# Real Chrome exposes this and Vexa found the bot's browser did not; the
# stealth evasions leave it alone.
DEVICE_MEMORY_JS = """
if (navigator.deviceMemory === undefined) {
  Object.defineProperty(Navigator.prototype, "deviceMemory", { get: () => 8 });
}
"""


class Turn:
    def __init__(self, speaker):
        self.speaker = speaker
        self.started = datetime.datetime.now()
        self.ended = None
        self.text = ""

    def line(self):
        # The server writes for dictation: it holds a trailing full stop back
        # until more text arrives, so it turns up at the start of the next
        # turn instead, and it lowercases the first word of the stream.
        text = self.text.strip().lstrip(".,?! ").strip()
        if not text:
            return None
        text = text[0].upper() + text[1:]
        if text[-1].isalnum():
            text += "."
        return f"[{self.started:%H:%M:%S}] {self.speaker.label}: {text}"


class Speaker:
    def __init__(self, label, port, transcript):
        self.label = label
        self.transcript = transcript
        self.sock = socket.create_connection(("127.0.0.1", port))
        self.turn = None
        self.last_turn = None
        self.heard = 0.0
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.reader.start()

    def read(self):
        with self.sock.makefile("r", encoding="utf-8") as lines:
            for fragment in lines:
                with self.transcript.lock:
                    turn = self.turn or self.last_turn
                    if turn is not None:
                        turn.text += fragment.rstrip("\n")


class Transcript:
    def __init__(self, path, port):
        self.path = path
        self.port = port
        self.lock = threading.Lock()
        self.speakers = {}
        self.turns = []
        self.file = path.open("a", encoding="utf-8")

    def audio(self, track, source, fresh, pcm):
        now = time.monotonic()
        with self.lock:
            speaker = self.speakers.get(source)
            if speaker is None:
                if not fresh:
                    return
                speaker = Speaker(f"Speaker {len(self.speakers) + 1}", self.port, self)
                self.speakers[source] = speaker
            if fresh:
                speaker.heard = now
                if speaker.turn is None:
                    speaker.turn = Turn(speaker)
                    self.turns.append(speaker.turn)
            elif speaker.turn is None:
                # Pauses inside a turn are kept, so words stay apart; the
                # silence after one is not fed at all.
                return
        speaker.sock.sendall(pcm)

    def tick(self, final=False):
        now = time.monotonic()
        ended = []
        with self.lock:
            for speaker in self.speakers.values():
                turn = speaker.turn
                if turn is not None and (final or now - speaker.heard > TURN_GAP):
                    turn.ended = now
                    speaker.last_turn, speaker.turn = turn, None
                    ended.append(speaker)
        for speaker in ended:
            speaker.sock.sendall(TAIL)
        self.flush(now, final)

    def flush(self, now, final=False):
        with self.lock:
            # Written in the order turns started, so a long turn holds back
            # the interjections made during it until it ends.
            while self.turns:
                turn = self.turns[0]
                if not final and (turn.ended is None or now - turn.ended < SETTLE):
                    break
                self.turns.pop(0)
                line = turn.line()
                if line:
                    print(line, flush=True)
                    self.file.write(line + "\n")
                    self.file.flush()

    def close(self):
        self.tick(final=True)
        for speaker in self.speakers.values():
            speaker.sock.shutdown(socket.SHUT_WR)
        for speaker in self.speakers.values():
            speaker.reader.join(timeout=5)
        self.flush(time.monotonic(), final=True)
        self.file.close()
        # A bot that never got in leaves nothing behind.
        if self.path.stat().st_size == 0:
            self.path.unlink()


def pause(low=0.6, high=1.6):
    time.sleep(random.uniform(low, high))


class CdpInput:
    """Playwright's own input. Meet refuses joins driven this way (Vexa's
    finding, and ours), so this is kept only to compare against."""

    def __init__(self, page):
        self.page = page

    def click(self, locator):
        locator.click()

    def type_into(self, locator, text):
        locator.fill(text)


class Xvfb:
    """A private X screen for the bot, so it has a real pointer and keyboard
    of its own (Vexa's setup) and never touches the desktop's."""

    WIDTH, HEIGHT = 1920, 1080

    def __init__(self):
        read, write = os.pipe()
        self.process = subprocess.Popen(
            ["Xvfb", "-displayfd", str(write), "-nolisten", "tcp",
             "-screen", "0", f"{self.WIDTH}x{self.HEIGHT}x24"],
            pass_fds=(write,), stderr=subprocess.DEVNULL)
        os.close(write)
        with os.fdopen(read) as pipe:
            self.display = f":{pipe.readline().strip()}"
        atexit.register(self.close)

    def env(self):
        env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
        env["DISPLAY"] = self.display
        return env

    def close(self):
        self.process.terminate()


class XInput:
    """Real X input through xdotool on the bot's Xvfb screen. There is no
    window manager there, so Chromium's window sits at 0,0 and a page point is
    a screen point once its toolbar is allowed for."""

    def __init__(self, page, xvfb):
        self.page = page
        self.xvfb = xvfb

    def xdotool(self, *args):
        return subprocess.run(["xdotool", *args], env=self.xvfb.env(), check=True,
                              capture_output=True, text=True).stdout

    def move(self, x, y):
        # A curved, eased path with a little tremor: xdotool alone jumps
        # straight to the target, which is the tell Meet looks for.
        found = dict(pair.split(":") for pair in self.xdotool("getmouselocation").split()[:2])
        x0, y0 = int(found["x"]), int(found["y"])
        distance = math.hypot(x - x0, y - y0)
        steps = max(12, min(60, int(distance / 15)))
        bend = random.uniform(-0.3, 0.3) * distance
        nx, ny = (-(y - y0) / distance, (x - x0) / distance) if distance else (0, 0)
        c1 = (x0 + (x - x0) * 0.3 + nx * bend, y0 + (y - y0) * 0.3 + ny * bend)
        c2 = (x0 + (x - x0) * 0.7 + nx * bend * 0.5, y0 + (y - y0) * 0.7 + ny * bend * 0.5)
        seconds = random.uniform(0.25, 0.4) + distance / 2500
        commands = []
        for i in range(1, steps + 1):
            t = i / steps
            t = t * t * (3 - 2 * t)
            u = 1 - t
            px = u**3 * x0 + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t**3 * x
            py = u**3 * y0 + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t**3 * y
            if i < steps:
                px += random.uniform(-1, 1)
                py += random.uniform(-1, 1)
            commands += ["mousemove", str(round(px)), str(round(py)),
                         "sleep", f"{seconds / steps:.3f}"]
        self.xdotool(*commands)

    def click(self, locator):
        locator.scroll_into_view_if_needed()
        box = locator.bounding_box()
        # The page sits below Chromium's tab strip and toolbar.
        top = self.page.evaluate("outerHeight - innerHeight")
        # Somewhere inside the target rather than its exact centre.
        self.move(box["x"] + box["width"] * random.uniform(0.3, 0.7),
                  top + box["y"] + box["height"] * random.uniform(0.3, 0.7))
        pause(0.1, 0.3)
        self.xdotool("mousedown", "1", "sleep", f"{random.uniform(0.05, 0.12):.3f}",
                     "mouseup", "1")

    def type_into(self, locator, text):
        self.click(locator)
        pause(0.3, 0.7)
        self.xdotool("type", "--delay", str(random.randint(60, 140)), text)


def join(page, name, evidence, act):
    # Meet's refusal, for guests it will not let knock (the meeting or the
    # organiser's domain bars them) and for browsers it takes for bots.
    refused = page.get_by_text(re.compile("can't join this video call|No one can join", re.I))
    button = page.get_by_role(
        "button", name=re.compile(r"^(Ask to join|Join now|Join anyway)$", re.I))
    button.or_(refused).first.wait_for(timeout=30000)
    if refused.first.is_visible():
        sys.exit("Meet refused the bot. Sign it in to a Google account "
                 "(meet-bot --login) or have the host open the meeting to guests.")
    # Arrive muted with the camera off, as a person would: the fake devices
    # Chromium was given are silent and blank, but Meet should not see them live.
    pause(1.5, 3.0)
    for label in ("Turn off microphone", "Turn off camera"):
        toggle = page.locator(f'[aria-label*="{label}"]').first
        if toggle.is_visible():
            act.click(toggle)
            pause()
    box = page.get_by_role("textbox", name=re.compile("name", re.I)).first
    if box.is_visible():
        # Only guests are asked; signed-in profiles join under their own name.
        act.type_into(box, name)
        pause()
    act.click(button.first)
    print("asked to join; waiting to be admitted", file=sys.stderr, flush=True)
    in_call(page).or_(refused).first.wait_for(timeout=15 * 60 * 1000)
    if refused.first.is_visible():
        page.screenshot(path=evidence.with_suffix(".png"))
        evidence.with_suffix(".txt").write_text(page.inner_text("body"))
        sys.exit(f"Meet refused the bot after it asked to join; see {evidence}.png/.txt")
    print("in the call", file=sys.stderr, flush=True)


def profile_directory(user_data):
    """Chromium's sign-in can move the account into a new profile beside the
    one it started in, so follow whichever one Chromium last had open."""
    try:
        state = json.loads((user_data / "Local State").read_text())
        return [f"--profile-directory={state['profile']['last_used']}"]
    except (OSError, ValueError, KeyError):
        return []


def in_call(page):
    return page.get_by_role("button", name=re.compile("Leave call", re.I)).first


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("url", nargs="?", help="Meet link, or any page for testing the tap")
    parser.add_argument("--name", default="Notetaker", help="name shown in the call")
    parser.add_argument("--port", type=int, default=8380, help="asr-stream-server")
    parser.add_argument("--out", type=pathlib.Path,
                        default=pathlib.Path.home() / ".local/share/meet-transcripts")
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--seconds", type=float, help="leave after this long")
    parser.add_argument("--profile", type=pathlib.Path,
                        default=pathlib.Path.home() / ".local/share/meet-bot/profile",
                        help="chromium profile; signed in, the bot joins as that account")
    parser.add_argument("--login", action="store_true",
                        help="open the profile (at url, if given) in a plain browser, "
                             "to sign in or to join by hand")
    parser.add_argument("--no-tap", action="store_true",
                        help="inject nothing into the page, to see whether Meet spots the tap")
    parser.add_argument("--input", choices=["xvfb", "cdp"], default="xvfb",
                        help="xvfb: a hidden X screen with real input through xdotool; "
                             "cdp: a visible window and Playwright's synthetic input")
    parser.add_argument("--no-stealth", action="store_true",
                        help="skip the fingerprint evasions, for comparison")
    args = parser.parse_args()
    if not args.url and not args.login:
        parser.error("a url is needed unless --login")
    if args.headless and args.input == "xvfb":
        parser.error("--input xvfb is already out of sight; --headless goes with --input cdp")

    meet = "meet.google.com" in (args.url or "")
    code = args.url.rstrip("/").rsplit("/", 1)[-1].split("?")[0] if meet else "test"
    path = args.out / f"{datetime.datetime.now():%Y-%m-%d-%H%M}-{code}.txt"

    with sync_playwright() as playwright:
        chromium = playwright.chromium.executable_path
        if args.login:
            # Google refuses sign-in from a browser under automation, so this
            # is the same chromium and profile with nothing attached.
            args.profile.mkdir(parents=True, exist_ok=True)
            subprocess.run([chromium, f"--user-data-dir={args.profile}",
                            *profile_directory(args.profile),
                            args.url or "https://accounts.google.com/"], check=False)
            return
        version = re.search(r"\d+(\.\d+)+", subprocess.run(
            [chromium, "--version"], capture_output=True, text=True).stdout).group()
        # A browser with no microphone or camera at all is unusual; Vexa gives
        # its bots fake ones. These are silent and blank, and join mutes both.
        silence = args.profile.parent / "silence.wav"
        if not silence.exists():
            silence.parent.mkdir(parents=True, exist_ok=True)
            with wave.open(str(silence), "wb") as out:
                out.setnchannels(1)
                out.setsampwidth(2)
                out.setframerate(RATE)
                out.writeframes(bytes(2 * RATE))
        xvfb = Xvfb() if args.input == "xvfb" else None
        screen = ["--ozone-platform=x11", "--window-position=0,0",
                  f"--window-size={Xvfb.WIDTH},{Xvfb.HEIGHT}"] if xvfb else []
        context = playwright.chromium.launch_persistent_context(
            args.profile,
            headless=args.headless,
            # Full chromium even when headless: the stripped headless shell is
            # what Meet most readily refuses.
            channel="chromium",
            # Playwright's own flag for this sets navigator.webdriver, which
            # Meet reads.
            ignore_default_args=["--enable-automation"],
            args=["--autoplay-policy=no-user-gesture-required", "--mute-audio",
                  "--disable-blink-features=AutomationControlled",
                  "--lang=en-US", "--accept-lang=en-US,en",
                  "--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream",
                  f"--use-file-for-fake-audio-capture={silence}",
                  *screen, *profile_directory(args.profile)],
            env=xvfb.env() if xvfb else None,
            # Headless Chromium announces itself in its user agent.
            user_agent=("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                        f"(KHTML, like Gecko) Chrome/{version} Safari/537.36"),
            locale="en-US",
            # The page fills the real window, so page coordinates map onto the
            # screen for OsInput.
            no_viewport=True,
            bypass_csp=True,
        )
        if not args.no_stealth:
            # The puppeteer-extra evasions Vexa runs, ported. Its platform
            # default is Win32, which would contradict the Linux user agent.
            # Xvfb has no GPU, so WebGL would name a software renderer; Vexa
            # reports a plausible Intel one instead. A real display is left be.
            Stealth(navigator_platform_override="Linux x86_64", chrome_runtime=True,
                    webgl_vendor=bool(xvfb),
                    webgl_vendor_override="Google Inc. (Intel)",
                    webgl_renderer_override="ANGLE (Intel, Mesa Intel(R) UHD Graphics 630 "
                                            "(CFL GT2), OpenGL 4.6)",
                    ).apply_stealth_sync(context)
            context.add_init_script(DEVICE_MEMORY_JS)
        args.out.mkdir(parents=True, exist_ok=True)
        transcript = Transcript(path, args.port)
        print(f"transcript: {path}", file=sys.stderr, flush=True)
        if not args.no_tap:
            context.expose_binding(
                "meetBotAudio",
                lambda _source, track, speaker, fresh, data:
                    transcript.audio(track, speaker, fresh, base64.b64decode(data)))
            context.add_init_script(TAP_JS)
        page = context.pages[0] if context.pages else context.new_page()
        act = XInput(page, xvfb) if xvfb else CdpInput(page)
        started = time.monotonic()
        try:
            page.goto(args.url)
            if meet:
                join(page, args.name, path.with_name(path.stem + "-refused"), act)
            missing = 0
            while not page.is_closed():
                page.wait_for_timeout(100)
                transcript.tick()
                if args.seconds and time.monotonic() - started > args.seconds:
                    break
                # Removed, or the call ended: the leave button goes away.
                if meet:
                    missing = 0 if in_call(page).is_visible() else missing + 1
                    if missing > 30:
                        print("no longer in the call", file=sys.stderr, flush=True)
                        break
            if meet and not page.is_closed():
                in_call(page).click(timeout=3000)
        except KeyboardInterrupt:
            pass
        except PlaywrightError as error:
            # Ctrl-C reaches the browser too, so the page can be gone first.
            print(f"browser: {error.message.splitlines()[0]}", file=sys.stderr, flush=True)
        finally:
            # Browser first: audio keeps arriving until it is gone.
            try:
                context.close()
            except PlaywrightError:
                pass
            if xvfb:
                xvfb.close()
            transcript.close()
    print(f"transcript: {path}", file=sys.stderr, flush=True)


if __name__ == "__main__":
    main()
