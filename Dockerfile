FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python3 nodejs npm libc6 libstdc++6 unzip wget tar \
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

# 3. Cria o proxy WebSocket-UDP compatível com o túnel Emscripten (xash.js)
RUN mkdir -p /server/proxy && cd /server/proxy && npm init -y && npm install ws \
    && node -e 'const fs=require("fs");fs.writeFileSync("/server/proxy/index.js",`const WebSocket=require("ws"),dgram=require("dgram");const wss=new WebSocket.Server({port:process.env.PORT||8080});wss.on("connection",ws=>{const udp=dgram.createSocket("udp4");let hdr=null;udp.on("message",msg=>{if(ws.readyState===1)ws.send(hdr?Buffer.concat([hdr,msg]):msg);});ws.on("message",data=>{const buf=Buffer.from(data);if(buf.length>6&&buf[0]===0&&buf[1]===0){hdr=buf.slice(0,6);udp.send(buf.slice(6),27015,"127.0.0.1");}else if(buf.length>8&&buf[0]===255&&buf[1]===255){udp.send(buf,27015,"127.0.0.1");}else if(buf.length>6){hdr=buf.slice(0,6);udp.send(buf.slice(6),27015,"127.0.0.1");}});ws.on("close",()=>udp.close());});`);'

ENV LD_LIBRARY_PATH=/server
EXPOSE 8080
CMD ["sh", "-c", "node /server/proxy/index.js & ./xashds -game cstrike +ip 0.0.0.0 +port 27015 +map de_dust2 +maxplayers 16 -console"]
