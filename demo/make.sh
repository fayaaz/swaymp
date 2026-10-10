#!/bin/bash
# Full pipeline: frames -> serve demo/ -> record canvas -> mux audio -> kb_final.mp4
# Needs: ffmpeg, browser-harness, Chromium reachable at $BU_CDP_URL
# (harness auto-launches Chrome if none is running).
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${PORT:-7171}"
export BU_CDP_URL="${BU_CDP_URL:-http://127.0.0.1:9333}"
export KB_DUR="${KB_DUR:-$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$DIR/swaymp-overlay.mp4")}"

"$DIR/sanitize_video.sh"
"$DIR/extract_frames.sh"

if ! curl -s -o /dev/null "http://127.0.0.1:$PORT/"; then
  (cd "$DIR" && setsid nohup python3 -m http.server "$PORT" --bind 127.0.0.1 \
    >/tmp/kb_demo_httpd.log 2>&1 < /dev/null &)
  echo $! > /tmp/kb_demo_httpd.pid
  sleep 1
fi

(cd "$DIR" && KB_URL="http://127.0.0.1:$PORT/" KB_OUT="$DIR/kb_final.webm" \
  browser-harness < "$DIR/record.py")
"$DIR/mux.sh"

if [ -f /tmp/kb_demo_httpd.pid ]; then
  kill "$(cat /tmp/kb_demo_httpd.pid)" 2>/dev/null || true
  rm -f /tmp/kb_demo_httpd.pid
fi
