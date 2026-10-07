# AGENTS.md

This repo is not an app codebase. It is the restore payload + repeatable setup script for a Hackberry Pi music player (MPD + myMPD + sway + waybar + PipeWire + snapclient + Euphonica flatpak).

## Layout & source of truth
- `setup-pi.sh` is the deploy entrypoint. Run **on the Pi as user `pi`** with the `restore/` tree tarred to `/tmp/restore.tar.gz` on the Pi (payload extracted with `tar --strip-components-2` into `$HOME`). It is idempotent.
- `restore/home/pi/` is the authoritative payload (paths assume `/home/pi`, so keep new files under `home/pi/`). `hackpi-backup/` and `hackpi-full-backup/` are raw snapshots of the running Pi for reference; do not treat them as the deploy source.
- `wiremix` in `restore/home/pi/.cargo/bin` is a prebuilt aarch64 binary — there is no source in this repo; don't attempt to rebuild it here. It is **gitignored** (repo keeps no binaries), so a fresh deploy needs the binary supplied separately.
- `.gitignore` keeps raw Pi snapshots (`hackpi-backup/`, `hackpi-full-backup/`, `*.tar.gz`), runtime caches (`mpd/tag_cache`, `mympd/tags`, `syncthing/index-*.db`), and all private keys/certs (`*.pem`, `*.key`, `mympd/ssl`, `pin_hash`) out of the repo. Consequence: a redeploy regenerates syncthing/mympd certs, so the syncthing device ID changes and pairing must be redone.

## Quirks an agent will miss
- **Keybinds**: `restore/home/pi/.config/sway/keys.json` is the single source of truth. Edit `keys.json`, then run `generate-keys.sh` (requires `jq` and `python3`) to regenerate `generated.conf` + `cheatsheet.txt` + `cheatsheet.svg`; never hand-edit `generated.conf`. `setup-pi.sh` comments out conflicting binds in the base sway config, so music keys live only in `keys.json`.
- `keys.json` commands hardcode `/home/pi/...` paths, and `cheatsheet.sh` reads the sway IPC socket from `/run/user/1000` (uid 1000 = `pi`). These only work on the Pi's `pi` user.
- **F13 is bound on the keyboard MCU** (custom VIAL layout on the Hackberry keyboard). Re-flashing firmware loses it; snapshot the `.vil` file first. F13 triggers `cheatsheet.sh` (toggles a floating `imv-wayland` overlay rendering `cheatsheet.svg`; the sway rule matches `app_id="imv"`).
- **PipeWire**: the stock Pi image masks pipewire/pulseaudio user units in BOTH `~/.config/systemd/user` and `/etc/systemd/user`. Unmask both or MPD audio (pipewire output) and snapclient break.
- **myMPD**: no Debian package — must be built from source with CMake (handled in `setup-pi.sh`); installed to `/usr`, runs as a user service against user MPD.
- **Euphonica** is a user-scope flatpak (`flatpak --user run io.github.htkhiem.Euphonica`); it must be installed with `--user`, and sway autostarts it on workspace `1:Music`.
- MPD runs as a **user** systemd service (not system), music dir is `/home/pi/Music` (MPD library root), playlists `/home/pi/playlists`, audio output is `pipewire`. Music arrives via syncthing (`Sync` → `Music`, `Mixes`).
- Waybar custom modules exec shell scripts in `restore/home/pi/.config/waybar/` (mixxx launch, now-playing via D-Bus/RIS, keyboard, power menu); waybar must be reloaded with `pkill -USR1 -x waybar` after config edits.
- **Brightness**: the HyperPixel4 panel backlight is on/off only (`/sys/class/backlight/backlight/max_brightness` = 1; hardware dimming is the physical button). Waybar's backlight module is removed and there is **no brightness keybind** (`$mod+b` is sway's stock `splith`). `~/.config/sway/brightness.py` (gammastep software dimmer) and `gammastep` remain installed — run it manually if needed: `foot -e python3 ~/.config/sway/brightness.py` or `brightness.py --set <percent>`.
- **Volume notifications**: `~/.config/sway/volume.sh` handles the sway volume keybinds and sends synchronous notifications; `volume-notify.service` runs `~/.config/sway/volume-notify.sh` to notify when PipeWire's default sink volume changes elsewhere. Notifications are not capped at 100%.

## Verification on the Pi
- After changes: copy payload → run `setup-pi.sh`, then `swaymsg reload` and `pkill -USR1 -x waybar`.
- If a waybar restart makes the top bar disappear, reboot the Pi (`sudo shutdown -r now`) and wait for SSH to return before continuing; do not keep retrying `pkill` or `swaymsg exec waybar` over SSH.
- Key services: `systemctl --user status mpd mympd syncthing snapclient pipewire pipewire-pulse wireplumber volume-notify`; test playback with `mpc toggle` / `mpc play`.

## Taking screen videos
- Use `wf-recorder` on the Pi for Wayland screen recordings. It is installed by `setup-pi.sh` dependencies on the live Pi; `ffmpeg` is also available for frame extraction.
- GUI recording commands need the same Wayland environment as other sway tests:
  ```bash
  export XDG_RUNTIME_DIR=/run/user/1000
  export WAYLAND_DISPLAY=wayland-1
  export SWAYSOCK=$(ls /run/user/1000/sway-ipc.*.sock | head -n1)
  ```
- Record a short action with continuous frames so transient window mapping is captured:
  ```bash
  ssh pi@hackpi.local 'bash -s' <<'EOF'
  export XDG_RUNTIME_DIR=/run/user/1000
  export WAYLAND_DISPLAY=wayland-1
  export SWAYSOCK=$(ls /run/user/1000/sway-ipc.*.sock | head -n1)

  timeout 5 wf-recorder -f /tmp/recording.mp4 -D -r 15 >/tmp/wf.log 2>&1 &
  rec_pid=$!
  sleep 1

  # Trigger the action being recorded, for example:
  swaymsg "exec /home/pi/.config/sway/cheatsheet.sh"

  sleep 3
  kill -INT $rec_pid
  wait $rec_pid || true
  EOF
  ```
- Pull the video to the workstation and extract frames for visual inspection:
  ```bash
  scp pi@hackpi.local:/tmp/recording.mp4 /tmp/opencode/
  mkdir -p /tmp/opencode/recording_frames
  ffmpeg -v error -i /tmp/opencode/recording.mp4 -vf fps=5 /tmp/opencode/recording_frames/frame_%02d.png
  ```
- Use `-D` (`--no-damage`) when recording short UI transitions; without it, `wf-recorder` may only emit frames when the screen changes and can miss the first mapped window state.
- Use `-r 15` for a small, inspectable frame rate. Use `-g x,y WxH` only when a cropped region is needed; full screen is `720x720`.
- Stop `wf-recorder` with `kill -INT`, not `kill -9`, so the MP4 is finalized cleanly.
- For stills, use `grim /tmp/screenshot.png`, then pull it to `/tmp/opencode/`.
