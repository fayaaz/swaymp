#!/bin/bash
# PipeWire output switcher ($mod+d): cycle the default audio sink through the
# outputs that are currently connected and report each switch with a
# synchronous notification. Actions: next (default), prev, pick (fuzzel picker),
# list (id<TAB>default<TAB>title rows, for scripts and the smoke test).
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}

action="${1:-next}"

# "id<TAB>default(0|1)<TAB>title" for every PipeWire Audio/Sink, from wpctl status.
# Works with both wpctl layouts (flat tree and Audio/Video/Settings trees).
sinks() {
    wpctl status 2>/dev/null | awk '
        BEGIN { tree = 1; insinks = 0 }
        /^Audio$/ { tree = 1; insinks = 0; next }
        /^(Video|Settings|Error)/ { tree = 0; insinks = 0; next }
        tree && /Sinks:/ { insinks = 1; next }
        insinks {
            line = $0
            if (line !~ /^[^A-Za-z]*[0-9]+\. /) { insinks = 0; next }
            def = (line ~ /\*[ ]*[0-9]+\./) ? 1 : 0
            match(line, /[0-9]+\. /)
            id = substr(line, RSTART, RLENGTH - 2)
            title = substr(line, RSTART + RLENGTH)
            sub(/[ \t]*\[[^]]*\][ \t]*$/, "", title)
            if (match(title, /"[^"]+"/)) title = substr(title, RSTART + 1, RLENGTH - 2)
            gsub(/^[ \t]+|[ \t]+$/, "", title)
            if (title != "") printf "%s\t%s\t%s\n", id, def, title
        }
    '
}

default_id() {
    wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk 'NR == 1 { gsub(/[^0-9]/, "", $2); print $2 }'
}

notify() {
    notify-send --expire-time=2000 --hint=string:x-canonical-private-synchronous:audio-output "Audio output" "$1"
}

mapfile -t rows < <(sinks)
count=${#rows[@]}

if [ "$action" = list ]; then
    [ "$count" -gt 0 ] && printf '%s\n' "${rows[@]}"
    exit 0
fi

if [ "$count" -eq 0 ]; then
    notify "No outputs available"
    exit 1
fi

cur=""
idx=-1
for i in "${!rows[@]}"; do
    IFS=$'\t' read -r id def title <<<"${rows[$i]}"
    [ "$def" = 1 ] && cur=$id
    [ "$id" = "$cur" ] && idx=$i
done
[ -z "$cur" ] && cur=$(default_id)
if [ "$idx" -lt 0 ] && [ -n "$cur" ]; then
    for i in "${!rows[@]}"; do
        IFS=$'\t' read -r id _ _ <<<"${rows[$i]}"
        [ "$id" = "$cur" ] && idx=$i
    done
fi

if [ "$action" = pick ]; then
    sel=$(for i in "${!rows[@]}"; do
        IFS=$'\t' read -r id def title <<<"${rows[$i]}"
        printf '%d) %s%s\n' "$((i + 1))" "$title" "$([ "$i" = "$idx" ] && printf '  <- current')"
    done | fuzzel --dmenu --width 44 --prompt "Audio output: ")
    sel=$(printf '%s\n' "$sel" | head -n1)
    n=$(printf '%s\n' "$sel" | grep -oE '^[0-9]+' | head -n1)
    [ -n "$n" ] || exit 0
    target=$((n - 1))
    [ "$target" -ge 0 ] && [ "$target" -lt "$count" ] || exit 0
else
    case "$action" in
        next) target=$(( (idx + 1) % count )) ;;
        prev) target=$(( (idx - 1 + count) % count )) ;;
        *) exit 1 ;;
    esac
fi

IFS=$'\t' read -r tid _ ttitle <<<"${rows[$target]}"
[ -n "$tid" ] || exit 1
wpctl set-default "$tid" >/dev/null 2>&1

if [ "$count" -eq 1 ]; then
    notify "$ttitle (only output)"
else
    notify "$((target + 1))/$count -> $ttitle"
fi
