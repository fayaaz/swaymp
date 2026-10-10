#!/usr/bin/env bash
# ORIGINAL screen-recording demo — runs ON THE PI as user pi (not here).
# Records /tmp/swaymp-overlay.mp4: Euphonica playback + timed Super+key events
# with notify-send popups, captured with wf-recorder + PipeWire audio.
# That mp4 is the demo/swaymp-overlay.mp4 input: it plays on the 3D device's
# display (as frames/) and its audio track is muxed into the final video.
# Body below is verbatim as recorded 2026-10-06.
set -u

export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-1
export SWAYSOCK=$(ls -1 /run/user/1000/sway-ipc.*.sock | head -n1)
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
export PATH=/usr/local/bin:/usr/bin:/bin:/home/pi/.cargo/bin

OUT=/tmp/swaymp-overlay.mp4
LOG=/tmp/swaymp-overlay.log
rm -f "$OUT" "$LOG"

kill_app() {
    swaymsg "[app_id=\"$1\"] kill" >/dev/null 2>&1 || true
}

kill_app cheatsheet
kill_app imv
kill_app imv-wayland
kill_app foot
kill_app wiremix
pkill -x fuzzel >/dev/null 2>&1 || true
pkill -x imv-wayland >/dev/null 2>&1 || true

swaymsg 'workspace "1:Music"; focus' >/dev/null 2>&1 || true
bash "$HOME/.config/waybar/euphonica.sh" >/dev/null 2>&1 &
sleep 3
swaymsg '[app_id="io.github.htkhiem.Euphonica"] focus' >/dev/null 2>&1 || true
sleep 1

mpc clear >/dev/null 2>&1 || true
mpc consume off >/dev/null 2>&1 || true
mpc random off >/dev/null 2>&1 || true
mpc single off >/dev/null 2>&1 || true
mpc add "ENOENT/ENOENT_shiral.wav" >/dev/null 2>&1 || true
mpc play >/dev/null 2>&1 || true
mpc seek 40 >/dev/null 2>&1 || true
wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.00 >/dev/null 2>&1 || true
sleep 2
mpc status >>"$LOG" 2>&1 || true

wf-recorder -y -a --audio-backend=pipewire -f "$OUT" -r 15 -D >/tmp/swaymp-overlay-rec.log 2>&1 &
REC=$!
sleep 1

notify-send -t 2500 "swaymp" "Now playing: ENOENT - Shiral (from 0:40)"
sleep 1

# t=2.0 Super+P
notify-send -t 1800 "Key" "Super+P Play/Pause"
wtype -M logo -k p -m logo
sleep 2.5

# t=4.5 Super+P
notify-send -t 1800 "Key" "Super+P Play/Pause"
wtype -M logo -k p -m logo
sleep 3.0

# t=7.5 Super+K
notify-send -t 1800 "Key" "Super+K Seek +5s"
wtype -M logo -k k -m logo
sleep 2.5

# t=10.0 Super+J
notify-send -t 1800 "Key" "Super+J Seek -5s"
wtype -M logo -k j -m logo
sleep 3.0

# t=13.0 Super+O
notify-send -t 1800 "Key" "Super+O Volume +"
wtype -M logo -k o -m logo
sleep 2.5

# t=15.5 Super+O
notify-send -t 1800 "Key" "Super+O Volume +"
wtype -M logo -k o -m logo
sleep 2.5

# t=18.0 Super+I
notify-send -t 1800 "Key" "Super+I Volume -"
wtype -M logo -k i -m logo
sleep 3.0

# t=21.0 Super+V
notify-send -t 2200 "Key" "Super+V Wiremix peaks"
wtype -M logo -k v -m logo
sleep 4.0
kill_app wiremix

# t=25.0 Super+D
notify-send -t 2200 "Key" "Super+D Notifications"
wtype -M logo -k d -m logo
sleep 4.0
swaync-client -cp >/dev/null 2>&1 || true

# t=29.0 Super+Space
notify-send -t 2200 "Key" "Super+Space Launcher"
wtype -M logo -k space -m logo
sleep 3.0
pkill -x fuzzel >/dev/null 2>&1 || true

notify-send -t 2500 "Done" "swaymp overlay demo"
sleep 2

kill -INT "$REC" 2>/dev/null || true
sleep 3
mpc status >>"$LOG" 2>&1 || true
