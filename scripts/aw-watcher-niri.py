"""ActivityWatch watcher for the niri compositor.

Consumes `niri msg --json event-stream` and pushes heartbeats to aw-server for
two buckets: currently focused window (app + title) and active workspace.
"""

import json
import select
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

AW_HOST = "http://localhost:5600"
HOSTNAME = socket.gethostname()
WINDOW_BUCKET = f"aw-watcher-window-niri_{HOSTNAME}"
WORKSPACE_BUCKET = f"aw-watcher-workspace-niri_{HOSTNAME}"
PULSETIME = 10.0
TICK_SECONDS = 5.0


def http(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"} if data else {}
    req = urllib.request.Request(
        f"{AW_HOST}/api/0{path}", data=data, method=method, headers=headers
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            payload = r.read()
            return json.loads(payload) if payload else None
    except urllib.error.HTTPError as e:
        if e.code == 304:
            return None
        raise


def wait_for_server():
    for _ in range(60):
        try:
            urllib.request.urlopen(f"{AW_HOST}/api/0/info", timeout=2).read()
            return
        except (urllib.error.URLError, ConnectionError):
            time.sleep(1)
    print("aw-server never came up", file=sys.stderr)
    sys.exit(1)


def ensure_bucket(bucket_id, event_type):
    http(
        "POST",
        f"/buckets/{bucket_id}",
        {
            "client": "aw-watcher-niri",
            "type": event_type,
            "hostname": HOSTNAME,
        },
    )


def heartbeat(bucket_id, data):
    http(
        "POST",
        f"/buckets/{bucket_id}/heartbeat?pulsetime={PULSETIME}",
        {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "duration": 0,
            "data": data,
        },
    )


def main():
    wait_for_server()
    ensure_bucket(WINDOW_BUCKET, "currentwindow")
    ensure_bucket(WORKSPACE_BUCKET, "currentworkspace")

    windows = {}
    workspaces = {}
    focused_window_id = None
    focused_workspace_id = None

    proc = subprocess.Popen(
        ["niri", "msg", "--json", "event-stream"],
        stdout=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    try:
        while True:
            ready, _, _ = select.select([proc.stdout], [], [], TICK_SECONDS)
            if ready:
                line = proc.stdout.readline()
                if not line:
                    raise RuntimeError("niri event stream closed")
                try:
                    evt = json.loads(line)
                except json.JSONDecodeError:
                    continue
                ((kind, payload),) = evt.items()

                if kind == "WindowsChanged":
                    windows = {w["id"]: w for w in payload["windows"]}
                    for w in payload["windows"]:
                        if w.get("is_focused"):
                            focused_window_id = w["id"]
                elif kind == "WindowOpenedOrChanged":
                    w = payload["window"]
                    windows[w["id"]] = w
                    if w.get("is_focused"):
                        focused_window_id = w["id"]
                elif kind == "WindowClosed":
                    windows.pop(payload["id"], None)
                    if focused_window_id == payload["id"]:
                        focused_window_id = None
                elif kind == "WindowFocusChanged":
                    focused_window_id = payload.get("id")
                elif kind == "WorkspacesChanged":
                    workspaces = {w["id"]: w for w in payload["workspaces"]}
                    for w in payload["workspaces"]:
                        if w.get("is_focused"):
                            focused_workspace_id = w["id"]
                elif kind == "WorkspaceActivated":
                    if payload.get("focused"):
                        focused_workspace_id = payload["id"]

            if focused_window_id is not None and focused_window_id in windows:
                w = windows[focused_window_id]
                heartbeat(
                    WINDOW_BUCKET,
                    {
                        "app": w.get("app_id") or "unknown",
                        "title": w.get("title") or "",
                    },
                )
            if (
                focused_workspace_id is not None
                and focused_workspace_id in workspaces
            ):
                ws = workspaces[focused_workspace_id]
                label = ws.get("name") or f"workspace-{ws.get('idx')}"
                heartbeat(
                    WORKSPACE_BUCKET,
                    {"workspace": label, "output": ws.get("output") or ""},
                )
    finally:
        proc.terminate()


if __name__ == "__main__":
    main()
