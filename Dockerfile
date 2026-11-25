FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python3-websockify libc6 libstdc++6 unzip wget tar && rm -rf /var/lib/apt/lists/*
WORKDIR /server

# Baixa o motor oficial Xash3D FWGS Linux (com xashds e libxash.so garantidos)
RUN wget -q https://github.com/FWGS/xash3d-fwgs/releases/download/continuous/xash3d-fwgs-linux-amd64.tar.gz \
    && tar -xzf xash3d-fwgs-linux-amd64.tar.gz \
    && rm xash3d-fwgs-linux-amd64.tar.gz

# Extrai apenas a sua pasta cstrike (parte2.zip)
COPY parte2.zip /server/
RUN unzip -o parte2.zip && rm parte2.zip \
    && CSTRIKE_DIR=$(find /server -maxdepth 3 -name cstrike -type d | head -n 1) \
    && if [ -n "$CSTRIKE_DIR" ] && [ "$CSTRIKE_DIR" != "/server/cstrike" ]; then cp -rn "$CSTRIKE_DIR" /server/; fi \
    && mkdir -p /server/valve/dlls \
    && cp -n /server/cstrike/dlls/*.so /server/valve/dlls/ 2>/dev/null || true \
    && chmod +x /server/xashds

ENV LD_LIBRARY_PATH=/server
EXPOSE 8080
CMD ["sh", "-c", "websockify 8080 127.0.0.1:27015 & ./xashds -game cstrike +map de_dust2 +maxplayers 16"]
