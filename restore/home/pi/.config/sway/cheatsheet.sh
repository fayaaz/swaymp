#!/bin/bash
# Toggle the keycap cheatsheet overlay (swayimg renders cheatsheet.svg from keys.json).
DIR="$(dirname "$0")"
sock=$(ls -1 /run/user/1000/sway-ipc.*.sock | head -n1)
if swaymsg -s "$sock" -t get_tree | jq -e '.. | .app_id? | select(. == "cheatsheet")' >/dev/null 2>&1; then
    swaymsg -s "$sock" '[app_id="cheatsheet"] kill'
    exit 0
fi
swayimg -a cheatsheet -w 700,520 -p 10,57 -s fit \
    -c info.show=no \
    -c viewer.window=#00000000 \
    -c viewer.transparency=#00000000 \
    "$DIR/cheatsheet.svg"
