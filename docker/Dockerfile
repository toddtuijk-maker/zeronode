# ZeroNode 开发/测试容器（生产节点使用裸机 systemd，本容器用于 CI 与本地验证）
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash curl openssl sqlite3 qrencode socat ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/zeronode
COPY . .

RUN chmod +x install.sh bin/zn bin/zn-daemon

ENTRYPOINT ["/bin/bash"]
