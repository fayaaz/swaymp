#!/bin/bash
# Repeatable Pi5 music player setup (run as the target non-root user on the Pi).
# Payload = files/ tree in this repo (fresh-setup payload, not a snapshot restore),
# scp'd to the Pi as /tmp/setup.tar.gz.
# Idempotent: re-running is safe.
set -u
PAYLOAD=${1:-/tmp/files}

# --- packages ---
sudo rm -f /etc/apt/sources.list.d/mympd.list /etc/apt/trusted.gpg.d/mympd.asc
sudo apt-get update >/dev/null
sudo apt-get install -y sway waybar foot fuzzel swayimg imv syncthing pipewire pipewire-pulse wireplumber \
    fonts-jetbrains-mono fonts-font-awesome mpd mpc mpdris2 snapclient wlogout sway-notification-center libnotify-bin jq gammastep \
    bluez-tools rfkill udevil network-manager network-manager-applet curl >/dev/null
# Cheatsheet overlay viewer (GTK3 transparent window).
sudo apt-get install -y python3-gi gir1.2-gtk-3.0 >/dev/null

# Bluetooth audio (PipeWire plays through paired devices): daemon on,
# user in the bluetooth group (re-login to take effect).
sudo systemctl enable --now bluetooth.service >/dev/null 2>&1 || true
sudo usermod -aG bluetooth "$USER" 2>/dev/null || true
sudo rfkill unblock bluetooth >/dev/null 2>&1 || true

# Network UI is the nmtui TUI (~/.config/sway/network.sh, waybar button / $mod+n).
# network-manager-applet stays installed (it is what pulls in nmtui alongside
# network-manager) but the sway config no longer autostarts the tray applet.
sudo systemctl enable --now NetworkManager >/dev/null 2>&1 || true

# bluetuith (TUI bluetooth manager, $mod+b): not packaged for Debian/Raspbian
# and the repo keeps no binaries, so fetch the GitHub release tarball for this
# architecture and verify it against the release checksums. Falls back to
# bluetoothctl in ~/.config/sway/bluetooth.sh when this step fails.
btver=0.2.7
if ! command -v bluetuith >/dev/null && [ ! -x "$HOME/.local/bin/bluetuith" ]; then
    case "$(uname -m)" in
        aarch64|arm64) btarch=arm64 ;;
        armv7l|armhf)  btarch=armv7 ;;
        x86_64)        btarch=x86_64 ;;
        *)             btarch="" ;;
    esac
    if [ -n "$btarch" ]; then
        btname=bluetuith_${btver}_Linux_${btarch}.tar.gz
        btbase=https://github.com/bluetuith-org/bluetuith/releases/download/v${btver}
        mkdir -p "$HOME/.local/bin"
        if curl -fsSL -o "/tmp/$btname" "$btbase/$btname" \
            && curl -fsSL "$btbase/checksums.txt" | grep " ${btname}\$" | (cd /tmp && sha256sum -c) \
            && tar -C /tmp -xzf "/tmp/$btname" \
            && install -m 755 /tmp/bluetuith "$HOME/.local/bin/bluetuith"; then
            echo "installed bluetuith $btver ($btarch) -> ~/.local/bin/bluetuith"
        else
            echo "WARNING: bluetuith install failed; the bluetooth UI falls back to bluetoothctl" >&2
        fi
        rm -f "/tmp/$btname" /tmp/bluetuith
    fi
fi

# myMPD from source (myMPD uses CMake; Debian has no package, GitHub has no deb assets).
if ! command -v mympd >/dev/null; then
    sudo apt-get install -y build-essential cmake pkg-config libmpdclient-dev libssl-dev >/dev/null
    [ -d "$HOME/src/myMPD" ] || git clone --depth 1 https://github.com/jcorporation/myMPD.git "$HOME/src/myMPD"
    cmake -S "$HOME/src/myMPD" -B "$HOME/src/myMPD/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build "$HOME/src/myMPD/build" -j "$(nproc)"
    sudo cmake --install "$HOME/src/myMPD/build"
fi

# --- configs from payload (template payload; no path rewriting) ---
if [ -f /tmp/setup.tar.gz ]; then
    tar -C "$HOME" --strip-components=2 -xzf /tmp/setup.tar.gz
else
    for d in waybar mpd syncthing pipewire mympd sway fuzzel wlogout swaync foot bluetuith; do
        cp -a "$PAYLOAD/home/pi/.config/$d" "$HOME/.config/"
    done
    cp -a "$PAYLOAD/home/pi/.config/systemd/user" "$HOME/.config/systemd/"
    cp -a "$PAYLOAD/home/pi/.cargo" "$HOME/"
    cp -a "$PAYLOAD/home/pi/wallpaper" "$HOME/"
fi
mkdir -p "$HOME/Music" "$HOME/Mixes" "$HOME/playlists"

# The payload is a template, not a /home/pi snapshot. Text configs use ~, $HOME,
# systemd %h/%t, or $XDG_RUNTIME_DIR so they work for whichever non-root user runs
# this script. Run setup-pi.sh as the target user: configs and user services are per-user.
# sway expands ~ and shell syntax (wordexp) in include/exec/output paths, so the
# sway config below needs no path rewriting either.

# --- sway config (payload-owned; no sed patching of /etc/sway/config) ---
# files/home/pi/.config/sway/config is the single source of truth: stock binds
# are vendored trimmed for the Hackberry, and music/cheatsheet binds are generated
# from keys.json and included last. The payload copy above already installed it.

# The payload ships the wallpaper (~/wallpaper/wallpaper.jpg - Unsplash photo by
# Daniel Olah, Unsplash license; see wallpaper.attribution.txt). sway references it
# as ~/wallpaper/wallpaper.jpg and errors on a missing file, so it must be deployed.

# Regenerate binds + cheatsheet from keys.json (single source of truth).
bash "$HOME/.config/sway/generate-keys.sh"

# Validate the assembled config before any reload.
if ! sway -C -c "$HOME/.config/sway/config" 2>/dev/null; then
    echo "WARNING: sway config validation failed; check ~/.config/sway/config" >&2
fi

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

# Everything sway-related (keyboard identity, generated binds, cheatsheet/foot/
# bluetooth/imv/wiremix window rules, Dracula theme, workspace assigns, waybar +
# swaync + Euphonica autostart, resize mode on $mod+Shift+r, collision-free stock
# binds) now lives in the payload config and is validated above. Nothing to patch.

# --- user services ---
chmod +x "$HOME/.config/sway/notifications.sh"
chmod +x "$HOME/.config/sway/device.sh"
chmod +x "$HOME/.config/sway/cheatsheet.sh"
chmod +x "$HOME/.config/sway/cheatsheet-svg.py"
chmod +x "$HOME/.config/sway/cheatsheet-viewer.py"
chmod +x "$HOME/.config/sway/wiremix.sh"
chmod +x "$HOME/.config/sway/browser.sh"
chmod +x "$HOME/.config/sway/bluetooth.sh"
chmod +x "$HOME/.config/sway/network.sh"
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

# MPD -> MPRIS bridge: swaync's miniplayer (mpris widget) reads MPD off the
# session bus, so the distro-provided user unit must be enabled and running.
mpdris_unit=$(systemctl --user list-unit-files --no-legend 2>/dev/null | awk 'tolower($1) ~ /mpdris/ {print $1; exit}')
[ -n "$mpdris_unit" ] || mpdris_unit=mpDris2.service
systemctl --user enable "$mpdris_unit" >/dev/null 2>&1 || true
systemctl --user restart "$mpdris_unit" >/dev/null 2>&1 || true

# VIAL keymap note: the custom Hackberry layout lives on the keyboard MCU.
# Snapshot it to a .vil file in this repo before reflashing firmware; F13 is a
# VIAL-side binding that sends F13 when pressed.
swaymsg reload 2>/dev/null
pkill -USR1 -x waybar 2>/dev/null
echo "setup complete"
