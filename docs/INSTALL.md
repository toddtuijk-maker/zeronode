# 安装文档

## 环境要求

- Linux（Debian/Ubuntu/CentOS/AlmaLinux/Rocky/Fedora/Amazon Linux/openSUSE/Arch/Alpine），systemd
- root 权限
- 至少 256MB 内存、1GB 磁盘
- 出站网络通畅（安装器需访问 GitHub）

## 一键安装

```bash
wget -N https://raw.githubusercontent.com/<你的仓库>/main/install.sh
bash install.sh
```

脚本会自动：

1. 安装到 `/opt/zeronode` 并创建 `zn` 命令；
2. 初始化数据目录 `/var/lib/zeronode`（SQLite、凭证库 0600、日志、配置历史）；
3. 安装依赖（curl/openssl/sqlite3/qrencode/socat 等）；
4. 显示环境检测报告并进入部署菜单。

## 部署模式

| 模式 | 内容 | 适用场景 |
| --- | --- | --- |
| 安全优先（默认） | Hysteria2+obfs + REALITY Vision + REALITY XHTTP | 默认推荐 |
| 速度优先 | Hysteria2+obfs + REALITY Vision | 大流量/追求吞吐 |
| 兼容优先 | REALITY Vision + Trojan+TLS | 客户端生态最广 |
| 域名版 | 以上组合 + 输入域名 | Hysteria2 申请正式证书 |

## 内核选择

- 默认内核：**sing-box**（VLESS+REALITY Vision/XHTTP + Trojan 服务端）；
- 备选内核：Xray —— 安装菜单选「9. 切换 VLESS 内核」，或 `export ZN_KERNEL=xray`；
- 两种内核客户端链接/订阅格式完全一致，切换不影响已生成链接（需重新部署该协议生效）。

## 安装后验证

```bash
zn status          # 协议状态 active
zn links           # 分享链接 + 二维码
systemctl status hysteria-server xray
```

## 常见客户端配置位置

- 链接/二维码：`zn links`
- 订阅文件：`/var/lib/zeronode/sub/`（sub.txt / clash.yaml / singbox.json）
- 服务端配置：`/etc/hysteria/config.yaml`、`/usr/local/etc/xray/config.json`

## Docker 部署

```bash
docker build -f docker/Dockerfile.prod -t zeronode .
# host 网络（推荐）
docker run -d --network host --name zeronode \
  -v zeronode-data:/var/lib/zeronode \
  -e ZN_AUTO_INSTALL=1 -e ZN_DEPLOY_MODE=security \
  zeronode
# 桥接模式（需映射端口；容器会自动探测已映射的可出网端口）
docker run -d --name zeronode \
  -p 443:443 -p 8443:8443 -p 5678:5678/udp \
  -v zeronode-data:/var/lib/zeronode \
  -e ZN_AUTO_INSTALL=1 zeronode
```

说明：

- 容器内没有 systemd，ZeroNode 自动以进程守护方式运行 Hysteria2/Xray；
- `ZN_AUTO_INSTALL=1` 时自动安装（参数全部随机，端口自动探测）；安装后日志查看 `docker logs zeronode`；
- UDP 端口（Hysteria2）无法自动探测，请务必用 `-p <port>:<port>/udp` 显式映射；
- 管理命令：`docker exec -it zeronode zn links` / `zn status` / `zn rotate xray`。
