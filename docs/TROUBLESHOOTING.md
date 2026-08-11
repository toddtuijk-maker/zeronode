# 故障排查

## 服务起不来

```bash
zn logs 100
systemctl status hysteria-server --no-pager -l
systemctl status xray --no-pager -l
```

常见原因：

- 端口被占用 → `zn restart` 前用 `ss -tunlp | grep <port>` 检查；
- 配置语法错误 → 查看 `zn config list` 并回滚 `zn config rollback <proto>`；
- 证书过期/缺失 → 检查 `/etc/hysteria/cert.crt`、`/usr/local/etc/xray/tls/`；
- 系统时间未同步 → TLS 握手失败，执行 `timedatectl set-ntp true`。

## 客户端连不上

- 确认分享链接中的 IP 是当前公网 IP：`zn links`；
- 云厂商安全组是否放行对应 TCP/UDP 端口；
- REALITY 无法连接 → 目标站（dest）可能被墙或不支持 TLS1.3，`zn env` 后换 dest；
- Hysteria2 走 UDP → 确认运营商/防火墙未封 UDP。

## 被墙/封 IP

- 先试 `zn rotate xray` 轮换密钥并换端口；
- 考虑启用域名版 + CDN（规划中的 WS+XHTTP+TLS 组合）；
- 检查是否可开 BBR：`systemctl` 查看 `/etc/sysctl.d/99-zeronode-bbr.conf`。

## Watchdog 保护模式

连续失败 3 次后进入保护模式（冷却 30 分钟），期间不会自动重启：

```bash
zn watchdog status
# 手动处理后清除计数:
zn rotate <proto> && zn restart <proto>
```

## 日志脱敏说明

日志中凭证值会自动替换为 `***`；若怀疑泄露，执行 `zn rotate <proto>` 立即轮换。

## Docker 容器专项

- **端口不通**：桥接模式未映射端口 → 用 `--network host` 或补 `-p`；查看容器日志中的实际端口（`docker logs zeronode | grep 端口`）。
- **UDP 不通（Hysteria2）**：确认 `-p <port>:<port>/udp`（TCP 映射不覆盖 UDP）。
- **IP 探测异常**：容器内 `zn env` 查看 Docker 与网络模式行；host 模式下公网 IP 应与宿主机一致。
- **重启容器后配置丢失**：必须挂载 `-v zeronode-data:/var/lib/zeronode` 持久化数据。
