#!/bin/bash
# Plug/unplug notifications: a PipeWire audio output or an external disk
# appearing or disappearing posts one swaync notification. No keybind - this
# runs as device-watch.service (user scope, tied to pipewire.service).
#
# Event-driven, not polled. Two producers push one token per event into a FIFO
# and the main loop blocks on read():
#   udevadm monitor --udev --subsystem-match=block  -> "disk"  (add/remove)
#   pw-dump -m -N                                   -> "audio" (PipeWire registry change)
# A snapshot (device.sh list / lsblk) is taken only after an event arrives,
# SETTLE seconds later, so udev rules, devmon's automount and PipeWire's node
# creation have finished. pw-dump must be run as "-m -N": passing "-C never"
# makes it emit nothing at all. Tokens are coalesced (see the main loop) so a
# chattering PipeWire cannot delay a disk event.
#
# Producers must never call log(): their stdout IS the fifo, so a log line
# would be read back as an event token.
#
# Priming rules keep boot quiet:
#   - producer startup chatter is discarded: pw-dump -m dumps the whole registry
#     as its first batch, so PRIME_DELAY seconds of tokens are drained before
#     the first snapshot.
#   - audio: the baseline is the first *non-empty* sink list, so a watcher that
#     starts before PipeWire has enumerated the card announces nothing, and a
#     later plug/unplug still fires (the baseline is only taken once).
#   - disks: the baseline is the first snapshot, taken after PRIME_DELAY, by
#     which time the system disk and devmon's automounts exist.
#
# Disk rules (lsblk, whole devices only): TYPE disk or dm, minus the disk that
# holds / (the Pi's own NVMe/SD), minus zram*/loop*/ram*. dm is included so
# mapped devices (and the smoke test's simulated disk) are visible; a physical
# USB disk is always detected as its own sd*/nvme*/mmcblk* node regardless.
#
# Test hooks (used by smoke-test.sh; never set by the service):
#   DEVICE_WATCH_SINKS_CMD    override the audio snapshot command
#   DEVICE_WATCH_DISKS_CMD    override the disk snapshot command
#   DEVICE_WATCH_EVENTS_CMD   replace both producers with this event producer
#   DEVICE_WATCH_SETTLE       seconds between an event and its snapshot
#   DEVICE_WATCH_PRIME_DELAY  seconds of producer startup chatter to discard
#   DEVICE_WATCH_LOG          log file (default $XDG_RUNTIME_DIR/swaymp-device-watch.log)
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}

SETTLE=${DEVICE_WATCH_SETTLE:-1.5}
PRIME_DELAY=${DEVICE_WATCH_PRIME_DELAY:-3}
LOG=${DEVICE_WATCH_LOG:-$XDG_RUNTIME_DIR/swaymp-device-watch.log}
SINKS_CMD=${DEVICE_WATCH_SINKS_CMD:-bash $HOME/.config/sway/device.sh list}
DISKS_CMD=${DEVICE_WATCH_DISKS_CMD:-}
EVENTS_CMD=${DEVICE_WATCH_EVENTS_CMD:-}

log() {
    printf '%s %s\n' "$(date '+%H:%M:%S')" "$1"
    printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" >> "$LOG" 2>/dev/null
}

notify() {
    notify-send --expire-time=4000 \
        --hint=string:x-canonical-private-synchronous:"device-watch-$3" "$1" "$2" 2>/dev/null
}

# "id<TAB>default<TAB>title" rows (device.sh list) -> "id|title". The default
# flag is deliberately dropped: switching outputs is not a plug event.
# PipeWire's fallback null sink ("Dummy Output") is dropped too - it appears
# whenever the real sink is briefly gone, so announcing it turns one plug into
# a connected+disconnected pair and buries the event the user cares about.
sinks_snapshot() {
    bash -c "$SINKS_CMD" 2>/dev/null | awk -F'\t' '
        NF == 0 { next }
        NF == 1 { if ($0 != "Dummy Output" && $0 != "AutoNullSink") print; next }
        {
            if (NF >= 3) title = $3; else title = $2
            if (title == "Dummy Output" || title == "AutoNullSink") next
            print $1 "|" title
        }' | sort
}

disks_snapshot() {
    if [ -n "$DISKS_CMD" ]; then
        bash -c "$DISKS_CMD" 2>/dev/null | sort
        return 0
    fi
    local root
    root=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null)
    # -l (flat list): the tree view prefixes child rows with box-drawing
    # characters in the NAME column, which would corrupt the snapshot keys.
    lsblk -ln -o NAME,TYPE,SIZE,VENDOR,MODEL 2>/dev/null | awk -v root="$root" '
        {
            name = $1; type = $2; size = $3
            desc = ""
            for (i = 4; i <= NF; i++) desc = desc (i > 4 ? " " : "") $i
            gsub(/^[ \t]+|[ \t]+$/, "", desc)
            if (type != "disk" && type != "dm") next
            if (name == root) next
            if (name ~ /^(zram|loop|ram)/) next
            printf "%s|%s|%s\n", name, desc, size
        }' | sort
}

# name|desc|size -> "SanDisk Ultra (32G)" / "smoke_disk (8M)"
disk_label() {
    local name=${1%%|*} rest desc
    rest=${1#*|}
    desc=${rest%|*}
    [ -n "$desc" ] && printf '%s (%s)' "$desc" "${rest##*|}" || printf '%s (%s)' "$name" "${rest##*|}"
}

# devmon automounts a little later than the node appears, so look for the mount
# point for a couple of seconds before giving up on it.
disk_mount() {
    local name="$1" i src tgt fs
    # devmon can only automount something that has a filesystem. A raw mapper or
    # a partitionless disk never gets mounted, so don't spend three seconds
    # waiting for a mount that cannot happen - that delay used to be most of the
    # plug notification's latency.
    fs=$(lsblk -n -o FSTYPE "$name" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$fs" ]; then i=3; else i=1; fi
    while [ "$i" -gt 0 ]; do
        while read -r src tgt; do
            case "${src##*/}" in
                "$name"|"$name"[0-9p]*) printf '%s' "$tgt"; return 0 ;;
            esac
        done < <(findmnt -rn -o SOURCE,TARGET 2>/dev/null)
        i=$((i - 1))
        [ "$i" -gt 0 ] && sleep 0.5
    done
    return 1
}

added_lines() {
    local a="$1" b="$2"
    [ -z "$b" ] && return 0
    if [ -z "$a" ]; then printf '%s\n' "$b"; return 0; fi
    comm -13 <(printf '%s\n' "$a") <(printf '%s\n' "$b")
}

# Removals are announced first so an addition is the notification that ends up
# on screen: swaync replaces a notification that carries the same synchronous
# id, and a plug almost always removes PipeWire's fallback sink at the same
# time - posting the removal last used to hide every "Connected" popup behind a
# "Disconnected" one. Distinct ids per direction keep the pair separate.
handle_sinks() {
    local cur="$1" row title
    while IFS= read -r row; do
        [ -n "$row" ] || continue
        title=${row#*|}
        log "audio output disconnected: $title"
        notify "Audio output" "Disconnected: $title" audio-del
    done < <(added_lines "$cur" "$prev_sinks")
    while IFS= read -r row; do
        [ -n "$row" ] || continue
        title=${row#*|}
        log "audio output connected: $title"
        notify "Audio output" "Connected: $title" audio-add
    done < <(added_lines "$prev_sinks" "$cur")
}

handle_disks() {
    local cur="$1" row name label mp
    while IFS= read -r row; do
        [ -n "$row" ] || continue
        name=${row%%|*}
        label=$(disk_label "$row")
        log "disk removed: $name ($label)"
        notify "Disk removed" "$label" disk-del
    done < <(added_lines "$cur" "$prev_disks")
    while IFS= read -r row; do
        [ -n "$row" ] || continue
        name=${row%%|*}
        label=$(disk_label "$row")
        if mp=$(disk_mount "$name"); then
            log "disk plugged in: $name ($label) at $mp"
            notify "Disk plugged in" "$label mounted at $mp" disk-add
        else
            log "disk plugged in: $name ($label)"
            notify "Disk plugged in" "$label" disk-add
        fi
    done < <(added_lines "$prev_disks" "$cur")
}

# UDEV lines are "UDEV [timestamp] action /devices/... (subsystem)". Only
# add/remove matter; loop*/zram*/ram* nodes are filtered here too so a
# loop-backed mapper (the smoke test) still shows up through its dm node.
# The consumer is a bash read loop, not awk/grep|sed: the Pi ships mawk, which
# buffers its output and ignores fflush(), and grep|sed chains proved flaky
# through a fifo. bash reads a pipe line-by-line immediately and printf writes
# unbuffered, so tokens reach the watcher the moment the event fires.
disk_events() {
    udevadm monitor --udev --subsystem-match=block 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            'UDEV  ['*'] add '*|'UDEV  ['*'] remove '*)
                case "$line" in
                    */loop[0-9]*|*/zram[0-9]*|*/ram[0-9]*) continue ;;
                esac
                printf 'disk\n'
                ;;
        esac
    done
}

# pw-dump -m re-dumps the changed objects as JSON arrays; a column-0 "]" closes
# one array, i.e. one registry change. Bluetooth sinks, USB sinks and the
# fallback null sink all arrive as registry changes, which udev alone would
# miss. pw-dump must be run as "-m -N": passing "-C never" makes it emit
# nothing at all.
audio_events() {
    pw-dump -m -N 2>/dev/null | while IFS= read -r line; do
        [ "$line" = "]" ] && printf 'audio\n'
    done
}

# A producer that dies (pw-dump exits when PipeWire restarts) is restarted after
# a short gap: this is a restart guard, not a poll for state.
supervised() {
    while true; do
        "$@"
        sleep 2
    done
}

EVENTS=$XDG_RUNTIME_DIR/swaymp-device-watch.events
rm -f "$EVENTS"
mkfifo "$EVENTS" || { log "cannot create event fifo $EVENTS"; exit 1; }
# O_RDWR keeps the fifo open from both ends: producers never block on an absent
# reader and the loop never sees EOF when a producer exits.
exec 3<>"$EVENTS"

pids=()
if [ -n "$EVENTS_CMD" ]; then
    bash -c "$EVENTS_CMD" > "$EVENTS" & pids+=($!)
else
    supervised disk_events > "$EVENTS" & pids+=($!)
    supervised audio_events > "$EVENTS" & pids+=($!)
fi

cleanup() {
    for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
    exec 3>&- 2>/dev/null
    rm -f "$EVENTS"
}
trap 'cleanup; exit 0' INT TERM
trap cleanup EXIT

prev_sinks="" primed_sinks=0 prev_disks="" primed_disks=0
sleep "$PRIME_DELAY"
while read -t 0.2 -r _ <&3; do :; done
log "device-watch started (event-driven, settle ${SETTLE}s)"

prev_disks=$(disks_snapshot)
primed_disks=1
prev_sinks=$(sinks_snapshot)
[ -n "$prev_sinks" ] && primed_sinks=1

# Coalesce bursts: pw-dump -m re-dumps one array per changed object, so an
# active stream emits ~4-5 audio tokens per second. Handling every token
# individually makes the queue grow faster than the loop drains it, and a disk
# token would then sit behind minutes of audio tokens. Instead: take the first
# token, swallow everything currently buffered, then run at most one pass per
# class. A disk event is therefore handled within one SETTLE window even while
# PipeWire is chattering.
need_disk=0 need_audio=0
while read -r what <&3; do
    case "$what" in disk) need_disk=1 ;; audio) need_audio=1 ;; esac
    n=0
    while [ "$n" -lt 5000 ] && read -t 0.1 -r w <&3; do
        case "$w" in disk) need_disk=1 ;; audio) need_audio=1 ;; esac
        n=$((n+1))
    done
    sleep "$SETTLE"
    if [ "$need_disk" = 1 ]; then
        need_disk=0
        cur_disks=$(disks_snapshot)
        handle_disks "$cur_disks"
        prev_disks="$cur_disks"
    fi
    if [ "$need_audio" = 1 ]; then
        need_audio=0
        cur_sinks=$(sinks_snapshot)
        if [ "$primed_sinks" = 0 ]; then
            [ -n "$cur_sinks" ] && { prev_sinks="$cur_sinks"; primed_sinks=1; }
        else
            handle_sinks "$cur_sinks"
            prev_sinks="$cur_sinks"
        fi
    fi
done
