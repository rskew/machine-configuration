# Hold the gamepad's L2 to record, release to transcribe and type the result.
#
# Driven by a keymasq superkey in overload mode: overload_down fires "start" on
# press, overload_up fires "stop" on release. keymasq delegates exec actions to
# keymasq-session, which runs as the user, so this has the pipewire session.
#
# Typing goes through `keymasq type`, which uses keymasq's own uinput keyboard -
# no wtype or ydotool needed, and it handles unicode.

STATE="${XDG_RUNTIME_DIR:-/tmp}/push-to-talk"
WAV="$STATE/clip.wav"
PIDFILE="$STATE/record.pid"
MODEL="@model@"

case "${1:-}" in
  start)
    mkdir -p "$STATE"
    rm -f "$WAV"
    # whisper wants 16kHz mono; recording it natively avoids a resample step.
    pw-record --rate 16000 --channels 1 --format s16 "$WAV" &
    echo "$!" > "$PIDFILE"
    # Short buzz so you know the mic is live without looking at anything.
    rumble 80 18000 0 >/dev/null 2>&1 &
    ;;

  stop)
    [ -f "$PIDFILE" ] || exit 0
    pid=$(cat "$PIDFILE")
    rm -f "$PIDFILE"
    # SIGINT rather than SIGTERM: pw-record writes the WAV header on the way
    # out, and a killed recorder leaves a file whisper cannot read.
    kill -INT "$pid" 2>/dev/null || exit 0
    i=0
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 50 ]; do
      sleep 0.05
      i=$((i + 1))
    done

    [ -f "$WAV" ] || exit 0
    # 16kHz mono s16 is 32000 bytes/sec, so this ignores anything under about
    # half a second - an accidental brush of the trigger rather than speech.
    bytes=$(wc -c < "$WAV")
    [ "$bytes" -gt 16000 ] || exit 0

    text=$(whisper-cli -m "$MODEL" -f "$WAV" -nt -np 2>/dev/null || true)
    text=$(printf '%s' "$text" | tr '\n' ' ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    # Whisper writes prose - leading capital, closing full stop - but this is
    # dictated into shells, prompts and tab names where neither is wanted.
    text=$(printf '%s' "$text" | sed 's/[.[:space:]]*$//; s/^\(.\)/\l\1/')
    [ -n "$text" ] || exit 0

    # Fed silence, whisper does not return nothing - it invents a stock phrase
    # from its training data. Typing those into whatever happens to be focused
    # is worse than dropping the odd real utterance, so filter the usual ones.
    case "$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]' | tr -d '.,!?[]')" in
      "" | you | "thank you" | "thanks for watching" | "blank_audio" | bye | "you're welcome")
        exit 0
        ;;
    esac

    printf '%s' "$text" | keymasq type
    ;;

  *)
    echo "usage: push-to-talk start|stop" >&2
    exit 2
    ;;
esac
