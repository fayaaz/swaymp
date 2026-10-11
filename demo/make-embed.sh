#!/bin/bash
# Regenerate the GitHub-embeddable promo assets from the master render kb_final.mp4:
#   - embed.mp4          linked video (README + landing page)
#   - embed-preview.webp inline animated preview shown in the README
#   - embed-poster.jpg   poster for the landing-page <video>
#
# Needs: ffmpeg (with libwebp_anim + libx264). Run after demo/make.sh produces kb_final.mp4.
# Tunables (env): EMBED_W/H/CRF, WEBP_W/H/FPS/QUALITY, POSTER_T.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${SRC:-$DIR/kb_final.mp4}"
[ -f "$SRC" ] || { echo "missing $SRC (run demo/make.sh first)"; exit 1; }

EMBED_W="${EMBED_W:-720}"; EMBED_H="${EMBED_H:-1050}"; EMBED_CRF="${EMBED_CRF:-22}"
WEBP_W="${WEBP_W:-480}";  WEBP_H="${WEBP_H:-700}";  WEBP_FPS="${WEBP_FPS:-12}"; WEBP_Q="${WEBP_Q:-80}"
WEBP_START="${WEBP_START:-1}"; WEBP_DUR="${WEBP_DUR:-20}"
POSTER_T="${POSTER_T:-27}"

# Linked video: higher resolution + lower CRF than the old 480px/CRF23 cut.
ffmpeg -v error -y -i "$SRC" \
  -vf "scale=${EMBED_W}:${EMBED_H}:flags=lanczos" \
  -c:v libx264 -preset slow -crf "$EMBED_CRF" -pix_fmt yuv420p -profile:v high \
  -movflags +faststart -c:a aac -b:a 160k "$DIR/embed.mp4"

# Inline README preview: a ~20s highlight loop (opening beats), smooth 12fps, high
# quality, under GitHub's 10MB image cap. The linked embed.mp4 stays full length.
ffmpeg -v error -y -ss "$WEBP_START" -t "$WEBP_DUR" -i "$SRC" \
  -vf "scale=${WEBP_W}:${WEBP_H}:flags=lanczos,fps=${WEBP_FPS}" \
  -loop 0 -c:v libwebp_anim -quality "$WEBP_Q" -compression_level 4 "$DIR/embed-preview.webp"

# Landing-page poster: a clean frame of the Euphonica player + album art.
ffmpeg -v error -y -ss "$POSTER_T" -i "$SRC" -frames:v 1 \
  -vf "scale=${EMBED_W}:${EMBED_H}:flags=lanczos" \
  -c:v mjpeg -q:v 2 "$DIR/embed-poster.jpg"

echo "wrote embed.mp4, embed-preview.webp, embed-poster.jpg"
