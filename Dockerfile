FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y python3 nodejs npm libc6 libstdc++6 libgcc-s1 unzip wget tar \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /server

# 1. Baixa o motor oficial Xash3D FWGS Linux (64-bit)
RUN wget -q https://github.com/FWGS/xash3d-fwgs/releases/download/continuous/xash3d-fwgs-linux-amd64.tar.gz \
    && tar -xzf xash3d-fwgs-linux-amd64.tar.gz \
    && rm xash3d-fwgs-linux-amd64.tar.gz \
    && ENGINE_DIR=$(dirname "$(find /server -name "libxash.so" | head -n 1)") \
    && if [ -n "$ENGINE_DIR" ] && [ "$ENGINE_DIR" != "/server" ]; then cp -rn "$ENGINE_DIR"/* /server/; fi \
    && if [ ! -f /server/xashds ] && [ -f /server/xash ]; then cp /server/xash /server/xashds; fi \
    && chmod +x /server/xashds

# 2. Extrai os pacotes do servidor e valida pastas cstrike/valve
COPY parte*.zip /server/
RUN for f in /server/parte*.zip; do unzip -o "$f"; rm "$f"; done \
    && CSTRIKE_DIR=$(find /server -maxdepth 3 -name cstrike -type d | head -n 1) \
    && if [ -n "$CSTRIKE_DIR" ] && [ "$CSTRIKE_DIR" != "/server/cstrike" ]; then cp -rn "$CSTRIKE_DIR" /server/; fi \
    && VALVE_DIR=$(find /server -maxdepth 3 -name valve -type d | head -n 1) \
    && if [ -n "$VALVE_DIR" ] && [ "$VALVE_DIR" != "/server/valve" ]; then cp -rn "$VALVE_DIR" /server/; fi \
    && mkdir -p /server/valve/dlls /server/cstrike/dlls \
    && printf 'sv_lan 1\n' > /server/cstrike/server.cfg \
    && python3 -c "import struct; data=b'\x00'*16384; hdr=struct.pack('<4sII',b'WAD3',1,12+len(data)); entry=struct.pack('<IIIccH16s',12,len(data),len(data),b'B',b'\x00',0,b'CONCHARS'); open('/server/valve/gfx.wad','wb').write(hdr+data+entry)" \
    && cp -f /server/valve/gfx.wad /server/cstrike/gfx.wad

# 3. Garante que existam bibliotecas de servidor 64-bit (.so) caso o zip so tenha mp.dll de Windows
RUN if ! ls /server/cstrike/dlls/*amd64.so >/dev/null 2>&1; then \
      wget -q https://github.com/FWGS/cs16-client/releases/download/continuous/cs16-linux-amd64.tar.gz -O /tmp/cs16.tar.gz \
      && tar -xzf /tmp/cs16.tar.gz -C /tmp \
      && find /tmp -name "*.so" -exec cp -n {} /server/cstrike/dlls/ \; \
      && rm -rf /tmp/cs16*; \
    fi

# Instala iproute2 (comando ss) para localizar exatamente a porta UDP do processo xashds
RUN apt-get update && apt-get install -y iproute2 && rm -rf /var/lib/apt/lists/*

# 4. Proxy HTTP + WebSocket-UDP que rastreia o PID/porta exata do xashds
RUN mkdir -p /server/proxy && cd /server/proxy && npm init -y && npm install ws \
    && printf 'const { execSync } = require("child_process");\nconst http = require("http");\nconst WebSocket = require("ws");\nconst dgram = require("dgram");\nconst PORT = Number(process.env.PORT) || 8080;\nfunction findXashPorts(excludePort) {\n  try {\n    const out = execSync("ss -ulnp", { encoding: "utf8" });\n    const found = new Set();\n    for (const line of out.split("\\n")) {\n      if (line.includes("xash")) {\n        const m = line.match(/:(\\d+)\\s+/);\n        if (m) {\n          const p = Number(m[1]);\n          if (p > 1024 && p !== excludePort) found.add(p);\n        }\n      }\n    }\n    if (found.size) return [...found];\n  } catch (e) {}\n  return [27015];\n}\nconst server = http.createServer((req, res) => { res.writeHead(200); res.end("OK"); });\nconst wss = new WebSocket.Server({ server });\nwss.on("connection", (ws) => {\n  console.log("Cliente WS conectado!");\n  const udp = dgram.createSocket("udp4");\n  let myPort = 0;\n  udp.bind(0, () => { myPort = udp.address().port; });\n  let prefix = null;\n  udp.on("message", (msg, rinfo) => {\n    console.log("TX UDP de :" + rinfo.port + " (" + msg.length + "b):", msg.slice(0, 20).toString("hex"));\n    if (ws.readyState === 1) ws.send(prefix ? Buffer.concat([prefix, msg]) : msg);\n  });\n  ws.on("message", (data) => {\n    const buf = Buffer.from(data);\n    const targets = findXashPorts(myPort);\n    console.log("RX WS (" + buf.length + "b) -> UDP portas " + targets.join(",") + ":", buf.slice(0, 20).toString("hex"));\n    const idx = buf.indexOf(Buffer.from([0xff, 0xff, 0xff, 0xff]));\n    const payload = idx > 0 ? buf.slice(idx) : (idx === 0 ? buf : null);\n    if (idx > 0) prefix = buf.slice(0, idx);\n    if (payload) targets.forEach(p => udp.send(payload, p, "127.0.0.1"));\n  });\n  ws.on("close", () => udp.close());\n});\nserver.listen(PORT, "0.0.0.0", () => console.log("Proxy listening on 0.0.0.0:" + PORT));\n' > /server/proxy/index.js

# 5. Script de inicializacao fixando -port 27015 antes de carregar o mapa
RUN printf '#!/bin/sh\ncd /server\nnode /server/proxy/index.js &\nsleep 1\nwhile true; do\n  echo "=== Iniciando xashds ==="\n  ./xashds -game cstrike -port 27015 +sv_lan 1 +map de_dust2 +maxplayers 16 -console 2>&1\n  echo "=== xashds saiu com codigo $? ==="\n  sleep 5\ndone\n' > /server/start.sh \
    && chmod +x /server/start.sh

ENV LD_LIBRARY_PATH=/server:/server/valve/dlls:/server/cstrike/dlls
EXPOSE 8080
CMD ["/server/start.sh"]
