#!/bin/bash
# Mux the silent canvas capture with the source video's audio track.
# Both start at t=0, so they stay in sync; -shortest trims the capture tail.
# Grade is deliberately mild: the 3D scene is already tone-mapped, this just
# tightens text edges and adds a touch of vignette/saturation.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
ffmpeg -v error -y -i "$DIR/kb_final.webm" -i "$DIR/hackpi-overlay.mp4" \
  -map 0:v -map 1:a \
  -vf "unsharp=5:5:0.5:5:5:0.0,eq=saturation=1.06:contrast=1.02,vignette=PI/5" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k \
  -shortest "$DIR/kb_final.mp4"
echo "wrote $DIR/kb_final.mp4"
