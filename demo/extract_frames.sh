#!/bin/bash
# Regenerate frames/ (the display texture sequence) from hackpi-overlay.mp4.
# This Chromium decodes <video> to black pixels for WebGL/canvas, so the page
# swaps pre-decoded JPEGs instead of using a VideoTexture. Skip if frames exist.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$DIR/frames/f_001.jpg" ]; then
  echo "frames/ already present, skipping"
  exit 0
fi
mkdir -p "$DIR/frames"
ffmpeg -v error -y -i "$DIR/hackpi-overlay.mp4" \
  -vf fps=8,scale=480:480 -q:v 4 "$DIR/frames/f_%03d.jpg"
echo "extracted $(ls "$DIR/frames" | wc -l) frames"
