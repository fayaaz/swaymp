#!/bin/bash
# Bluetooth manager: toggle bluetuith (TUI bluetooth manager) in foot.
# Pair/connect/trust devices, switch audio profiles (A), remove devices (d);
# PipeWire plays through a device once it is connected. Falls back to
# bluetoothctl when bluetuith is not installed.
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
sock=$(ls -1 "$runtime"/sway-ipc.*.sock | head -n1)
if swaymsg -s "$sock" -t get_tree | jq -e '.. | .app_id? | select(. == "bluetooth")' >/dev/null 2>&1; then
    swaymsg -s "$sock" '[app_id="bluetooth"] kill'
    exit 0
fi
bluetoothctl power on >/dev/null 2>&1
sudo -n /usr/sbin/rfkill unblock bluetooth >/dev/null 2>&1 || true

bt=$(command -v bluetuith 2>/dev/null || true)
[ -x "$bt" ] || bt="$HOME/.local/bin/bluetuith"
if [ ! -x "$bt" ]; then
    exec foot --app-id bluetooth --title bluetooth -e bluetoothctl
fi

mkdir -p "$HOME/Downloads"
export BLUETUITH_RECEIVE_DIR="$HOME/Downloads"
# Smaller font than foot.ini so the TUI's menu bar (adapter name + menu +
# Powered/Scanning/Pairable chips), device rows and help line fit the 720x720 panel.
exec foot --app-id bluetooth --title bluetooth --font "JetBrains Mono:size=13" -e "$bt"
