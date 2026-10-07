#!/bin/bash
# Toggle Euphonica: hide it to the scratchpad when visible,
# otherwise show it tiled and focused on workspace 1:Music.
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
export SWAYSOCK=${SWAYSOCK:-$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'sway-ipc.*' -print -quit)}

APP_ID="io.github.htkhiem.Euphonica"

if ! pgrep -x euphonica >/dev/null; then
    flatpak --user run --env=GSK_RENDERER=cairo io.github.htkhiem.Euphonica >/dev/null 2>&1 &
    sleep 2
fi

if swaymsg -t get_tree | jq -e --arg app "$APP_ID" \
        '.. | objects | select(.app_id? == $app and .visible == true)' >/dev/null 2>&1; then
    swaymsg "[app_id=\"$APP_ID\"] move scratchpad" >/dev/null 2>&1
else
    swaymsg 'workspace "1:Music"' >/dev/null 2>&1
    swaymsg "[app_id=\"$APP_ID\"] move to workspace \"1:Music\", floating disable, focus" >/dev/null 2>&1
fi
