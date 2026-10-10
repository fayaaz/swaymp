#!/bin/bash
# Blur sensitive time windows in the source screen recording in place.
# Audio is copied unchanged; duration stays the same for make.sh/record.py.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/swaymp-overlay.mp4"
MARKER="$DIR/.swaymp-overlay.sanitized"
SIGMA=32
ENABLE="between(t,49.40,53.40)+between(t,54.00,58.50)"

if [ ! -f "$SRC" ]; then
  exit 0
fi
if [ -f "$MARKER" ]; then
  echo "swaymp-overlay.mp4 already sanitized, skipping"
  exit 0
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/swaymp-overlay.XXXXXX.mp4")
ffmpeg -v error -y -i "$SRC" \
  -vf "gblur=sigma=$SIGMA:enable='$ENABLE'" \
  -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p \
  -c:a copy "$tmp"
mv "$tmp" "$SRC"
touch "$MARKER"
echo "sanitized $SRC"
