# Hackpi Multiroom Audio Plan (Snapcast)

Working plan for adding low-latency multiroom audio to the Hackberry Pi music
player. Written for the repo's deploy model: everything lands as payload files
under `files/home/pi/` and repeatable changes to `setup-pi.sh`.

Status: **v5 — sender/receiver only.** Implementation field notes for agents
are in §15. The receiver-forcing agent (`snapswitch`) is designed in §13 but
**deferred to phase 2**; do not implement it yet.

---

## 1. Goal

- **Broadcast**: send this Pi's music (MPD) to other machines on the network.
- **Receive**: play a stream from another Snapcast server.
- **Group**: this Pi and other rooms play sample-synced audio together.
- Low latency (~150-250 ms end-to-end, tunable), PCM path, no resampling.
- No changes to the receiver machines for the features implemented in this
  phase: receivers are pointed at a server once (their own picker, config, or
  Avahi discovery) and stay there.

Non-goals in this phase: AirPlay, Spotify Connect, Bluetooth sources, and
remote receiver switching (see §13).

## 2. Locked decisions

| Topic | Decision | Why |
|---|---|---|
| Transport | Snapcast, standalone `snapserver` from apt (0.31 on trixie) | Protocol-level clock sync; tunable buffer; official clients for all OSes |
| Server input | MPD `fifo` output -> `pipe:///tmp/snapfifo` | Kernel-only raw PCM path, no PipeWire hop, lowest latency, apt-managed |
| Server lifecycle | On demand only: started by the picker/waybar (Broadcast or Group), stopped in Receiver; never enabled at boot | No server running or advertised on the LAN when not sending |
| Local output | `snapclient --player=pipewire` (payload unit) | Upstream v0.35.0 `with-pipewire` .deb installed by `setup-pi.sh`; Debian's 0.31 has no pipewire player |
| Local modes | off / receiver / broadcast / group (+ "Listen to...") | Covers local-only, listen, send, sync use cases |
| UI | `$mod+x` fuzzel picker + waybar indicator | Matches `device.sh` / `network.sh` conventions |
| Codec/latency | PCM, `chunk_ms=20`, `buffer=150` | ~200 ms end-to-end; tunable 80-300 ms; ~1.5 Mbit/s per client |
| Web UI | Bundle snapweb per sender, served at `:1780` | Free phone UI for volume/mute/group/streams of connected receivers |
| Receiver switching | Deferred (§13) | Snapcast has no remote server-switch protocol; needs an agent |

Rejected for this phase:
- **MPD's built-in snapcast output**: `bufferMs` is hardcoded to 1000 ms in
  `src/output/plugins/snapcast/Client.cxx` (no config knob), so it cannot meet
  the latency goal.
- **Native PipeWire capture** (`pipewire://` source): only in snapcast >= 0.33
  built with `-DBUILD_WITH_PIPEWIRE=ON`; trixie apt has 0.31. Would also need
  a dedicated null sink + MPD `target` to avoid capturing all audio.
- **Two-server discovery tricks**: `snapclient` picks the first Avahi
  responder and sticks to it; non-deterministic.
- **SSH push / MQTT broker**: key sprawl / extra coordinator; deferred with
  `snapswitch`.

## 3. Verified constraints and findings

Checked against the live Pi (`ssh pi@hackpi.local`) and upstream sources:

- Pi runs Debian trixie: `mpd 0.24.0` (has `fifo` + `snapcast` output
  plugins), `snapclient 0.35.0` (upstream `with-pipewire` .deb), `snapserver
  0.31.0` from apt (`http://deb.debian.org/debian trixie/main`).
- **Double-client bug**: the apt system unit `snapclient.service`
  (`User=_snapclient`, ALSA player) is `active` **and** `enabled`, while the
  payload user unit (`--player=pipewire`) is also active. With a server
  present, both would play (double audio). Must be disabled in `setup-pi.sh`.
- **Debian's snapclient has no pipewire player.** Trixie's 0.31 links
  libpulse/libasound but not libpipewire; `--player=pipewire` only fails once
  the client actually connects to a server (`Exception: No audio player
  support for: pipewire`), which is why the latent bug never showed before
  this feature (with no server, the client sits in discovery forever).
  `setup-pi.sh` therefore installs the upstream v0.35.0
  `snapclient_*_trixie_with-pipewire.deb` (checksum-verified against the
  GitHub release asset digest) and the payload unit uses
  `--player=pipewire`.
- MPD `state_file` persists audio-output enable states
  (`audio_output_state_save/read` in `StateFile.cxx`), so after a reboot in
  broadcast/group mode MPD re-enables the `Multiroom` output. A boot restore
  service is needed.
- MPD `fifo` output (plugin docs): writes raw PCM, **path must be absolute**,
  creates the FIFO if missing (same uid as MPD) and reuses an existing one.
- `fs.protected_fifos=1`: a FIFO in `/tmp` created by user `pi` can be opened
  for writing by `pi` (MPD). A stale FIFO created by another user
  (`snapserver`/`_snapclient`) blocks writes and must be removed at deploy.
- `snapserver 0.31` config supports `[stream] source/buffer/chunk_ms/codec/
  sampleformat`, ports 1704 (stream) / 1705 (TCP JSON-RPC) / 1780 (HTTP), and
  a default `doc_root = /usr/share/snapserver/snapweb`.
- Debian trixie has **no `snapweb` package** (verified `apt-cache policy
  snapweb` / `apt-cache search snapweb`). snapweb must come from its upstream
  GitHub release.
- Snapcast control model: a server fully controls its connected clients via
  JSON-RPC (`Group.SetStream`, `Group.SetClients`, `Group.SetMute`,
  `Client.SetVolume/Latency/Name`) but **cannot** make a client switch
  servers. snapweb is a UI over exactly one server's RPC; it cannot see or
  move clients on other servers.
- `snapclient --player=file[,filename=...]` writes **raw PCM** (verified in
  `client/player/file_player.cpp`, "Raw PCM file output", default stdout).
  This enables a future bridge of another server's stream into a local
  `pipe://` source (§13, phase 3).
- `fuzzel` is installed; Avahi is present (snapclient depends on it);
  `avahi-utils` (`avahi-browse`) and `python3` must be added to the deploy.
- `sway` config is payload-owned; `$mod+x` is free (stock collisions
  absent), `$mod+Shift+r` is resize mode, `$mod+Shift+4` is Euphonica.

## 4. Architecture

```
MPD (user) --pipewire out--> PipeWire --> speaker          [receiver, broadcast]
    |
    +--fifo out--> /tmp/snapfifo --> snapserver:1704 --> remote snapclients
                                            ^               [broadcast, group]
              snapclient --player=pipewire -+--> PipeWire --> speaker  [group]
```

- `snapserver` is a payload-owned **user** unit, started on demand and stopped
  in receiver mode (avoids self-advertisement and the local client discovering
  its own server).
- The local `snapclient` is explicitly pointed at `127.0.0.1:1704` in group
  mode, stopped in off/broadcast modes, and uses discovery or a chosen host
  in receiver mode. No mode can loop or double-play.
- Ports: 1704 stream, 1705 JSON-RPC, 1780 HTTP/snapweb. All unprivileged.

**snapserver must not run at all times.** It is never enabled at boot and
never started by `setup-pi.sh`; it runs only when the user selects Broadcast
or Group via the `$mod+x` picker (or the waybar `custom/audio` button),
and it is stopped again when Off or Receiver is selected. `snapserver.service` is a
payload-owned user unit left disabled precisely so the only things that can
start it are the shortcut and the waybar. This keeps the Pi from advertising a
`_snapcast._tcp` server (and from holding ports 1704/1780) when it is not
sending, and prevents the local snapclient from discovering its own server.
The boot restore service re-applies the last mode, so if the Pi was
broadcasting when it shut down, snapserver is started again by that restore,
not by the unit's enable state.

### 4.1 Local modes

| Mode | snapserver | local snapclient | MPD outputs | Result |
|---|---|---|---|---|
| **off** (default) | stopped | stopped | `PipeWire Sound Server` | plain local playback; nothing sent, received, or advertised |
| **receiver** | stopped | discovery, or a host chosen via "Listen to..." | `PipeWire Sound Server` | Pi listens to another server |
| **broadcast** | running | stopped | `PipeWire Sound Server` + `Multiroom` | Pi plays locally; other rooms can join `hackpi.local:1704`; Pi is the (slightly ahead) master |
| **group** | running | `127.0.0.1:1704` | `Multiroom` only | every room including the Pi is synced (buffer 150 ms) |

Mode state is stored in `~/.config/sway/.audio-mode` (one word; missing or
invalid = off). `audio-mode-restore.service` re-applies it at boot after
MPD is up.

## 5. The picker: how it works and how it is used

`~/.config/sway/audio-mode.sh` is the single entry point.

### 5.1 Actions

| Action | Caller | Behaviour |
|---|---|---|
| `pick` (default) | `$mod+x`, waybar click | opens the fuzzel picker, applies the selection |
| `set <mode>` | internal, smoke test | applies off/receiver/broadcast/group directly |
| `listen <host:port>` | picker entry 5 | sets the remote host for receiver mode (see 5.3) |
| `listen auto` | picker entry 5 | clears the host; client uses Avahi discovery |
| `status` | waybar every 5 s | one line `<icon> <mode>`; `--waybar` variant for the module |
| `restore` | boot oneshot | reads the saved state and re-applies it |
| `list` | smoke test | `mode<TAB>active<TAB>description` rows |

Environment bootstrap is copied from `device.sh` (`XDG_RUNTIME_DIR`,
`DBUS_SESSION_BUS_ADDRESS`, `WAYLAND_DISPLAY` defaults) so it works from sway
binds, waybar, and SSH tests.

### 5.2 Opening and choosing

`$mod+x` (or clicking the waybar icon) runs:

```bash
fuzzel --dmenu --width 56 --prompt "Audio mode: "
```

Menu rows (active mode marked `  <- current`, same convention as
`device.sh pick`):

```
1) Off       — local playback only                    <- current
2) Receiver  — remote Snapcast server
3) Broadcast — send this Pi's music
4) Group     — sync with other rooms
5) Listen to… — choose a discovered server
```

Keyboard/UX:
- Type to filter (`off`, `rec`, `broad`, `group`, `listen`, also `1`-`5`);
  Enter confirms.
- **Esc / click-away cancels silently**: empty selection -> `exit 0`, no
  notification, mode unchanged.
- Choosing the current mode re-applies it idempotently and notifies.
- `norepeat: true` in `keys.json` prevents a held key from spawning several
  fuzzel windows.

### 5.3 "Listen to..." flow (receiver-side, local only)

Entry 5 opens a second fuzzel list built from
`avahi-browse -rpt _snapcast._tcp` (plus an explicit "Automatic (discovery)"
row):

```
1) hackpi-b (192.168.1.42:1704)
2) nas (192.168.1.10:1704)
3) Automatic (discovery)
```

- Selecting a server runs `audio-mode.sh listen <host:port>`: writes
  `SNAPCLIENT_OPTS=--host <host> --port <port>` to
  `~/.config/snapclient/env`, restarts `snapclient`, ensures receiver mode
  (PipeWire output, snapserver stopped), stores the host in the state file.
- "Automatic" clears the env override (comment only), restarts `snapclient`,
  which falls back to Avahi discovery.
- If `avahi-browse` finds nothing, the notification says
  `No Snapcast servers found` and offers the manual path
  (`SNAPCLIENT_OPTS` in `/etc/default/snapclient`).
- `avahi-browse` comes from `avahi-utils`, which is **not installed** on the
  current Pi (verified: `avahi-browse: No such file or directory`, while
  `avahi-daemon` is active). `setup-pi.sh` must add it, and the script should
  detect a missing binary and notify (`ERROR: avahi-utils missing`) instead of
  failing silently.
- Discovery gotcha: a snapclient using Avahi can resolve a sender's IPv6
  address while snapserver listens on IPv4 only by default (upstream issue
  #715), producing `Connection refused`. Either set `bind_to_address = ::` in
  `snapserver.conf` or prefer an explicit host; this flow always passes
  `--host`, which avoids the problem for the receiver side.
- This is how a receiver is pointed at a sender in this phase: locally on the
  receiver, once. There is no remote takeover yet (§13).

### 5.4 Applying a mode (order matters)

**off**
1. `mpc enable only "PipeWire Sound Server"` (stops the fifo writer first).
2. `systemctl --user stop snapserver`.
3. `systemctl --user stop snapclient`.
4. Save state, notify.

**receiver**
1. `mpc enable only "PipeWire Sound Server"` (stops the fifo writer first).
2. Restart `snapclient` with the env file as-is (discovery or chosen host).
3. `systemctl --user stop snapserver`.
4. Save state, notify.

**broadcast**
1. `systemctl --user start snapserver`; wait up to 3 s for `is-active`
   (failure -> §5.6).
2. `systemctl --user stop snapclient`.
3. `mpc enable only "PipeWire Sound Server" "Multiroom"`.
4. Save state, notify.

**group**
1. Start snapserver, wait.
2. Write `SNAPCLIENT_OPTS=--host 127.0.0.1 --port 1704` to
   `~/.config/snapclient/env`, `systemctl --user restart snapclient`.
3. `mpc enable only Multiroom`.
4. Save state, notify.

Ordering rule: snapserver must be up before the MPD fifo output is enabled,
and the fifo output must be disabled before snapserver stops (otherwise MPD's
fifo open fails and the output is marked errored until re-enabled).

### 5.5 Notifications

Synchronous (replace-in-place), same pattern as `device.sh`:

```
notify-send --expire-time=2000 \
  --hint=string:x-canonical-private-synchronous:audio-mode \
  "Audio mode" "Broadcast — other rooms can join hackpi.local:1704"
```

Copy: `Off — local playback only (Snapcast stopped)`,
`Receiver — listening for a remote Snapcast server`,
`Broadcast — other rooms can join hackpi.local:1704`,
`Group — synced with other rooms (buffer 150 ms)`,
`Listening to hackpi-b (192.168.1.42:1704)`.

### 5.6 Failure handling

- snapserver won't start (port busy, config error): notify
  `ERROR: snapserver failed to start (systemctl --user status snapserver)`
  and revert to the previously saved mode (off when the server was down).
- `mpc` fails (MPD down): notify `ERROR: MPD unavailable`, state unchanged.
- `/tmp/snapfifo` not writable (stale owner): notify
  `ERROR: /tmp/snapfifo not writable` and point at `setup-pi.sh`.
- All failures leave the system in a working mode (never "output enabled but
  no server").

### 5.7 Waybar indicator

```jsonc
"custom/audio": {
    "exec": "/bin/bash $HOME/.config/sway/audio-mode.sh status --waybar",
    "interval": 5,
    "format": " {} ",
    "tooltip-format": "Audio mode (click to switch)",
    "on-click": "/bin/bash $HOME/.config/sway/audio-mode.sh pick",
    "spacing": 10
}
```

`status --waybar` prints one line with a Font Awesome glyph: off `\uf204`,
receiver `\uf028` (speaker; the music note `\uf001` looked like Euphonica's
headphones and signal bars `\uf012` like wifi), broadcast `\uf0a1` (FA 4.7
has no broadcast-tower `\uf519`), group `\uf0c0` (verified against the
installed font during implementation). Placed in `modules-right` next to
`custom/network`. Optional nicety: waybar `"signal": 8` +
`pkill -RTMIN+8 -x waybar` from the script for instant refresh instead of the
5 s poll.

### 5.8 Boot restore

`audio-mode-restore.service` (user, `WantedBy=default.target`,
`After=mpd.service snapclient.service`, oneshot) runs
`audio-mode.sh restore`: polls `mpc outputs` for up to ~15 s, then applies the
saved mode silently (log only). This fixes MPD's persisted output state after
reboots, e.g. broadcast survives a power cycle.

### 5.9 Usage walkthrough

1. Play music as usual (Euphonica/myMPD/`mpc`).
2. **Off** is the default: local playback only, nothing sent or received.
3. `Super+X` -> **Broadcast** -> Pi keeps playing locally; on another
   machine run `snapclient --host hackpi.local` (or let it auto-discover) to
   hear it.
4. Want the Pi itself sample-synced with the other rooms? Pick **Group**.
5. To listen to someone else's `snapserver`, pick **Receiver** ->
   **Listen to...** and choose the discovered server (or Automatic).
6. `http://hackpi.local:1780` (snapweb) controls volume/mute/group/streams of
   whatever receivers are connected to this Pi while it is broadcasting.
7. Esc on the picker means "do nothing".

## 6. File-by-file changes

New:

| File | Purpose |
|---|---|
| `multiroomaudio.md` | this document |
| `files/home/pi/.config/snapserver/snapserver.conf` | payload-owned server config |
| `files/home/pi/.config/systemd/user/snapserver.service` | on-demand user unit, not enabled at boot |
| `files/home/pi/.config/systemd/user/audio-mode-restore.service` | boot restore oneshot |
| `files/home/pi/.config/sway/audio-mode.sh` | picker/set/status/restore/listen |
| `files/home/pi/.config/snapclient/env` | env override placeholder (comment only) |

Modified:

| File | Change |
|---|---|
| `files/home/pi/.config/mpd/mpd.conf` | add disabled `fifo` output `Multiroom` |
| `files/home/pi/.config/systemd/user/snapclient.service` | read `EnvironmentFile=-%h/.config/snapclient/env` after `/etc/default` |
| `files/home/pi/.config/sway/keys.json` | add `$mod+x` bind (norepeat) |
| `files/home/pi/.config/sway/generated.conf`, `cheatsheet.txt`, `cheatsheet.svg` | regenerate via `generate-keys.sh` |
| `files/home/pi/.config/waybar/config` | add `custom/audio` |
| `setup-pi.sh` | install/disable services, copy dirs, chmod, enable restore service |
| `AGENTS.md` | document multiroom feature |
| `smoke-test.sh` | new multiroom stage |

### 6.1 mpd.conf addition

```ini
audio_output {
        type            "fifo"
        name            "Multiroom"
        path            "/tmp/snapfifo"
        format          "48000:16:2"
        mixer_type      "software"
        enabled         "no"
}
```

`mixer_type "software"` keeps `mpc volume` affecting the network stream.
`enabled "no"` prevents MPD trying to open the FIFO on a fresh boot.

### 6.2 snapserver.conf

```ini
[server]
threads = -1

[http]
# doc_root is not a compiled default: our -c config replaces /etc/snapserver.conf,
# so without this :1780 serves snapserver's built-in placeholder page.
doc_root = /usr/share/snapserver/snapweb

[stream]
source = pipe:///tmp/snapfifo?name=Multiroom&sampleformat=48000:16:2&codec=pcm&chunk_ms=20
buffer = 150
```

### 6.3 snapserver.service (user)

```ini
[Unit]
Description=Snapcast server (multiroom broadcast)
Documentation=man:snapserver(1)
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/bin/snapserver -c %h/.config/snapserver/snapserver.conf
Restart=on-failure
StandardOutput=null

[Install]
WantedBy=default.target
```

### 6.4 snapclient.service change

Add after the existing `/etc/default` line:

```ini
EnvironmentFile=-%h/.config/snapclient/env
```

`SNAPCLIENT_OPTS` from the later file overrides the earlier one; receiver mode
leaves it comment-only so `/etc/default/snapclient` (if customized) still
applies.

## 7. `setup-pi.sh` changes

1. Add `snapserver python3 avahi-utils` to the apt install line
   (`setup-pi.sh:12-14`). `python3` also fixes the existing gap for
   `generate-keys.sh`/cheatsheet scripts.
2. Install the pinned upstream `snapclient` v0.35.0
   `with-pipewire` `.deb` (arm64/armhf/amd64, checksum-verified against the
   GitHub release asset digest) unless `snapclient --version` already reports
   v0.35.0. Debian trixie's 0.31 has no pipewire player. No distro fallback:
   a download/checksum/install failure aborts `setup-pi.sh` (`exit 1`) instead
   of leaving a client that cannot play through PipeWire.
3. After install:
   - `sudo systemctl disable --now snapclient.service` — fixes the
     double-client bug.
   - `sudo systemctl disable --now snapserver.service` — the distro unit
     would own 1704/1780 and create a root/`snapserver`-owned FIFO.
   - `sudo rm -f /tmp/snapfifo` — clear any stale FIFO from the brief system
     service run.
4. Add `snapserver snapclient` to the fallback copy loop (`setup-pi.sh:126`).
5. `chmod +x "$HOME/.config/sway/audio-mode.sh"` with the other scripts
   (`setup-pi.sh:179-190`).
6. Add `audio-mode-restore.service` to the user `enable` list
   (`setup-pi.sh:197`). Do **not** enable or start `snapserver.service` — it is
   strictly on demand: the picker (or waybar) starts it for Broadcast/Group
   and Off/Receiver stop it. Only the boot restore service may start it, and
   only to restore a saved Broadcast/Group mode. `setup-pi.sh` also starts
   `audio-mode-restore.service` once at the end so the saved/default mode
   (off) applies immediately instead of waiting for the next boot.
7. Restart MPD after the config copy:
   `systemctl --user restart mpd.service`. The existing `start` call is a
   no-op when MPD is already running, so the new `fifo` output would otherwise
   not apply on a re-run of `setup-pi.sh`.
8. Keep regenerating keys and validating sway as today.
9. snapweb (optional but recommended): install the pinned upstream release
   into `/usr/share/snapserver/snapweb` and set `[http] doc_root` in the
   payload `snapserver.conf` (the snapserver package ships only a placeholder
   and the compiled `doc_root` default is empty). Checksum-verified, same
   pattern as bluetuith/wifitui. Skip cleanly if the download fails.

## 8. Client setup on other machines

- **Linux**: `sudo apt install snapclient`, then
  `snapclient --host hackpi.local` (or omit `--host` for Avahi discovery
  while the Pi is in broadcast/group and is the only advertising server).
- **Windows/macOS**: Snapcast release binaries (Windows also has Snap.Net);
  **Android/iOS**: Snapcast apps. Point at `hackpi.local:1704`.
- **Controller**: snapweb at `http://hackpi.local:1780`, or the mobile apps,
  for per-room volume/mute/grouping/streams of receivers connected to the Pi.
- Server is live only in broadcast/group mode; receiver mode advertises
  nothing.

## 9. Verification

Per mode on the Pi:

```bash
mpc outputs
systemctl --user is-active snapserver snapclient
tr '\0' '\n' < /proc/$(systemctl --user show snapclient -p MainPID --value)/environ | grep SNAPCLIENT_OPTS
# prove the server actually serves audio (writes non-empty PCM):
timeout 3 snapclient --host 127.0.0.1 --player=file:filename=/tmp/cap.raw,mode=w && test -s /tmp/cap.raw
```

- Picker: `wtype -M logo -k x`, wait, `grim /tmp/picker.png` (verify
  fuzzel + current marker), `wtype -k Escape`; assert mode unchanged.
  Deterministic assertions use `audio-mode.sh set ...`.
- "Listen to...": verify `avahi-browse -rpt _snapcast._tcp` output parsing
  with a live sender; assert the env file and `systemctl --user show
  snapclient` pick up the host.
- Boot: reboot in group mode, confirm the restore service returns to group
  and MPD's fifo output is consistent.
- Sway: `sway -C -c ~/.config/sway/config`, and after reboot verify
  `pgrep -ax swaynag` is empty (red-banner collision check per repo memory).
- Smoke test stage: off (assert PipeWire only, snapserver and snapclient
  stopped) -> receiver -> group (assert Multiroom only, snapserver active,
  client host `127.0.0.1`, `/tmp/cap.raw` non-empty) -> broadcast (assert both
  outputs, client stopped) -> receiver, restoring the starting mode at the end.

## 10. Risks and gotchas

| Risk | Mitigation |
|---|---|
| Stale `/tmp/snapfifo` owned by another user (`fs.protected_fifos`) | `setup-pi.sh` removes it; picker detects unwritable FIFO and errors |
| Distro system snapclient/snapserver units active | disabled in `setup-pi.sh` |
| MPD persists output state across reboots | `audio-mode-restore.service` |
| snapserver mDNS self-discovery loop | server stopped in receiver; client explicitly `127.0.0.1` in group; client stopped in broadcast |
| WiFi jitter raises latency | `buffer=150` default; tune 80-300 in `snapserver.conf`; `codec=flac` (+26 ms) if bandwidth matters |
| PCM bandwidth (~1.5 Mbit/s/client) | OK on LAN; FLAC fallback documented |
| `mpc enable` while MPD down | picker errors without changing state |
| snapweb missing from Debian | pinned upstream release; install failure is non-fatal |
| `avahi-utils` missing on the Pi | `setup-pi.sh` installs it; picker notifies if `avahi-browse` is absent |
| Avahi resolves IPv6 but snapserver binds IPv4 | set `bind_to_address = ::` or always use an explicit `--host` |
| `mpd.conf` changes ignored on re-run | `setup-pi.sh` must `systemctl --user restart mpd` |

## 11. Implementation order

1. Payload configs/units/script: `snapserver.conf`, `snapserver.service`,
   `audio-mode-restore.service`, `audio-mode.sh`, `snapclient/env`,
   `snapclient.service` env hook, `mpd.conf` fifo output.
2. `keys.json` bind + regenerate `generated.conf`/cheatsheet; waybar module.
3. `setup-pi.sh` changes (§7).
4. Deploy to the Pi (tar -> `setup-pi.sh` -> reboot), run §9 verification.
5. snapweb install step + smoke-test stage.
6. Update `AGENTS.md`.

## 12. Latency budget (PCM, defaults)

| Stage | Approx. |
|---|---|
| MPD decode + fifo write | ~5-10 ms |
| snapserver chunk | 20 ms |
| snapserver buffer | 150 ms |
| network + client jitter | covered by buffer |
| snapclient -> PipeWire device | 20-40 ms |
| **Total** | **~200 ms** |

`buffer = 80` on wired Ethernet gets closer to ~130 ms; raise it if WiFi
stutters.

## 13. Phase 2: remote receiver switching (`snapswitch`) — deferred

The original goal — senders automatically pointing receivers at their channel
without touching the receiver — requires a receiver-side agent, because
Snapcast has no server-switch protocol. Design preserved here for later:

- **Receiver agent** `snapswitchd.py` (Python 3 stdlib user service):
  advertises `_snapswitch._tcp` (TXT `room=`, `tags=`) via
  `avahi-publish-service`; HTTP JSON API on port 1710: `GET /status`,
  `POST /switch {"server":"auto"}` (uses the HTTP peer address),
  `POST /release`. Rewrites `~/.config/snapclient/env` and restarts
  `snapclient`; tracks `owner`, `default_server`; optional bearer token.
- **Sender CLI** `channels.sh`: `list` (avahi-browse), `takeover [rooms|@tags|all]`,
  `release`, `status`, `pick`; remembers the last resolved selection in
  `~/.config/snapswitch/last.json` (bare takeover reuses it, fallback all);
  ownership-filtered release; fuzzel toggle-loop "Choose speakers...".
- **Picker** `$mod+Shift+c`: Take over / Release / Speaker status / Room
  controls (web) / Listen to someone.
- **Semantics**: explicit takeover only (no auto-on-play), last takeover wins
  per receiver, release reverts to the receiver's default or idle. Lease/TTL
  and auto-pause of local playback on takeover are phase 2+ options.
- **Bridge** (phase 3): `snapclient --player=file,filename=<fifo>` writes raw
  PCM, which a local `pipe://` source can rebroadcast, letting one hub relay
  another Snapcast server's stream (+150-300 ms).

When this is implemented, the current "Listen to..." flow on each receiver
becomes optional, and receivers can stay parked on any server until a sender
takes them over.

## 14. Source references (verified)

- MPD output plugins: `fifo` (absolute path, raw PCM, create/reuse) and
  `snapcast` (server, `bufferMs: 1000` hardcoded) —
  https://mpd.readthedocs.io/en/latest/plugins.html
- MPD state persistence: `src/StateFile.cxx` (v0.24.4),
  `audio_output_state_save/read`
- snapserver 0.31 config: `[server] [http] [tcp] [stream] [logging]`,
  `--<section>.<name>` CLI overrides, default `doc_root` —
  https://raw.githubusercontent.com/badaix/snapcast/v0.31.0/server/etc/snapserver.conf
- snapclient players: `client/player/file_player.cpp` ("Raw PCM file
  output"), `--player` argument; v0.35.0 release assets include
  `snapclient_*_trixie_with-pipewire.deb` —
  https://github.com/badaix/snapcast/releases/tag/v0.35.0
- Snapcast JSON-RPC control API —
  https://github.com/snapcast/snapcast/blob/develop/doc/json_rpc_api/control.md
- snapweb (single-server UI; no server switching) —
  https://github.com/snapcast/snapweb
- snapcast PipeWire source (0.33+) / release packages —
  https://github.com/snapcast/snapcast/releases

## 15. Implementation field notes (for agents)

Everything below was learned while researching this plan; it is the material
an implementer would otherwise rediscover the hard way. Repo-wide conventions
live in `AGENTS.md` and `.opencode/memory/hackpi.md`; this section is
self-contained for the multiroom work.

### 15.1 Deploy mechanics

- Payload layout: files live under `files/home/pi/...` as a tar convention
  only. `setup-pi.sh` extracts with `tar -C "$HOME" --strip-components=2`, so
  the tarball must be built from **inside** `files/`:
  `tar -C files -czf /tmp/setup.tar.gz home`
- Run `setup-pi.sh` as the target user (`pi`), never root; it configures
  per-user services.
- The script uses `set -u` but not `set -e`, so a failed step does not abort.
  New steps should print `WARNING:` and continue (see the bluetuith/wifitui
  blocks for the established pattern).
- On the live Pi, do not run the full script casually: it can clobber live
  Syncthing pairing and myMPD state. Test payload edits by copying individual
  files and restarting the relevant user unit.
- Swapping the sway config needs a **reboot**, not `swaymsg reload`, because
  payload autostart `exec` lines re-run and can stack duplicates. Also,
  `pkill -USR1 -x waybar` over SSH can blank the top bar; if that happens,
  reboot and wait for SSH before continuing.

### 15.2 Exact commands and formats

- Avahi discovery (`avahi-utils` is **not** installed by default; the
  `avahi-daemon` is active):
  `avahi-browse -rpt _snapcast._tcp` emits terminated records like
  `=;wlan0;IPv4;hackpi;_snapcast._tcp;local;hackpi.local;192.168.1.42;1704;`
  with fields 4=name, 7=hostname, 8=IPv4, 9=port. Filter
  `$1=="=" && $3=="IPv4"`. Escaped `\;` can appear inside names; keep the awk
  simple (the snapMULTI project does the same).
- MPD: `mpc enable only <name...>` accepts several outputs; `mpc outputs`
  prints `Output 1 (PipeWire Sound Server) is enabled`; `mpc toggleoutput`
  exists. `mpc --version` is invalid on this build (use `mpc version`).
  Parse `mpc status`'s plain line (`[playing] #1/14 2:58/4:31 (66%)`), not
  `%position%`/`%elapsed%` (this mpc prints the specifiers literally).
- Verify the env override landed:
  `systemctl --user show snapclient -p Environment | tr ' ' '\n' | grep SNAPCLIENT_OPTS`
- Wait for snapserver after starting it:
  `for i in $(seq 1 15); do systemctl --user is-active --quiet snapserver && break; sleep 0.2; done`
- Prove the server serves audio without a second machine:
  `timeout 3 snapclient --host 127.0.0.1 --player=file:filename=/tmp/cap.raw,mode=w && test -s /tmp/cap.raw`
  The file-player syntax is verified from `snapclient --player='file:?'`:
  `filename=stdout|stderr|null|<file>` and `mode=w|a` (raw PCM output).
- Port check: `ss -ltnp | grep -E '1704|1705|1780'`.
- JSON-RPC (snapweb/debug): HTTP POST to `http://127.0.0.1:1780/jsonrpc`
  with `{"jsonrpc":"2.0","id":1,"method":"Server.GetStatus"}`; TCP 1705
  speaks the same protocol. Useful methods: `Server.GetStatus`,
  `Group.SetStream`, `Group.SetClients`, `Group.SetMute`,
  `Client.SetVolume`, `Client.SetLatency`.

### 15.3 `audio-mode.sh` skeleton

Follow `device.sh` for structure and conventions (env exports, `notify()`,
fuzzel parsing). Core shape:

```bash
#!/bin/bash
# audio mode: receiver | broadcast | group (+ listen <host:port>|auto)
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
STATE="$HOME/.config/sway/.audio-mode"
ENVF="$HOME/.config/snapclient/env"

notify() { notify-send --expire-time=2000 \
  --hint=string:x-canonical-private-synchronous:audio-mode "Audio mode" "$1"; }

server_up() {
  systemctl --user start snapserver || return 1
  for _ in $(seq 1 15); do
    systemctl --user is-active --quiet snapserver && return 0
    sleep 0.2
  done
  return 1
}

apply_receiver() {
  mpc enable only "PipeWire Sound Server" || { notify "ERROR: MPD unavailable"; return 1; }
  systemctl --user stop snapserver
  systemctl --user restart snapclient
}
apply_broadcast() {
  server_up || { notify "ERROR: snapserver failed to start"; return 1; }
  systemctl --user stop snapclient
  mpc enable only "PipeWire Sound Server" "Multiroom" || { notify "ERROR: MPD unavailable"; return 1; }
}
apply_group() {
  server_up || { notify "ERROR: snapserver failed to start"; return 1; }
  printf 'SNAPCLIENT_OPTS=--host 127.0.0.1 --port 1704\n' > "$ENVF"
  systemctl --user restart snapclient
  mpc enable only Multiroom || { notify "ERROR: MPD unavailable"; return 1; }
}
```

- Picker parsing mirrors `device.sh`: run fuzzel, extract the leading number
  with `grep -oE '^[0-9]+'`, ignore an empty result (Esc).
- `listen <host:port>` writes the env line, ensures receiver mode, restarts
  `snapclient`, and saves the mode in the state file (the host itself lives in
  `~/.config/snapclient/env`); `listen auto` writes a comment-only env file.
- Failures must not change the state file, so `status` keeps reporting a
  truthful mode.

### 15.4 Pitfalls

1. **FIFO ownership**: `/tmp/snapfifo` must be created/owned by `pi`
   (`fs.protected_fifos=1` verified). Remove stale FIFOs as root during
   deploy; never let the distro system snapserver create it.
2. **Ordering rule**: snapserver up before enabling `Multiroom`; `Multiroom`
   disabled before stopping snapserver. MPD's fifo open with no reader fails
   (ENXIO) and the output is marked errored until re-enabled —
   `journalctl --user -u mpd` shows it.
3. **MPD restart**: `mpd.conf` changes require
   `systemctl --user restart mpd`; `start` is a no-op on a running MPD.
4. **Env vs unit changes**: env-file content needs only a `snapclient`
   restart; unit-file changes need `daemon-reload` + restart.
5. **Sampleformat must match exactly**: MPD `format "48000:16:2"` ==
   snapserver `sampleformat=48000:16:2`. MPD resamples 44.1 kHz sources to
   48 kHz; a mismatch yields silence/garbage or hidden resampling.
6. **Discovery IPv6 trap** (issue #715): server binds IPv4 by default while
   Avahi may hand the client an IPv6 address. Set `bind_to_address = ::` or
   always use an explicit `--host`.
7. **Buffer tuning**: `buffer=150` is the default; too low causes
   dropouts/crackle, too high adds latency. Keep `buffer >= ~4 * chunk_ms`.
   Per-client tweaks: `snapclient --latency <ms>` or RPC
   `Client.SetLatency`.
8. **No NTP required**: Snapcast syncs clocks itself via TIME messages.
9. **snapserver 0.31 has no mDNS toggle** (added in 0.33); receiver mode
   stops the server so nothing advertises. Multiple advertising servers make
   snapclient discovery non-deterministic.
10. **snapserver state**: when not daemonized it persists state in
    `$HOME/.config/snapserver/server.json`; expected, not tracked.
11. **snapweb**: not in trixie apt (verified); the `snapserver` package ships
    only a placeholder `index.html`. Install the upstream release into
    `/usr/share/snapserver/snapweb` **and set `[http] doc_root`** in the
    payload config — the compiled default is empty because `-c` replaces
    `/etc/snapserver.conf`, so without it :1780 serves the built-in
    placeholder. Verify with `curl -sI http://127.0.0.1:1780/`; failure is
    non-fatal.
12. **Keybind regeneration**: `bash files/home/pi/.config/sway/generate-keys.sh`
    (needs `jq` + `python3`; `cheatsheet-svg.py` is stdlib-only and runnable
    from the workstation). `generated.conf` is generated — never hand-edit it.
13. **Sway validation blind spot**: `sway -C` passes even with duplicate
    binding warnings; after reboot check `pgrep -ax swaynag`. Test binds with
    `wtype -M logo -k x` (named keys only — literal letters add an
    implicit shift). F13 cannot be injected from uinput; F11 is bound to the
    same cheatsheet action and works for tests.
14. **Waybar**: reload with `pkill -USR1 -x waybar`; if the bar disappears,
    reboot rather than retrying over SSH. For instant status refresh add
    `"signal": 8` to the module and `pkill -RTMIN+8 -x waybar` from the
    script.
15. **System units**: disable both distro units in `setup-pi.sh` — the
    system `snapclient` (runs as `_snapclient`, ALSA, would double-play) and
    the system `snapserver` (binds 1704/1780 as user `snapserver`, owns the
    FIFO).
16. **Restore race**: `audio-mode-restore` must poll `mpc outputs` before
    applying, because it starts concurrently with MPD.
17. **Optional snapclient hardening**: add `PartOf=pipewire.service` so the
    client restarts with PipeWire and never ends up orphaned (upstream issue
    #1496).
18. **Picker environment**: sway binds and waybar run without a login shell;
    export `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS`/`WAYLAND_DISPLAY`
    defaults exactly like `device.sh` or `fuzzel`/`notify-send` will fail
    under SSH-based tests.
19. **snapclient player**: use `--player=pipewire`; Debian 0.31 has no
    pipewire player and exits 1 the moment a server connects.
    `setup-pi.sh` installs the pinned upstream v0.35.0
    `snapclient_*_trixie_with-pipewire.deb` for arm64/armhf/amd64
    (checksum = GitHub release asset digest); `snapclient --version` reports
    `v0.35.0 (rev ...)` and the journal shows `(PipeWirePlayer)`.
20. **snapclient start rate limit**: switching modes restarts the client, and
    a quick series of switches hits systemd's default 5-starts/10 s limit
    (`Result: start-limit-hit`). The payload unit sets
    `StartLimitIntervalSec=0`, and `audio-mode.sh` runs `reset-failed` before
    restarts.
21. **Env verification**: `systemctl --user show snapclient -p Environment`
    is empty for EnvironmentFile values; check the running process instead:
    `tr '\0' '\n' < /proc/$(systemctl --user show snapclient -p MainPID --value)/environ | grep SNAPCLIENT_OPTS`
    (or read `/proc/<pid>/cmdline` to prove `$SNAPCLIENT_OPTS` word-split).
22. **Fuzzel on the HyperPixel**: `dpi-aware=auto` scales the font to the
    panel's ~260 DPI while sway reports scale 1, so any picker wider than the
    config's 25 chars overflows the 720 px screen. The audio pickers pass
    `--dpi-aware=no --font "JetBrains Mono:size=13" --width 56`.

### 15.5 Test recipes

- Loopback audio proof (no second machine):
  `timeout 3 snapclient --host 127.0.0.1 --player=file:filename=/tmp/cap.raw,mode=w && test -s /tmp/cap.raw`
- Mode cycle (smoke stage), restoring the starting mode at the end:
  off -> assert `mpc outputs` shows only PipeWire and snapserver/snapclient
  are inactive; receiver -> PipeWire only, client active, server inactive;
  group -> assert only Multiroom, snapserver active,
  `SNAPCLIENT_OPTS` contains `127.0.0.1`, capture file non-empty; broadcast ->
  assert both outputs and snapclient inactive; restore.
- Picker: `wtype -M logo -k x`, wait, `grim /tmp/picker.png`, then
  `wtype -k Escape` and assert the mode file is unchanged. Use
  `audio-mode.sh set ...` for deterministic assertions.
- Two-machine sync: Broadcast on the Pi, `snapclient --host hackpi.local` on
  a laptop; both should play the same track. If one stutters, raise `buffer`;
  if latency bothers, lower it.
- After any failure:
  `journalctl --user -u snapserver -u snapclient -u mpd --since "-5 min"`.

### 15.6 Where to look

- `AGENTS.md`: "Fresh Raspbian -> music player", "Quirks an agent will miss",
  "Verification on the Pi", smoke-test notes.
- `.opencode/memory/hackpi.md`: live-Pi testing, SSH host-key resets,
  waybar/reboot caveats.
- Repo patterns: `device.sh` (picker/notify), `volume.sh`,
  `network.sh`, `setup-pi.sh` (service enable list, copy loop, chmod list).
