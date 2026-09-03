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
VAD_MODEL="@vadmodel@"
PORT="@port@"
# Every accepted clip is kept with the transcript it produced. Chunked streaming
# has to be judged against whole-clip output, so the pair is the reference.
EVAL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/push-to-talk/eval"
EVAL_KEEP=500

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

    # whisper's encoder always runs over a padded 30-second window, so a 3-second
    # clip costs as much as a 20-second one - about 1.9s either way. Sizing the
    # audio context to the audio instead cuts that to well under half a second,
    # with output identical to the full context.
    #
    # Size it to the speech rather than the clip: the trigger is always held a
    # beat before and after talking, and the server drops that silence anyway, so
    # charging the encoder for it is waste. The VAD pass costs about 8ms. Segment
    # bounds are printed in centiseconds, so 50 context units per second of speech
    # is speech_cs / 2. The fixed margin matters - too tight a context makes
    # whisper repeat itself instead of stopping.
    speech_cs=0
    while read -r seg_start seg_end; do
      speech_cs=$(( speech_cs + seg_end - seg_start ))
    done < <(whisper-vad-speech-segments -vm "$VAD_MODEL" -f "$WAV" 2>/dev/null |
      sed -n 's/^Speech segment [0-9]*: start = \([0-9]*\)\.[0-9]*, end = \([0-9]*\)\.[0-9]*$/\1 \2/p')

    # A VAD that returned nothing is a failed pass, not proven silence - fall back
    # to the clip length and let the hallucination filter below catch real silence.
    if [ "$speech_cs" -gt 0 ]; then
      ctx=$(( speech_cs / 2 + 150 ))
    else
      ctx=$(( bytes / 640 + 150 ))
    fi
    ctx=$(( (ctx + 63) / 64 * 64 ))
    [ "$ctx" -lt 1500 ] || ctx=0   # 0 is whisper's own default, the full window

    # No one-shot fallback on purpose: a silent slow path would hide the server
    # being down. curl -sS puts the failure in the journal and nothing is typed.
    text=$(curl -sS --max-time 30 "http://127.0.0.1:$PORT/inference" \
      -F file=@"$WAV" -F response_format=text -F audio_ctx="$ctx" || true)
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

    # Keep the pair before typing, so the eval set records what whisper actually
    # produced rather than anything downstream. Newest EVAL_KEEP pairs only.
    mkdir -p "$EVAL_DIR"
    stamp=$(date +%Y%m%d-%H%M%S)
    cp "$WAV" "$EVAL_DIR/$stamp.wav"
    printf '%s\n' "$text" > "$EVAL_DIR/$stamp.txt"
    # Timestamped names sort chronologically, so a reverse sort is newest-first.
    printf '%s\n' "$EVAL_DIR"/*.wav | sort -r | tail -n "+$(( EVAL_KEEP + 1 ))" |
      while read -r old; do rm -f "$old" "${old%.wav}.txt"; done

    printf '%s' "$text" | keymasq type
    ;;

  *)
    echo "usage: push-to-talk start|stop" >&2
    exit 2
    ;;
esac
