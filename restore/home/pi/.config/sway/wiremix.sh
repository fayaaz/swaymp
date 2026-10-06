#!/bin/bash
# Toggle wiremix: close it if already open, otherwise dock it below the focused window.
sock=$(ls -1 /run/user/1000/sway-ipc.*.sock | head -n1)
if swaymsg -s "$sock" -t get_tree | jq -e '.. | .app_id? | select(. == "wiremix")' >/dev/null 2>&1; then
    swaymsg -s "$sock" '[app_id="wiremix"] kill'
    exit 0
fi
swaymsg -s "$sock" 'split v'
foot --app-id wiremix --title wiremix -e /home/pi/.cargo/bin/wiremix --peaks mono
