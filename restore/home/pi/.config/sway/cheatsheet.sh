#!/bin/bash
# Toggle the keycap cheatsheet overlay (swayimg renders cheatsheet.svg from keys.json).
# The window is fully transparent so the card's rounded corners show through.
DIR="$(dirname "$0")"
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
sock=$(ls -1 "$runtime"/sway-ipc.*.sock | head -n1)
if swaymsg -s "$sock" -t get_tree | jq -e '.. | objects | select(.app_id? == "cheatsheet" or .name? == "cheatsheet")' >/dev/null 2>&1; then
    swaymsg -s "$sock" '[app_id="cheatsheet"] kill' >/dev/null 2>&1 || true
    swaymsg -s "$sock" '[title="cheatsheet"] kill' >/dev/null 2>&1 || true
    exit 0
fi
# swayimg -p is relative to the workspace content origin (below waybar, y=43),
# so 10,57 lands the 700x520 window at absolute 10,100 like the for_window rule.
swayimg -a cheatsheet -w 700,520 -p 10,57 -s fit \
    -c "viewer.window=#00000000" \
    -c "viewer.transparency=#00000000" \
    -c "info.show=no" \
    "$DIR/cheatsheet.svg" >/dev/null 2>&1 &
