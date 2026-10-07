#!/bin/bash
# Toggle Euphonica: hide it to the scratchpad when visible,
# otherwise show it tiled and focused on workspace 1:Music.
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
export SWAYSOCK=${SWAYSOCK:-$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'sway-ipc.*' -print -quit)}

APP_ID="io.github.htkhiem.Euphonica"

# Debounce: collapse mash bursts (and firmware repeats) into one toggle.
# A second press inside the window exits silently; deliberate presses are
# slower and pass through. (sway --no-repeat only stops holds.)
LASTFILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/euphonica.last"
now=$(date +%s%3N)
last=$(cat "$LASTFILE" 2>/dev/null || echo 0)
if [ "$((now - last))" -lt 600 ]; then
    exit 0
fi
echo "$now" > "$LASTFILE"

if ! pgrep -x euphonica >/dev/null; then
    flatpak --user run --env=GSK_RENDERER=cairo io.github.htkhiem.Euphonica >/dev/null 2>&1 &
fi

# A cold flatpak start takes many seconds; wait for the window (warm
# toggles find it immediately) and fail loudly if it never appears.
found=0
for _w in $(seq 1 40); do
    if swaymsg -t get_tree | jq -e --arg app "$APP_ID" \
            '.. | objects | select(.app_id? == $app)' >/dev/null 2>&1; then
        found=1
        break
    fi
    sleep 0.5
done
unset _w
if [ "$found" = 0 ]; then
    notify-send "ERROR: euphonica failed to open" "no window after 20s" >/dev/null 2>&1 || true
    exit 1
fi

if swaymsg -t get_tree | jq -e --arg app "$APP_ID" \
        '.. | objects | select(.app_id? == $app and .visible == true)' >/dev/null 2>&1; then
    swaymsg "[app_id=\"$APP_ID\"] move scratchpad" >/dev/null 2>&1
else
    swaymsg 'workspace "1:Music"' >/dev/null 2>&1
    # Separate steps, retried until shown: a freshly mapped window can
    # drop the first commands, and a scratchpad window needs the move
    # before it can untile (one chained command aborts on error).
    for _s in $(seq 1 10); do
        swaymsg "[app_id=\"$APP_ID\"] move to workspace \"1:Music\"" >/dev/null 2>&1
        swaymsg "[app_id=\"$APP_ID\"] floating disable" >/dev/null 2>&1
        swaymsg "[app_id=\"$APP_ID\"] focus" >/dev/null 2>&1
        if swaymsg -t get_tree | jq -e --arg app "$APP_ID" \
                '.. | objects | select(.app_id? == $app and .visible == true and .focused == true)' >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done
    unset _s
    if ! swaymsg -t get_tree | jq -e --arg app "$APP_ID" \
            '.. | objects | select(.app_id? == $app and .visible == true)' >/dev/null 2>&1; then
        notify-send "ERROR: euphonica failed to show" "window never became visible" >/dev/null 2>&1 || true
    fi
fi
