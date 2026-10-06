#!/bin/bash
DIR="$(dirname "$0")"
sock=$(ls -1 /run/user/1000/sway-ipc.*.sock | head -n1)
if swaymsg -s "$sock" -t get_tree | jq -e '.. | .name? | select(. == "cheatsheet")' >/dev/null 2>&1; then
    swaymsg -s "$sock" 'kill [title="cheatsheet"]'
    exit 0
fi
foot --title cheatsheet --app-id cheatsheet -W 44x20 -H cat "$DIR/cheatsheet.txt"
