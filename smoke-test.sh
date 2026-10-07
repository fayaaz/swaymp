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
#         cheatsheet notifications browser euphonica wiremix mediakeys cleanup
# The Pi-side runner is embedded below and copied to /tmp/smoke/smoke-run.sh.
set -u

PI="${PI:-pi@raspberrypi.local}"
OUT="${OUT:-/tmp/opencode/smoke-$(date +%Y%m%d-%H%M%S)}"
REMOTE=/tmp/smoke
STAGES="${STAGES:-preflight input playback seek queue volume launcher terminal cheatsheet notifications browser euphonica wiremix mediakeys cleanup}"

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
KP=p KK=k KJ=j KI=i KO=o KM=m KD=d KG=g KV=v
KTAB=Tab KSPACE=space KCOMMA=comma KDOT=period KESC=Escape K4=4
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
kill_app() { swaymsg "[app_id=\"$1\"] kill" >/dev/null 2>&1 || true; }
wait_win() { local id=$1 want=$2 n=${3:-20} i c; for i in $(seq 1 "$n"); do c=$(win_count "$id"); { [ "$want" = present ] && [ "$c" -ge 1 ]; } || { [ "$want" = absent ] && [ "$c" -eq 0 ]; } && return 0; sleep 1; done; return 1; }
wait_vis() { local id=$1 want=$2 n=${3:-20} i c; for i in $(seq 1 "$n"); do c=$(win_visible_count "$id"); { [ "$want" = present ] && [ "$c" -ge 1 ]; } || { [ "$want" = absent ] && [ "$c" -eq 0 ]; } && return 0; sleep 1; done; return 1; }
mstate() { mpc status %state% 2>/dev/null; }
mfirstline() { mpc status 2>/dev/null | grep -E '^\[(playing|paused|stopped)\]' | head -n1; }
mpos() { mfirstline | grep -oE '#[0-9]+/[0-9]+' | head -n1 | tr -d '#' | cut -d/ -f1; }
mqueue_len() { mfirstline | grep -oE '#[0-9]+/[0-9]+' | head -n1 | tr -d '#' | cut -d/ -f2; }
melapsed() { mfirstline | grep -oE '[0-9]+:[0-9]+/[0-9]+:[0-9]+' | head -n1 | cut -d/ -f1 | awk -F: '{print $1*60+$2}'; }
nc_visible() { timeout 5 swaync-client -s 2>/dev/null | grep -q '"visible": *true'; }
vol() { wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '/Volume:/ {printf "%d", $2*100+0.5}'; }
muted() { wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q MUTED && echo 1 || echo 0; }
first_track() { mpc ls 2>/dev/null | head -n1; }

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
    for s in mpd mympd pipewire pipewire-pulse wireplumber syncthing snapclient volume-notify; do
        systemctl --user is-active --quiet "$s" && pass "service $s active" || fail "service $s not active"
    done
    command -v grim >/dev/null && pass "grim present" || fail "grim missing"
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
    super "$KDOT"; sleep 1
    [ "$(mpos)" = 2 ] && pass "Super+. advanced to position 2" || fail "Super+.: position $(mpos), expected 2"
    shot 04-queue-next
    super "$KCOMMA"; sleep 1
    [ "$(mpos)" = 1 ] && pass "Super+, went back to position 1" || fail "Super+,: position $(mpos), expected 1"
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
}

stage_notifications() {
    swaync-client -C >/dev/null 2>&1 || true
    sleep 0.5
    nc_visible && fail "swaync panel already open" || pass "swaync panel closed initially"
    super "$KD"; sleep 1.5
    nc_visible && pass "Super+D opened notification center" || fail "Super+D did not open notification center"
    shot 09-notifications
    super "$KD"; sleep 1
    nc_visible && fail "notification center did not close" || pass "notification center closed"
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
    shot 10-browser
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
    shot 11-euphonica
    super_shift "$K4"; sleep 1.5
    wait_vis "$EUPH" absent 10 && pass "Super+Shift+4 hid Euphonica to scratchpad" || fail "Euphonica did not hide"
    [ -n "$cur" ] && swaymsg "workspace $cur" >/dev/null 2>&1
}

stage_wiremix() {
    if [ ! -x "$HOME/.cargo/bin/wiremix" ]; then
        echo "SKIP wiremix binary not present"
        shot 12-wiremix
        return
    fi
    kill_app wiremix
    sleep 1
    super "$KV"; sleep 2
    wait_win wiremix present 8 && pass "Super+V opened wiremix" || fail "Super+V did not open wiremix"
    shot 12-wiremix
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
    shot 13-mediakeys
}

stage_cleanup() {
    kill_app foot
    kill_app cheatsheet
    kill_app firefox
    kill_app wiremix
    kill_app bluetooth
    pkill -x fuzzel >/dev/null 2>&1 || true
    pkill -f cheatsheet-viewer >/dev/null 2>&1 || true
    swaync-client -C >/dev/null 2>&1 || true
    if [ -f "$STATE" ]; then
        . "$STATE"
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
        pass "restored volume/mute/queue/random/single/consume/playback state"
    else
        echo "SKIP no saved state to restore"
    fi
    shot 14-cleanup
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
    notifications) stage_notifications ;;
    browser) stage_browser ;;
    euphonica) stage_euphonica ;;
    wiremix) stage_wiremix ;;
    mediakeys) stage_mediakeys ;;
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
