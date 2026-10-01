# Hold the gamepad's L2 to dictate: text is typed as you talk, and release
# finishes the last words.
#
# Driven by a keymasq superkey in overload mode: overload_down fires "start" on
# press, overload_up fires "stop" on release. keymasq delegates exec actions to
# keymasq-session, which runs as the user, so this has the pipewire session.
#
# Typing goes through `keymasq type`, which uses keymasq's own uinput keyboard -
# no wtype or ydotool needed, and it handles unicode.

STATE="${XDG_RUNTIME_DIR:-/tmp}/push-to-talk"
WAV="$STATE/clip.wav"
RAW="$STATE/clip.raw"
TEXT="$STATE/clip.txt"
PIDFILE="$STATE/record.pid"
PIPEFILE="$STATE/pipeline.pid"
# asr-stream-server.py.
PORT="@port@"
# Every accepted clip is kept with the transcript it produced, so a model or
# decoder change can be judged against what was actually said.
EVAL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/push-to-talk/eval"
EVAL_KEEP=500

wait_for() {
  i=0
  while kill -0 "$1" 2>/dev/null && [ "$i" -lt "$2" ]; do
    sleep 0.05
    i=$((i + 1))
  done
}

case "${1:-}" in
  start)
    mkdir -p "$STATE"
    rm -f "$RAW" "$TEXT" "$PIDFILE"
    # pw-record's pid has to come out of the pipeline so stop can signal it,
    # and it is the recorder ending that tells the server the dictation is over:
    # nc -N passes the EOF on as a half-close, and the last words come back.
    {
      pw-record --raw --rate 16000 --channels 1 --format s16 - &
      echo "$!" > "$PIDFILE"
      wait
    } | tee "$RAW" | nc -N 127.0.0.1 "$PORT" | tee "$TEXT" |
      while IFS= read -r fragment; do
        printf '%s' "$fragment" | keymasq type
      done &
    echo "$!" > "$PIPEFILE"
    # Short buzz so you know the mic is live without looking at anything.
    rumble 80 18000 0 >/dev/null 2>&1 &
    ;;

  stop)
    [ -f "$PIPEFILE" ] || exit 0
    pipeline=$(cat "$PIPEFILE")
    rm -f "$PIPEFILE"
    # A quick tap can release before start's pipeline has written the pid.
    i=0
    while [ ! -f "$PIDFILE" ] && [ "$i" -lt 20 ]; do
      sleep 0.05
      i=$((i + 1))
    done
    [ -f "$PIDFILE" ] || exit 0
    kill -INT "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
    # The server is finishing the last chunk and the typist is catching up.
    wait_for "$pipeline" 600
    [ -s "$TEXT" ] || exit 0
    text=$(tr -d '\n' < "$TEXT")

    # 16kHz mono s16 is 32000 bytes/sec, so this skips anything under about
    # half a second - an accidental brush of the trigger rather than speech.
    if [ "$(wc -c < "$RAW")" -gt 16000 ]; then
      sox -t raw -r 16000 -e signed -b 16 -c 1 "$RAW" "$WAV"
      mkdir -p "$EVAL_DIR"
      stamp=$(date +%Y%m%d-%H%M%S)
      cp "$WAV" "$EVAL_DIR/$stamp.wav"
      printf '%s\n' "$text" > "$EVAL_DIR/$stamp.txt"
      # Timestamped names sort chronologically, so a reverse sort is newest-first.
      printf '%s\n' "$EVAL_DIR"/*.wav | sort -r | tail -n "+$(( EVAL_KEEP + 1 ))" |
        while read -r old; do rm -f "$old" "${old%.wav}.txt"; done
    fi

    # Trailing space so consecutive dictations do not run together. Cheaper than
    # tracking whether the target already has text, and a trailing space is
    # harmless everywhere this lands - shells, agent prompts, herdr name fields.
    printf ' ' | keymasq type
    ;;

  *)
    echo "usage: push-to-talk start|stop" >&2
    exit 2
    ;;
esac
