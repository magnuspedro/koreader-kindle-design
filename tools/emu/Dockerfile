FROM debian:bookworm-slim
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libsdl2-2.0-0 xvfb xdotool x11-apps imagemagick ca-certificates zip && rm -rf /var/lib/apt/lists/*
