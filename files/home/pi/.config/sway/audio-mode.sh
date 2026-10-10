#!/bin/bash
# Multiroom audio mode (Snapcast) — the single entry point for $mod+Shift+m,
# the waybar custom/audio button, boot restore, and tests.
#
#   pick                      open the fuzzel picker and apply the selection
#   set <mode>                apply off|receiver|broadcast|group directly
#   listen <host:port>|auto   point the local snapclient at a remote server
#   status [--waybar]         one line "<icon> <mode>" (or just the icon)
#   restore                   re-apply the saved mode (boot oneshot, silent)
#   list                      mode<TAB>active<TAB>description rows
#
# Modes (state in ~/.config/sway/.audio-mode, one word, default off):
#   off        MPD -> PipeWire (local only); snapserver and snapclient stopped,
#              so nothing is sent, received, or advertised
#   receiver   MPD -> PipeWire (local); snapserver stopped; snapclient listens
#              to a remote server (Avahi discovery or a chosen host)
#   broadcast  MPD -> PipeWire + fifo -> snapserver; snapclient stopped; other
#              rooms can join <hostname>.local:1704
#   group      MPD -> fifo -> snapserver; local snapclient feeds PipeWire from
#              127.0.0.1:1704, so this Pi and every room are sample-synced
#
# Ordering rules (see multiroomaudio.md):
#   - snapserver must be up before MPD's Multiroom fifo output is enabled
#   - the Multiroom output must be disabled before snapserver stops
# so failures never leave the fifo output enabled with no reader.
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}

STATE="$HOME/.config/sway/.audio-mode"
ENVF="$HOME/.config/snapclient/env"
MPD_OUT="PipeWire Sound Server"

# mDNS name receivers should use ("hackpi" -> "hackpi.local").
HOSTLOCAL=$(hostname)
case "$HOSTLOCAL" in *.*) ;; *) HOSTLOCAL="$HOSTLOCAL.local" ;; esac

notify() {
    if [ "${QUIET:-0}" = 1 ]; then
        printf 'audio-mode: %s\n' "$1"
        return 0
    fi
    notify-send --expire-time=2000 \
        --hint=string:x-canonical-private-synchronous:audio-mode "Audio mode" "$1"
}

# Ask waybar to re-run the custom/audio exec now ("signal": 8) instead of
# waiting for the 5 s poll.
refresh_waybar() { pkill -RTMIN+8 -x waybar 2>/dev/null || true; }

read_mode() {
    local m=""
    [ -f "$STATE" ] && read -r m _ < "$STATE"
    case "$m" in off|receiver|broadcast|group) printf '%s' "$m" ;; *) printf 'off' ;; esac
}

save_mode() { printf '%s\n' "$1" > "$STATE"; }

# Icon set verified against the installed FontAwesome 4.7: f028 speaker
# (receiver; f001 music note looked like Euphonica's headphones and f012
# signal bars looked like wifi), f0a1 bullhorn (broadcast; FA 4 has no
# broadcast-tower f519), f0c0 users, f204 toggle-off.
icon_for() {
    case "$1" in
        off)       printf '\uf204' ;;
        receiver)  printf '\uf028' ;;
        broadcast) printf '\uf0a1' ;;
        group)     printf '\uf0c0' ;;
    esac
}

write_env_auto() {
    printf '# comment-only: snapclient uses Avahi discovery (set by audio-mode.sh)\n' > "$ENVF"
}

# Group mode points the local client at 127.0.0.1; leaving group must drop that
# override or receiver would keep dialing the (now stopped) local server.
clear_group_env() {
    if grep -qE '^SNAPCLIENT_OPTS=--host (127\.0\.0\.1|localhost)([[:space:]]|$)' "$ENVF" 2>/dev/null; then
        write_env_auto
    fi
}

fifo_check() {
    if [ -e /tmp/snapfifo ] && [ ! -p /tmp/snapfifo ]; then
        notify "ERROR: /tmp/snapfifo exists and is not a fifo (run setup-pi.sh)"
        return 1
    fi
    if [ -p /tmp/snapfifo ] && [ ! -w /tmp/snapfifo ]; then
        notify "ERROR: /tmp/snapfifo not writable (stale owner; run setup-pi.sh)"
        return 1
    fi
    return 0
}

# snapserver creates /tmp/snapfifo itself (same user as MPD), so starting it
# before MPD's fifo output is enabled is safe.
server_up() {
    systemctl --user start snapserver || return 1
    for _ in $(seq 1 15); do
        systemctl --user is-active --quiet snapserver && return 0
        sleep 0.2
    done
    return 1
}

# Snapserver failed while applying broadcast/group: fall back to the previously
# saved mode (off for a dead server, receiver/off otherwise), without touching
# the state file.
revert_to_saved() {
    case "$(read_mode)" in
        receiver) apply_receiver >/dev/null 2>&1 || true ;;
        *)        apply_off >/dev/null 2>&1 || true ;;
    esac
}

apply_off() {
    clear_group_env
    mpc enable only "$MPD_OUT" || { notify "ERROR: MPD unavailable"; return 1; }
    systemctl --user stop snapserver
    systemctl --user stop snapclient
}

apply_receiver() {
    mpc enable only "$MPD_OUT" || { notify "ERROR: MPD unavailable"; return 1; }
    systemctl --user reset-failed snapclient 2>/dev/null
    systemctl --user restart snapclient
    systemctl --user stop snapserver
}

apply_broadcast() {
    fifo_check || return 1
    if ! server_up; then
        notify "ERROR: snapserver failed to start (systemctl --user status snapserver)"
        revert_to_saved
        return 1
    fi
    systemctl --user stop snapclient
    if ! mpc enable only "$MPD_OUT" "Multiroom"; then
        notify "ERROR: MPD unavailable"
        systemctl --user stop snapserver
        systemctl --user start snapclient
        return 1
    fi
}

apply_group() {
    fifo_check || return 1
    if ! server_up; then
        notify "ERROR: snapserver failed to start (systemctl --user status snapserver)"
        revert_to_saved
        return 1
    fi
    printf 'SNAPCLIENT_OPTS=--host 127.0.0.1 --port 1704\n' > "$ENVF"
    systemctl --user reset-failed snapclient 2>/dev/null
    systemctl --user restart snapclient
    if ! mpc enable only Multiroom; then
        notify "ERROR: MPD unavailable"
        systemctl --user stop snapserver
        systemctl --user start snapclient
        return 1
    fi
}

do_set() {
    case "$1" in
        off)
            apply_off || return 1
            save_mode off
            notify "Off — local playback only (Snapcast stopped)" ;;
        receiver)
            clear_group_env
            apply_receiver || return 1
            save_mode receiver
            notify "Receiver — listening for a remote Snapcast server" ;;
        broadcast)
            apply_broadcast || return 1
            save_mode broadcast
            notify "Broadcast — other rooms can join $HOSTLOCAL:1704" ;;
        group)
            apply_group || return 1
            save_mode group
            notify "Group — synced with other rooms (buffer 150 ms)" ;;
        *)
            notify "ERROR: unknown mode '$1'"
            return 1 ;;
    esac
    refresh_waybar
}

listen_to() {
    local target="$1" name="${2:-}" host port text
    if [ "$target" = auto ]; then
        write_env_auto
        text="Automatic (discovery)"
    else
        host="${target%:*}"
        port="${target##*:}"
        if [ -z "$host" ] || ! printf '%s' "$port" | grep -qE '^[0-9]+$'; then
            notify "ERROR: invalid server '$target' (expected host:port)"
            return 1
        fi
        printf 'SNAPCLIENT_OPTS=--host %s --port %s\n' "$host" "$port" > "$ENVF"
        if [ -n "$name" ]; then
            text="Listening to $name ($host:$port)"
        else
            text="Listening to $host:$port"
        fi
    fi
    apply_receiver || return 1
    save_mode receiver
    notify "$text"
    refresh_waybar
}

# Decode Avahi's decimal escapes ("Snapcast\032\0352" -> "Snapcast #2").
decode_name() {
    printf '%s' "$1" | awk '{
        s = $0; out = ""
        while (match(s, /\\[0-9][0-9][0-9]/)) {
            out = out substr(s, 1, RSTART - 1) sprintf("%c", substr(s, RSTART + 1, 3) + 0)
            s = substr(s, RSTART + RLENGTH)
        }
        print out s
    }'
}

# Second fuzzel list built from Avahi. avahi-browse -rpt emits terminated
# records: =;iface;IPv4;name;_snapcast._tcp;domain;host;ip;port;
# One row per interface/address: skip loopback and keep the first IPv4 row
# per hostname so a server reachable over several NICs appears once.
pick_server() {
    if ! command -v avahi-browse >/dev/null; then
        notify "ERROR: avahi-utils missing (sudo apt install avahi-utils)"
        return 1
    fi
    local labels=() targets=() seen=" " eq iface proto name type domain host ip port rest
    while IFS=';' read -r eq iface proto name type domain host ip port rest; do
        [ "$eq" = "=" ] || continue
        [ "$proto" = IPv4 ] || continue
        [ "$iface" = lo ] && continue
        [ -n "$ip" ] && [ -n "$port" ] || continue
        case "$seen" in *" $host "*) continue ;; esac
        seen="$seen$host "
        labels+=("$(decode_name "$name") ($ip:$port)")
        targets+=("$ip:$port")
    done < <(avahi-browse -rpt _snapcast._tcp 2>/dev/null)

    if [ "${#labels[@]}" -eq 0 ]; then
        notify "No Snapcast servers found (set SNAPCLIENT_OPTS manually in ~/.config/snapclient/env)"
        return 1
    fi

    local n=$(( ${#labels[@]} + 1 )) sel choice
    sel=$({
        for i in "${!labels[@]}"; do printf '%d) %s\n' "$((i + 1))" "${labels[$i]}"; done
        printf '%d) Automatic (discovery)\n' "$n"
    } | fuzzel --dmenu --width 56 --dpi-aware=no --font "JetBrains Mono:size=13" --prompt "Snapcast server: ")
    sel=$(printf '%s\n' "$sel" | head -n1)
    choice=$(printf '%s\n' "$sel" | grep -oE '^[0-9]+' | head -n1)
    [ -n "$choice" ] || return 0
    if [ "$choice" -eq "$n" ]; then
        listen_to auto
    elif [ "$choice" -ge 1 ] && [ "$choice" -lt "$n" ]; then
        listen_to "${targets[$((choice - 1))]}" "${labels[$((choice - 1))]%% (*}"
    fi
}

pick() {
    local mode sel n
    mode=$(read_mode)
    # The panel has a ~260 DPI panel but scale 1; fuzzel's default dpi-aware=auto
    # then renders pickers wider than the 720px screen. Pin the size and turn
    # DPI scaling off for the picker.
    sel=$(printf '%s\n' \
        "1) Off       — local playback only$([ "$mode" = off ] && printf '  <- current')" \
        "2) Receiver  — remote Snapcast server$([ "$mode" = receiver ] && printf '  <- current')" \
        "3) Broadcast — send this Pi's music$([ "$mode" = broadcast ] && printf '    <- current')" \
        "4) Group     — sync with other rooms$([ "$mode" = group ] && printf '  <- current')" \
        "5) Listen to… — choose a discovered server" \
        | fuzzel --dmenu --width 56 --dpi-aware=no --font "JetBrains Mono:size=13" --prompt "Audio mode: ")
    sel=$(printf '%s\n' "$sel" | head -n1)
    n=$(printf '%s\n' "$sel" | grep -oE '^[0-9]+' | head -n1)
    [ -n "$n" ] || exit 0
    case "$n" in
        1) do_set off ;;
        2) do_set receiver ;;
        3) do_set broadcast ;;
        4) do_set group ;;
        5) pick_server ;;
    esac
}

do_status() {
    local mode
    mode=$(read_mode)
    if [ "${1:-}" = --waybar ]; then
        printf '%s\n' "$(icon_for "$mode")"
    else
        printf '%s %s\n' "$(icon_for "$mode")" "$mode"
    fi
}

do_list() {
    local mode
    mode=$(read_mode)
    printf 'off\t%s\tOff — local playback only (Snapcast stopped)\n' "$([ "$mode" = off ] && echo 1 || echo 0)"
    printf 'receiver\t%s\tReceiver — listen to a remote Snapcast server\n' "$([ "$mode" = receiver ] && echo 1 || echo 0)"
    printf 'broadcast\t%s\tBroadcast — send this Pi'"'"'s music to the network\n' "$([ "$mode" = broadcast ] && echo 1 || echo 0)"
    printf 'group\t%s\tGroup — this Pi and the other rooms play in sync\n' "$([ "$mode" = group ] && echo 1 || echo 0)"
}

do_restore() {
    local mode i
    mode=$(read_mode)
    for i in $(seq 1 30); do
        mpc outputs >/dev/null 2>&1 && break
        sleep 0.5
    done
    QUIET=1
    case "$mode" in
        receiver)  apply_receiver ;;
        broadcast) apply_broadcast ;;
        group)     apply_group ;;
        *)         mode=off; apply_off ;;
    esac
    printf 'audio-mode: restore attempted for mode %s\n' "$mode"
}

case "${1:-pick}" in
    pick)    pick ;;
    set)     do_set "${2:?usage: audio-mode.sh set off|receiver|broadcast|group}" ;;
    listen)  listen_to "${2:?usage: audio-mode.sh listen <host:port>|auto}" "${3:-}" ;;
    status)  shift; do_status "${1:-}" ;;
    restore) do_restore ;;
    list)    do_list ;;
    *) echo "usage: audio-mode.sh [pick|set <mode>|listen <host:port|auto>|status [--waybar]|restore|list]" >&2; exit 2 ;;
esac
