# KOReader emulator (Docker, Kindle Basic 2024 screen: 1072x1448 @ 300 dpi)

Setup (once), from this folder:
    curl -LO https://github.com/koreader/koreader/releases/download/v2026.07.1/koreader-linux-arm64-v2026.07.1.tar.xz
    mkdir work && tar xf koreader-linux-arm64-*.tar.xz -C work && cp run.sh work/
    mkdir -p work/home/.config/koreader/patches work/books work/shots
    cp ../../patches/*.lua work/home/.config/koreader/patches/   # + a settings.reader.lua from the Kindle
    cp *.epub work/books/                  # KOARG=/work/books/x.epub opens a book directly
    docker build -t koemu .
    docker run -d --name koemu -v "$PWD/work:/work" koemu /work/run.sh

Use:
    ./t.sh shot1 tap 536 1400 wait 1     # taps, then saves work/shots/shot1.png
    ./t.sh shot2 swipe 900 700 200 700 hold 536 25
    ./restart.sh                         # after copying new patches
Notes: patch files must start with "2-" (3-7 are reserved and never run).
The first tap right after a page re-render is sometimes dropped: add "wait 1".
