FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python3-websockify libc6 libstdc++6 unzip && rm -rf /var/lib/apt/lists/*
WORKDIR /server
COPY servidor.zip /server/
RUN unzip servidor.zip && rm servidor.zip && chmod +x /server/xashds
EXPOSE 8080
CMD ["sh", "-c", "websockify 8080 127.0.0.1:27015 & ./xashds -game cstrike +map de_dust2 +maxplayers 16"]