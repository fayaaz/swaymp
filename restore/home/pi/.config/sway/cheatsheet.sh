#!/bin/bash
# Toggle the keycap cheatsheet overlay (cheatsheet-viewer.py renders
# cheatsheet.svg from keys.json in a transparent GTK window).
# The window is fully transparent so the card's rounded corners show through.
DIR="$(dirname "$0")"
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
sock=$(ls -1 "$runtime"/sway-ipc.*.sock | head -n1)
PIDFILE="$runtime/cheatsheet.pid"
if swaymsg -s "$sock" -t get_tree | jq -e '.. | objects | select(.app_id? == "cheatsheet" or .name? == "cheatsheet")' >/dev/null 2>&1; then
    # Stop the viewer process itself (fast and exact); the window kills
    # below only catch strays, since a bare window kill leaves the
    # Python process lingering for seconds.
    if [ -f "$PIDFILE" ]; then
        pid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$pid" ] && grep -qa "cheatsheet-viewer" "/proc/$pid/cmdline" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$PIDFILE"
    fi
    swaymsg -s "$sock" '[app_id="cheatsheet"] kill' >/dev/null 2>&1 || true
    swaymsg -s "$sock" '[title="cheatsheet"] kill' >/dev/null 2>&1 || true
    exit 0
fi
# The viewer is a small GTK window (cheatsheet-viewer.py): borderless and
# fully transparent, app_id "cheatsheet", so the for_window rule does all
# sizing/placement (resize 700x520, move 10,57 for absolute 10,100).
CHEATSHEET_PIDFILE="$PIDFILE" python3 "$DIR/cheatsheet-viewer.py" >/dev/null 2>&1 &
viewer=$!
echo "$viewer" > "$PIDFILE"
sleep 2
# Only a real crash reports: a close press above removes PIDFILE, and a
# newer opener overwrites it with its own PID, so a rapidly toggled
# viewer that was closed on purpose stays silent.
if ! kill -0 $viewer 2>/dev/null && [ "$(cat "$PIDFILE" 2>/dev/null)" = "$viewer" ]; then
    rm -f "$PIDFILE"
    # Normal urgency so a failure is a transient note, not a sticky pile.
    notify-send "ERROR: cheatsheet failed to open" "viewer exited unexpectedly" >/dev/null 2>&1 || true
fi
