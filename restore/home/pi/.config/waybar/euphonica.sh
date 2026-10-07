#!/bin/bash
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
export SWAYSOCK=${SWAYSOCK:-$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'sway-ipc.*' -print -quit)}

if ! pgrep -x euphonica >/dev/null; then
    flatpak --user run --env=GSK_RENDERER=cairo io.github.htkhiem.Euphonica >/dev/null 2>&1 &
    sleep 2
fi

swaymsg 'workspace "1:Music"; [app_id="io.github.htkhiem.Euphonica"] focus'
