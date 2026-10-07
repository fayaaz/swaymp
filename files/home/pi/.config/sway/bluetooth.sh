#!/bin/bash
# Bluetooth manager: toggle an interactive bluetoothctl terminal.
# Pair/connect audio devices here; PipeWire plays through them once connected.
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
sock=$(ls -1 "$runtime"/sway-ipc.*.sock | head -n1)
if swaymsg -s "$sock" -t get_tree | jq -e '.. | .app_id? | select(. == "bluetooth")' >/dev/null 2>&1; then
    swaymsg -s "$sock" '[app_id="bluetooth"] kill'
    exit 0
fi
bluetoothctl power on >/dev/null 2>&1
sudo -n /usr/sbin/rfkill unblock bluetooth >/dev/null 2>&1 || true
foot --app-id bluetooth --title bluetooth -e bluetoothctl
