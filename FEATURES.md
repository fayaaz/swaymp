## Default device switcher tui: DONE
A shortcut (super + D - move notifications to super + Enter) which switches the main device through the ones connected. A tui or notification when this happens.
If a tui already exists that does mostly this, see how to use that instead


## Miniplayer always in notifications: DONE
Have a miniplayer always in notifications.

## Better bluetooth ui: DONE
Investigate and use https://github.com/bluetuith-org/bluetuith


## Replace network manager gnome applet with wifitui: DONE

Floating terminal again. Leave network-manager/network-manager-applet installed but don't start nm-applet. Replace the tray button with a waybar button that opens a floating terminal running wifitui, with nmtui as fallback.

## Standardise size of floating terminals: DONE

Make it 600x600 for terminal, wiremix, bluetuith and network (wifitui).


## Multiroom audio (Snapcast): DONE

`$mod+x` (and the waybar audio button) picks a mode: **Off** (local only), **Receiver** (listen to another Snapcast server), **Broadcast** (send this Pi's MPD to other rooms), **Group** (play sample-synced with them). MPD `fifo` -> `snapserver` started on demand (never enabled at boot), local `snapclient --player=pipewire`, snapweb phone UI at `http://<host>:1780`, and the saved mode is restored at boot. Remote receiver switching is deferred: Snapcast has no server-switch protocol, so a receiver is pointed at a sender locally once (`Listen to...`).

## Notification when devices are plugged in: DONE

Swaync notification on audio devices plugged in as well as external hard disks. `~/.config/sway/device-watch.sh` runs as the user service `device-watch.service` (tied to `pipewire.service`, no keybind). It is event-driven, not polled: `udevadm monitor --udev --subsystem-match=block` emits `disk` tokens and `pw-dump -m -N` emits `audio` tokens into a fifo; the loop blocks on `read`, coalesces bursts, waits `SETTLE` (1.5 s) for udev rules/automount/PipeWire node creation, then diffs a snapshot (`device.sh list` / `lsblk`) against the previous one. Announcements: `Disk plugged in` / `Disk removed` (with the mount point when devmon mounted it) and `Audio output connected` / `Audio output disconnected`. Removals are announced before additions with distinct synchronous ids (`disk-del`/`disk-add`/`audio-del`/`audio-add`) so swaync does not replace the "connected" popup with the "disconnected" one. The Pi's own root disk, `zram*`/`loop*`/`ram*` nodes and PipeWire's fallback `Dummy Output`/`AutoNullSink` are ignored, so a plug never turns into a connected+disconnected pair. Log: `$XDG_RUNTIME_DIR/swaymp-device-watch.log` (the Pi has no user journal).

## Super + X should go through the options in the popup: DONE

When the network audio options open super + x should go through the options and then when the user hits enter that one is picked. `$mod+x` now runs `audio-mode.sh cycle`: the first press opens the fuzzel picker, later presses move the selection one row down (`wtype -k Down`), wrapping back to the first row after the last, and Enter picks the highlighted mode. The picker state (PID, row count, current step) lives in `$XDG_RUNTIME_DIR/swaymp-audio-picker`; a picker that is no longer running is ignored and the next press reopens it.

## Network audio mode should be off on restart: DONE

Restoring the network audio mode when you reboot doesn't work right now anyway. Restore to off on reboot. `audio-mode-restore.service` no longer restores the saved mode: boot always comes up **Off** (snapserver and snapclient stopped, local PipeWire playback only) and it clears a stale MPD `Multiroom` fifo output state left behind by the previous session. `$mod+x` still saves the mode for the session, and `audio-mode.sh restore` is the manual "force Off" reset.
