FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python3 nodejs npm libc6 libstdc++6 unzip wget tar git \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /server

# 1. Baixa o motor oficial Xash3D FWGS Linux
RUN wget -q https://github.com/FWGS/xash3d-fwgs/releases/download/continuous/xash3d-fwgs-linux-amd64.tar.gz \
    && tar -xzf xash3d-fwgs-linux-amd64.tar.gz \
    && rm xash3d-fwgs-linux-amd64.tar.gz \
    && ENGINE_DIR=$(dirname "$(find /server -name "libxash.so" | head -n 1)") \
    && if [ "$ENGINE_DIR" != "/server" ]; then cp -rn "$ENGINE_DIR"/* /server/; fi \
    && if [ ! -f /server/xashds ] && [ -f /server/xash ]; then cp /server/xash /server/xashds; fi \
    && chmod +x /server/xashds

# 2. Extrai os pacotes do servidor e gera gfx.wad
COPY parte*.zip /server/
RUN for f in /server/parte*.zip; do unzip -o "$f"; rm "$f"; done \
    && CSTRIKE_DIR=$(find /server -maxdepth 3 -name cstrike -type d | head -n 1) \
    && if [ -n "$CSTRIKE_DIR" ] && [ "$CSTRIKE_DIR" != "/server/cstrike" ]; then cp -rn "$CSTRIKE_DIR" /server/; fi \
    && VALVE_DIR=$(find /server -maxdepth 3 -name valve -type d | head -n 1) \
    && if [ -n "$VALVE_DIR" ] && [ "$VALVE_DIR" != "/server/valve" ]; then cp -rn "$VALVE_DIR" /server/; fi \
    && mkdir -p /server/valve/dlls /server/cstrike/dlls \
    && touch /server/valve/valve.rc /server/cstrike/server.cfg \
    && python3 -c "import struct; data=b'\x00'*16384; hdr=struct.pack('<4sII',b'WAD3',1,12+len(data)); entry=struct.pack('<IIIccH16s',12,len(data),len(data),b'B',b'\x00',0,b'CONCHARS'); open('/server/valve/gfx.wad','wb').write(hdr+data+entry)" \
    && cp -f /server/valve/gfx.wad /server/cstrike/gfx.wad

# 3. Instala o proxy oficial WebSocket-UDP compatível com a rede virtual 172.29.x.x do xash.js
RUN git clone --depth 1 https://github.com/yohimik/xash3d-emscripten.git /tmp/em \
    && cp -r /tmp/em/proxy /server/proxy \
    && cd /server/proxy && npm install \
    && rm -rf /tmp/em

ENV LD_LIBRARY_PATH=/server
EXPOSE 8080
CMD ["sh", "-c", "node /server/proxy/index.js --port ${PORT:-8080} --host 127.0.0.1 --rport 27015 & ./xashds -game cstrike +ip 0.0.0.0 +port 27015 +map de_dust2 +maxplayers 16 -console"]
