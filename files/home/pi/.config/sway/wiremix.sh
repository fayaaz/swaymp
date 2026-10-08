#!/bin/bash
# Toggle wiremix on workspace 1:Music: close it if already open, otherwise
# go to 1:Music and open it as a floating 600x600 window (sway window rule).
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
sock=$(ls -1 "$runtime"/sway-ipc.*.sock | head -n1)
if swaymsg -s "$sock" -t get_tree | jq -e '.. | .app_id? | select(. == "wiremix")' >/dev/null 2>&1; then
    swaymsg -s "$sock" '[app_id="wiremix"] kill'
    exit 0
fi
swaymsg -s "$sock" 'workspace "1:Music"'
foot --app-id wiremix --title wiremix -e "$HOME/.cargo/bin/wiremix" --peaks mono
