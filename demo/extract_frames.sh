#!/bin/bash
# Regenerate frames/ (the display texture sequence) from hackpi-overlay.mp4.
# This Chromium decodes <video> to black pixels for WebGL/canvas, so the page
# swaps pre-decoded JPEGs instead of using a VideoTexture. Skip if frames exist.
# 720px matches the 720x720 panel 1:1; 12fps keeps motion smooth at sane size.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$DIR/frames/f_001.jpg" ]; then
  echo "frames/ already present, skipping"
  exit 0
fi
mkdir -p "$DIR/frames"
ffmpeg -v error -y -i "$DIR/hackpi-overlay.mp4" \
  -vf fps=12,scale=720:720 -q:v 2 "$DIR/frames/f_%03d.jpg"
echo "extracted $(ls "$DIR/frames" | wc -l) frames"
