"""Focus Mode for niri: make leaving a workspace deliberate, visible and
time-bounded, without ever blocking it outright.

Subcommands:
  daemon          watch niri events, run the timers, raise overdue prompts
  bar             stream JSON for a waybar custom module
  menu            start a session if idle, otherwise offer return / end
  start           prompt for duration / done / next action, then start
  end             end the session explicitly
  return          focus the focus workspace
  guard ACTION..  run `niri msg action ACTION..`, but if that would leave the
                  focus workspace without a detour, ask for one first
  left            prompt after leaving without a detour (spawned by daemon)
  overdue         prompt after a detour has run out (spawned by daemon)
  finished        end-of-session notification (spawned by daemon)

State lives in $XDG_RUNTIME_DIR/focus-mode. Every read-modify-write goes
through update_state() under a lock; prompts hold a separate lock so only one
fuzzel is ever open.
"""

import fcntl
import html
import json
import os
import re
import select
import subprocess
import sys
import time
from contextlib import contextmanager
from pathlib import Path

RUN_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "focus-mode"
STATE = RUN_DIR / "state.json"
LAST = RUN_DIR / "last.json"

FOCUS_NAME = "focus"
DURATION_PRESETS = [25, 50, 15, 90]
DETOUR_PRESETS = [2, 5, 10, 20]
OVERDUE_GRACE = 30  # seconds between detour expiry and the prompt
RENAG = 60  # seconds before re-prompting if the overdue prompt is dismissed
REENTRY_WINDOW = 600  # seconds a finished session's notes are offered again
DETOUR_SETTLE = 2  # seconds a fresh detour survives on the focus workspace


# --- state -----------------------------------------------------------------

def read_json(path):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def write_json(path, data):
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    if data is None:
        path.unlink(missing_ok=True)
        return
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data))
    os.replace(tmp, path)


@contextmanager
def file_lock(name, blocking=True):
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    with open(RUN_DIR / name, "w") as f:
        flags = fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB)
        try:
            fcntl.flock(f, flags)
        except BlockingIOError:
            yield False
            return
        yield True


def update_state(fn):
    """Apply fn(state) -> new state (None clears). Returns the old state."""
    with file_lock("state.lock"):
        old = read_json(STATE)
        new = fn(json.loads(json.dumps(old)) if old else None)
        if new != old:
            write_json(STATE, new)
        return old


def set_detour(minutes):
    now = time.time()

    def fn(s):
        if s:
            ends = now + minutes * 60
            s["detour"] = {
                "set_at": now,
                "ends": ends,
                "nag_at": ends + OVERDUE_GRACE,
            }
        return s

    update_state(fn)


def finish(s):
    """Tidy up after a session has been removed from the state file."""
    write_json(LAST, {
        "ws_id": s["ws_id"],
        "ended_at": time.time(),
        "minutes": s["minutes"],
        "done": s["done"],
        "next": s["next"],
    })
    if s.get("named"):
        action("unset-workspace-name", s["ws_ref"])


# --- niri ------------------------------------------------------------------

def action(*args):
    subprocess.run(["niri", "msg", "action", *args])


def focused_workspace():
    out = subprocess.run(
        ["niri", "msg", "--json", "workspaces"],
        capture_output=True, text=True, check=True,
    ).stdout
    workspaces = json.loads(out)
    focused = next(w for w in workspaces if w["is_focused"])
    return focused, workspaces


def on_focus_workspace(s):
    return focused_workspace()[0]["id"] == s["ws_id"]


def return_to_focus(s):
    action("focus-workspace", s["ws_ref"])


# --- prompts ---------------------------------------------------------------

def fuzzel(prompt, options=None, search=None, mesg=None):
    """Return the chosen/typed text, or None if dismissed."""
    cmd = ["fuzzel", "--dmenu", "--no-sort", "--width", "50"]
    if options:
        cmd += ["--prompt", prompt, "--lines", str(len(options))]
    else:
        cmd += ["--prompt-only", prompt]
    if search:
        cmd += ["--search", search]
    if mesg:
        cmd += ["--mesg", mesg]
    r = subprocess.run(
        cmd, input="\n".join(options or []), capture_output=True, text=True,
    )
    return r.stdout.strip() if r.returncode == 0 else None


def minutes_in(text):
    m = re.search(r"\d+", text or "")
    return int(m.group()) if m and int(m.group()) > 0 else None


def mmss(seconds):
    seconds = max(0, int(seconds))
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02}:{s:02}" if h else f"{m:02}:{s:02}"


def session_mesg(s):
    lines = [f"Focus: {mmss(s['ends'] - time.time())} left"]
    if s["done"]:
        lines.append(f"Done looks like: {s['done']}")
    if s["next"]:
        lines.append(f"Next action: {s['next']}")
    return "\n".join(lines)


def detour_prompt(s, first, prompt, verb="Detour"):
    """Offer `first` plus detour presets. Returns minutes, or None for
    `first`/dismissed (callers distinguish via the second value)."""
    options = [first] + [f"{verb} {m} min" for m in DETOUR_PRESETS]
    choice = fuzzel(prompt, options, mesg=session_mesg(s))
    return minutes_in(choice), choice is None


# --- subcommands -----------------------------------------------------------

def cmd_guard(args):
    s = read_json(STATE)
    if s and not s.get("detour") and on_focus_workspace(s):
        with file_lock("prompt.lock", blocking=False) as ok:
            # Another prompt is open (e.g. repeated wheel ticks): do nothing.
            if not ok:
                return
            minutes, _ = detour_prompt(
                s, "↩ Stay focused", "Leave focus? ")
            if minutes is None:
                return
            set_detour(minutes)
    action(*args)


def cmd_left():
    with file_lock("prompt.lock", blocking=False) as ok:
        if not ok:
            return
        s = read_json(STATE)
        if not s or s.get("detour") or on_focus_workspace(s):
            return
        minutes, _ = detour_prompt(
            s, "↩ Return to focus", "Left focus workspace: ")
        if minutes is None:
            return_to_focus(s)
        else:
            set_detour(minutes)


def cmd_overdue():
    with file_lock("prompt.lock", blocking=False) as ok:
        if not ok:
            return
        s = read_json(STATE)
        if not s or not s.get("detour") or on_focus_workspace(s):
            return
        over = mmss(time.time() - s["detour"]["ends"])
        minutes, dismissed = detour_prompt(
            s, "↩ Return to focus", f"Detour over by {over}: ",
            verb="Another")
        if minutes is not None:
            set_detour(minutes)
        elif not dismissed:
            return_to_focus(s)
        # Dismissed: the daemon asks again after RENAG seconds.


def start_flow():
    ws, workspaces = focused_workspace()
    last = read_json(LAST) or {}
    recent = (
        last.get("ws_id") == ws["id"]
        and time.time() - last.get("ended_at", 0) <= REENTRY_WINDOW
    )
    presets = list(DURATION_PRESETS)
    if last.get("minutes") in presets:
        presets.remove(last["minutes"])
    if last.get("minutes"):
        presets.insert(0, last["minutes"])

    minutes = minutes_in(fuzzel(
        "Focus minutes: ", [f"{m} min" for m in presets],
        mesg="Type any number of minutes, or pick one"))
    if not minutes:
        return
    mesg = "Continuing the previous session here" if recent else None
    # Escape on the optional fields just leaves them blank.
    done = fuzzel(
        "Done looks like: ", search=recent and last.get("done"), mesg=mesg,
    ) or ""
    nxt = fuzzel(
        "Very next action: ", search=recent and last.get("next"), mesg=mesg,
    ) or ""

    # Name the workspace so niri keeps it even if empty, and so we can
    # return to it by name from any output.
    # A leftover FOCUS_NAME (e.g. after a crash) is ours, not the user's.
    ref, named = ws["name"], ws["name"] == FOCUS_NAME
    if not ref:
        if any(w["name"] == FOCUS_NAME for w in workspaces):
            action("unset-workspace-name", FOCUS_NAME)
        action("set-workspace-name", "--workspace", str(ws["idx"]),
               FOCUS_NAME)
        ref, named = FOCUS_NAME, True

    now = time.time()
    update_state(lambda _: {
        "ws_id": ws["id"],
        "ws_ref": ref,
        "named": named,
        "started": now,
        "ends": now + minutes * 60,
        "minutes": minutes,
        "done": done,
        "next": nxt,
        "detour": None,
    })


def cmd_start():
    with file_lock("prompt.lock", blocking=False) as ok:
        if ok:
            if read_json(STATE):
                menu_flow()
            else:
                start_flow()


def menu_flow():
    s = read_json(STATE)
    if not s:
        return start_flow()
    options = ["Keep going", "End focus session"]
    if not on_focus_workspace(s):
        options.insert(0, "↩ Return to focus")
    choice = fuzzel("Focus: ", options, mesg=session_mesg(s))
    if choice == "End focus session":
        cmd_end()
    elif choice == "↩ Return to focus":
        return_to_focus(s)


def cmd_menu():
    with file_lock("prompt.lock", blocking=False) as ok:
        if ok:
            menu_flow()


def cmd_end():
    s = update_state(lambda _: None)
    if s:
        finish(s)


def cmd_return():
    s = read_json(STATE)
    if s:
        return_to_focus(s)


def cmd_finished():
    last = read_json(LAST) or {}
    body = f"{last.get('minutes', '?')} minutes done."
    if last.get("done"):
        body += f"\nDone looked like: {last['done']}"
    r = subprocess.run(
        ["notify-send", "-a", "focus-mode", "-A", "default=Start another",
         "Focus session complete", body],
        capture_output=True, text=True,
    )
    if r.stdout.strip() == "default":
        cmd_start()


def bar_output(s, now):
    if not s:
        return {"text": "○ focus", "class": "idle",
                "tooltip": "Start a focus session"}
    tip = [f"Focus ends {time.strftime('%H:%M', time.localtime(s['ends']))}"]
    if s["done"]:
        tip.append(f"Done looks like: {s['done']}")
    if s["next"]:
        tip.append(f"Next action: {s['next']}")
    left = mmss(s["ends"] - now)
    d = s.get("detour")
    if not d:
        text, cls = f"● FOCUS {left}", "focus"
        if s["next"]:
            nxt = s["next"]
            text += f" › {nxt[:40] + '…' if len(nxt) > 40 else nxt}"
    elif now < d["ends"]:
        text, cls = f"◐ DETOUR {mmss(d['ends'] - now)} · focus {left}", \
            "detour"
    else:
        text, cls = f"⚠ OVERDUE +{mmss(now - d['ends'])} · focus {left}", \
            "overdue"
    return {"text": html.escape(text), "class": cls,
            "tooltip": html.escape("\n".join(tip))}


def cmd_bar():
    while True:
        print(json.dumps(bar_output(read_json(STATE), time.time())),
              flush=True)
        time.sleep(1 - time.time() % 1)


def cmd_daemon():
    me = os.path.abspath(sys.argv[0])
    proc = subprocess.Popen(
        ["niri", "msg", "--json", "event-stream"],
        stdout=subprocess.PIPE, text=True, bufsize=1,
    )
    focused = None
    prompt = None  # at most one prompt child at a time
    notifiers = []

    def tick():
        nonlocal prompt
        now = time.time()
        todo = []

        def fn(s):
            if not s:
                return s
            if now >= s["ends"]:
                todo.append(("finished", s))
                return None
            d = s.get("detour")
            if focused is None:
                return s
            if focused == s["ws_id"]:
                # Back on the focus workspace: any detour is over. A detour
                # set moments ago by `guard` hasn't switched away yet.
                if d and now - d["set_at"] > DETOUR_SETTLE:
                    s["detour"] = None
            elif d is None:
                todo.append(("left", s))
            elif now >= d["nag_at"] and prompt is None:
                d["nag_at"] = now + RENAG
                todo.append(("overdue", s))
            return s

        update_state(fn)
        for kind, s in todo:
            if kind == "finished":
                finish(s)
                notifiers.append(subprocess.Popen([me, "finished"]))
            elif prompt is None:
                prompt = subprocess.Popen([me, kind])

    try:
        while True:
            ready, _, _ = select.select([proc.stdout], [], [], 1.0)
            if ready:
                line = proc.stdout.readline()
                if not line:
                    raise RuntimeError("niri event stream closed")
                try:
                    ((kind, payload),) = json.loads(line).items()
                except (json.JSONDecodeError, ValueError):
                    continue
                if kind == "WorkspacesChanged":
                    for w in payload["workspaces"]:
                        if w["is_focused"]:
                            focused = w["id"]
                elif kind == "WorkspaceActivated" and payload["focused"]:
                    focused = payload["id"]
            if prompt is not None and prompt.poll() is not None:
                prompt = None
            notifiers[:] = [n for n in notifiers if n.poll() is None]
            tick()
    finally:
        proc.terminate()


def main():
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    commands = {
        "daemon": cmd_daemon, "bar": cmd_bar, "menu": cmd_menu,
        "start": cmd_start, "end": cmd_end, "return": cmd_return,
        "left": cmd_left, "overdue": cmd_overdue, "finished": cmd_finished,
    }
    if cmd == "guard" and args:
        cmd_guard(args)
    elif cmd in commands and not args:
        commands[cmd]()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
