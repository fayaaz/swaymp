#!/bin/bash
# Blur sensitive frames in place. Frame numbers are derived from the same
# sensitive time windows used by demo/index.html and demo/sanitize_video.sh.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMES="$DIR/frames"
FPS=12
SIGMA=32
MARKER="$FRAMES/.sanitized"
# No sensitive windows in the v4 demo (bluetooth/network beats removed).
SENSITIVE=""

if [ ! -f "$FRAMES/f_001.jpg" ]; then
  exit 0
fi
if [ -f "$MARKER" ]; then
  echo "frames/ already sanitized, skipping"
  exit 0
fi

count=0
for seg in $SENSITIVE; do
  start="${seg%-*}"
  end="${seg#*-}"
  first=$(awk -v t="$start" -v fps="$FPS" 'BEGIN { printf "%d", int(t * fps) + 1 }')
  last=$(awk -v t="$end" -v fps="$FPS" 'BEGIN { printf "%d", int(t * fps) + 1 }')
  for n in $(seq "$first" "$last"); do
    f=$(printf '%s/f_%03d.jpg' "$FRAMES" "$n")
    [ -f "$f" ] || continue
    tmp=$(mktemp "${TMPDIR:-/tmp}/swaymp-frame.XXXXXX.jpg")
    ffmpeg -v error -y -i "$f" -vf "gblur=sigma=$SIGMA" -q:v 2 "$tmp"
    mv "$tmp" "$f"
    count=$((count + 1))
  done
done

touch "$MARKER"
echo "sanitized $count sensitive frames"
