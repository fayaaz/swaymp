## Default device switcher tui
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
