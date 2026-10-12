#!/bin/sh
HERE=$(cd "$(dirname "$0")" && pwd)
GAME=${1:-"$HOME/.steam/steam/steamapps/common/DELTARUNE"}
exec "$HERE/drm-patcher" uninstall "$GAME"
