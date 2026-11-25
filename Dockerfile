FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python3-websockify libc6 libstdc++6 unzip wget tar && rm -rf /var/lib/apt/lists/*
WORKDIR /server

RUN wget -q https://github.com/FWGS/xash3d-fwgs/releases/download/continuous/xash3d-fwgs-linux-amd64.tar.gz \
    && tar -xzf xash3d-fwgs-linux-amd64.tar.gz \
    && rm xash3d-fwgs-linux-amd64.tar.gz \
    && ENGINE_DIR=$(dirname "$(find /server -name "libxash.so" | head -n 1)") \
    && if [ "$ENGINE_DIR" != "/server" ]; then cp -rn "$ENGINE_DIR"/* /server/; fi \
    && if [ ! -f /server/xashds ] && [ -f /server/xash ]; then cp /server/xash /server/xashds; fi \
    && chmod +x /server/xashds

COPY parte2.zip /server/
RUN unzip -o parte2.zip && rm parte2.zip \
    && CSTRIKE_DIR=$(find /server -maxdepth 3 -name cstrike -type d | head -n 1) \
    && if [ -n "$CSTRIKE_DIR" ] && [ "$CSTRIKE_DIR" != "/server/cstrike" ]; then cp -rn "$CSTRIKE_DIR" /server/; fi \
    && mkdir -p /server/valve/dlls \
    && cp -n /server/cstrike/dlls/*.so /server/valve/dlls/ 2>/dev/null || true

ENV LD_LIBRARY_PATH=/server
EXPOSE 8080
CMD ["sh", "-c", "websockify 8080 127.0.0.1:27015 & ./xashds -game cstrike +map de_dust2 +maxplayers 16"]
