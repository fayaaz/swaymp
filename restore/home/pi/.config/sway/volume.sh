#!/bin/bash
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/1000}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}

marker="$XDG_RUNTIME_DIR/hackpi-volume-marker"
action="${1:-status}"
case "$action" in
    up) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ ;;
    down) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
    mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    status) ;;
    *) exit 1 ;;
esac

[ "$action" != "status" ] && touch "$marker"

out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
vol=$(printf '%s\n' "$out" | awk '/Volume:/ {printf "%d", $2 * 100 + 0.5}')

if printf '%s\n' "$out" | grep -q MUTED; then
    notify-send --expire-time=1500 --hint=string:x-canonical-private-synchronous:volume "Volume" "Muted"
else
    notify-send --expire-time=1500 --hint=string:x-canonical-private-synchronous:volume "Volume" "${vol:-0}%"
fi
