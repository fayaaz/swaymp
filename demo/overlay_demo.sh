#!/usr/bin/env bash
# Pi-side screen recording for the swaymp demo (v3) — runs ON THE PI as the
# target user (not on the workstation). Produces /tmp/swaymp-overlay.mp4:
#   ENOENT - Hopscotch (starting at 0:40) + a timed tour of the whole feature
#   set the smoke test covers, each beat labelled with a notify popup and
#   captured with wf-recorder + PipeWire audio:
#     Euphonica opens (Super+Shift+4 = the dollar key; the demo starts with it
#     closed and shows it opening on Now Playing), playback (Super+P), seek
#     (Super+K/J), Euphonica play queue (Ctrl+7 shows the queued ENOENT + Shin
#     Bone tunes), queue prev/next (Super+H/L), then touch the Queue header's
#     yellow play button to return to Now Playing, volume (Super+I/O) + mute
#     (Super+M),
#     wiremix (Super+V), bluetooth (Super+B), network (Super+N), audio output
#     (Super+D), notifications/miniplayer (Super+Return), browser (Super+G),
#     audio mode picker (Super+X), launcher (Super+Space), cheatsheet (pointer
#     touch on the waybar button, then the pointer is moved off the button so
#     no tooltip lingers).
# Copy to the Pi and run:
#   scp overlay_demo.sh swaymp-touch.c pi@hackpi.local:/tmp/
#   ssh pi@hackpi.local 'bash /tmp/overlay_demo.sh'
# The .marks file it writes is the source of truth for EVENTS in index.html.
set -u

RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR="$RT"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export SWAYSOCK="${SWAYSOCK:-$(ls -1 "$RT"/sway-ipc.*.sock | head -n1)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$RT/bus}"
export PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.cargo/bin:$HOME/.local/bin

OUT=/tmp/swaymp-overlay.mp4
LOG=/tmp/swaymp-overlay.log
MARKS=/tmp/swaymp-overlay.marks
TOUCH=/tmp/swaymp-touch
EUPH=io.github.htkhiem.Euphonica
AM="$HOME/.config/sway/audio-mode.sh"
VSH="$HOME/.config/sway/volume.sh"
VSH_BAK=/tmp/swaymp-volume.sh.bak

restore_volume() {
    [ -f "$VSH_BAK" ] && cp -a "$VSH_BAK" "$VSH" 2>/dev/null || true
}
trap restore_volume EXIT

if [ -f "$VSH" ]; then
    cp -a "$VSH" "$VSH_BAK"
    cat > "$VSH" <<'EOF'
#!/bin/bash
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}

marker="$XDG_RUNTIME_DIR/swaymp-volume-marker"
action="${1:-status}"
vol() {
    mpc status 2>/dev/null | awk -F'volume:' '/volume:/ {split($2, a, "%"); print a[1] + 0; exit}'
}

cur=$(vol)
[ -z "$cur" ] && cur=100

case "$action" in
    up)
        new=$((cur + 5))
        [ "$new" -gt 100 ] && new=100
        mpc volume "$new" >/dev/null 2>&1 || true
        ;;
    down)
        new=$((cur - 5))
        [ "$new" -lt 0 ] && new=0
        mpc volume "$new" >/dev/null 2>&1 || true
        ;;
    mute)
        if [ "$cur" -eq 0 ]; then new=100; else new=0; fi
        mpc volume "$new" >/dev/null 2>&1 || true
        ;;
    status)
        new=$cur
        ;;
    *)
        exit 1
        ;;
esac

[ "$action" != "status" ] && touch "$marker"

new=$(vol)
if [ "${new:-0}" -eq 0 ]; then
    notify-send --expire-time=1500 --hint=string:x-canonical-private-synchronous:volume "Volume" "Muted"
else
    notify-send --expire-time=1500 --hint=string:x-canonical-private-synchronous:volume "Volume" "${new:-0}%"
fi
EOF
    chmod +x "$VSH"
fi
TRACK="ENOENT/Sinbiotic EP/enoent_hopscotch_16bitwav_master.wav"
TRACK2="ENOENT/Sinbiotic EP/Shin_Bone_Blow_16bitwav_master.wav"
TRACK3="ENOENT/Sinbiotic EP/blow_enoent_halftime_remix_16bitwav_master.wav"
START_AT=40
VOL_STEPS=10          # 10 x 5% = 50 percentage points
STEP_GAP=0.45
rm -f "$OUT" "$LOG" "$MARKS"

if [ ! -x "$TOUCH" ] && [ -f /tmp/swaymp-touch.c ]; then
    gcc -O2 -o "$TOUCH" /tmp/swaymp-touch.c >/dev/null 2>&1 || true
fi

T0=0
mark() {
    local t
    t=$(awk -v a="$T0" -v b="$(date +%s.%N)" 'BEGIN { printf "%.2f", b - a }')
    printf '%s %s\n' "$t" "$*" >>"$MARKS"
}

kill_app() { swaymsg "[app_id=\"$1\"] kill" >/dev/null 2>&1 || true; }
key()      { wtype -M logo -k "$1" -m logo; }
keyshift4(){ wtype -M logo -M shift -k 4 -m shift -m logo; }   # dollar key = Shift+4
ekey()     { wtype -M ctrl -k "$1" -m ctrl; }                  # Euphonica window accel
euph_visible() { swaymsg -t get_tree 2>/dev/null \
    | jq -r --arg id "$EUPH" '.. | objects | select(.app_id? == $id and .visible == true) | .app_id' | grep -c .; }
swaync_visible() {
    busctl --user call org.erikreider.swaync.cc /org/erikreider/swaync/cc \
        org.erikreider.swaync.cc GetVisibility 2>/dev/null | grep -q true
}
swaync_close() {
    swaync-client -cp >/dev/null 2>&1 || true
    for _ in $(seq 1 10); do
        if swaync_visible; then
            swaync-client -cp >/dev/null 2>&1 || true
            sleep 0.2
        else
            return 0
        fi
    done
    return 1
}

# clean slate: close anything a previous run left open
kill_app cheatsheet
kill_app foot
kill_app wiremix
kill_app bluetooth
kill_app network
kill_app firefox
kill_app imv
kill_app imv-wayland
pkill -x fuzzel >/dev/null 2>&1 || true
pkill -x imv-wayland >/dev/null 2>&1 || true
pkill -x swayimg >/dev/null 2>&1 || true
swaync_close >/dev/null 2>&1 || true

# local playback only for a clean recorded audio track; restore at the end
START_MODE=$(head -n1 "$HOME/.config/sway/.audio-mode" 2>/dev/null)
case "$START_MODE" in off|receiver|broadcast|group) ;; *) START_MODE=off ;; esac
[ -x "$AM" ] && bash "$AM" set off >/dev/null 2>&1 || true

swaymsg 'workspace "1:Music"; focus' >/dev/null 2>&1 || true
if [ "$(euph_visible)" -lt 1 ]; then
    bash "$HOME/.config/waybar/euphonica.sh" >/dev/null 2>&1 &
    sleep 3
fi
swaymsg "[app_id=\"$EUPH\"] focus" >/dev/null 2>&1 || true
sleep 1

mpc clear >/dev/null 2>&1 || true
mpc consume off >/dev/null 2>&1 || true
mpc random off >/dev/null 2>&1 || true
mpc single off >/dev/null 2>&1 || true
mpc add "$TRACK" >/dev/null 2>&1 || true
mpc add "$TRACK2" >/dev/null 2>&1 || true
mpc add "$TRACK3" >/dev/null 2>&1 || true
mpc play >/dev/null 2>&1 || true
mpc seek "$START_AT" >/dev/null 2>&1 || true
mpc volume 100 >/dev/null 2>&1 || true
# warm Euphonica onto its Now Playing page: Ctrl+7 jumps to Queue, then the
# Queue header's yellow play button pushes Now Playing. Hide it so the demo
# starts closed and the opening toggle shows Now Playing.
swaymsg "[app_id=\"$EUPH\"] focus" >/dev/null 2>&1 || true
sleep 0.5
wtype -k Escape >/dev/null 2>&1 || true
ekey 7; sleep 1.0
if [ -x "$TOUCH" ]; then
    swaymsg 'input * accel_profile flat' >/dev/null 2>&1 || true
    swaymsg 'input * pointer_accel 0' >/dev/null 2>&1 || true
    sudo "$TOUCH" home pause 250 move 582 66 pause 500 click pause 500
    swaymsg 'input * accel_profile adaptive' >/dev/null 2>&1 || true
fi
swaymsg "[app_id=\"$EUPH\"] move scratchpad" >/dev/null 2>&1 || true
swaymsg 'workspace "1:Music"; focus' >/dev/null 2>&1 || true
wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.00 >/dev/null 2>&1 || true
wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 >/dev/null 2>&1 || true
sleep 2
mpc status >>"$LOG" 2>&1 || true
wpctl get-volume @DEFAULT_AUDIO_SINK@ >>"$LOG" 2>&1 || true

wf-recorder -y -a --audio-backend=pipewire -f "$OUT" -r 15 -D >/tmp/swaymp-overlay-rec.log 2>&1 &
REC=$!
T0=$(date +%s.%N)
sleep 1
mark "REC_START"

# ---- Euphonica opens (starts closed; dollar key shows it on Now Playing) ----
notify-send -t 2200 "Key" "Super+Shift+4 Euphonica"
keyshift4; mark "KEY super dollar euphonica-open"; sleep 3.0

notify-send -t 2500 "swaymp" "Now playing: ENOENT - Hopscotch (from 0:40)"
mark "NOTIFY now-playing"
sleep 1.0

# ---- playback ----
notify-send -t 1800 "Key" "Super+P Play/Pause"
key p; mark "KEY super P pause"; sleep 2.5
notify-send -t 1800 "Key" "Super+P Play/Pause"
key p; mark "KEY super P resume"; sleep 3.0

# ---- seek ----
notify-send -t 1800 "Key" "Super+K Seek +5s"
key k; mark "KEY super K seek+5"; sleep 2.5
notify-send -t 1800 "Key" "Super+J Seek -5s"
key j; mark "KEY super J seek-5"; sleep 3.0

# ---- Euphonica Queue view: show the queue list ----
# Ctrl+7 jumps to Queue. The return to Now Playing happens after the queue
# prev/next demo, via the Queue header's yellow play button.
swaymsg "[app_id=\"$EUPH\"] focus" >/dev/null 2>&1 || true; sleep 0.5
wtype -k Escape >/dev/null 2>&1 || true
ekey 7; mark "KEY ctrl7 queue-view"; sleep 3.0

# ---- queue prev/next (Super+L next, Super+H previous) ----
notify-send -t 2000 "Key" "Super+L Next track"
key l; mark "KEY super L next"; sleep 2.5
notify-send -t 2000 "Key" "Super+H Previous track"
key h; mark "KEY super H prev"; sleep 1.0
mpc seek "$START_AT" >/dev/null 2>&1 || true
sleep 1.5

# ---- return from Queue to Now Playing after the queue demo ----
swaync_close >/dev/null 2>&1 || true
swaymsg "[app_id=\"$EUPH\"] focus" >/dev/null 2>&1 || true; sleep 0.5
if [ -x "$TOUCH" ]; then
    swaymsg 'input * accel_profile flat' >/dev/null 2>&1 || true
    swaymsg 'input * pointer_accel 0' >/dev/null 2>&1 || true
    sudo "$TOUCH" home pause 250 move 582 66 pause 500 click pause 500
    mark "TOUCH queue-nowplaying"
    swaymsg 'input * accel_profile adaptive' >/dev/null 2>&1 || true
fi
sleep 1.0

# ---- volume 100% -> 50% -> 100% ----
notify-send -t 2000 "Key" "Super+I Volume - (100% to 50%)"
mark "NOTIFY volume-down"
for i in $(seq 1 "$VOL_STEPS"); do key i; mark "KEY super I vol-down-$i"; sleep "$STEP_GAP"; done
sleep 1.5; mark "HOLD 50%"; mpc status >>"$LOG" 2>&1 || true

notify-send -t 2000 "Key" "Super+O Volume + (50% to 100%)"
mark "NOTIFY volume-up"
for i in $(seq 1 "$VOL_STEPS"); do key o; mark "KEY super O vol-up-$i"; sleep "$STEP_GAP"; done
sleep 1.5; mark "HOLD 100%"; mpc status >>"$LOG" 2>&1 || true

notify-send -t 1800 "Key" "Super+M Mute"
key m; mark "KEY super M mute"; sleep 2.0
notify-send -t 1800 "Key" "Super+M Unmute"
key m; mark "KEY super M unmute"; sleep 2.0

# ---- wiremix peaks ----
notify-send -t 2200 "Key" "Super+V Wiremix peaks"
key v; mark "KEY super V wiremix"; sleep 3.0
key v; mark "KEY super V wiremix-close"; sleep 1.0

# ---- bluetooth (bluetuith) ----
notify-send -t 2200 "Key" "Super+B Bluetooth"
key b; mark "KEY super B bluetooth"; sleep 3.5
key b; mark "KEY super B bluetooth-close"; sleep 1.0

# ---- network (wifitui) ----
notify-send -t 2200 "Key" "Super+N Network"
key n; mark "KEY super N network"; sleep 4.0
key n; mark "KEY super N network-close"; sleep 1.0

# ---- audio output switcher (notification) ----
notify-send -t 2200 "Key" "Super+D Audio output"
key d; mark "KEY super D output"; sleep 2.5

# ---- notifications / miniplayer (control center) ----
swaync_close >/dev/null 2>&1 || true
notify-send -t 2200 "Key" "Super+Return Notifications"
key Return; mark "KEY super Return notifications"; sleep 3.5
swaync_close >/dev/null 2>&1 || true; mark "CMD swaync-close"; sleep 1.0

# ---- browser (firefox -> 2:Browser, type the repo URL into the address bar) ----
notify-send -t 2200 "Key" "Super+G Browser"
key g; mark "KEY super G browser"
for _f in $(seq 1 24); do
    swaymsg -t get_tree | jq -e '..|objects|select(.app_id?=="firefox")' >/dev/null 2>&1 && break
    sleep 0.5
done
swaymsg '[app_id="firefox"] focus' >/dev/null 2>&1; sleep 1.0
wtype -M ctrl -k l -m ctrl; sleep 0.5
wtype "https://github.com/fayaaz/swaymp"; mark "CMD type-url"; sleep 0.5
wtype -k Return; mark "KEY enter load"; sleep 5.0
kill_app firefox; sleep 1.0
swaymsg 'workspace "1:Music"; focus' >/dev/null 2>&1 || true
sleep 1.0

# ---- audio mode picker (fuzzel; Esc leaves the mode unchanged) ----
notify-send -t 2200 "Key" "Super+X Audio mode"
key x; mark "KEY super X audio-mode"; sleep 2.5
wtype -k Escape; mark "KEY esc audio-mode-close"; sleep 1.0

# ---- launcher (fuzzel) ----
notify-send -t 2200 "Key" "Super+Space Launcher"
key space; mark "KEY super space launcher"; sleep 3.0
pkill -x fuzzel >/dev/null 2>&1 || true
sleep 0.5

# ---- cheatsheet: pointer touch on the waybar button (no keycap) ----
notify-send -t 2200 "Key" "Cheatsheet (waybar)"
mark "NOTIFY cheatsheet"
swaymsg 'input * accel_profile flat' >/dev/null 2>&1 || true
swaymsg 'input * pointer_accel 0' >/dev/null 2>&1 || true
if [ -x "$TOUCH" ]; then
    sudo "$TOUCH" home pause 300 move 82 20 pause 800 click
    mark "TOUCH waybar cheatsheet-open"
    sudo "$TOUCH" move 360 400          # move the pointer off the button/card (no lingering tooltip)
    mark "TOUCH cheatsheet-move-off"
    sleep 5.5
    wtype -k F11                        # close via keyboard so no cursor lingers on the card
    mark "KEY F11 cheatsheet-close"
else
    wtype -k F11
    mark "KEY F11 cheatsheet-open"
    sleep 5.5
    wtype -k F11
    mark "KEY F11 cheatsheet-close"
fi
sleep 1.5

notify-send -t 2500 "Done" "swaymp overlay demo"
mark "NOTIFY done"
sleep 2

swaync_close >/dev/null 2>&1 || true
kill -INT "$REC" 2>/dev/null || true
sleep 3
swaymsg 'input * accel_profile adaptive' >/dev/null 2>&1 || true
swaymsg 'input * pointer_accel 0' >/dev/null 2>&1 || true
mpc status >>"$LOG" 2>&1 || true
wpctl get-volume @DEFAULT_AUDIO_SINK@ >>"$LOG" 2>&1 || true
[ -x "$AM" ] && bash "$AM" set "$START_MODE" >/dev/null 2>&1 || true
echo "wrote $OUT"
