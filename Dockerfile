FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python3-websockify libc6 libstdc++6 unzip && rm -rf /var/lib/apt/lists/*
WORKDIR /server
COPY parte1.zip parte2.zip /server/
RUN unzip -o parte1.zip && unzip -o parte2.zip && rm parte1.zip parte2.zip \
    && echo "=== ARQUIVOS ENCONTRADOS ===" \
    && find /server -maxdepth 3 \
    && BIN=$(find /server -type f \( -name "xashds" -o -name "xash" -o -name "xash3d" \) | head -n 1) \
    && if [ -z "$BIN" ]; then echo "ERRO: Executavel Linux nao encontrado!"; exit 1; fi \
    && if [ "$(dirname "$BIN")" != "/server" ]; then cp -rn "$(dirname "$BIN")"/* /server/; fi \
    && mv "$BIN" /server/xashds 2>/dev/null || true \
    && CSTRIKE_DIR=$(find /server -maxdepth 3 -name cstrike -type d | head -n 1) \
    && if [ -n "$CSTRIKE_DIR" ] && [ "$CSTRIKE_DIR" != "/server/cstrike" ]; then cp -rn "$CSTRIKE_DIR" /server/; fi \
    && VALVE_DIR=$(find /server -maxdepth 3 -name valve -type d | head -n 1) \
    && if [ -n "$VALVE_DIR" ] && [ "$VALVE_DIR" != "/server/valve" ]; then cp -rn "$VALVE_DIR" /server/; fi \
    && chmod +x /server/xashds
EXPOSE 8080
CMD ["sh", "-c", "websockify 8080 127.0.0.1:27015 & ./xashds -game cstrike +map de_dust2 +maxplayers 16"]
