#!/bin/bash
# Usage: keys.sh <display> <key[:wait]>...   Presses real keys in a game window
# (held for 0.1 s so the 30 fps game sees them). Default wait after each key: 0.4 s.
export DISPLAY=:$1; shift
# No window manager on the test displays: give the game window keyboard focus first.
# (The window title changes per chapter: pick deltarune.exe's big window.)
W=""
for w in $(xdotool search --onlyvisible --class deltarune 2>/dev/null); do
  [ "$(xdotool getwindowgeometry "$w" | awk '/Geometry/{split($2,a,"x"); print a[1]}')" -ge 320 ] 2>/dev/null && W=$w
done
[ -n "$W" ] && xdotool mousemove --window "$W" 320 240 click 1 2>/dev/null && sleep 0.3
for k in "$@"; do
  key=${k%%:*}; w=0.4; [[ "$k" == *:* ]] && w=${k#*:}
  xdotool keydown "$key"; sleep 0.1; xdotool keyup "$key"; sleep "$w"
done
