#!/bin/bash
# Regenerate frames/ (the display texture sequence) from swaymp-overlay.mp4.
# This Chromium decodes <video> to black pixels for WebGL/canvas, so the page
# swaps pre-decoded JPEGs instead of using a VideoTexture. Skip if frames exist.
# 720px matches the 720x720 panel 1:1; 12fps keeps motion smooth at sane size.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$DIR/frames/f_001.jpg" ]; then
  echo "frames/ already present"
  "$DIR/sanitize_frames.sh"
  exit 0
fi
mkdir -p "$DIR/frames"
ffmpeg -v error -y -i "$DIR/swaymp-overlay.mp4" \
  -vf fps=12,scale=720:720 -q:v 2 "$DIR/frames/f_%03d.jpg"
if [ -f "$DIR/.swaymp-overlay.sanitized" ]; then
  touch "$DIR/frames/.sanitized"
else
  "$DIR/sanitize_frames.sh"
fi
echo "extracted $(ls "$DIR/frames" | wc -l) frames"
