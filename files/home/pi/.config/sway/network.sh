#!/bin/bash
# Network manager: toggle nmtui (NetworkManager TUI) in a floating foot window.
# Connect/disconnect access points, edit connections, set up a hotspot.
# Replaces the nm-applet tray icon: the package stays installed but is no
# longer autostarted (see the Session block of the sway config).
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
sock=$(ls -1 "$runtime"/sway-ipc.*.sock | head -n1)
if swaymsg -s "$sock" -t get_tree | jq -e '.. | .app_id? | select(. == "network")' >/dev/null 2>&1; then
    swaymsg -s "$sock" '[app_id="network"] kill'
    exit 0
fi
command -v nmtui >/dev/null || { notify-send "Network" "nmtui not installed"; exit 1; }
exec foot --app-id network --title network -e nmtui
