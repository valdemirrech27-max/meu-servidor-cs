FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python3-websockify libc6 libstdc++6 unzip && rm -rf /var/lib/apt/lists/*
WORKDIR /server
COPY parte1.zip parte2.zip /server/
RUN unzip -o parte1.zip && unzip -o parte2.zip && rm parte1.zip parte2.zip \
    && XASH_DIR=$(dirname "$(find /server -name xashds -type f | head -n 1)") \
    && if [ "$XASH_DIR" != "/server" ]; then cp -rn "$XASH_DIR"/* /server/; fi \
    && chmod +x /server/xashds
EXPOSE 8080
CMD ["sh", "-c", "websockify 8080 127.0.0.1:27015 & ./xashds -game cstrike +map de_dust2 +maxplayers 16"]
