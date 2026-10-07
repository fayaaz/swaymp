#!/bin/bash
# Toggle the keycap cheatsheet overlay (swayimg renders cheatsheet.svg from keys.json).
# The window is fully transparent so the card's rounded corners show through.
DIR="$(dirname "$0")"
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
sock=$(ls -1 "$runtime"/sway-ipc.*.sock | head -n1)
if swaymsg -s "$sock" -t get_tree | jq -e '.. | objects | select(.app_id? == "cheatsheet" or .name? == "cheatsheet")' >/dev/null 2>&1; then
    swaymsg -s "$sock" '[app_id="cheatsheet"] kill' >/dev/null 2>&1 || true
    swaymsg -s "$sock" '[title="cheatsheet"] kill' >/dev/null 2>&1 || true
    exit 0
fi
# swayimg runs with SWAYSOCK unset: its Sway-mode parent-window lookup
# segfaults when the active workspace has no windows, and the for_window
# rule below does all sizing/placement (resize 700x520, move 10,57 which
# lands at absolute 10,100). Window/app_id stay "cheatsheet".
env -u SWAYSOCK swayimg -a cheatsheet \
    -c "viewer.window=#00000000" \
    -c "viewer.transparency=#00000000" \
    -c "info.show=no" \
    "$DIR/cheatsheet.svg" >/dev/null 2>&1 &
viewer=$!
sleep 2
if ! kill -0 $viewer 2>/dev/null; then
    # Normal urgency so a failure is a transient note, not a sticky pile.
    notify-send "ERROR: cheatsheet failed to open" "swayimg exited unexpectedly" >/dev/null 2>&1 || true
fi
