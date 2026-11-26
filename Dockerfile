FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y python3 nodejs npm libc6 libstdc++6 libgcc-s1 unzip wget tar \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /server

# 1. Baixa e organiza o motor oficial Xash3D FWGS Linux (64-bit)
RUN wget -q https://github.com/FWGS/xash3d-fwgs/releases/download/continuous/xash3d-fwgs-linux-amd64.tar.gz \
    && tar -xzf xash3d-fwgs-linux-amd64.tar.gz \
    && rm xash3d-fwgs-linux-amd64.tar.gz \
    && ENGINE_DIR=$(dirname "$(find /server -name "libxash.so" | head -n 1)") \
    && if [ -n "$ENGINE_DIR" ] && [ "$ENGINE_DIR" != "/server" ]; then cp -rn "$ENGINE_DIR"/* /server/; fi \
    && if [ ! -f /server/xashds ] && [ -f /server/xash ]; then cp /server/xash /server/xashds; fi \
    && chmod +x /server/xashds

# 2. Extrai os pacotes do servidor, valida pastas cstrike/valve e gera gfx.wad
COPY parte*.zip /server/
RUN for f in /server/parte*.zip; do unzip -o "$f"; rm "$f"; done \
    && CSTRIKE_DIR=$(find /server -maxdepth 3 -name cstrike -type d | head -n 1) \
    && if [ -n "$CSTRIKE_DIR" ] && [ "$CSTRIKE_DIR" != "/server/cstrike" ]; then cp -rn "$CSTRIKE_DIR" /server/; fi \
    && VALVE_DIR=$(find /server -maxdepth 3 -name valve -type d | head -n 1) \
    && if [ -n "$VALVE_DIR" ] && [ "$VALVE_DIR" != "/server/valve" ]; then cp -rn "$VALVE_DIR" /server/; fi \
    && mkdir -p /server/valve/dlls /server/cstrike/dlls \
    && printf 'sv_lan 1\nnet_port 27015\n' > /server/cstrike/server.cfg \
    && python3 -c "import struct; data=b'\x00'*16384; hdr=struct.pack('<4sII',b'WAD3',1,12+len(data)); entry=struct.pack('<IIIccH16s',12,len(data),len(data),b'B',b'\x00',0,b'CONCHARS'); open('/server/valve/gfx.wad','wb').write(hdr+data+entry)" \
    && cp -f /server/valve/gfx.wad /server/cstrike/gfx.wad

# 3. Cria o proxy HTTP + WebSocket-UDP com autodeteccao de porta e filtro de pacotes
RUN mkdir -p /server/proxy && cd /server/proxy && npm init -y && npm install ws \
    && printf 'const fs = require("fs");\nconst http = require("http");\nconst WebSocket = require("ws");\nconst dgram = require("dgram");\nconst PORT = Number(process.env.PORT) || 8080;\nfunction findXashPorts(excludePort) {\n  try {\n    const lines = fs.readFileSync("/proc/net/udp", "utf8").trim().split("\\n").slice(1);\n    const ports = [...new Set(lines.map(l => parseInt(l.trim().split(/\\s+/)[1].split(":")[1], 16)).filter(p => p > 1024 && p !== excludePort))];\n    return ports.length ? ports : [27015];\n  } catch (e) { return [27015]; }\n}\nconst server = http.createServer((req, res) => { res.writeHead(200); res.end("OK"); });\nconst wss = new WebSocket.Server({ server });\nwss.on("connection", (ws) => {\n  console.log("Cliente WS conectado!");\n  const udp = dgram.createSocket("udp4");\n  let myPort = 0;\n  udp.bind(0, () => { myPort = udp.address().port; });\n  let prefix = null;\n  udp.on("message", (msg, rinfo) => {\n    console.log("TX UDP de :" + rinfo.port + " (" + msg.length + "b):", msg.slice(0, 20).toString("hex"));\n    if (ws.readyState === 1) ws.send(prefix ? Buffer.concat([prefix, msg]) : msg);\n  });\n  ws.on("message", (data) => {\n    const buf = Buffer.from(data);\n    const targets = findXashPorts(myPort);\n    console.log("RX WS (" + buf.length + "b) -> UDP portas " + targets.join(",") + ":", buf.slice(0, 20).toString("hex"));\n    const idx = buf.indexOf(Buffer.from([0xff, 0xff, 0xff, 0xff]));\n    const payload = idx > 0 ? buf.slice(idx) : (idx === 0 ? buf : null);\n    if (idx > 0) prefix = buf.slice(0, idx);\n    if (payload) targets.forEach(p => udp.send(payload, p, "127.0.0.1"));\n  });\n  ws.on("close", () => udp.close());\n});\nserver.listen(PORT, "0.0.0.0", () => console.log("Proxy listening on 0.0.0.0:" + PORT));\n' > /server/proxy/index.js

# 4. Script de inicializacao com diagnostico de bibliotecas e loop de seguranca
RUN printf '#!/bin/sh\ncd /server\necho "=== Arquivos em /server ==="\nls -la /server\necho "=== Arquivos em /server/cstrike/dlls ==="\nls -la /server/cstrike/dlls\nnode /server/proxy/index.js &\nwhile true; do\n  echo "=== Iniciando xashds ==="\n  ./xashds -game cstrike -dedicated +ip 0.0.0.0 -port 27015 +sv_lan 1 +developer 2 +map de_dust2 +maxplayers 16 -console\n  echo "=== xashds encerrou, reiniciando em 3s ==="\n  sleep 3\ndone\n' > /server/start.sh \
    && chmod +x /server/start.sh

ENV LD_LIBRARY_PATH=/server:/server/valve/dlls:/server/cstrike/dlls
EXPOSE 8080
CMD ["/server/start.sh"]
