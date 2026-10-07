#!/bin/bash
# Mux the silent canvas capture with the source video's audio track.
# Both start at t=0, so they stay in sync; -shortest trims the capture tail.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
ffmpeg -v error -y -i "$DIR/kb_final.webm" -i "$DIR/hackpi-overlay.mp4" \
  -map 0:v -map 1:a -c:v libx264 -pix_fmt yuv420p -crf 20 -c:a aac \
  -shortest "$DIR/kb_final.mp4"
echo "wrote $DIR/kb_final.mp4"
