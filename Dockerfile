FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python3 python3-pip libc6 libstdc++6 unzip wget tar \
    && pip3 install --no-cache-dir websockets \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /server

RUN wget -q https://github.com/FWGS/xash3d-fwgs/releases/download/continuous/xash3d-fwgs-linux-amd64.tar.gz \
    && tar -xzf xash3d-fwgs-linux-amd64.tar.gz \
    && rm xash3d-fwgs-linux-amd64.tar.gz \
    && ENGINE_DIR=$(dirname "$(find /server -name "libxash.so" | head -n 1)") \
    && if [ "$ENGINE_DIR" != "/server" ]; then cp -rn "$ENGINE_DIR"/* /server/; fi \
    && if [ ! -f /server/xashds ] && [ -f /server/xash ]; then cp /server/xash /server/xashds; fi \
    && chmod +x /server/xashds

COPY parte*.zip /server/
RUN for f in /server/parte*.zip; do unzip -o "$f"; rm "$f"; done \
    && CSTRIKE_DIR=$(find /server -maxdepth 3 -name cstrike -type d | head -n 1) \
    && if [ -n "$CSTRIKE_DIR" ] && [ "$CSTRIKE_DIR" != "/server/cstrike" ]; then cp -rn "$CSTRIKE_DIR" /server/; fi \
    && VALVE_DIR=$(find /server -maxdepth 3 -name valve -type d | head -n 1) \
    && if [ -n "$VALVE_DIR" ] && [ "$VALVE_DIR" != "/server/valve" ]; then cp -rn "$VALVE_DIR" /server/; fi \
    && mkdir -p /server/valve/dlls /server/cstrike/dlls \
    && touch /server/valve/valve.rc /server/cstrike/server.cfg \
    && python3 -c "import struct; data=b'\x00'*16384; hdr=struct.pack('<4sII',b'WAD3',1,12+len(data)); entry=struct.pack('<IIIccH16s',12,len(data),len(data),b'B',b'\x00',0,b'CONCHARS'); open('/server/valve/gfx.wad','wb').write(hdr+data+entry)" \
    && cp -f /server/valve/gfx.wad /server/cstrike/gfx.wad \
    && printf 'import asyncio,os,socket,websockets\nasync def h(ws):\n s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)\n s.connect(("127.0.0.1",27015))\n s.setblocking(False)\n loop=asyncio.get_running_loop()\n async def rx():\n  while True:\n   d=await loop.sock_recv(s,4096)\n   await ws.send(d)\n t=asyncio.create_task(rx())\n try:\n  async for m in ws:\n   await loop.sock_sendall(s,m if isinstance(m,bytes) else m.encode())\n finally:\n  t.cancel();s.close()\nasync def main():\n async with websockets.serve(h,"0.0.0.0",int(os.environ.get("PORT",8080))): await asyncio.Future()\nasyncio.run(main())\n' > /server/proxy.py

ENV LD_LIBRARY_PATH=/server
EXPOSE 8080
CMD ["sh", "-c", "python3 /server/proxy.py & ./xashds -game cstrike +ip 0.0.0.0 +port 27015 +map de_dust2 +maxplayers 16 -console"]
