#!/bin/bash
# Volume notifications for changes made *elsewhere* (another app, a PulseAudio
# client, a phone). The sway keybinds announce themselves through volume.sh and
# touch a marker this watcher suppresses for a second, so a keypress is never
# announced twice.
#
# Event-driven, not polled. pw-dump -m re-dumps the objects whose params
# changed, and a sink volume/mute change is exactly such a change. Only a
# re-dump that carries "volume"/"mute" props becomes a token: measured on the
# Pi, 12 s of active playback emits 61 registry dumps but only 1 carries volume
# props, so the watcher sleeps in read() instead of polling wpctl every 0.5 s.
# pw-dump must be run as "-m -N": passing "-C never" makes it emit nothing.
#
# The producer is a bash read loop, not awk/grep|sed: the Pi ships mawk, which
# buffers its output and ignores fflush(), so an awk stage would hold the
# tokens. Producers must never call log(): their stdout IS the fifo.
#
# Priming: pw-dump -m dumps the whole registry as its first batch (which does
# carry volume props), so PRIME_DELAY seconds of tokens are drained before the
# first wpctl read; the baseline is that first read.
#
# Test hooks (used by tests; never set by the service):
#   VOLUME_NOTIFY_EVENTS_CMD  replace the producer with this command
#   VOLUME_NOTIFY_SETTLE      seconds between an event and the wpctl read
#   VOLUME_NOTIFY_PRIME_DELAY seconds of producer startup chatter to discard
#   VOLUME_NOTIFY_LOG         log file (default $XDG_RUNTIME_DIR/swaymp-volume-notify.log)
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}

SETTLE=${VOLUME_NOTIFY_SETTLE:-0.4}
PRIME_DELAY=${VOLUME_NOTIFY_PRIME_DELAY:-2}
LOG=${VOLUME_NOTIFY_LOG:-$XDG_RUNTIME_DIR/swaymp-volume-notify.log}
EVENTS_CMD=${VOLUME_NOTIFY_EVENTS_CMD:-}

marker="$XDG_RUNTIME_DIR/swaymp-volume-marker"

log() {
    printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >> "$LOG" 2>/dev/null
}

notify() {
    notify-send --expire-time=1500 \
        --hint=string:x-canonical-private-synchronous:volume "$1" "$2" 2>/dev/null
}

# "wpctl get-volume" prints "Volume: 0.65 [MUTED]" - the flag is bracketed, so
# match it loosely ($3 == "MUTED" never matched and mute changes went unnoticed
# in the old polling version too).
read_state() {
    wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null |
        awk '/Volume:/ {printf "%d|%s", $2 * 100 + 0.5, ($3 ~ /MUTED/ ? "muted" : "unmuted")}'
}

# One token per re-dumped array that carries sink volume/mute state. A
# column-0 "]" closes one array; the hit flag is set by any line holding a
# "volume": or "mute": key, which only the sink/device Props block has.
audio_events() {
    pw-dump -m -N 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            *'"volume":'*|*'"mute":'*) hit=1 ;;
        esac
        if [ "$line" = "]" ]; then
            [ "${hit:-0}" = 1 ] && printf 'vol\n'
            hit=0
        fi
    done
}

# A producer that dies (pw-dump exits when PipeWire restarts) is restarted after
# a short gap: this is a restart guard, not a poll for state.
supervised() {
    while true; do
        "$@"
        sleep 2
    done
}

EVENTS=$XDG_RUNTIME_DIR/swaymp-volume-events
rm -f "$EVENTS"
mkfifo "$EVENTS" || { log "cannot create event fifo $EVENTS"; exit 1; }
# O_RDWR keeps the fifo open from both ends: the producer never blocks on an
# absent reader and the loop never sees EOF when the producer exits.
exec 3<>"$EVENTS"

if [ -n "$EVENTS_CMD" ]; then
    bash -c "$EVENTS_CMD" > "$EVENTS" & producer=$!
else
    supervised audio_events > "$EVENTS" & producer=$!
fi

cleanup() {
    kill "$producer" 2>/dev/null
    exec 3>&- 2>/dev/null
    rm -f "$EVENTS"
}
trap 'cleanup; exit 0' INT TERM
trap cleanup EXIT

last=""
sleep "$PRIME_DELAY"
while read -t 0.2 -r _ <&3; do :; done
last=$(read_state)
log "volume-notify started (event-driven, settle ${SETTLE}s)"

# Coalesce bursts: a volume drag (or a client setting several channels) emits a
# dump per change, so take the first token, swallow everything currently
# buffered, settle once, then read the sink state a single time.
while read -r _ <&3; do
    n=0
    while [ "$n" -lt 5000 ] && read -t 0.1 -r _ <&3; do n=$((n+1)); done
    sleep "$SETTLE"

    state=$(read_state)
    [ -z "$state" ] && continue

    if [ -n "$last" ] && [ "$state" != "$last" ]; then
        suppress=0
        if [ -e "$marker" ]; then
            marker_age=$(( $(date +%s) - $(stat -c %Y "$marker" 2>/dev/null || echo 0) ))
            if [ "$marker_age" -le 1 ]; then
                suppress=1
            fi
        fi

        if [ "$suppress" -eq 0 ]; then
            vol=${state%%|*}
            muted=${state##*|}
            if [ "$muted" = "muted" ]; then
                notify "Volume" "Muted"
            else
                notify "Volume" "${vol}%"
            fi
            log "volume changed: $state"
        else
            log "volume changed: $state (suppressed, keybind)"
        fi
    fi

    last="$state"
done
