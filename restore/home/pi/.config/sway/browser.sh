#!/bin/bash
# Open the default browser on workspace 2:Browser (focus it if already running).
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
export SWAYSOCK=${SWAYSOCK:-$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'sway-ipc.*' -print -quit)}

if pgrep -x firefox >/dev/null 2>&1; then
    swaymsg 'workspace "2:Browser"; [app_id="firefox"] focus' >/dev/null 2>&1
else
    swaymsg 'workspace "2:Browser"' >/dev/null 2>&1
    swaymsg 'exec xdg-open about:blank' >/dev/null 2>&1
fi
