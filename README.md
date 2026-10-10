# swaymp — Music Player for the Hackberry Pi

A complete software stack that turns a Hackberry Pi (CM5 handheld) into a
dedicated music player: MPD + myMPD + Euphonica for playback, sway + waybar on
a HyperPixel4 square panel, PipeWire audio, and Snapcast multiroom.

Built primarily for the Hackberry Pi CM5 handheld, but the stack is mostly
portable — MPD, myMPD, sway/waybar, PipeWire, and Snapcast run on any Debian
or Ubuntu machine. Only the HyperPixel4 display setup (`setup-hyperpixel.sh`),
the Hackberry keyboard keybinds, and the 720×720 panel tuning are hardware-specific.

**Live site:** https://fayaaz.github.io/swaymp

<video src="demo/embed.mp4" width="480" controls poster="demo/embed-poster.jpg"></video>

*The promo render: the real Pi screen recording playing as the 3D Hackberry
keyboard's display texture, with each shortcut lighting the key that fires it.*

## What you get

- **Playback** — MPD (user service, `~/Music` library, `pipewire` output) with
  MPC keybinds: play/pause, next/previous, ±5s seek, volume + mute
- **Touch-friendly clients** — Euphonica (flatpak) on Now Playing, myMPD web UI
  (`https://hackpi.local:8443`)
- **Multiroom audio** — Snapcast Receiver / Broadcast / Group via `Super+X`,
  snapweb phone UI on port 1780, mode restored at boot
- **Handheld UI** — sway + waybar + fuzzel launcher on the 720×720 HyperPixel4
  panel, Dracula theme, single-source keybinds (`keys.json` → generated sway
  binds + SVG cheatsheet on F13), Bluetooth (bluetuith) and Wi-Fi (wifitui) TUIs
- **Music delivery** — Syncthing (`~/Sync`, `~/Music`, `~/Mixes`)

## Setup

`setup-pi.sh` is the deploy entrypoint (run on the Pi as the target user),
with `files/home/pi/` as the template payload — but a fresh Raspbian image is
**not** currently a supported one-shot target (see the gaps in `AGENTS.md`:
login session, Syncthing pairing, myMPD state). Follow the operator manual
until that path is tested end-to-end.

## Repo layout

- `setup-pi.sh` — deploy entrypoint (run on the Pi as the target user)
- `setup-hyperpixel.sh` — HyperPixel4 display setup (run first)
- `files/home/pi/` — authoritative fresh-setup template payload
- `demo/` — promo-video pipeline (Pi screen capture → 3D keyboard render);
  `demo/embed.mp4` is the small GitHub-embeddable cut
- `index.html` + `.github/workflows/pages.yml` — this project's GitHub Pages
  site (https://fayaaz.github.io/swaymp)

See `AGENTS.md` for the full operator manual (deploy recipe, quirks,
verification, demo pipeline).

## Credits

- Wallpaper / render backdrop: photo by Pat Hayden on
  [Unsplash](https://unsplash.com/photos/a-black-and-white-photo-of-a-circular-object-biaGCdzlDAk)
- Hackberry Pi CM5 body shells: ZitaoTech ([MIT](https://github.com/ZitaoTech/HackberryPiCM5))
- Demo track: ENOENT — *Hopscotch* (from `Sinbiotic EP`)
