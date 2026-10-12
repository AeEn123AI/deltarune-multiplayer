#!/bin/bash
# Usage: mkgamedir.sh <dest> <chapter> <patched data.win>
# Builds a lightweight game directory of symlinks to the original DELTARUNE
# install, with one chapter's data.win replaced by a patched copy.
set -e
SRC=$(cd "$(dirname "$0")/../DELTARUNE" && pwd)
DEST=$1; CH=$2; WIN=$(realpath "$3")
mkdir -p "$DEST"
for f in "$SRC"/*; do
  b=$(basename "$f")
  if [[ "$b" == chapter*_windows ]]; then
    mkdir -p "$DEST/$b"
    for g in "$f"/*; do
      # (Leave other chapters' patched data.win alone: several tests may share this folder.)
      [ "$(basename "$g")" = data.win ] && [ -e "$DEST/$b/data.win" ] && continue
      ln -sfn "$g" "$DEST/$b/$(basename "$g")"
    done
    # The chapters stream music from mus/ relative to the working directory (the install
    # root when started from the launcher; run_game.sh starts inside the chapter folder).
    ln -sfn "$SRC/mus" "$DEST/$b/mus"
  else
    ln -sfn "$f" "$DEST/$b"
  fi
done
ln -sfn "$WIN" "$DEST/chapter${CH}_windows/data.win"
