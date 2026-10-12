#!/bin/sh
# DELTARUNE Multiplayer installer: ./install.sh [path to DELTARUNE]
HERE=$(cd "$(dirname "$0")" && pwd)
GAME=${1:-"$HOME/.steam/steam/steamapps/common/DELTARUNE"}
[ -d "$GAME/chapter1_windows" ] || { echo "DELTARUNE not found at $GAME - pass its path as an argument."; exit 1; }
exec "$HERE/drm-patcher" install "$GAME" --mod "$HERE/mod"
