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
    fonts-jetbrains-mono fonts-font-awesome mpd mpc mpdris2 snapserver python3 avahi-utils \
    wlogout libnotify-bin jq gammastep \
    bluez-tools rfkill udevil network-manager network-manager-applet curl >/dev/null
# Cheatsheet overlay viewer (GTK3 transparent window).
sudo apt-get install -y python3-gi gir1.2-gtk-3.0 >/dev/null

# snapclient with the PipeWire player: Debian trixie's 0.31 is built without it
# ("No audio player support for: pipewire"), which only surfaces once the
# client connects to a server. Install the pinned upstream with-pipewire .deb
# (checksum = GitHub release asset digest). There is deliberately no distro
# fallback: a failure aborts setup instead of drifting to a client that cannot
# play through PipeWire.
scver=0.35.0
if ! snapclient --version 2>/dev/null | grep -q "v$scver"; then
    case "$(uname -m)" in
        aarch64|arm64) scarch=arm64; scsha=6ed5573c59cbf457a04bc8b4b972e42e66219f14ba586f6f357de48730f7bc1e ;;
        armv7l|armhf)  scarch=armhf; scsha=d4cc565f6dfe621d89c88efc3147f60676fecd53b7e5dfa4afba9a8648194728 ;;
        x86_64)        scarch=amd64; scsha=05e112410c536199181adae50419801d2e155afa53493cb80b7420854ecb0375 ;;
        *)             scarch="" ;;
    esac
    if [ -z "$scarch" ]; then
        echo "ERROR: no pinned snapclient $scver build for $(uname -m); aborting" >&2
        exit 1
    fi
    scdeb=snapclient_${scver}-1_${scarch}_trixie_with-pipewire.deb
    scbase=https://github.com/badaix/snapcast/releases/download/v${scver}
    if curl -fsSL -o "/tmp/$scdeb" "$scbase/$scdeb" \
        && echo "$scsha  /tmp/$scdeb" | sha256sum -c >/dev/null 2>&1 \
        && sudo apt-get install -y -o Dpkg::Options::="--force-confold" "/tmp/$scdeb" >/dev/null; then
        rm -f "/tmp/$scdeb"
        echo "installed snapclient $scver ($scarch, pipewire player)"
    else
        rm -f "/tmp/$scdeb"
        echo "ERROR: failed to install snapclient $scver ($scarch, with-pipewire); aborting" >&2
        exit 1
    fi
fi

# Multiroom audio (Snapcast) is payload-owned: user snapserver.service is
# started on demand by audio-mode.sh, user snapclient.service plays through
# PipeWire. The distro SYSTEM units must be off:
#  - system snapclient runs as _snapclient with ALSA and would double-play
#    alongside the payload user snapclient;
#  - system snapserver would own ports 1704/1780 and create a
#    snapserver-owned /tmp/snapfifo (fs.protected_fifos then blocks MPD).
sudo systemctl disable --now snapclient.service >/dev/null 2>&1 || true
sudo systemctl disable --now snapserver.service >/dev/null 2>&1 || true
sudo rm -f /tmp/snapfifo

# Bluetooth audio (PipeWire plays through paired devices): daemon on,
# user in the bluetooth group (re-login to take effect).
sudo systemctl enable --now bluetooth.service >/dev/null 2>&1 || true
sudo usermod -aG bluetooth "$USER" 2>/dev/null || true
sudo rfkill unblock bluetooth >/dev/null 2>&1 || true

# Network UI is wifitui (https://github.com/shazow/wifitui), a NetworkManager
# wifi TUI (~/.config/sway/network.sh, waybar button / $mod+n).
# network-manager + network-manager-applet stay installed: NetworkManager is the
# backend wifitui talks to over D-Bus, and nmtui (from network-manager) is the
# fallback. The sway config no longer autostarts the tray applet.
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

# wifitui (wifi TUI, $mod+n / waybar network button): not packaged for
# Debian/Raspbian and the repo keeps no binaries, so fetch the pinned GitHub
# release tarball for this architecture and verify it against the release
# checksums. ~/.config/sway/network.sh falls back to nmtui when this fails
# (the release ships no 32-bit arm asset).
wfver=0.13.0
if ! command -v wifitui >/dev/null && [ ! -x "$HOME/.local/bin/wifitui" ]; then
    case "$(uname -m)" in
        aarch64|arm64) wfarch=arm64 ;;
        x86_64)        wfarch=x86_64 ;;
        *)             wfarch="" ;;
    esac
    if [ -n "$wfarch" ]; then
        wfname=wifitui-${wfver}-linux-${wfarch}.tar.gz
        wfbase=https://github.com/shazow/wifitui/releases/download/v${wfver}
        wftmp=$(mktemp -d)
        mkdir -p "$HOME/.local/bin"
        if curl -fsSL -o "$wftmp/$wfname" "$wfbase/$wfname" \
            && curl -fsSL -o "$wftmp/wifitui_${wfver}_checksums.txt" "$wfbase/wifitui_${wfver}_checksums.txt" \
            && (cd "$wftmp" && grep " ${wfname}\$" "wifitui_${wfver}_checksums.txt" | sha256sum -c) \
            && tar -C "$wftmp" -xzf "$wftmp/$wfname" \
            && install -m 755 "$wftmp/wifitui" "$HOME/.local/bin/wifitui"; then
            echo "installed wifitui $wfver ($wfarch) -> ~/.local/bin/wifitui"
        else
            echo "WARNING: wifitui install failed; the network UI falls back to nmtui" >&2
        fi
        rm -rf "$wftmp"
    fi
fi

# snapweb (snapserver's phone UI on :1780): Debian trixie has no snapweb
# package; the snapserver package ships only a placeholder index.html at
# snapserver's default doc_root. Install the pinned upstream release there
# (checksum-verified, same pattern as bluetuith/wifitui); manifest.webmanifest
# marks the real build. Optional: a failure only means no phone UI.
swver=0.9.3
swsha=cc258df98b8c474ea19048bc84c0c2e2c5fbc3b0856aef03a838f3a4489fa4c7
if [ ! -f /usr/share/snapserver/snapweb/manifest.webmanifest ]; then
    swtmp=$(mktemp -d)
    if curl -fsSL -o "$swtmp/snapweb.zip" \
            "https://github.com/snapcast/snapweb/releases/download/v${swver}/snapweb.zip" \
        && echo "$swsha  $swtmp/snapweb.zip" | sha256sum -c >/dev/null 2>&1 \
        && (command -v unzip >/dev/null || sudo apt-get install -y unzip >/dev/null) \
        && unzip -q "$swtmp/snapweb.zip" -d "$swtmp/web" \
        && sudo mkdir -p /usr/share/snapserver/snapweb \
        && sudo cp -a "$swtmp/web/." /usr/share/snapserver/snapweb/; then
        echo "installed snapweb $swver -> /usr/share/snapserver/snapweb"
    else
        echo "WARNING: snapweb install failed; snapserver still streams (no phone UI)" >&2
    fi
    rm -rf "$swtmp"
fi

# myMPD from source (myMPD uses CMake; Debian has no package, GitHub has no deb assets).
if ! command -v mympd >/dev/null; then
    sudo apt-get install -y build-essential cmake pkg-config libmpdclient-dev libssl-dev >/dev/null
    [ -d "$HOME/src/myMPD" ] || git clone --depth 1 https://github.com/jcorporation/myMPD.git "$HOME/src/myMPD"
    cmake -S "$HOME/src/myMPD" -B "$HOME/src/myMPD/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build "$HOME/src/myMPD/build" -j "$(nproc)"
    sudo cmake --install "$HOME/src/myMPD/build"
fi

# swaync from source: Debian ships only 0.11.0 (GTK3), whose mpris widget makes
# synchronous D-Bus calls that deadlock with mpdris2 on every song skip. 0.12.6
# (GTK4 rewrite) makes them async and honors the payload's 0.12-only mpris keys.
if ! swaync --version 2>/dev/null | grep -q " 0\.12"; then
    sudo apt-get install -y valac libgtk-4-dev libadwaita-1-dev libgtk4-layer-shell-dev \
        libgee-0.8-dev libjson-glib-dev libgranite-7-dev libwayland-dev wayland-protocols \
        scdoc sassc blueprint-compiler >/dev/null
    sudo apt-get remove -y sway-notification-center >/dev/null 2>&1 || true
    mkdir -p "$HOME/src"
    if [ ! -f "$HOME/src/swaync-0.12.6.tar.gz" ] \
        && ! curl -fsSL -o "$HOME/src/swaync-0.12.6.tar.gz" \
            https://github.com/ErikReider/SwayNotificationCenter/archive/refs/tags/v0.12.6.tar.gz; then
        echo "WARNING: swaync download failed; notification daemon will be missing" >&2
    elif echo "0c844eb5c9524f924495bd4145e5db575096de36f3ec87fb37e4c1ed6eacb897  $HOME/src/swaync-0.12.6.tar.gz" | sha256sum -c >/dev/null 2>&1; then
        [ -d "$HOME/src/SwayNotificationCenter-0.12.6" ] || tar -C "$HOME/src" -xzf "$HOME/src/swaync-0.12.6.tar.gz"
        meson setup "$HOME/src/SwayNotificationCenter-0.12.6/build" "$HOME/src/SwayNotificationCenter-0.12.6" \
            --prefix=/usr -Dpulse-audio=false >/dev/null || true
        ninja -C "$HOME/src/SwayNotificationCenter-0.12.6/build"
        sudo ninja -C "$HOME/src/SwayNotificationCenter-0.12.6/build" install >/dev/null
    else
        echo "WARNING: swaync tarball checksum mismatch; not building" >&2
    fi
fi

# --- configs from payload (template payload; no path rewriting) ---
if [ -f /tmp/setup.tar.gz ]; then
    tar -C "$HOME" --strip-components=2 -xzf /tmp/setup.tar.gz
else
    for d in waybar mpd syncthing pipewire mympd sway fuzzel wlogout swaync foot bluetuith wifitui mpDris2 snapserver snapclient; do
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
chmod +x "$HOME/.config/sway/audio-mode.sh"
systemctl --user disable --now dunst.service >/dev/null 2>&1 || true
rm -f "$HOME/.config/systemd/user/dunst.service"
systemctl --user disable --now mpd-notify.service >/dev/null 2>&1 || true
rm -f "$HOME/.config/systemd/user/mpd-notify.service"
rm -f "$HOME/.config/waybar/mpd-notify.sh"
systemctl --user daemon-reload
# snapserver.service is deliberately NOT enabled: it must only ever be started
# on demand by audio-mode.sh (Broadcast/Group); audio-mode-restore.service may
# start it at boot solely to restore a saved Broadcast/Group mode.
systemctl --user enable mpd.service mympd.service syncthing.service snapclient.service \
    pipewire.service pipewire-pulse.service wireplumber.service \
    swaync.service volume-notify.service audio-mode-restore.service >/dev/null
systemctl --user restart swaync.service
systemctl --user start pipewire.service pipewire-pulse.service wireplumber.service \
    mpd.service mympd.service syncthing.service snapclient.service
# `start` is a no-op on a running MPD, so re-runs would not pick up mpd.conf
# changes (the Multiroom fifo output) without an explicit restart.
systemctl --user restart mpd.service
systemctl --user restart volume-notify.service
# Apply the saved (or default off) audio mode now, so a fresh deploy does not
# leave snapclient running in discovery until the next boot.
systemctl --user start audio-mode-restore.service >/dev/null 2>&1 || true

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
