#!/bin/bash
# Network manager: toggle wifitui (NetworkManager wifi TUI) in a floating foot
# window. Scan/join networks, reveal saved passphrases, QR code for sharing.
# Replaces the nm-applet tray icon: the package stays installed but is no
# longer autostarted (see the Session block of the sway config). Falls back to
# nmtui when wifitui is not installed.
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
sock=$(ls -1 "$runtime"/sway-ipc.*.sock | head -n1)
if swaymsg -s "$sock" -t get_tree | jq -e '.. | .app_id? | select(. == "network")' >/dev/null 2>&1; then
    swaymsg -s "$sock" '[app_id="network"] kill'
    exit 0
fi

wf=$(command -v wifitui 2>/dev/null || true)
[ -x "$wf" ] || wf="$HOME/.local/bin/wifitui"
if [ -x "$wf" ]; then
    [ -f "$HOME/.config/wifitui/theme.toml" ] && export WIFITUI_THEME="$HOME/.config/wifitui/theme.toml"
    exec foot --app-id network --title network --font "JetBrains Mono:size=15" -e "$wf"
fi

command -v nmtui >/dev/null || { notify-send "Network" "wifitui not installed"; exit 1; }
exec foot --app-id network --title network --font "JetBrains Mono:size=15" -e nmtui
