FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 1. Dependencias essenciais em uma unica camada
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates python3 nodejs npm libc6 libstdc++6 libgcc-s1 iproute2 unzip wget tar \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /server

# 2. Motor oficial Xash3D FWGS Linux (64-bit)
RUN wget -q https://github.com/FWGS/xash3d-fwgs/releases/download/continuous/xash3d-fwgs-linux-amd64.tar.gz \
    && tar -xzf xash3d-fwgs-linux-amd64.tar.gz \
    && rm xash3d-fwgs-linux-amd64.tar.gz \
    && ENGINE_DIR=$(dirname "$(find /server -name "libxash.so" | head -n 1)") \
    && if [ -n "$ENGINE_DIR" ] && [ "$ENGINE_DIR" != "/server" ]; then cp -rn "$ENGINE_DIR"/* /server/; fi \
    && if [ ! -f /server/xashds ] && [ -f /server/xash ]; then cp /server/xash /server/xashds; fi \
    && chmod +x /server/xashds

# 3. Extracao dos pacotes, organizacao de diretorios e WAD basico
COPY parte*.zip /server/
RUN for f in /server/parte*.zip; do unzip -o "$f"; rm "$f"; done \
    && CSTRIKE_DIR=$(find /server -maxdepth 3 -name cstrike -type d | head -n 1) \
    && if [ -n "$CSTRIKE_DIR" ] && [ "$CSTRIKE_DIR" != "/server/cstrike" ]; then cp -rn "$CSTRIKE_DIR" /server/; fi \
    && VALVE_DIR=$(find /server -maxdepth 3 -name valve -type d | head -n 1) \
    && if [ -n "$VALVE_DIR" ] && [ "$VALVE_DIR" != "/server/valve" ]; then cp -rn "$VALVE_DIR" /server/; fi \
    && mkdir -p /server/valve/dlls /server/cstrike/dlls \
    && printf 'sv_lan 1\nhostname "CS 1.6 Web Server"\n' > /server/cstrike/server.cfg \
    && python3 -c "import struct; data=b'\x00'*16384; hdr=struct.pack('<4sII',b'WAD3',1,12+len(data)); entry=struct.pack('<IIIccH16s',12,len(data),len(data),b'B',b'\x00',0,b'CONCHARS'); open('/server/valve/gfx.wad','wb').write(hdr+data+entry)" \
    && cp -f /server/valve/gfx.wad /server/cstrike/gfx.wad

# 4. Proxy WebSocket-UDP seguro usando heredoc literal (sem risco de escape quebrado)
RUN mkdir -p /server/proxy && cd /server/proxy && npm init -y && npm install ws
RUN cat << 'EOF' > /server/proxy/index.js
const { exec } = require("child_process");
const http = require("http");
const WebSocket = require("ws");
const dgram = require("dgram");

const PORT = Number(process.env.PORT) || 8080;
let cachedPorts = [27015];

function refreshPorts() {
  exec("ss -ulnp", { encoding: "utf8" }, (err, out) => {
    if (err || !out) return;
    const found = new Set();
    for (const line of out.split("\n")) {
      if (line.includes("xash") && !line.includes("node")) {
        const matches = line.matchAll(/(?:\*|0\.0\.0\.0|\[::\]|127\.0\.0\.1):(\d+)/g);
        for (const m of matches) {
          const p = Number(m[1]);
          if (p > 1024) found.add(p);
        }
      }
    }
    if (found.size) cachedPorts = [...found];
  });
}

setInterval(refreshPorts, 2000);
refreshPorts();

const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("OK");
});

const wss = new WebSocket.Server({ server });

wss.on("connection", (ws) => {
  console.log("Cliente WS conectado! Portas alvo:", cachedPorts.join(","));
  const udp = dgram.createSocket("udp4");
  let prefix = null;
  let closed = false;

  const cleanup = () => {
    if (!closed) {
      closed = true;
      try { udp.close(); } catch (e) {}
    }
  };

  udp.on("error", (err) => {
    console.error("Erro UDP:", err.message);
    cleanup();
  });

  udp.bind(0);

  udp.on("message", (msg, rinfo) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(prefix ? Buffer.concat([prefix, msg]) : msg);
    }
  });

  ws.on("message", (data) => {
    const buf = Buffer.from(data);
    const idx = buf.indexOf(Buffer.from([0xff, 0xff, 0xff, 0xff]));
    const payload = idx > 0 ? buf.slice(idx) : (idx === 0 ? buf : null);
    if (idx > 0) prefix = buf.slice(0, idx);
    if (payload && !closed) {
      cachedPorts.forEach((p) => udp.send(payload, p, "127.0.0.1"));
    }
  });

  ws.on("close", cleanup);
  ws.on("error", cleanup);
});

server.listen(PORT, "0.0.0.0", () => {
  console.log("Proxy listening on 0.0.0.0:" + PORT);
});
EOF

# 5. Script de inicializacao com verificacao de bibliotecas e logs limpos
RUN cat << 'EOF' > /server/start.sh
#!/bin/sh
cd /server
echo "=== Arquivos em /server/cstrike/dlls ==="
ls -la /server/cstrike/dlls

node /server/proxy/index.js &
sleep 1

while true; do
  echo "=== Iniciando xashds ==="
  ./xashds -dedicated -game cstrike -port 27015 +sv_lan 1 +map de_dust2 +maxplayers 16 -console 2>&1
  echo "=== xashds saiu com codigo $? ==="
  sleep 5
done
EOF
RUN chmod +x /server/start.sh

ENV LD_LIBRARY_PATH=/server:/server/valve/dlls:/server/cstrike/dlls
EXPOSE 8080
CMD ["/server/start.sh"]
