#!/bin/bash
# Repeatable Pi5 music player setup (run as pi on the Pi).
# Payload = restore/ tree in this repo, scp'd to the Pi as /tmp/restore.tar.gz.
# Idempotent: re-running is safe.
set -u
PAYLOAD=${1:-/tmp/restore}

# --- packages ---
sudo rm -f /etc/apt/sources.list.d/mympd.list /etc/apt/trusted.gpg.d/mympd.asc
sudo apt-get update >/dev/null
sudo apt-get install -y mpd mpc mpdris2 snapclient wlogout sway-notification-center libnotify-bin jq gammastep >/dev/null

# myMPD from source (myMPD uses CMake; Debian has no package, GitHub has no deb assets).
if ! command -v mympd >/dev/null; then
    sudo apt-get install -y build-essential cmake pkg-config libmpdclient-dev libssl-dev >/dev/null
    [ -d "$HOME/src/myMPD" ] || git clone --depth 1 https://github.com/jcorporation/myMPD.git "$HOME/src/myMPD"
    cmake -S "$HOME/src/myMPD" -B "$HOME/src/myMPD/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build "$HOME/src/myMPD/build" -j "$(nproc)"
    sudo cmake --install "$HOME/src/myMPD/build"
fi

# --- configs from backup/payload (paths already rewritten to $HOME) ---
if [ -f /tmp/restore.tar.gz ]; then
    tar -C "$HOME" --strip-components=2 -xzf /tmp/restore.tar.gz
else
    for d in waybar mpd syncthing pipewire mympd sway fuzzel wlogout swaync foot; do
        cp -a "$PAYLOAD/home/pi/.config/$d" "$HOME/.config/"
    done
    cp -a "$PAYLOAD/home/pi/.config/systemd/user" "$HOME/.config/systemd/"
    cp -a "$PAYLOAD/home/pi/.cargo" "$HOME/"
fi
mkdir -p "$HOME/Music" "$HOME/Mixes" "$HOME/playlists"

# Keep the original image sway font.
sed -i 's/^font pango:monospace .*/font pango:monospace 1/' "$HOME/.config/sway/config"

# --- Euphonica flatpak ---
if ! command -v flatpak >/dev/null; then
    sudo apt-get install -y flatpak >/dev/null
fi
flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y --user flathub io.github.htkhiem.Euphonica || true
flatpak override --user --env=GSK_RENDERER=cairo --talk-name=org.freedesktop.Notifications --talk-name=org.freedesktop.portal.Desktop io.github.htkhiem.Euphonica >/dev/null 2>&1 || true

# The stock Pi image masks pipewire user units; the music player needs them.
# Masks exist in BOTH ~/.config/systemd/user and /etc/systemd/user.
for u in pipewire.service pipewire.socket pipewire-pulse.service pipewire-pulse.socket pulseaudio.service pulseaudio.socket wireplumber.service; do
    [ -L "$HOME/.config/systemd/user/$u" ] && rm "$HOME/.config/systemd/user/$u"
    [ -L "/etc/systemd/user/$u" ] && sudo rm "/etc/systemd/user/$u"
done

# --- sway: keyboard identity + generated binds + cheatsheet overlay ---
if ! grep -q "hackpi music player" "$HOME/.config/sway/config"; then
    bash "$HOME/.config/sway/generate-keys.sh"
    cat >> "$HOME/.config/sway/config" <<EOF

# --- hackpi music player (generated from keys.json) ---
input "16962:3:ZitaoTech_HackberryPi9900" {
    repeat_delay 300
    repeat_rate 35
}
default_border none
default_floating_border none
floating_minimum_size 420 x 240
floating_maximum_size 720 x 700
for_window [title="cheatsheet"] floating enable, border pixel 1
for_window [app_id="wiremix"] resize set height 320 px
include $HOME/.config/sway/generated.conf
EOF
else
    bash "$HOME/.config/sway/generate-keys.sh"
    if ! grep -q "^default_border none" "$HOME/.config/sway/config"; then
        echo "default_border none" >> "$HOME/.config/sway/config"
    fi
    if ! grep -q "^default_floating_border none" "$HOME/.config/sway/config"; then
        echo "default_floating_border none" >> "$HOME/.config/sway/config"
    fi
    if ! grep -q 'for_window \[app_id="wiremix"\]' "$HOME/.config/sway/config"; then
        echo 'for_window [app_id="wiremix"] resize set height 320 px' >> "$HOME/.config/sway/config"
    fi
fi

# Resolve base-config collisions with the music keybinds.
sed -i 's/^floating_maximum_size 800 x 500$/floating_maximum_size 720 x 700/' "$HOME/.config/sway/config"
sed -i 's/^    bindsym \$mod+\$down focus down/    #bindsym \$mod+$down focus down/' "$HOME/.config/sway/config"
sed -i 's/^    bindsym \$mod+\$up focus up/    #bindsym \$mod+$up focus up/' "$HOME/.config/sway/config"
sed -i 's/^    bindsym \$mod+s layout stacking/    #bindsym $mod+s layout stacking/' "$HOME/.config/sway/config"
sed -i 's/^    #bindsym \$mod+b splith/    bindsym $mod+b splith/' "$HOME/.config/sway/config"
sed -i 's/^    bindsym \$mod+v splitv/    #bindsym $mod+v splitv/' "$HOME/.config/sway/config"
sed -i 's/^bindsym \$mod+r mode "resize"/bindsym \$mod+Shift+r mode "resize"/' "$HOME/.config/sway/config"
if grep -q '^bindsym \$mod+Shift+r mode "default"' "$HOME/.config/sway/config"; then
    sed -i 's/^        bindsym \$mod+Shift+r mode "default"/        bindsym $mod+Shift+r mode "default"/' "$HOME/.config/sway/config"
fi

# Keep keys.json/generated.conf as the single source for music and cheatsheet keys.
sed -i 's/^    bindsym \$mod+p exec mpc toggle/    #bindsym $mod+p exec mpc toggle/' "$HOME/.config/sway/config"
sed -i 's/^bindsym \$mod+p exec mpc toggle/#bindsym $mod+p exec mpc toggle/' "$HOME/.config/sway/config"
sed -i 's/^    bindsym \$mod+i exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-/    #bindsym $mod+i exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-/' "$HOME/.config/sway/config"
sed -i 's/^bindsym \$mod+i exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-/#bindsym $mod+i exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-/' "$HOME/.config/sway/config"
sed -i 's/^    bindsym \$mod+o exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+/    #bindsym $mod+o exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+/' "$HOME/.config/sway/config"
sed -i 's/^bindsym \$mod+o exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+/#bindsym $mod+o exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+/' "$HOME/.config/sway/config"
sed -i 's/^    bindsym \$mod+m exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle/    #bindsym $mod+m exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle/' "$HOME/.config/sway/config"
sed -i 's/^bindsym \$mod+m exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle/#bindsym $mod+m exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle/' "$HOME/.config/sway/config"
sed -i "s/^    bindsym \$mod+n exec foot -o font='monospace:size=[0-9]*' -e \/home\/pi\/.cargo\/bin\/wiremix --peaks mono/    #bindsym \$mod+n exec foot -o font='monospace:size=18' -e \/home\/pi\/.cargo\/bin\/wiremix --peaks mono/" "$HOME/.config/sway/config"
sed -i "s/^bindsym \$mod+n exec foot -o font='monospace:size=[0-9]*' -e \/home\/pi\/.cargo\/bin\/wiremix --peaks mono/#bindsym \$mod+n exec foot -o font='monospace:size=18' -e \/home\/pi\/.cargo\/bin\/wiremix --peaks mono/" "$HOME/.config/sway/config"
sed -i 's/^bindsym F13 exec \/home\/pi\/.config\/sway\/cheatsheet.sh/#bindsym F13 exec \/home\/pi\/.config\/sway\/cheatsheet.sh/' "$HOME/.config/sway/config"

# Start Euphonica when sway starts.
if grep -q "exec flatpak --user run io.github.htkhiem.Euphonica" "$HOME/.config/sway/config"; then
    sed -i "s|exec flatpak --user run io.github.htkhiem.Euphonica|exec flatpak --user run --env=GSK_RENDERER=cairo io.github.htkhiem.Euphonica|" "$HOME/.config/sway/config"
elif ! grep -q "--env=GSK_RENDERER=cairo io.github.htkhiem.Euphonica" "$HOME/.config/sway/config"; then
    echo "exec swaymsg 'workspace \"1:Music\"; exec flatpak --user run --env=GSK_RENDERER=cairo io.github.htkhiem.Euphonica'" >> "$HOME/.config/sway/config"
fi

# Ensure waybar is the only bar and title bars are hidden.
if ! grep -q "^set \$mod" "$HOME/.config/sway/config"; then
    echo "set \$mod Mod4" >> "$HOME/.config/sway/config"
fi
if ! grep -q "^font pango:monospace" "$HOME/.config/sway/config"; then
    echo "font pango:monospace 1" >> "$HOME/.config/sway/config"
fi
if ! grep -q "^titlebar_border_thickness" "$HOME/.config/sway/config"; then
    echo "titlebar_border_thickness 0" >> "$HOME/.config/sway/config"
fi
if ! grep -q "^titlebar_padding" "$HOME/.config/sway/config"; then
    echo "titlebar_padding 0" >> "$HOME/.config/sway/config"
fi
if grep -q "^bar {" "$HOME/.config/sway/config"; then
    sed -i '/^bar {/,/^}/ s/^/#/g' "$HOME/.config/sway/config"
fi
if ! grep -q "^exec --no-startup-id waybar" "$HOME/.config/sway/config"; then
    echo "exec --no-startup-id waybar" >> "$HOME/.config/sway/config"
fi
# Start swaync via sway: the unit's graphical-session.target WantedBy never
# activates on this image, so an enabled unit alone leaves notifications dead.
if ! grep -q "^exec --no-startup-id systemctl --user start swaync.service" "$HOME/.config/sway/config"; then
    echo "exec --no-startup-id systemctl --user start swaync.service" >> "$HOME/.config/sway/config"
fi
# Software brightness tool (brightness.py + gammastep) is installed but has no
# keybind; run it manually if needed. The panel backlight is on/off only.

# --- user services ---
chmod +x "$HOME/.config/sway/notifications.sh"
chmod +x "$HOME/.config/sway/cheatsheet.sh"
chmod +x "$HOME/.config/sway/wiremix.sh"
chmod +x "$HOME/.config/sway/brightness.py"
systemctl --user disable --now dunst.service >/dev/null 2>&1 || true
rm -f "$HOME/.config/systemd/user/dunst.service"
systemctl --user disable --now mpd-notify.service >/dev/null 2>&1 || true
rm -f "$HOME/.config/systemd/user/mpd-notify.service"
rm -f "$HOME/.config/waybar/mpd-notify.sh"
systemctl --user daemon-reload
systemctl --user enable mpd.service mympd.service syncthing.service snapclient.service \
    pipewire.service pipewire-pulse.service wireplumber.service \
    swaync.service >/dev/null
systemctl --user restart swaync.service
systemctl --user start pipewire.service pipewire-pulse.service wireplumber.service \
    mpd.service mympd.service syncthing.service snapclient.service

# VIAL keymap note: the custom Hackberry layout lives on the keyboard MCU.
# Snapshot it to a .vil file in this repo before reflashing firmware; F13 is a
# VIAL-side binding that sends F13 when pressed.
swaymsg reload 2>/dev/null
pkill -USR1 -x waybar 2>/dev/null
echo "setup complete"
