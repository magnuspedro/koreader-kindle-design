#!/bin/sh
# usage: t.sh shotname [tap X Y | swipe X1 Y1 X2 Y2 | hold X Y | wait N]...
name=$1; shift
cmd=""
while [ $# -gt 0 ]; do
  case $1 in
    tap) cmd="$cmd xdotool mousemove $2 $3 click 1; sleep 1.5;"; shift 3;;
    hold) cmd="$cmd xdotool mousemove $2 $3 mousedown 1; sleep 1.2; xdotool mouseup 1; sleep 1.5;"; shift 3;;
    swipe) cmd="$cmd xdotool mousemove $2 $3 mousedown 1 mousemove --sync $(( ($2+$4)/2 )) $(( ($3+$5)/2 )) mousemove --sync $4 $5 mouseup 1; sleep 1.5;"; shift 5;;
    wait) cmd="$cmd sleep $2;"; shift 2;;
  esac
done
docker exec -e DISPLAY=:1 koemu sh -c "$cmd import -window root /work/shots/$name.png"
