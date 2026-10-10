#!/bin/bash
# Blur sensitive time windows in the source screen recording in place.
# Audio is copied unchanged; duration stays the same for make.sh/record.py.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/swaymp-overlay.mp4"
MARKER="$DIR/.swaymp-overlay.sanitized"
SIGMA=32
# No sensitive windows in the v4 demo (bluetooth/network beats removed), so
# the blur never enables. Keep the mechanism for future beats.
ENABLE="0"

if [ ! -f "$SRC" ]; then
  exit 0
fi
if [ -f "$MARKER" ]; then
  echo "swaymp-overlay.mp4 already sanitized, skipping"
  exit 0
fi

if [ "$ENABLE" = "0" ]; then
  echo "no sensitive windows, skipping"
  touch "$MARKER"
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
