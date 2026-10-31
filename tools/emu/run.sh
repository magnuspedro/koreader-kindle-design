#!/bin/sh
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1; Xvfb :1 -screen 0 1072x1448x24 >/dev/null 2>&1 &
sleep 1
export DISPLAY=:1 EMULATE_READER_W=1072 EMULATE_READER_H=1448 EMULATE_READER_DPI=300 HOME=/work/home
cd /work && ./bin/koreader ${KOARG:-/work/books} > /work/ko.log 2>&1 &
sleep 1000000
