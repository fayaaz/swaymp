#!/bin/bash
# Repeatable Pi5 music player setup (run as the target non-root user on the Pi).
# Payload = restore/ tree in this repo, scp'd to the Pi as /tmp/restore.tar.gz.
# Idempotent: re-running is safe.
set -u
PAYLOAD=${1:-/tmp/restore}

# --- packages ---
sudo rm -f /etc/apt/sources.list.d/mympd.list /etc/apt/trusted.gpg.d/mympd.asc
sudo apt-get update >/dev/null
sudo apt-get install -y sway waybar foot fuzzel swayimg imv syncthing pipewire pipewire-pulse wireplumber \
    fonts-jetbrains-mono fonts-font-awesome mpd mpc mpdris2 snapclient wlogout sway-notification-center libnotify-bin jq gammastep \
    bluez-tools rfkill >/dev/null
# Cheatsheet overlay viewer (GTK3 transparent window).
sudo apt-get install -y python3-gi gir1.2-gtk-3.0 >/dev/null

# Bluetooth audio (PipeWire plays through paired devices): daemon on,
# user in the bluetooth group (re-login to take effect).
sudo systemctl enable --now bluetooth.service >/dev/null 2>&1 || true
sudo usermod -aG bluetooth "$USER" 2>/dev/null || true
sudo rfkill unblock bluetooth >/dev/null 2>&1 || true

# myMPD from source (myMPD uses CMake; Debian has no package, GitHub has no deb assets).
if ! command -v mympd >/dev/null; then
    sudo apt-get install -y build-essential cmake pkg-config libmpdclient-dev libssl-dev >/dev/null
    [ -d "$HOME/src/myMPD" ] || git clone --depth 1 https://github.com/jcorporation/myMPD.git "$HOME/src/myMPD"
    cmake -S "$HOME/src/myMPD" -B "$HOME/src/myMPD/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build "$HOME/src/myMPD/build" -j "$(nproc)"
    sudo cmake --install "$HOME/src/myMPD/build"
fi

# --- configs from payload (template payload; no path rewriting) ---
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

# The payload is a template, not a /home/pi snapshot. Text configs use ~, $HOME,
# systemd %h/%t, or $XDG_RUNTIME_DIR so they work for whichever non-root user runs
# this script. Run setup-pi.sh as the target user: configs and user services are per-user.

# Seed the stock sway config if the payload does not provide one. sway's user config
# overrides /etc/sway/config, so without this the hackpi block would be the whole config.
mkdir -p "$HOME/.config/sway"
if [ ! -f "$HOME/.config/sway/config" ]; then
    if [ -f /etc/sway/config ]; then
        cp /etc/sway/config "$HOME/.config/sway/config"
    else
        cat > "$HOME/.config/sway/config" <<'EOF'
set $mod Mod4
font pango:monospace 1
EOF
    fi
fi

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
default_border pixel 1
default_floating_border pixel 1
floating_minimum_size 420 x 240
floating_maximum_size 720 x 700
for_window [app_id="cheatsheet"] floating enable, resize set 700 520, move position 10 57, border none
for_window [app_id="wiremix"] resize set height 320 px
client.focused #bd93f9 #bd93f9 #282a36 #bd93f9 #bd93f9
client.focused_inactive #6272a4 #6272a4 #f8f8f2 #6272a4 #6272a4
client.unfocused #44475a #44475a #f8f8f2 #44475a #44475a
client.urgent #ff5555 #ff5555 #f8f8f2 #ff5555 #ff5555
client.placeholder #44475a #44475a #f8f8f2 #44475a #44475a
client.background #282a36
include $HOME/.config/sway/generated.conf
EOF
else
    bash "$HOME/.config/sway/generate-keys.sh"
    sed -i 's/^default_border none$/default_border pixel 1/' "$HOME/.config/sway/config"
    sed -i 's/^default_floating_border none$/default_floating_border pixel 1/' "$HOME/.config/sway/config"
    if ! grep -q "^default_border pixel 1" "$HOME/.config/sway/config"; then
        echo "default_border pixel 1" >> "$HOME/.config/sway/config"
    fi
    if ! grep -q "^default_floating_border pixel 1" "$HOME/.config/sway/config"; then
        echo "default_floating_border pixel 1" >> "$HOME/.config/sway/config"
    fi
    if ! grep -q 'for_window \[app_id="wiremix"\]' "$HOME/.config/sway/config"; then
        echo 'for_window [app_id="wiremix"] resize set height 320 px' >> "$HOME/.config/sway/config"
    fi
    if ! grep -q "^client.focused" "$HOME/.config/sway/config"; then
        cat >> "$HOME/.config/sway/config" <<EOF
client.focused #bd93f9 #bd93f9 #282a36 #bd93f9 #bd93f9
client.focused_inactive #6272a4 #6272a4 #f8f8f2 #6272a4 #6272a4
client.unfocused #44475a #44475a #f8f8f2 #44475a #44475a
client.urgent #ff5555 #ff5555 #f8f8f2 #ff5555 #ff5555
client.placeholder #44475a #44475a #f8f8f2 #44475a #44475a
client.background #282a36
EOF
    fi
fi

# Resolve base-config collisions with the music keybinds.
sed -i 's/^floating_maximum_size 800 x 500$/floating_maximum_size 720 x 700/' "$HOME/.config/sway/config"
sed -i 's/^    bindsym \$mod+\$down focus down/    #bindsym \$mod+$down focus down/' "$HOME/.config/sway/config"
sed -i 's/^    bindsym \$mod+\$up focus up/    #bindsym \$mod+$up focus up/' "$HOME/.config/sway/config"
sed -i 's/^    bindsym \$mod+s layout stacking/    #bindsym $mod+s layout stacking/' "$HOME/.config/sway/config"
sed -i 's/^    #bindsym \$mod+b splith/    bindsym $mod+b splith/' "$HOME/.config/sway/config"
sed -i 's/^    bindsym \$mod+v splitv/    #bindsym $mod+v splitv/' "$HOME/.config/sway/config"
# The Hackberry dollar key sends Shift+4, and shifted numbers are a trap
# on this keyboard generally, so all stock move-to-workspace binds go.
# Viewing workspaces via $mod+w/e/3..0 still works; only the moves are
# sacrificed (like $mod+v). Euphonica owns $mod+Shift+4 now.
sed -i 's/^\([[:space:]]*\)\(bindsym \$mod+Shift+[0-9] move container to workspace number\)/\1#\2/' "$HOME/.config/sway/config"

# Cheatsheet overlay geometry: for_window move is relative to the workspace
# content origin (below waybar, y=43), so 10,57 lands at absolute 10,100.
# cheatsheet-viewer.py is a transparent GTK window with app_id cheatsheet;
# the rule below does all sizing and placement.
sed -i 's/^for_window \[title="cheatsheet"\].*/for_window [app_id="cheatsheet"] floating enable, resize set 700 520, move position 10 57, border none/' "$HOME/.config/sway/config"
sed -i 's/^for_window \[app_id="cheatsheet"\].*/for_window [app_id="cheatsheet"] floating enable, resize set 700 520, move position 10 57, border none/' "$HOME/.config/sway/config"
sed -i 's/^for_window \[app_id="imv"\].*/for_window [app_id="imv"] floating enable, resize set 700 520, move position 10 100, border none/' "$HOME/.config/sway/config"
if ! grep -q '^for_window \[app_id="imv"\]' "$HOME/.config/sway/config"; then
    echo 'for_window [app_id="imv"] floating enable, resize set 700 520, move position 10 100, border none' >> "$HOME/.config/sway/config"
fi
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
sed -i 's/^    bindsym \$mod+space exec \$menu/    #bindsym $mod+space exec $menu/' "$HOME/.config/sway/config"
sed -i 's/^bindsym \$mod+space exec \$menu/#bindsym $mod+space exec $menu/' "$HOME/.config/sway/config"

# Terminal is bound from keys.json as $mod+tab; disable the stock terminal/Tab binds.
sed -i 's/^    bindsym \$mod+return exec \$term/    #bindsym $mod+return exec $term/' "$HOME/.config/sway/config"
sed -i 's/^bindsym \$mod+return exec \$term/#bindsym $mod+return exec $term/' "$HOME/.config/sway/config"
sed -i 's/^    bindsym \$mod+Return exec \$term/    #bindsym $mod+Return exec $term/' "$HOME/.config/sway/config"
sed -i 's/^bindsym \$mod+Return exec \$term/#bindsym $mod+Return exec $term/' "$HOME/.config/sway/config"
sed -i 's/^    bindsym \$mod+Tab workspace next/    #bindsym $mod+Tab workspace next/' "$HOME/.config/sway/config"
sed -i 's/^bindsym \$mod+Tab workspace next/#bindsym $mod+Tab workspace next/' "$HOME/.config/sway/config"

# Floating centered terminal (foot background alpha is set in foot.ini).
if ! grep -q '^for_window \[app_id="foot"\]' "$HOME/.config/sway/config"; then
    echo 'for_window [app_id="foot"] floating enable, resize set 640 480, move position center, border none' >> "$HOME/.config/sway/config"
fi

# Floating centered bluetooth manager (same geometry as the terminal).
if ! grep -q '^for_window \[app_id="bluetooth"\]' "$HOME/.config/sway/config"; then
    echo 'for_window [app_id="bluetooth"] floating enable, resize set 640 480, move position center, border none' >> "$HOME/.config/sway/config"
fi

# Start Euphonica when sway starts.
if grep -q "exec flatpak --user run io.github.htkhiem.Euphonica" "$HOME/.config/sway/config"; then
    sed -i "s|exec flatpak --user run io.github.htkhiem.Euphonica|exec flatpak --user run --env=GSK_RENDERER=cairo io.github.htkhiem.Euphonica|" "$HOME/.config/sway/config"
elif ! grep -q "--env=GSK_RENDERER=cairo io.github.htkhiem.Euphonica" "$HOME/.config/sway/config"; then
    echo "exec swaymsg 'workspace \"1:Music\"; exec flatpak --user run --env=GSK_RENDERER=cairo io.github.htkhiem.Euphonica'" >> "$HOME/.config/sway/config"
fi

# Workspace placement: music player + wiremix on 1:Music, browser on
# 2:Browser. The terminal always opens floating on the current workspace.
# The launcher helpers (*.sh) switch to the right workspace before launching.
for _rule in \
    'assign [app_id="io.github.htkhiem.Euphonica"] "1:Music"' \
    'assign [app_id="wiremix"] "1:Music"' \
    'assign [app_id="firefox"] "2:Browser"'; do
    grep -Fq "$_rule" "$HOME/.config/sway/config" || echo "$_rule" >> "$HOME/.config/sway/config"
done
unset _rule

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
chmod +x "$HOME/.config/sway/cheatsheet-svg.py"
chmod +x "$HOME/.config/sway/cheatsheet-viewer.py"
chmod +x "$HOME/.config/sway/wiremix.sh"
chmod +x "$HOME/.config/sway/browser.sh"
chmod +x "$HOME/.config/sway/bluetooth.sh"
chmod +x "$HOME/.config/sway/volume.sh"
chmod +x "$HOME/.config/sway/volume-notify.sh"
chmod +x "$HOME/.config/sway/brightness.py"
systemctl --user disable --now dunst.service >/dev/null 2>&1 || true
rm -f "$HOME/.config/systemd/user/dunst.service"
systemctl --user disable --now mpd-notify.service >/dev/null 2>&1 || true
rm -f "$HOME/.config/systemd/user/mpd-notify.service"
rm -f "$HOME/.config/waybar/mpd-notify.sh"
systemctl --user daemon-reload
systemctl --user enable mpd.service mympd.service syncthing.service snapclient.service \
    pipewire.service pipewire-pulse.service wireplumber.service \
    swaync.service volume-notify.service >/dev/null
systemctl --user restart swaync.service
systemctl --user start pipewire.service pipewire-pulse.service wireplumber.service \
    mpd.service mympd.service syncthing.service snapclient.service
systemctl --user restart volume-notify.service

# VIAL keymap note: the custom Hackberry layout lives on the keyboard MCU.
# Snapshot it to a .vil file in this repo before reflashing firmware; F13 is a
# VIAL-side binding that sends F13 when pressed.
swaymsg reload 2>/dev/null
pkill -USR1 -x waybar 2>/dev/null
echo "setup complete"
