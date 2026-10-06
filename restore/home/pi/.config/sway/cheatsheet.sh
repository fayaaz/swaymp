#!/bin/bash
# Toggle the keycap cheatsheet overlay (imv-wayland renders cheatsheet.svg from keys.json).
DIR="$(dirname "$0")"
sock=$(ls -1 /run/user/1000/sway-ipc.*.sock | head -n1)
if swaymsg -s "$sock" -t get_tree | jq -e '.. | objects | select(.app_id? == "cheatsheet" or .name? == "cheatsheet")' >/dev/null 2>&1; then
    swaymsg -s "$sock" '[app_id="cheatsheet"] kill' >/dev/null 2>&1 || true
    swaymsg -s "$sock" '[title="cheatsheet"] kill' >/dev/null 2>&1 || true
    exit 0
fi
imv-wayland -w cheatsheet -W 700 -H 520 -s full -b '#000000' "$DIR/cheatsheet.svg"
