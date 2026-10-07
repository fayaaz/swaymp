#!/bin/bash
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}

marker="$XDG_RUNTIME_DIR/hackpi-volume-marker"
last=""

while true; do
    out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
    if [ -z "$out" ]; then
        sleep 1
        continue
    fi

    state=$(printf '%s\n' "$out" | awk '/Volume:/ {printf "%d|%s", $2 * 100 + 0.5, ($3 == "MUTED" ? "muted" : "unmuted")}')
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
                notify-send --expire-time=1500 --hint=string:x-canonical-private-synchronous:volume "Volume" "Muted"
            else
                notify-send --expire-time=1500 --hint=string:x-canonical-private-synchronous:volume "Volume" "${vol}%"
            fi
        fi
    fi

    last="$state"
    sleep 0.5
done
