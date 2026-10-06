#!/bin/bash
# Single source of truth: keys.json -> generated.conf (sway binds) + cheatsheet.txt (compact overlay)
DIR="$(dirname "$0")"
jq -r '.binds[] | "bindsym \(.key) \(.cmd)"' "$DIR/keys.json" > "$DIR/generated.conf"

C=28
printf 'HACKPI MUSIC KEYS\n' > "$DIR/cheatsheet.txt"
jq -r '.binds[] | "\(.key)\t\(.label)"' "$DIR/keys.json" | awk -v c=$C '{
  key=$1; $1=""; sub(/^ /,""); lab=$0
  if (length(key) > 12) key=substr(key,1,12)
  printf "%-12s %s\n", key, lab
}' >> "$DIR/cheatsheet.txt"
