#!/usr/bin/env bash
# Pi-side screen recording for the HackPi demo (v2) — runs ON THE PI as the
# target user (not on the workstation). Produces /tmp/hackpi-overlay.mp4:
#   ENOENT - Hopscotch (starting at 0:40) + timed Super+key events with
#   notify popups, volume 100% -> 50% -> 100%, a pointer touch on the waybar
#   cheatsheet button, and the Super+Space launcher (fuzzel).
# Captured with wf-recorder + PipeWire audio.
# Copy to the Pi and run:
#   scp overlay_demo.sh hackpi-touch.c pi@hackpi.local:/tmp/
#   ssh pi@hackpi.local 'bash /tmp/overlay_demo.sh'
# The .marks file it writes is the source of truth for EVENTS in index.html.
set -u

RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR="$RT"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export SWAYSOCK="${SWAYSOCK:-$(ls -1 "$RT"/sway-ipc.*.sock | head -n1)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$RT/bus}"
export PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.cargo/bin

OUT=/tmp/hackpi-overlay.mp4
LOG=/tmp/hackpi-overlay.log
MARKS=/tmp/hackpi-overlay.marks
TOUCH=/tmp/hackpi-touch
TRACK="ENOENT/Sinbiotic EP/enoent_hopscotch_16bitwav_master.wav"
START_AT=40
VOL_STEPS=10          # 10 x 5% = 50 percentage points
STEP_GAP=0.45
rm -f "$OUT" "$LOG" "$MARKS"

if [ ! -x "$TOUCH" ] && [ -f /tmp/hackpi-touch.c ]; then
    gcc -O2 -o "$TOUCH" /tmp/hackpi-touch.c >/dev/null 2>&1 || true
fi

T0=0
mark() {
    local t
    t=$(awk -v a="$T0" -v b="$(date +%s.%N)" 'BEGIN { printf "%.2f", b - a }')
    printf '%s %s\n' "$t" "$*" >>"$MARKS"
}

kill_app() { swaymsg "[app_id=\"$1\"] kill" >/dev/null 2>&1 || true; }

kill_app cheatsheet
kill_app imv
kill_app imv-wayland
kill_app foot
kill_app wiremix
pkill -x fuzzel >/dev/null 2>&1 || true
pkill -x imv-wayland >/dev/null 2>&1 || true
pkill -x swayimg >/dev/null 2>&1 || true
swaync-client -C >/dev/null 2>&1 || true

swaymsg 'workspace "1:Music"; focus' >/dev/null 2>&1 || true
bash "$HOME/.config/waybar/euphonica.sh" >/dev/null 2>&1 &
sleep 3
swaymsg '[app_id="io.github.htkhiem.Euphonica"] focus' >/dev/null 2>&1 || true
sleep 1

mpc clear >/dev/null 2>&1 || true
mpc consume off >/dev/null 2>&1 || true
mpc random off >/dev/null 2>&1 || true
mpc single off >/dev/null 2>&1 || true
mpc add "$TRACK" >/dev/null 2>&1 || true
mpc play >/dev/null 2>&1 || true
mpc seek "$START_AT" >/dev/null 2>&1 || true
wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.00 >/dev/null 2>&1 || true
sleep 2
mpc status >>"$LOG" 2>&1 || true
wpctl get-volume @DEFAULT_AUDIO_SINK@ >>"$LOG" 2>&1 || true

wf-recorder -y -a --audio-backend=pipewire -f "$OUT" -r 15 -D >/tmp/hackpi-overlay-rec.log 2>&1 &
REC=$!
T0=$(date +%s.%N)
sleep 1
mark "REC_START"

notify-send -t 2500 "HackPi" "Now playing: ENOENT - Hopscotch (from 0:40)"
mark "NOTIFY now-playing"
sleep 1.0

notify-send -t 1800 "Key" "Super+P Play/Pause"
wtype -M logo -k p -m logo
mark "KEY super P pause"
sleep 2.5

notify-send -t 1800 "Key" "Super+P Play/Pause"
wtype -M logo -k p -m logo
mark "KEY super P resume"
sleep 3.0

notify-send -t 1800 "Key" "Super+K Seek +5s"
wtype -M logo -k k -m logo
mark "KEY super K seek+5"
sleep 2.5

notify-send -t 1800 "Key" "Super+J Seek -5s"
wtype -M logo -k j -m logo
mark "KEY super J seek-5"
sleep 3.0

notify-send -t 2000 "Key" "Super+I Volume - (100% to 50%)"
mark "NOTIFY volume-down"
for i in $(seq 1 "$VOL_STEPS"); do
    wtype -M logo -k i -m logo
    mark "KEY super I vol-down-$i"
    sleep "$STEP_GAP"
done
sleep 1.9
mark "HOLD 50%"

notify-send -t 2000 "Key" "Super+O Volume + (50% to 100%)"
mark "NOTIFY volume-up"
for i in $(seq 1 "$VOL_STEPS"); do
    wtype -M logo -k o -m logo
    mark "KEY super O vol-up-$i"
    sleep "$STEP_GAP"
done
sleep 1.9
mark "HOLD 100%"

notify-send -t 2200 "Key" "Cheatsheet (waybar)"
mark "NOTIFY cheatsheet"
# Flat accel so the injected pointer deltas land 1:1 on the waybar button.
swaymsg 'input * accel_profile flat' >/dev/null 2>&1 || true
swaymsg 'input * pointer_accel 0' >/dev/null 2>&1 || true
if [ -x "$TOUCH" ]; then
    sudo "$TOUCH" home pause 300 move 82 20 pause 800 click
    mark "TOUCH waybar cheatsheet-open"
    sleep 5.5
    sudo "$TOUCH" pause 300 click
    mark "TOUCH waybar cheatsheet-close"
else
    wtype -k F13
    mark "KEY F13 cheatsheet-open"
    sleep 5.5
    wtype -k F13
    mark "KEY F13 cheatsheet-close"
fi
sleep 1.5

notify-send -t 2200 "Key" "Super+Space Launcher"
wtype -M logo -k space -m logo
mark "KEY super space launcher"
sleep 3.5
pkill -x fuzzel >/dev/null 2>&1 || true

notify-send -t 2500 "Done" "HackPi overlay demo"
mark "NOTIFY done"
sleep 2

kill -INT "$REC" 2>/dev/null || true
sleep 3
swaymsg 'input * accel_profile adaptive' >/dev/null 2>&1 || true
swaymsg 'input * pointer_accel 0' >/dev/null 2>&1 || true
mpc status >>"$LOG" 2>&1 || true
wpctl get-volume @DEFAULT_AUDIO_SINK@ >>"$LOG" 2>&1 || true
echo "wrote $OUT"
