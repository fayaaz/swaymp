# AGENTS.md

This repo is not an app codebase. It is the restore payload + repeatable setup script for a Hackberry Pi music player (MPD + myMPD + sway + waybar + PipeWire + snapclient + Euphonica flatpak).

## Layout & source of truth
- `setup-pi.sh` is the deploy entrypoint. Run **on the Pi as the target non-root user** with the payload tarred to `/tmp/restore.tar.gz` — tar from **inside** `restore/` so members are `home/pi/...`, because the script extracts with `tar -C "$HOME" --strip-components=2` (stripping the template prefix `home/pi`). The `home/pi` prefix is only a tar convention; it is not the required login username. It is idempotent. See "Fresh Raspbian → music player" below for exactly what it does and does not cover.
- `setup-hyperpixel.sh` is the **display** entrypoint and must run on the Pi **before** `setup-pi.sh`: it appends an `[all]` block with `dtoverlay=vc4-kms-dpi-hyperpixel4sq` to `/boot/firmware/config.txt` (backing the file up to `config.txt.hackpi.bak`), refuses to run on non-Pi hardware, is idempotent, and needs a reboot to take effect. `OVERLAY=vc4-kms-dpi-hyperpixel4` selects the rectangular panel; `OVERLAY_PARAMS` passes the overlay's own params (`rotate=90`, `touchscreen-swapped-x-y=1`, `disable-touch=1`).
- `restore/home/pi/` is the authoritative **template payload**. Keep new files under `home/pi/` for the tar layout, but do not bake `/home/pi` or `/run/user/1000` into file contents. Use `~`, `$HOME`, `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}`, systemd `%h`/`%t`, or service-relative paths so the payload works for any target user. `hackpi-backup/` and `hackpi-full-backup/` are raw snapshots of the running Pi for reference; do not treat them as the deploy source.
- `wiremix` in `restore/home/pi/.cargo/bin` is a prebuilt aarch64 binary — there is no source in this repo; don't attempt to rebuild it here. It is **gitignored** (repo keeps no binaries), so a fresh deploy needs the binary supplied separately.
- `demo/` is the promo-video pipeline (Pi screen capture → 3D keyboard render), not part of the deployed payload. See "Generating the demo video" for how a clip is recorded, re-timed, and rendered.
- `.gitignore` keeps raw Pi snapshots (`hackpi-backup/`, `hackpi-full-backup/`, `*.tar.gz`), runtime caches (`mpd/tag_cache`, `mympd/tags`, `syncthing/index-*.db`), and all private keys/certs (`*.pem`, `*.key`, `mympd/ssl`, `pin_hash`) out of the repo. `restore/home/pi/.config/syncthing/config.xml` is a sanitized folder template only: it uses `~/Sync`, `~/Music`, `~/Mixes`, and contains no device IDs, API keys, passwords, or TLS material. Consequence: a redeploy regenerates syncthing/mympd certs, so the syncthing device ID changes and pairing must be redone.
- Template rules: MPD config paths use `~`; sway key commands use `exec ~/.config/...`; shell helpers use `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}`; systemd user units use `%h`/`%t`; myMPD state connects to `127.0.0.1` with port `6600`; Syncthing folder paths use `~`. Do not reintroduce `/home/pi` or `/run/user/1000` into payload files.

## Fresh Raspbian → music player (what `setup-pi.sh` covers)

**Verdict:** the script installs and configures the entire software stack, but it is **not yet a complete "default Raspbian → music player" converter**. On a stock image it either leaves the machine booting a different compositor (no sway session) or leaves sway with a partial config. The gaps are listed below; treat them as the remaining work for a true one-shot conversion.

Deploy recipe the script assumes:
```bash
tar -C restore -czf /tmp/restore.tar.gz home      # members MUST be home/pi/...
scp /tmp/restore.tar.gz setup-pi.sh pi@hackpi.local:/tmp/
ssh pi@hackpi.local 'bash /tmp/setup-pi.sh'
```
Without `/tmp/restore.tar.gz` the script falls back to `$PAYLOAD` (default `/tmp/restore`) via `cp -a`, so that directory must mirror `restore/home/pi/`.

What it does:
- apt-installs the stack: sway, waybar, foot, fuzzel, swayimg, imv, syncthing, pipewire/pipewire-pulse/wireplumber, mpd/mpc/mpdris2, snapclient, wlogout, sway-notification-center, libnotify-bin, jq, gammastep, fonts.
- builds myMPD from source with CMake (installs to `/usr`) when `mympd` is missing.
- copies the payload configs (`waybar mpd syncthing pipewire mympd sway fuzzel wlogout swaync foot`, `systemd/user`, `.cargo`) and creates `Music`, `Mixes`, `playlists`.
- seeds `~/.config/sway/config` from `/etc/sway/config` when the payload has no sway config, then edits that user config.
- unmasks PipeWire/PulseAudio user units in **both** `~/.config/systemd/user` and `/etc/systemd/user`.
- regenerates sway binds from `keys.json`, themes sway, comments out colliding stock binds, forces waybar as the only bar, autostarts waybar + swaync + Euphonica.
- installs Euphonica as a **user** flatpak with the `GSK_RENDERER=cairo` override.
- enables/starts user services (mpd, mympd, syncthing, snapclient, pipewire trio, swaync, volume-notify) and removes dunst/mpd-notify.

Gaps that block a clean first-boot conversion:
- **No base sway config in the payload.** `restore/home/pi/.config/sway/` still has no `config`, but `setup-pi.sh` now seeds `~/.config/sway/config` from `/etc/sway/config` before editing it. If `/etc/sway/config` is missing, it writes a minimal fallback, so a fresh image still needs verification that the stock sway binds are present.
- **Nothing makes sway the login session.** The live Pi boots sway via lightdm (`/etc/lightdm/lightdm.conf`: `user-session=sway`, `autologin-user=pi`, `autologin-session=sway`, greeter `pi-greeter-wayfire`); `setup-pi.sh` never touches lightdm, so a default Raspberry Pi OS desktop keeps booting its own session (labwc on Bookworm) and the script's final `swaymsg reload` is a no-op.
- **HyperPixel4 panel setup is scripted but must run first.** `setup-hyperpixel.sh` now adds the DPI overlay to `/boot/firmware/config.txt`; run it before `setup-pi.sh` and reboot. `/boot/firmware/config.txt` itself is still not captured in `hackpi-full-backup/`.
- **`wiremix` is gitignored** → `$mod+v` is dead on a fresh deploy until the aarch64 binary is supplied separately.
- **Packages the payload assumes but never installs:** `python3` (`generate-keys.sh`, `cheatsheet-svg.py`, `brightness.py`), `git` (myMPD clone) — both present on the desktop image, absent on Lite; `wvkbd` (waybar `custom/keyboard` button), `swayidle`, `wf-recorder`/`grim`/`ffmpeg` (screen-capture workflow below), `pipewire-alsa`/`pipewire-jack`. `mixxx` is referenced by `waybar/mixxx.sh` but is not installed and not used by the current waybar config.
- **Wallpaper asset missing:** the live sway config does `output * bg /home/pi/wallpaper/wallpaper.jpg fill`, but `wallpaper/` is not in the payload.
- **Silent failures:** `set -u` without `set -e`, plus `apt-get ... >/dev/null` and `flatpak install ... || true`, mean a failed package/build/flatpak step still prints `setup complete`.
- **State that must be re-established after any deploy:** syncthing's device ID changes (certs/keys gitignored) → re-pair the sanitized `~/Sync`, `~/Music`, and `~/Mixes` folders; myMPD regenerates its TLS cert and PIN (`ssl=true`, `pin_hash` gitignored); MPD needs `mpc update` since no music is seeded; snapclient needs a snapserver elsewhere on the network.
- **`wlogout` power buttons run `sudo shutdown ...`** from the GUI, which needs passwordless sudo for `pi`.

## Quirks an agent will miss
- **Keybinds**: `restore/home/pi/.config/sway/keys.json` is the single source of truth. Edit `keys.json`, then run `generate-keys.sh` (requires `jq` and `python3`) to regenerate `generated.conf` + `cheatsheet.txt` + `cheatsheet.svg`; never hand-edit `generated.conf`. `setup-pi.sh` comments out conflicting binds in the base sway config, so music keys live only in `keys.json`. The Hackberry dollar key sends Shift+4 scancodes (verified via `libinput debug-events` + sway binding events), so it is bound as `$mod+Shift+4` and the stock `move container to workspace number 4` bind is disabled; when testing binds with `wtype`, send exactly what the hardware sends (here: Super+Shift+`4`), or the test gives a false negative. Toggles and launchers set `"norepeat": true` in `keys.json` (`generate-keys.sh` emits `bindsym --no-repeat`): a held key repeats past the 300ms delay and would thrash hide/show pairs. `euphonica.sh` additionally debounces presses inside 1200ms so mash bursts converge to one toggle. Validate with `sway -C -c ~/.config/sway/config` after every config change.
- `keys.json` commands use `~/.config/...`, and helper scripts use `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}` for sway IPC/runtime files. Verified on the live Pi: sway `exec` expands `~`, MPD expands `~` in config paths, and Syncthing expands `~` in folder paths.
- **F13 is bound on the keyboard MCU** (custom VIAL layout on the Hackberry keyboard). Re-flashing firmware loses it; snapshot the `.vil` file first. F13 triggers `cheatsheet.sh` (toggles `cheatsheet-viewer.py`, a borderless fully-transparent GTK3 window rendering `cheatsheet.svg`, so the card's rounded corners show through; the sway rule matches `app_id="cheatsheet"` and does the sizing/placement). The viewer used to be `swayimg`, but 3.8 segfaults (worse over uptime, all formats, even with `SWAYSOCK` unset, while `imv`/GTK stay fine — root cause unknown), so it was replaced; `swayimg` stays installed as a general image viewer. `for_window move` is workspace-content-relative, so the rule uses `resize set 700 520, move position 10 57` for absolute 10,100. When the viewer dies on launch, `cheatsheet.sh` posts an `ERROR:` notification instead of opening (with a PID-file check so rapid toggling stays silent).
- **PipeWire**: the stock Pi image masks pipewire/pulseaudio user units in BOTH `~/.config/systemd/user` and `/etc/systemd/user`. Unmask both or MPD audio (pipewire output) and snapclient break.
- **myMPD**: no Debian package — must be built from source with CMake (handled in `setup-pi.sh`); installed to `/usr`, runs as a user service against user MPD.
- **Euphonica** is a user-scope flatpak (`flatpak --user run io.github.htkhiem.Euphonica`); it must be installed with `--user`, and sway autostarts it on workspace `1:Music`.
- **Workspaces**: Euphonica + `wiremix` are assigned to `1:Music`, `firefox` to `2:Browser` (assigns in sway config, added by `setup-pi.sh`). The launcher helpers (`euphonica.sh`, `wiremix.sh`, `browser.sh`) switch to the target workspace before launching, and `$mod+g` opens the default browser. The terminal (`$mod+tab`) always opens floating on the current workspace.
- **Bluetooth**: `setup-pi.sh` installs `bluez-tools` + `rfkill`, enables `bluetooth.service`, and adds the user to the `bluetooth` group (re-login needed). `$mod+u` toggles a floating `bluetoothctl` terminal (`bluetooth.sh`); PipeWire plays through connected devices via `libspa-bluetooth`.
- MPD runs as a **user** systemd service (not system), music dir is `~/Music` (MPD library root), playlists `~/playlists`, audio output is `pipewire`. Music arrives via syncthing (`Sync` → `Music`, `Mixes`).
- Waybar custom modules exec shell scripts in `restore/home/pi/.config/waybar/` (mixxx launch, now-playing via D-Bus/RIS, keyboard, power menu); waybar must be reloaded with `pkill -USR1 -x waybar` after config edits.
- **Brightness**: the HyperPixel4 panel backlight is on/off only (`/sys/class/backlight/backlight/max_brightness` = 1; hardware dimming is the physical button). Waybar's backlight module is removed and there is **no brightness keybind** (`$mod+b` is sway's stock `splith`). `~/.config/sway/brightness.py` (gammastep software dimmer) and `gammastep` remain installed — run it manually if needed: `foot -e python3 ~/.config/sway/brightness.py` or `brightness.py --set <percent>`.
- **Volume notifications**: `~/.config/sway/volume.sh` handles the sway volume keybinds and sends synchronous notifications; `volume-notify.service` runs `~/.config/sway/volume-notify.sh` to notify when PipeWire's default sink volume changes elsewhere. Notifications are not capped at 100%.

## Verification on the Pi
- After changes: copy payload → run `setup-pi.sh`, then `swaymsg reload` and `pkill -USR1 -x waybar`.
- On a fresh image, additionally check: the login session is actually sway (`swaymsg -t get_version`), `~/.config/sway/config` contains the stock binds *and* the hackpi block, the HyperPixel4 is the active output (`swaymsg -t get_outputs`), syncthing is paired, and myMPD answers on `https://hackpi.local:8443` with the regenerated PIN.
- If a waybar restart makes the top bar disappear, reboot the Pi (`sudo shutdown -r now`) and wait for SSH to return before continuing; do not keep retrying `pkill` or `swaymsg exec waybar` over SSH.
- Key services: `systemctl --user status mpd mympd syncthing snapclient pipewire pipewire-pulse wireplumber volume-notify`; test playback with `mpc toggle` / `mpc play`.

## Taking screen videos
- Use `wf-recorder` on the Pi for Wayland screen recordings. It is installed on the live Pi but **not** by `setup-pi.sh` — install it first: `sudo apt-get install -y wf-recorder grim ffmpeg`.
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

## Generating the demo video
`demo/` is the promo-video pipeline, separate from the Pi payload. It has two stages: record the real Pi screen, then render the 3D Hackberry keyboard with that recording as its screen texture.

Stage 1 — record on the Pi (`demo/overlay_demo.sh`):
- Copy both files first: `scp demo/overlay_demo.sh demo/hackpi-touch.c pi@hackpi.local:/tmp/`, then `ssh pi@hackpi.local 'bash /tmp/overlay_demo.sh'`. It plays `ENOENT/Sinbiotic EP/enoent_hopscotch_16bitwav_master.wav` from `START_AT=40`, fires timed `Super+P/K/J`, sweeps volume with 10 `Super+I` then 10 `Super+O` (`volume.sh` steps 5%, so 10 presses = 50 points), touches the waybar `custom/cheatsheet` button, then opens `fuzzel` with `Super+Space`.
- Output: `/tmp/hackpi-overlay.mp4` (wf-recorder + PipeWire audio) and `/tmp/hackpi-overlay.marks`. **The `.marks` file is the source of truth for `EVENTS` in `index.html`** — copy the timings, don't guess them.
- Needs `wf-recorder`, `wtype`, `notify-send`, `mpc`, `wpctl`, `swaymsg`, `gcc`, and passwordless sudo: `demo/hackpi-touch.c` is a uinput pointer injector (compiled to `/tmp/hackpi-touch`, run via `sudo`) used because the cheatsheet beat is a *pointer* click on the waybar button (~`(82, 20)` on the 720x720 panel), not a keypress. Sway pointer accel is set `flat 0` for the touch and restored to `adaptive 0` after, otherwise the injected pointer drifts.
- There is **no F13 keycap in the 3D model**, so cheatsheet beats must be shown on the Pi screen only — do not add a keycap event for them.

Stage 2 — render on the workstation (`demo/make.sh`):
- `extract_frames.sh` → `demo/frames/` (8fps, 480x480 JPEGs; committed, they are the screen texture). This Chromium decodes `<video>` to black pixels for WebGL/canvas, so the page uses pre-decoded JPEGs instead of a `VideoTexture`.
- serves `demo/` on `127.0.0.1:7171`, runs `record.py` through `browser-harness` (attaches to Chromium CDP at `BU_CDP_URL`, default `http://127.0.0.1:9333`, auto-launching a browser if none is running) to capture the three.js canvas via the page's own `MediaRecorder` → `kb_final.webm`.
- `mux.sh` maps the canvas video with the **source clip's audio** → `kb_final.mp4`. Both start at t=0, so audio stays in sync; `-shortest` trims the capture tail.

Coupling rules (the failure modes):
- `index.html` `EVENTS` must match the `.marks` timings, and `record.py`'s `KB_DUR` must be **≥ the source clip duration** or the final video is truncated.
- `index.html` sizes the frame preload from `vid.duration` (no hardcoded frame count) with a 400-frame fallback after 4s.
- `extract_frames.sh` **skips when `frames/f_001.jpg` exists** — delete `demo/frames/` whenever the source clip changes, or the render keeps the old screen.
- `kb_final.webm` / `kb_final.mp4` are build outputs; do not commit videos. `demo/hackpi-overlay.mp4` is tracked as the source clip, so replacing it is a deliberate change.
- If `make.sh` is interrupted, the `http.server` on 7171 and the harness Chromium can be left running; the blob download streams in 4MB chunks, so a long clip legitimately takes several minutes.
