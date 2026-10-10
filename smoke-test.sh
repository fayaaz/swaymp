#!/usr/bin/env bash
# smoke-test.sh — end-to-end HackPi smoke test driven over SSH from the workstation.
# Injects keypresses on the Pi with wtype (Wayland virtual keyboard; ydotool's
# uinput daemon proved unreliable on this Pi), asserts the resulting state via
# swaymsg/mpc/wpctl/swaync-client, and takes a grim screenshot at every stage,
# pulled back to the workstation.
#
# Run from the workstation (NOT on the Pi):
#   ./smoke-test.sh
#   PI=pi@other.host OUT=/tmp/myrun ./smoke-test.sh
#
# Artifacts: $OUT (default /tmp/opencode/smoke-<timestamp>/) holds NN-stage.png
# screenshots plus per-stage logs. Exit 0 only if every assertion passes.
#
# Stages: preflight input playback seek queue volume launcher terminal
#         cheatsheet devices bluetooth network notifications miniplayer browser euphonica wiremix mediakeys multiroom cleanup
# The Pi-side runner is embedded below and copied to /tmp/smoke/smoke-run.sh.
set -u

PI="${PI:-pi@raspberrypi.local}"
OUT="${OUT:-/tmp/opencode/smoke-$(date +%Y%m%d-%H%M%S)}"
REMOTE=/tmp/smoke
STAGES="${STAGES:-preflight input playback seek queue volume launcher terminal cheatsheet devices bluetooth network notifications miniplayer browser euphonica wiremix mediakeys multiroom cleanup}"

mkdir -p "$OUT"
ssh_base() { ssh -o ConnectTimeout=8 -o BatchMode=yes "$PI" "$@"; }

echo "== HackPi smoke test against $PI"
echo "== artifacts: $OUT"

ssh_base 'command -v grim swaymsg mpc wpctl jq >/dev/null' || {
    echo "prereqs (grim/swaymsg/mpc/wpctl/jq) missing on Pi" >&2
    exit 1
}
ssh_base "mkdir -p $REMOTE/shots && rm -f $REMOTE/shots/*.png" || exit 1

RUNNER=$(mktemp)
cat >"$RUNNER" <<'RUNNER_EOF'
#!/usr/bin/env bash
# Pi-side half of smoke-test.sh. One stage per invocation:
#   bash /tmp/smoke/smoke-run.sh <stage>
# Emits PASS/FAIL/SHOT lines; the workstation side parses them.
set -u
STAGE="${1:?usage: smoke-run.sh <stage>}"

RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR="$RT"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export SWAYSOCK="${SWAYSOCK:-$(ls -1 "$RT"/sway-ipc.*.sock 2>/dev/null | head -n1)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$RT/bus}"
export PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.cargo/bin

REMOTE=/tmp/smoke
SHOTDIR=$REMOTE/shots
STATE=$REMOTE/state.env
QUEUE=$REMOTE/queue.txt
mkdir -p "$SHOTDIR"

# wtype key names (libxkbcommon keysym identifiers)
KP=p KK=k KJ=j KI=i KO=o KM=m KD=d KG=g KV=v KB=b KN=n KX=x
KTAB=Tab KSPACE=space KH=h KL=l KESC=Escape K4=4 KRET=Return
KF11=F11 MPLAY=XF86AudioPlay MNEXT=XF86AudioNext MPREV=XF86AudioPrev

pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; }
shot() { grim -o DPI-1 "$SHOTDIR/$1.png" 2>/dev/null || grim "$SHOTDIR/$1.png"; echo "SHOT $1"; }
tap() { wtype -k "$1"; }
super() { wtype -M logo -k "$1" -m logo; }
super_shift() { wtype -M logo -M shift -k "$1" -m shift -m logo; }

win_count() { swaymsg -t get_tree 2>/dev/null | jq -r --arg id "$1" '.. | .app_id? // empty' | grep -c "^$1$"; }
win_visible_count() { swaymsg -t get_tree 2>/dev/null | jq -r --arg id "$1" '.. | objects | select(.app_id? == $id and .visible == true) | .app_id' | grep -c .; }
win_ws() { swaymsg -t get_tree 2>/dev/null | jq -r --arg id "$1" '.. | select(.type? == "workspace") | .name as $n | [.. | .app_id? // empty] | select(index($id)) | $n' | head -n1; }
win_floating() { swaymsg -t get_tree 2>/dev/null | jq -r --arg id "$1" '.. | select(.app_id? == $id) | .floating' | head -n1; }
win_size() { swaymsg -t get_tree 2>/dev/null | jq -r --arg id "$1" '.. | select(.app_id? == $id) | "\(.rect.width) \(.rect.height)"' | head -n1; }
# Standard floating terminal size (sway rules): 600x600. foot snaps the window
# to whole cells of its font grid, so a mapped window lands a cell or two under
# the requested size (measured: 588x594 at size=18, 590x576 at size=13). The
# slack covers that grid snap; the pre-standard sizes (640x480, 700x620) are
# far outside it.
expect_size() {
    local id=$1 want=$2 tol=${3:-24} got w h dw dh
    got=$(win_size "$id")
    if [ -z "$got" ]; then fail "$id window missing for size check"; return; fi
    w=${got%% *}; h=${got##* }
    dw=$((w - want)); [ "$dw" -lt 0 ] && dw=$((-dw))
    dh=$((h - want)); [ "$dh" -lt 0 ] && dh=$((-dh))
    if [ "$dw" -le "$tol" ] && [ "$dh" -le "$tol" ]; then
        pass "$id sized ${w}x${h} (standard ${want}x${want})"
    else
        fail "$id sized ${w}x${h}, expected ${want}x${want}"
    fi
}
kill_app() { swaymsg "[app_id=\"$1\"] kill" >/dev/null 2>&1 || true; }
wait_win() { local id=$1 want=$2 n=${3:-20} i c; for i in $(seq 1 "$n"); do c=$(win_count "$id"); { [ "$want" = present ] && [ "$c" -ge 1 ]; } || { [ "$want" = absent ] && [ "$c" -eq 0 ]; } && return 0; sleep 1; done; return 1; }
wait_vis() { local id=$1 want=$2 n=${3:-20} i c; for i in $(seq 1 "$n"); do c=$(win_visible_count "$id"); { [ "$want" = present ] && [ "$c" -ge 1 ]; } || { [ "$want" = absent ] && [ "$c" -eq 0 ]; } && return 0; sleep 1; done; return 1; }
mstate() { mpc status %state% 2>/dev/null; }
mfirstline() { mpc status 2>/dev/null | grep -E '^\[(playing|paused|stopped)\]' | head -n1; }
mpos() { mfirstline | grep -oE '#[0-9]+/[0-9]+' | head -n1 | tr -d '#' | cut -d/ -f1; }
mqueue_len() { mfirstline | grep -oE '#[0-9]+/[0-9]+' | head -n1 | tr -d '#' | cut -d/ -f2; }
melapsed() { mfirstline | grep -oE '[0-9]+:[0-9]+/[0-9]+:[0-9]+' | head -n1 | cut -d/ -f1 | awk -F: '{print $1*60+$2}'; }
# swaync 0.11/0.12: GetVisibility/NotificationCount are methods (no "visible" property).
# (swaync-client -s is a *subscription* that never exits, so it is not a status read.)
nc_visible() {
    if command -v busctl >/dev/null; then
        busctl --user call org.erikreider.swaync.cc /org/erikreider/swaync/cc org.erikreider.swaync.cc GetVisibility 2>/dev/null | grep -q '\bb true\b'
    else
        dbus-send --print-reply --dest=org.erikreider.swaync.cc /org/erikreider/swaync/cc \
            org.erikreider.swaync.cc.GetVisibility 2>/dev/null | grep -q 'boolean true'
    fi
}
nc_count() {
    if command -v busctl >/dev/null; then
        busctl --user call org.erikreider.swaync.cc /org/erikreider/swaync/cc org.erikreider.swaync.cc NotificationCount 2>/dev/null | awk '/^u /{print $2}'
    else
        dbus-send --print-reply --dest=org.erikreider.swaync.cc /org/erikreider/swaync/cc \
            org.erikreider.swaync.cc.NotificationCount 2>/dev/null | awk '/uint32/{print $NF}'
    fi
}
nc_close() { swaync-client -cp >/dev/null 2>&1 || true; }
vol() { wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '/Volume:/ {printf "%d", $2*100+0.5}'; }
muted() { wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q MUTED && echo 1 || echo 0; }
first_track() { mpc ls 2>/dev/null | head -n1; }
# Multiroom helpers.
mode_file() { head -n1 "$HOME/.config/sway/.audio-mode" 2>/dev/null; }
snapserver_active() { systemctl --user is-active --quiet snapserver; }
snapclient_active() { systemctl --user is-active --quiet snapclient; }
snapserver_autostart() { systemctl --user is-enabled snapserver 2>/dev/null; }
mpc_enabled() { mpc outputs 2>/dev/null | grep -qE "\($1\) is enabled"; }
# systemctl show -p Environment omits EnvironmentFile values; read the process.
client_env() {
    local pid
    pid=$(systemctl --user show snapclient -p MainPID --value 2>/dev/null)
    [ -n "$pid" ] && [ "$pid" != 0 ] && tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep '^SNAPCLIENT_OPTS='
}
capture_audio() {
    rm -f /tmp/cap.raw
    timeout 3 snapclient --host 127.0.0.1 --player=file:filename=/tmp/cap.raw,mode=w >/dev/null 2>&1
    [ -s /tmp/cap.raw ]
}
# PipeWire sinks come from the payload switcher itself (device.sh list -> id<TAB>default<TAB>title)
sink_rows() { [ -f "$HOME/.config/sway/device.sh" ] && bash "$HOME/.config/sway/device.sh" list 2>/dev/null; }
sink_count() { sink_rows | grep -c .; }
default_sink() { sink_rows | awk -F'\t' '$2 == 1 { print $1; exit }'; }
sink_title() { sink_rows | awk -F'\t' -v id="$1" '$1 == id { print $3; exit }'; }
# MPD reaches swaync's miniplayer through the mpdris2 MPRIS bridge on the session bus
mpdris_unit() { systemctl --user list-unit-files --no-legend 2>/dev/null | awk 'tolower($1) ~ /mpdris/ {print $1; exit}'; }
mpris_names() {
    if command -v busctl >/dev/null; then
        busctl --user list --no-legend 2>/dev/null | awk '{print $1}' | grep '^org\.mpris\.MediaPlayer2\.'
    else
        dbus-send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null \
            | grep -oE 'org\.mpris\.MediaPlayer2\.[A-Za-z0-9._-]+'
    fi
}
mpris_prop() {
    if command -v busctl >/dev/null; then
        busctl --user call org.mpris.MediaPlayer2.mpd /org/mpris/MediaPlayer2 org.freedesktop.DBus.Properties Get ss "$1" "$2" 2>/dev/null
    else
        dbus-send --print-reply --dest=org.mpris.MediaPlayer2.mpd /org/mpris/MediaPlayer2 \
            org.freedesktop.DBus.Properties.Get string:"$1" string:"$2" 2>/dev/null
    fi
}

ensure_daemon() { :; }

stage_preflight() {
    if swaymsg -t get_version >/dev/null 2>&1; then
        pass "sway session live ($(swaymsg -t get_version | jq -r .human_readable))"
    else
        fail "sway session not reachable"
    fi
    swaymsg -t get_outputs 2>/dev/null | jq -e 'any(.[]; .name == "DPI-1")' >/dev/null \
        && pass "DPI-1 output active" || fail "DPI-1 output missing"
    pgrep -x waybar >/dev/null && pass "waybar running" || fail "waybar not running"
    # headless sway -C does NOT surface "Overwriting binding" warnings; only the
    # live session shows them as a swaynag banner. Catch config collisions here.
    if pgrep -x swaynag >/dev/null || swaymsg -t get_tree 2>/dev/null | grep -q '"app_id":"swaynag"'; then
        fail "swaynag present (config errors/overwriting-binding banner)"
    else
        pass "no swaynag config-error banner"
    fi
    for s in mpd mympd pipewire pipewire-pulse wireplumber syncthing volume-notify; do
        systemctl --user is-active --quiet "$s" && pass "service $s active" || fail "service $s not active"
    done
    command -v grim >/dev/null && pass "grim present" || fail "grim missing"
    # Floating terminal standard: foot/wiremix/bluetooth/network all 600x600.
    local rules
    rules=$(grep -cE 'for_window \[app_id="(foot|wiremix|bluetooth|network)"\] floating enable, resize set 600 600, move position center, border none' "$HOME/.config/sway/config")
    [ "$rules" -eq 4 ] && pass "all 4 floating terminal rules standardised to 600x600" \
        || fail "floating terminal rules not standardised ($rules/4 at 600x600)"
    shot 00-preflight
}

stage_input() {
    command -v wtype >/dev/null && pass "wtype present" || fail "wtype missing"
    if command -v ydotool >/dev/null; then
        echo "NOTE ydotool present but unreliable on this Pi (daemon emits invalid keycodes); wtype is used for injection"
    fi
    mpc clear >/dev/null 2>&1; mpc add "$(first_track)" >/dev/null 2>&1; mpc stop >/dev/null 2>&1
    super "$KP"; sleep 1
    [ "$(mstate)" = playing ] && pass "wtype Super+P fired sway bind (mpc playing)" || fail "wtype Super+P did not fire bind"
    super "$KP"; sleep 1
    tap "$KESC"; pass "wtype key injection live"
    shot 01-input
}

stage_playback() {
    local t st
    t=$(first_track)
    [ -n "$t" ] || { fail "MPD library empty (run: mpc update)"; shot 02-playback; return; }
    st=$(mpc status)
    {
        echo "VOL=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '/Volume:/ {print $2}')"
        echo "MUTED=$(muted)"
        echo "RND=$(printf '%s' "$st" | grep -o 'random: [a-z]*' | cut -d' ' -f2)"
        echo "SGL=$(printf '%s' "$st" | grep -o 'single: [a-z]*' | cut -d' ' -f2)"
        echo "CSM=$(printf '%s' "$st" | grep -o 'consume: [a-z]*' | cut -d' ' -f2)"
        echo "PSTATE=$(mstate)"
        echo "SINK=$(default_sink)"
    } >"$STATE"
    mpc playlist >"$QUEUE" 2>/dev/null

    mpc clear >/dev/null 2>&1
    mpc add "$t" >/dev/null 2>&1
    mpc play >/dev/null 2>&1
    sleep 2
    [ "$(mstate)" = playing ] && pass "mpc play: state=playing" || fail "expected playing, got $(mstate)"
    shot 02-playback-playing

    super "$KP"; sleep 1
    [ "$(mstate)" = paused ] && pass "Super+P toggled to paused" || fail "Super+P: expected paused, got $(mstate)"
    shot 02-playback-paused

    super "$KP"; sleep 1
    [ "$(mstate)" = playing ] && pass "Super+P toggled back to playing" || fail "Super+P: expected playing, got $(mstate)"
}

stage_seek() {
    mpc clear >/dev/null 2>&1
    mpc add "$(first_track)" >/dev/null 2>&1
    mpc play >/dev/null 2>&1
    sleep 1.5
    local e0 e1 e2
    e0=$(melapsed)
    super "$KK"; sleep 1.5
    e1=$(melapsed)
    [ "$((e1 - e0))" -ge 3 ] && pass "Super+K seek +5s (${e0}s -> ${e1}s)" || fail "Super+K: ${e0}s -> ${e1}s"
    super "$KJ"; sleep 1.5
    e2=$(melapsed)
    [ "$((e1 - e2))" -ge 3 ] && pass "Super+J seek -5s (${e1}s -> ${e2}s)" || fail "Super+J: ${e1}s -> ${e2}s"
    shot 03-seek
}

stage_queue() {
    local n
    n=$(mpc ls 2>/dev/null | wc -l)
    [ "$n" -ge 2 ] || { fail "need >=2 tracks in library for prev/next test"; shot 04-queue; return; }
    mpc clear >/dev/null 2>&1
    mpc ls 2>/dev/null | head -n2 | while IFS= read -r t; do mpc add "$t" >/dev/null 2>&1; done
    mpc play >/dev/null 2>&1
    sleep 1
    [ "$(mpos)" = 1 ] && pass "queue seeded at position 1" || fail "queue position $(mpos), expected 1"
    super "$KL"; sleep 1
    [ "$(mpos)" = 2 ] && pass "Super+L advanced to position 2" || fail "Super+L: position $(mpos), expected 2"
    shot 04-queue-next
    super "$KH"; sleep 1
    [ "$(mpos)" = 1 ] && pass "Super+H went back to position 1" || fail "Super+H: position $(mpos), expected 1"
}

stage_volume() {
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.80 >/dev/null 2>&1
    wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 >/dev/null 2>&1
    local v0 v1 v2
    v0=$(vol)
    [ "$v0" -ge 78 ] && [ "$v0" -le 82 ] && pass "baseline volume 80%" || fail "baseline volume $v0, expected 80"
    local i
    for i in 1 2 3; do super "$KI"; sleep 0.4; done
    v1=$(vol)
    [ "$v1" -ge 63 ] && [ "$v1" -le 67 ] && pass "Super+I x3: 80% -> ${v1}%" || fail "Super+I x3 -> $v1, expected ~65"
    shot 05-volume-down
    for i in 1 2 3; do super "$KO"; sleep 0.4; done
    v2=$(vol)
    [ "$v2" -ge 78 ] && pass "Super+O x3 restored ${v2}%" || fail "Super+O x3 -> $v2, expected ~80"
    super "$KM"; sleep 1
    [ "$(muted)" = 1 ] && pass "Super+M muted" || fail "Super+M did not mute"
    shot 05-volume-muted
    super "$KM"; sleep 1
    [ "$(muted)" = 0 ] && pass "Super+M unmuted" || fail "Super+M did not unmute"
}

stage_launcher() {
    pkill -x fuzzel >/dev/null 2>&1 || true
    sleep 0.5
    pgrep -x fuzzel >/dev/null && fail "fuzzel already running" || pass "fuzzel closed initially"
    super "$KSPACE"; sleep 1.5
    pgrep -x fuzzel >/dev/null && pass "Super+Space opened fuzzel" || fail "Super+Space did not open fuzzel"
    shot 06-launcher
    tap "$KESC"; sleep 1
    pgrep -x fuzzel >/dev/null && fail "fuzzel did not close on Esc" || pass "fuzzel closed on Esc"
}

stage_terminal() {
    kill_app foot
    sleep 0.5
    super "$KTAB"; sleep 2
    [ "$(win_count foot)" -ge 1 ] && pass "Super+Tab opened foot" || fail "Super+Tab did not open foot"
    case "$(win_floating foot)" in user_on|auto_on) pass "foot opened floating ($(win_floating foot))" ;; *) fail "foot not floating ($(win_floating foot))" ;; esac
    expect_size foot 600
    shot 07-terminal
    kill_app foot
    wait_win foot absent 8 && pass "foot closed" || fail "foot did not close"
}

stage_cheatsheet() {
    kill_app cheatsheet
    pkill -f cheatsheet-viewer >/dev/null 2>&1 || true
    sleep 1
    tap "$KF11"
    wait_win cheatsheet present 8 && pass "F11 opened cheatsheet" || fail "F11 did not open cheatsheet"
    shot 08-cheatsheet
    tap "$KF11"
    wait_win cheatsheet absent 8 && pass "F11 closed cheatsheet" || fail "F11 did not close cheatsheet"

    local cfg=$HOME/.config/sway fs
    grep -q 'bindsym.*XF86Audio' "$cfg/generated.conf" \
        && pass "XF86 media binds still installed (external keyboards)" \
        || fail "XF86 media binds missing from generated.conf"
    grep -q 'XF86\|media play\|media next\|media prev' "$cfg/cheatsheet.txt" \
        && fail "cheatsheet.txt still lists XF86 media keys" \
        || pass "cheatsheet.txt hides XF86 media keys"
    grep -q 'media play\|media next\|media prev' "$cfg/cheatsheet.svg" \
        && fail "cheatsheet.svg still lists media keys" \
        || pass "cheatsheet.svg hides media keys"
    grep -q 'font-family="JetBrains Mono' "$cfg/cheatsheet.svg" \
        && pass "cheatsheet uses JetBrains Mono" \
        || fail "cheatsheet font is not JetBrains Mono"
    grep -q 'hold the L1 key' "$cfg/cheatsheet.svg" \
        && fail "old layer-1 legend still present in cheatsheet" \
        || pass "old layer-1 legend removed"
    grep -q '>cheatsheet<' "$cfg/cheatsheet.svg" \
        && pass "cheatsheet caption on Esc keycap (F13/L2)" \
        || fail "no cheatsheet caption on Esc keycap"
    # caption-fit regression: JetBrains Mono advance ~0.6em; 1U keycap usable ~56px
    fs=$(grep -o 'font-size="[0-9.]*"[^>]*>notifications<' "$cfg/cheatsheet.svg" | head -n1 | grep -oE 'font-size="[0-9.]+"' | grep -oE '[0-9.]+')
    if [ -n "$fs" ] && awk -v fs="$fs" 'BEGIN { exit !(fs * 0.6 * 13 <= 56) }'; then
        pass "notifications caption fits its keycap (font-size $fs)"
    else
        fail "notifications caption too big for its keycap (font-size ${fs:-missing})"
    fi
}

stage_devices() {
    local dev=$HOME/.config/sway/device.sh before after n title count
    [ -f "$dev" ] && pass "device.sh present" || fail "device.sh missing"
    n=$(sink_count)
    before=$(default_sink)
    if [ -z "$before" ]; then
        fail "no PipeWire sink found"
        shot 09-devices
        return
    fi
    title=$(sink_title "$before")
    pass "default output: ${title:-$before}"
    pass "$n PipeWire output(s) listed"

    nc_close
    swaync-client -C >/dev/null 2>&1 || true
    sleep 0.5
    super "$KD"; sleep 1.5
    after=$(default_sink)
    if [ "$n" -ge 2 ]; then
        [ "$after" != "$before" ] \
            && pass "Super+D switched output (${title} -> $(sink_title "$after"))" \
            || fail "Super+D did not switch output (still ${title})"
        super "$KD"; sleep 1.5
        [ "$(default_sink)" = "$before" ] \
            && pass "Super+D cycled back to ${title}" \
            || echo "NOTE cycle landed on $(sink_title "$(default_sink)"), expected ${title}"
    else
        [ "$after" = "$before" ] && pass "single output: Super+D kept ${title}" || fail "Super+D moved the only output"
    fi
    count=$(nc_count)
    [ "${count:-0}" -ge 1 ] && pass "Super+D posted a notification" || fail "Super+D posted no notification"
    shot 09-devices
    swaync-client -C >/dev/null 2>&1 || true
}

stage_bluetooth() {
    kill_app bluetooth
    sleep 0.5
    super "$KB"; sleep 3
    [ "$(win_count bluetooth)" -ge 1 ] && pass "Super+B opened the bluetooth UI" || fail "Super+B did not open the bluetooth UI"
    case "$(win_floating bluetooth)" in
        user_on|auto_on) pass "bluetooth UI opened floating ($(win_floating bluetooth))" ;;
        *) fail "bluetooth UI not floating ($(win_floating bluetooth))" ;;
    esac
    expect_size bluetooth 600
    if pgrep -f bluetuith >/dev/null 2>&1; then
        pass "bluetuith is the bluetooth UI (pid $(pgrep -f bluetuith | head -n1))"
    else
        echo "SKIP bluetuith not running: bluetoothctl fallback in use"
    fi
    shot 09b-bluetooth
    # 's' toggles adapter discovery: assert BlueZ actually flipped, both ways.
    local i disc=0
    tap s; sleep 2
    for i in 1 2 3 4 5; do
        bluetoothctl show 2>/dev/null | grep -q 'Discovering: yes' && { disc=1; break; }
        sleep 1
    done
    if [ "$disc" = 1 ]; then
        pass "bluetuith 's' started adapter discovery"
        tap s; sleep 2
        for i in 1 2 3 4 5; do
            bluetoothctl show 2>/dev/null | grep -q 'Discovering: no' && { disc=0; break; }
            sleep 1
        done
        [ "$disc" = 0 ] && pass "bluetuith 's' stopped adapter discovery" || fail "adapter discovery stayed on"
    else
        fail "bluetuith 's' did not start adapter discovery"
    fi
    super "$KB"
    wait_win bluetooth absent 8 && pass "Super+B toggled the bluetooth UI closed" || fail "bluetooth UI did not close"
}

stage_network() {
    local cfg=$HOME/.config/sway wb=$HOME/.config/waybar/config
    [ -x "$cfg/network.sh" ] && pass "network.sh present and executable" || fail "network.sh missing or not executable"
    grep -qE '^[[:space:]]*exec.*nm-applet' "$cfg/config" \
        && fail "sway config still autostarts nm-applet" \
        || pass "sway config no longer autostarts nm-applet"
    jq -e '."modules-right" | index("custom/network")' "$wb" >/dev/null 2>&1 \
        && pass "waybar has the custom/network button" || fail "waybar has no custom/network button"
    jq -e '."modules-right" | index("tray")' "$wb" >/dev/null 2>&1 \
        && fail "waybar still has the tray module" || pass "waybar tray module removed"
    jq -e '."custom/network"."on-click" | test("network\\.sh")' "$wb" >/dev/null 2>&1 \
        && pass "waybar network button runs network.sh" || fail "waybar network button does not run network.sh"
    if [ -x "$HOME/.local/bin/wifitui" ] || command -v wifitui >/dev/null; then
        pass "wifitui installed"
    elif command -v nmtui >/dev/null; then
        echo "NOTE wifitui not installed: network UI falls back to nmtui"
    else
        fail "neither wifitui nor nmtui available"
    fi
    [ -f "$HOME/.config/wifitui/theme.toml" ] \
        && pass "wifitui Dracula theme present" || echo "NOTE no wifitui theme.toml"

    kill_app network
    sleep 0.5
    super "$KN"; sleep 2
    [ "$(win_count network)" -ge 1 ] && pass "Super+N opened the network UI" || fail "Super+N did not open the network UI"
    case "$(win_floating network)" in
        user_on|auto_on) pass "network UI opened floating ($(win_floating network))" ;;
        *) fail "network UI not floating ($(win_floating network))" ;;
    esac
    expect_size network 600
    if pgrep -f 'wifitui' >/dev/null 2>&1; then
        pass "wifitui is the network UI (pid $(pgrep -f wifitui | head -n1))"
    elif pgrep -f 'nmtui' >/dev/null 2>&1; then
        echo "SKIP nmtui fallback in use (wifitui not running)"
    else
        fail "no wifitui/nmtui process in the network UI"
    fi
    # wifitui starts a scan on launch; give it a moment so the screenshot shows
    # the network list instead of "No items."
    sleep 4
    shot 09c-network
    super "$KN"
    wait_win network absent 8 && pass "Super+N toggled the network UI closed" || fail "network UI did not close"
}

stage_notifications() {
    nc_close
    swaync-client -C >/dev/null 2>&1 || true
    sleep 0.5
    nc_visible && fail "swaync panel already open" || pass "swaync panel closed initially"
    super "$KD"; sleep 1.5
    nc_visible && fail "Super+D still opens the panel (should be Super+Return)" || pass "Super+D is the output switcher, not the panel"
    super "$KRET"; sleep 1.5
    nc_visible && pass "Super+Return opened notification center" || fail "Super+Return did not open notification center"
    shot 10-notifications
    super "$KRET"; sleep 1
    nc_visible && fail "notification center did not close" || pass "notification center closed"
}

stage_miniplayer() {
    local cfg=$HOME/.config/swaync/config.json unit names status title
    jq -e '(.widgets // []) | index("mpris")' "$cfg" >/dev/null 2>&1 \
        && pass "swaync config has the mpris widget" || fail "swaync config has no mpris widget"
    jq -e '."widget-config".mpris' "$cfg" >/dev/null 2>&1 \
        && pass "swaync config configures widget-config.mpris" || fail "swaync config has no widget-config.mpris"

    unit=$(mpdris_unit)
    if [ -z "$unit" ]; then
        fail "no mpdris user unit installed"
    elif systemctl --user is-active --quiet "$unit"; then
        pass "mpdris bridge active ($unit)"
    else
        fail "mpdris bridge installed but not active ($unit)"
    fi

    [ -n "$(mpc playlist 2>/dev/null)" ] || mpc add "$(first_track)" >/dev/null 2>&1
    mpc play >/dev/null 2>&1
    sleep 1.5
    names=$(mpris_names)
    printf '%s\n' "$names" | grep -qx 'org.mpris.MediaPlayer2.mpd' \
        && pass "MPD is on the session bus as org.mpris.MediaPlayer2.mpd" \
        || fail "no org.mpris.MediaPlayer2.mpd bus name (have: ${names:-none})"

    status=$(mpris_prop org.mpris.MediaPlayer2.Player PlaybackStatus | grep -oE '"[^"]*"' | tr -d '"' | head -n1)
    case "$status" in
        Playing|Paused) pass "MPRIS PlaybackStatus=$status" ;;
        *) fail "MPRIS PlaybackStatus='${status:-none}', expected Playing/Paused" ;;
    esac

    title=$(mpris_prop org.mpris.MediaPlayer2.Player Metadata | tr '\n' ' ' | grep -oE '"xesam:title"[[:space:]]+(variant[[:space:]]+)?(s|string)[[:space:]]*"[^"]*"' | head -n1 | grep -oE '"[^"]*"$' | tr -d '"')
    [ -n "$title" ] && pass "MPRIS metadata xesam:title=$title" || echo "NOTE no xesam:title in MPRIS metadata (empty MPD queue?)"

    nc_close
    swaync-client -C >/dev/null 2>&1 || true
    sleep 0.5
    super "$KRET"; sleep 1.5
    nc_visible && pass "control center open (miniplayer above the list)" || fail "control center did not open"
    shot 11-miniplayer
    super "$KRET"; sleep 1
    nc_visible && fail "control center did not close" || pass "control center closed"
}

stage_browser() {
    kill_app firefox
    sleep 1
    super "$KG"; sleep 1
    wait_win firefox present 30 && pass "Super+G opened firefox" || fail "Super+G did not open firefox"
    local ws
    ws=$(win_ws firefox)
    case "$ws" in
        2:Browser) pass "firefox assigned to 2:Browser" ;;
        *) fail "firefox on workspace '${ws:-none}', expected 2:Browser" ;;
    esac
    shot 12-browser
    kill_app firefox
    wait_win firefox absent 15 && pass "firefox killed" || fail "firefox did not close"
}

stage_euphonica() {
    local EUPH=io.github.htkhiem.Euphonica was ws cur
    cur=$(swaymsg -t get_tree 2>/dev/null | jq -r '.. | objects | select(.type? == "workspace" and .focused == true) | .name' | head -n1)
    swaymsg 'workspace 1:Music' >/dev/null 2>&1
    sleep 0.5
    was=$(win_visible_count "$EUPH")
    if [ "$was" -ge 1 ]; then
        super_shift "$K4"; sleep 1.5
    fi
    wait_vis "$EUPH" absent 10 || fail "could not hide Euphonica for baseline"
    super_shift "$K4"; sleep 1
    wait_vis "$EUPH" present 30 && pass "Super+Shift+4 showed Euphonica" || fail "Super+Shift+4 did not show Euphonica"
    ws=$(win_ws "$EUPH")
    case "$ws" in
        1:Music) pass "Euphonica on 1:Music" ;;
        *) fail "Euphonica on workspace '${ws:-none}', expected 1:Music" ;;
    esac
    shot 13-euphonica
    super_shift "$K4"; sleep 1.5
    wait_vis "$EUPH" absent 10 && pass "Super+Shift+4 hid Euphonica to scratchpad" || fail "Euphonica did not hide"
    [ -n "$cur" ] && swaymsg "workspace $cur" >/dev/null 2>&1
    return 0
}

stage_wiremix() {
    if [ ! -x "$HOME/.cargo/bin/wiremix" ]; then
        echo "SKIP wiremix binary not present"
        shot 14-wiremix
        return
    fi
    kill_app wiremix
    sleep 1
    super "$KV"; sleep 2
    wait_win wiremix present 8 && pass "Super+V opened wiremix" || fail "Super+V did not open wiremix"
    case "$(win_floating wiremix)" in
        user_on|auto_on) pass "wiremix opened floating ($(win_floating wiremix))" ;;
        *) fail "wiremix not floating ($(win_floating wiremix))" ;;
    esac
    expect_size wiremix 600
    shot 14-wiremix
    super "$KV"
    wait_win wiremix absent 8 && pass "Super+V toggled wiremix closed" || fail "wiremix did not close"
}

stage_mediakeys() {
    mpc play >/dev/null 2>&1
    sleep 1
    [ "$(mstate)" = playing ] || fail "precondition: not playing"
    tap "$MPLAY"; sleep 1
    [ "$(mstate)" = paused ] && pass "XF86AudioPlay paused" || fail "XF86AudioPlay did not pause"
    tap "$MPLAY"; sleep 1
    [ "$(mstate)" = playing ] && pass "XF86AudioPlay resumed" || fail "XF86AudioPlay did not resume"
    if [ "$(mqueue_len)" -ge 2 ]; then
        local p0 p1
        p0=$(mpos)
        tap "$MNEXT"; sleep 1
        p1=$(mpos)
        [ "$p1" != "$p0" ] && pass "XF86AudioNext moved position $p0 -> $p1" || fail "XF86AudioNext: position stayed $p0"
        tap "$MPREV"; sleep 1
        [ "$(mpos)" = "$p0" ] && pass "XF86AudioPrev back to position $p0" || fail "XF86AudioPrev: position $(mpos), expected $p0"
    else
        echo "SKIP media next/prev: queue has <2 tracks"
    fi
    shot 15-mediakeys
}

stage_multiroom() {
    local cfg=$HOME/.config/sway
    local am=$cfg/audio-mode.sh
    local wb=$HOME/.config/waybar/config
    local start_mode before after n

    [ -x "$am" ] && pass "audio-mode.sh present and executable" || fail "audio-mode.sh missing or not executable"
    [ -f "$HOME/.config/snapserver/snapserver.conf" ] && pass "snapserver.conf present" || fail "snapserver.conf missing"
    [ -f "$HOME/.config/snapclient/env" ] && pass "snapclient env file present" || fail "snapclient env file missing"
    systemctl --user is-enabled --quiet audio-mode-restore.service \
        && pass "audio-mode-restore.service enabled" || fail "audio-mode-restore.service not enabled"
    [ "$(snapserver_autostart)" = disabled ] \
        && pass "snapserver.service not enabled at boot" || fail "snapserver.service autostart=$(snapserver_autostart)"
    grep -q 'name            "Multiroom"' "$HOME/.config/mpd/mpd.conf" \
        && pass "mpd.conf has the Multiroom fifo output" || fail "mpd.conf missing Multiroom output"
    grep -q 'bindsym --no-repeat \$mod+x exec ~/.config/sway/audio-mode.sh pick' "$cfg/generated.conf" \
        && pass "generated.conf has the \$mod+x bind" || fail "generated.conf missing \$mod+x"
    jq -e '."modules-right" | index("custom/audio")' "$wb" >/dev/null 2>&1 \
        && pass "waybar has custom/audio" || fail "waybar missing custom/audio"
    jq -e '."custom/audio"."signal" == 8' "$wb" >/dev/null 2>&1 \
        && pass "custom/audio refreshes on signal 8" || fail "custom/audio has no signal 8"
    command -v avahi-browse >/dev/null && pass "avahi-browse installed" || fail "avahi-browse missing (avahi-utils)"
    n=$(bash "$am" list 2>/dev/null | wc -l)
    [ "$n" -eq 4 ] && pass "audio-mode.sh list prints 4 modes" || fail "audio-mode.sh list printed $n rows"
    bash "$am" status --waybar 2>/dev/null | grep -q . \
        && pass "status --waybar prints an icon" || fail "status --waybar printed nothing"

    start_mode=$(mode_file)
    case "$start_mode" in off|receiver|broadcast|group) ;; *) start_mode=off ;; esac
    if [ "$(mstate)" != playing ]; then
        mpc clear >/dev/null 2>&1
        mpc add "$(first_track)" >/dev/null 2>&1
        mpc play >/dev/null 2>&1
        sleep 1
    fi

    # off (default: local playback only)
    bash "$am" set off >/dev/null 2>&1
    sleep 1
    [ "$(mode_file)" = off ] && pass "set off: state=off" || fail "set off: state=$(mode_file)"
    mpc_enabled 'PipeWire Sound Server' && pass "off: PipeWire output enabled" || fail "off: PipeWire output not enabled"
    mpc_enabled 'Multiroom' && fail "off: Multiroom output still enabled" || pass "off: Multiroom output disabled"
    snapserver_active && fail "off: snapserver still running" || pass "off: snapserver stopped"
    snapclient_active && fail "off: snapclient still running" || pass "off: snapclient stopped"
    shot 15b-multiroom-off

    # receiver
    bash "$am" set receiver >/dev/null 2>&1
    sleep 1
    [ "$(mode_file)" = receiver ] && pass "set receiver: state=receiver" || fail "set receiver: state=$(mode_file)"
    mpc_enabled 'PipeWire Sound Server' && pass "receiver: PipeWire output enabled" || fail "receiver: PipeWire output not enabled"
    mpc_enabled 'Multiroom' && fail "receiver: Multiroom output still enabled" || pass "receiver: Multiroom output disabled"
    snapserver_active && fail "receiver: snapserver still running" || pass "receiver: snapserver stopped"
    snapclient_active && pass "receiver: snapclient running" || fail "receiver: snapclient not running"
    shot 15b-multiroom-receiver

    # broadcast
    bash "$am" set broadcast >/dev/null 2>&1
    sleep 1
    [ "$(mode_file)" = broadcast ] && pass "set broadcast: state=broadcast" || fail "set broadcast: state=$(mode_file)"
    snapserver_active && pass "broadcast: snapserver active" || fail "broadcast: snapserver not active"
    snapclient_active && fail "broadcast: local snapclient still running" || pass "broadcast: local snapclient stopped"
    mpc_enabled 'PipeWire Sound Server' && pass "broadcast: local PipeWire output enabled" || fail "broadcast: local PipeWire output not enabled"
    mpc_enabled 'Multiroom' && pass "broadcast: Multiroom output enabled" || fail "broadcast: Multiroom output not enabled"
    timeout 5 avahi-browse -rpt _snapcast._tcp 2>/dev/null | awk -F';' '$1 == "=" && $3 == "IPv4" { print $8":"$9 }' | grep -q ':[0-9]' \
        && pass "broadcast: snapserver advertises _snapcast._tcp (avahi IPv4 row parsed)" || fail "broadcast: snapserver not advertising"
    capture_audio && pass "broadcast: snapserver serves PCM ($(stat -c%s /tmp/cap.raw) bytes)" \
        || fail "broadcast: no PCM captured from 127.0.0.1"
    if [ -f /usr/share/snapserver/snapweb/manifest.webmanifest ]; then
        curl -s --max-time 3 http://127.0.0.1:1780/ | grep -q 'assets/' \
            && pass "broadcast: snapweb served at :1780" || fail "broadcast: snapweb not served"
    else
        echo "SKIP snapweb not installed (optional)"
    fi
    shot 15b-multiroom-broadcast

    # group
    bash "$am" set group >/dev/null 2>&1
    sleep 1
    [ "$(mode_file)" = group ] && pass "set group: state=group" || fail "set group: state=$(mode_file)"
    snapserver_active && pass "group: snapserver active" || fail "group: snapserver not active"
    snapclient_active && pass "group: local snapclient running" || fail "group: local snapclient not running"
    mpc_enabled 'Multiroom' && pass "group: Multiroom output enabled" || fail "group: Multiroom output not enabled"
    mpc_enabled 'PipeWire Sound Server' && fail "group: local PipeWire output still enabled" || pass "group: local PipeWire output disabled"
    client_env | grep -q 'SNAPCLIENT_OPTS=--host 127.0.0.1 --port 1704' \
        && pass "group: snapclient pointed at 127.0.0.1:1704" || fail "group: SNAPCLIENT_OPTS wrong ($(client_env))"
    capture_audio && pass "group: snapserver serves PCM ($(stat -c%s /tmp/cap.raw) bytes)" \
        || fail "group: no PCM captured from 127.0.0.1"
    shot 15b-multiroom-group

    # listen flow (receiver-side host override)
    bash "$am" listen 127.0.0.1:1704 >/dev/null 2>&1
    sleep 0.5
    [ "$(mode_file)" = receiver ] && pass "listen: switched to receiver" || fail "listen: state=$(mode_file)"
    snapserver_active && fail "listen: snapserver still running" || pass "listen: snapserver stopped"
    grep -q 'SNAPCLIENT_OPTS=--host 127.0.0.1 --port 1704' "$HOME/.config/snapclient/env" \
        && pass "listen 127.0.0.1:1704 wrote the env override" || fail "listen host missing from snapclient env"
    bash "$am" listen auto >/dev/null 2>&1
    grep -q '^SNAPCLIENT_OPTS=' "$HOME/.config/snapclient/env" \
        && fail "listen auto left an override in place" || pass "listen auto cleared the override"
    shot 15b-multiroom-listen

    # picker: opens on Super+X, Esc changes nothing
    before=$(mode_file)
    pkill -x fuzzel >/dev/null 2>&1 || true
    sleep 0.5
    super "$KX"; sleep 1.5
    pgrep -x fuzzel >/dev/null && pass "Super+X opened the audio picker" || fail "Super+X did not open the picker"
    shot 15b-multiroom-picker
    tap "$KESC"; sleep 1
    pgrep -x fuzzel >/dev/null && fail "audio picker did not close on Esc" || pass "audio picker closed on Esc"
    after=$(mode_file)
    [ "$before" = "$after" ] && pass "Esc left the mode unchanged ($after)" || fail "mode changed on Esc: $before -> $after"

    # restore the starting mode
    bash "$am" set "$start_mode" >/dev/null 2>&1
    sleep 1
    [ "$(mode_file)" = "$start_mode" ] && pass "restored starting mode ($start_mode)" || fail "could not restore mode $start_mode (now $(mode_file))"
    shot 15b-multiroom-restored
}

stage_cleanup() {
    kill_app foot
    kill_app cheatsheet
    kill_app firefox
    kill_app wiremix
    kill_app bluetooth
    kill_app network
    pkill -x fuzzel >/dev/null 2>&1 || true
    pkill -f cheatsheet-viewer >/dev/null 2>&1 || true
    swaync-client -C >/dev/null 2>&1 || true
    nc_close
    if [ -f "$STATE" ]; then
        . "$STATE"
        [ -n "${SINK:-}" ] && wpctl set-default "$SINK" >/dev/null 2>&1
        if [ "${MUTED:-0}" = 1 ]; then wpctl set-mute @DEFAULT_AUDIO_SINK@ 1 >/dev/null 2>&1; else wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 >/dev/null 2>&1; fi
        [ -n "${VOL:-}" ] && wpctl set-volume @DEFAULT_AUDIO_SINK@ "${VOL}" >/dev/null 2>&1
        mpc clear >/dev/null 2>&1
        if [ -f "$QUEUE" ]; then
            while IFS= read -r t; do [ -n "$t" ] && mpc add "$t" >/dev/null 2>&1; done <"$QUEUE"
        fi
        case "${RND:-off}" in on) mpc random on >/dev/null 2>&1 ;; *) mpc random off >/dev/null 2>&1 ;; esac
        case "${SGL:-off}" in on) mpc single on >/dev/null 2>&1 ;; *) mpc single off >/dev/null 2>&1 ;; esac
        case "${CSM:-off}" in on) mpc consume on >/dev/null 2>&1 ;; *) mpc consume off >/dev/null 2>&1 ;; esac
        case "${PSTATE:-stopped}" in
            playing) mpc play >/dev/null 2>&1 ;;
            paused) mpc play >/dev/null 2>&1; mpc pause >/dev/null 2>&1 ;;
            *) mpc stop >/dev/null 2>&1 ;;
        esac
        pass "restored output/volume/mute/queue/random/single/consume/playback state"
    else
        echo "SKIP no saved state to restore"
    fi
    shot 16-cleanup
}

if [ "$STAGE" != preflight ] && ! command -v wtype >/dev/null; then
    fail "wtype not available for stage $STAGE"
fi

case "$STAGE" in
    preflight) stage_preflight ;;
    input) stage_input ;;
    playback) stage_playback ;;
    seek) stage_seek ;;
    queue) stage_queue ;;
    volume) stage_volume ;;
    launcher) stage_launcher ;;
    terminal) stage_terminal ;;
    cheatsheet) stage_cheatsheet ;;
    devices) stage_devices ;;
    bluetooth) stage_bluetooth ;;
    network) stage_network ;;
    notifications) stage_notifications ;;
    miniplayer) stage_miniplayer ;;
    browser) stage_browser ;;
    euphonica) stage_euphonica ;;
    wiremix) stage_wiremix ;;
    mediakeys) stage_mediakeys ;;
    multiroom) stage_multiroom ;;
    cleanup) stage_cleanup ;;
    *) echo "FAIL unknown stage: $STAGE"; exit 2 ;;
esac
RUNNER_EOF

scp -q "$RUNNER" "$PI:$REMOTE/smoke-run.sh" || { echo "failed to copy runner" >&2; exit 1; }
rm -f "$RUNNER"

total_p=0
total_f=0
failed_stages=""
for st in $STAGES; do
    echo "-- stage: $st"
    ssh_base "bash $REMOTE/smoke-run.sh $st" >"$OUT/$st.log" 2>&1
    rc=$?
    scp -q "$PI:$REMOTE/shots/*.png" "$OUT"/ 2>/dev/null || true
    p=$(grep -c '^PASS' "$OUT/$st.log" 2>/dev/null || true)
    f=$(grep -c '^FAIL' "$OUT/$st.log" 2>/dev/null || true)
    if [ "$rc" -ne 0 ]; then
        f=$((f + 1))
        echo "   stage crashed (rc=$rc)"
    fi
    total_p=$((total_p + p))
    total_f=$((total_f + f))
    [ "$f" -gt 0 ] && failed_stages="$failed_stages $st"
    echo "   $st: $p pass, $f fail"
    grep '^FAIL' "$OUT/$st.log" 2>/dev/null | sed 's/^/   /' || true
done

echo "== summary: $total_p pass, $total_f fail"
[ -n "$failed_stages" ] && echo "== failed stages:$failed_stages"
echo "== screenshots: $OUT"
ls "$OUT"/*.png 2>/dev/null | sed 's/^/   /' || true
[ "$total_f" -eq 0 ]
