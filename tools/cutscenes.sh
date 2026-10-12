#!/bin/bash
# Scripted shared-cutscene tests: in each scenario the host triggers a real story cutscene
# (on entering a room, or by walking into a trigger) while the client is in another room.
# The client must be pulled in and the cutscene must play in its game too (never a frozen
# spectator); afterwards everyone is back in free roam. Results via tools/mpcheck.py.
# Usage: cutscenes.sh [seconds] [nclients] [scenario...]
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SECS=${1:-75}; NC=${2:-1}; shift 2
# name: chapter | host room | plot | extra host tokens | client room
declare -A S=(
  [ch2_entry]="2|room_dw_cyber_queen_boxing|53|partyat:400|room_dw_cyber_intro_2"
  [ch3_walk]="3|room_dw_snow_zone|250|walk:r:300:400|room_dw_couch_overworld_01"
  [ch4_entry]="4|room_dw_church_glass|110|partyat:400|room_dw_church_bookcase"
  [ch4_walk]="4|room_dw_church_bookcase|140|walk:l:300:200|room_dw_church_glass"
  [ch5_entry]="5|room_dw_garden_intro|100|partyat:400|room_dw_garden_meetflowery"
)
# Scenarios with their own token lists: name -> "chapter|seconds|host tokens|client tokens". The host walks
# (away:) into the scene while the client has gone to another room, like a player running ahead.
declare -A X=(
  [ch2_library]="2|120|party,room:room_library,plot:19,check,mash,log,partyat:400|party,room:room_krisroom,plot:19,check,mash,log,wander"
  [ch2_card_scene]="2|120|party,room:room_dw_castle_area_2_transformed,plot:15,check,mash,log,partyat:400|party,room:room_dw_castle_area_1,plot:15,check,mash,log,wander"
  [ch2_schooldoor]="2|120|party,room:room_schooldoor,plot:16,check,mash,log,partyat:400|party,room:room_krisroom,plot:16,check,mash,log,wander"
  [ch2_queen]="2|300|party,room:room_dw_cyber_intro_1,plot:50,check,mash,log,bot,botrand,weak,away:room_dw_cyber_intro_2:900:560:240|party,room:room_dw_cyber_intro_1,plot:50,check,mash,log,bot,botrand,weak,away:room_dw_cyber_intro_connector:300"
)
LIST=${@:-ch2_entry ch3_walk ch4_entry ch4_walk ch5_entry ${!X[@]}}
for n in $LIST; do
  if [ -n "${X[$n]}" ]; then
    IFS='|' read -r CH XS HT CT <<< "${X[$n]}"
    OUT=$ROOT/work/cut_$n
    MPTEST_OUT=$OUT NOBUILD=1 SHOTS="${SHOTS:-30 60 90}" "$ROOT/tools/mptest.sh" $CH $XS "$HT" "$CT" $NC >/dev/null 2>&1
    echo "=== $n (chapter $CH, custom)"
    python3 "$ROOT/tools/mpcheck.py" $OUT --strict-end | sed 's/^/  /'
    continue
  fi
  IFS='|' read -r CH HR PL HX CR <<< "${S[$n]}"
  OUT=$ROOT/work/cut_$n
  MPTEST_OUT=$OUT NOBUILD=1 SHOTS="${SHOTS:-20 30 40 50}" "$ROOT/tools/mptest.sh" $CH $SECS \
    "party,room:$HR,plot:$PL,check,mash,log,$HX" "party,room:$CR,plot:$PL,check,mash,log,wander" $NC >/dev/null 2>&1
  echo "=== $n (chapter $CH: host in $HR, client in $CR)"
  grep -h "MPD.*\(send pull\|got pull\|watching\)\|Joining" $OUT/*.log | sed 's/^/    /'
  python3 "$ROOT/tools/mpcheck.py" $OUT --strict-end | sed 's/^/  /'
done
pkill -x DELTARUNE.exe
