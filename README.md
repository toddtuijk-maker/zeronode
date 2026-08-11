# ZeroNode · 零号节点管理平台

> 作者频道: **零号协议 @linghaoxieyi**
>
> 高安全 · 高稳定 · 高隐蔽 · 易维护 · 易扩展的自建节点部署管理系统

ZeroNode 是在 `flame1ce/hysteria2-install`（2023 年停更的单协议脚本）基础上，按长期维护的软件工程标准重构的多协议节点管理平台。
保留「`wget` + `bash` 一键安装」的简单体验，内部采用分层架构：协议层插件化、配置变更强制备份/校验/回滚、凭证独立管理、Watchdog 自愈、版本锁定升级、多客户端订阅生成。

---

## 支持的协议组合

| 协议 | 是否需要域名 | 隐蔽性 | 说明 | 状态 |
| --- | --- | --- | --- | --- |
| VLESS + REALITY + XTLS Vision | 否 | 高 | 借用目标站证书，客户端生态最广 | ✅ 已实现 |
| VLESS + REALITY + XHTTP | 否 | 高 | 抗封锁较好（Xray 官方支持） | ✅ 已实现 |
| Hysteria 2 + TLS + obfs(salamander) | 否（自签） | 中高 | UDP 高吞吐 | ✅ 已实现 |
| Trojan + TLS | 可选（自签/正式证书） | 中 | 老牌兼容 | ✅ 已实现 |
| VLESS + WS + TLS（CDN 逃生） | 是 | 中 | CDN 隐藏源站 IP | 🚧 规划 |
| VLESS + gRPC + REALITY | 否 | 高 | | 🚧 规划 |
| Shadowsocks 2022 | 否 | 低 | 兼容极广 | 🚧 规划 |
| TUIC v5 | 否 | 中 | UDP 高性能 | 🚧 规划 |

新增协议只需复制 `protocols/_template.sh.example` 并实现 Protocol Interface 契约。

## 内核选择（默认 sing-box）

VLESS/REALITY/Trojan 家族支持两种服务端内核，**默认推荐 sing-box**：

| 内核 | 说明 | 如何选择 |
| --- | --- | --- |
| **sing-box（默认推荐）** | 统一生态、配置简洁、与客户端生态一致 | 安装菜单选「9. 切换内核」或 `export ZN_KERNEL=singbox` |
| Xray（备选） | Xray-core，生态成熟 | `export ZN_KERNEL=xray` 或在菜单切换 |

两种内核生成完全相同的分享链接/订阅（vless://、trojan://），客户端侧无感知；已安装节点可用 `zn rotate <proto>` 轮换，切换内核需重新部署对应协议。

---

## 快速安装

```bash
# 国内/海外均可（脚本会自动安装依赖）
wget -N https://raw.githubusercontent.com/toddtuijk-maker/zeronode/main/install.sh && bash install.sh
```

> 单文件即可安装：脚本会自动从仓库拉取完整组件（lib/protocols/vendor 等）、做结构与语法校验后安装到 `/opt/zeronode`，并提供 `zn` 命令。若你 fork 了本项目，请设置环境变量后运行：
>
> ```bash
> export ZN_REPO_URL=https://github.com/<你的账号>/zeronode
> wget -N https://raw.githubusercontent.com/<你的账号>/zeronode/main/install.sh && bash install.sh
> ```

安装后进入菜单：

```text
 1. 一键部署 · 安全优先（IP 全家桶: Hysteria2 + Vision + XHTTP）
 2. 一键部署 · 域名版（输入域名，Hysteria2 申请正式证书）
 3. 一键部署 · 速度优先（Hysteria2 + Vision）
 4. 一键部署 · 兼容优先（Vision + Trojan）
 5. 单协议安装（IP 一键）
 6. 显示全部链接 / 二维码 / 订阅
 7. 环境检测报告
 8. 管理入口
```

所有参数（端口 / UUID / 密码 / 伪装网站）直接回车即为随机生成；REALITY 目标站与伪装网站从可信清单中随机稳定选取，也可自定义。

## 系统兼容性

支持常见的 Linux 发行版（需 systemd）：

| 发行版 | 包管理器 | 支持 |
| --- | --- | --- |
| Debian / Ubuntu | apt | ✅ |
| CentOS 7 / AlmaLinux / Rocky | yum | ✅ |
| CentOS 8+ / AlmaLinux 9 / Rocky 9 / Fedora / Amazon Linux 2023 | dnf | ✅ |
| openSUSE / SLES | zypper | ✅ |
| Arch Linux / Manjaro | pacman | ✅ |
| Alpine（OpenRC，无 systemd） | apk | ⚠️ 不支持（Hysteria/Xray 官方安装器依赖 systemd） |

兼容性细节：

- 依赖安装按发行版自动映射包名（例如 RHEL 系的 `sqlite`、`cronie`）；
- RHEL 系 SELinux 自动执行 `restorecon` 修复服务单元与二进制上下文；
- 防火墙（ufw/firewalld）自动放行协议端口；启用默认拒绝时会自动保留 SSH 端口，防止锁死；
- BBR 自动启用（内核 ≥4.9，fq + bbr）；网络参数调优写入 `/etc/sysctl.d/`。

## Docker 支持

ZeroNode 提供生产容器镜像（`docker/Dockerfile.prod`），容器内以进程守护代替 systemd：

- **自动识别容器环境**：检测到 Docker 时自动切换到容器模式；
- **端口自动探索**：自动探测宿主机已映射/可达（可出网）的 TCP 端口作为默认端口（连通性通过「容器内监听 + 回连公网/网关 IP」验证）；Hysteria2 的 UDP 端口需确保 `-p <port>:<port>/udp` 已映射；
- **一键部署**：设置 `ZN_AUTO_INSTALL=1` 自动完成安装与配置生成；
- **推荐网络模式**：`--network host` 最简单；桥接模式需显式 `-p` 映射端口。

```bash
# 方式一：host 网络（推荐）
docker build -f docker/Dockerfile.prod -t zeronode .
docker run -d --network host --name zeronode \
  -v zeronode-data:/var/lib/zeronode \
  -e ZN_AUTO_INSTALL=1 -e ZN_DEPLOY_MODE=security \
  zeronode

# 方式二：桥接 + 端口映射（先看容器日志确认实际端口）
docker run -d --name zeronode \
  -p 443:443 -p 8443:8443 -p 9443:9443 -p 5678:5678/udp \
  -v zeronode-data:/var/lib/zeronode \
  -e ZN_AUTO_INSTALL=1 zeronode
```

容器内管理：`docker exec -it zeronode zn links`、`docker exec zeronode zn status` 等。

---

## 架构

```text
用户层    Web UI(规划)   CLI(bin/zn)   Local API(127.0.0.1)
管理层    Node/Config/Credential/Update/Backup Manager
策略层    Security / Stealth / Performance Policy
协议层    Protocol Interface（hysteria2 / xray / trojan / 未来）
系统层    OS 检测 · 包管理 · systemd · 防火墙 · BBR · DNS · 时间同步
监控层    Watchdog 自愈 · 健康检查 · 保护模式
```

详细设计见 [docs/PHASE2-architecture.md](docs/PHASE2-architecture.md)，现状分析见 [docs/PHASE1-analysis.md](docs/PHASE1-analysis.md)。

---

## 安全设计（默认开启）

- **最小权限**：协议服务以独立低权限用户运行；管理命令仅必要时提权；管理 API 默认只监听 `127.0.0.1`。
- **凭证管理**：UUID/密码/REALITY 私钥统一存于 0600 凭证库；日志自动脱敏；支持轮换、撤销、加密备份。
- **配置安全**：任何配置变更强制走「备份 → 临时配置 → 校验 → 原子应用 → 健康检查 → 失败自动回滚」，禁止改完直接 restart。
- **供应链**：Hysteria2 / Xray 均使用 vendored 官方安装器（内置 SHA256 校验），升级支持版本锁定，失败自动恢复。
- **防火墙**：检测到 ufw/firewalld 时自动放行协议端口，可配置默认拒绝入站。
- **完整性自检**：对自身脚本生成 SHA256 清单，运行前校验是否被篡改。
- **证书策略**：IP 版 REALITY 借用目标站证书（客户端可信）；Hysteria2 自签（insecure=1 属协议预期）；域名版用 acme.sh 申请 Let's Encrypt 正式证书并自动续期。

## 稳定性设计

- **Watchdog 自愈**：每 60s 健康检查（systemd 状态 + 端口监听），异常自动重启；连续失败 3 次进入保护模式并冷却。
- **配置版本管理**：`zn config list <proto>` / `zn config rollback <proto> [ver]`。
- **升级体系**：`zn check <proto>` / `zn upgrade <proto> [版本]` / `zn pin <proto> [版本]`，全程备份 + 验证 + 回滚。
- **备份恢复**：`zn backup [口令]`（可选 AES-256 加密）/ `zn restore <文件> [口令]`。

---

## 客户端与订阅（多客户端兼容）

部署完成后自动生成：

- **分享链接**：`vless://`（REALITY Vision/XHTTP）、`hysteria2://`、`trojan://` —— 兼容 v2rayN / v2rayNG / 小火箭(Shadowrocket) / Stash / Loon / Karing 等
- **二维码**：终端直接扫码导入
- **sing-box**：`/var/lib/zeronode/sub/singbox.json`
- **Clash Meta**：`/var/lib/zeronode/sub/clash.yaml`（含节点组与规则）
- **纯文本订阅**：`/var/lib/zeronode/sub/sub.txt`

对外订阅端点（默认关闭，Token 鉴权）：

```bash
zn sub enable 8081
# 客户端填入:
#   http://<IP>:8081/sub?token=<TOKEN>&type=plain     (v2ray/小火箭等)
#   http://<IP>:8081/sub?token=<TOKEN>&type=clash     (Clash Meta/mihomo/ClashX)
#   http://<IP>:8081/sub?token=<TOKEN>&type=singbox   (sing-box/Karing)
```

---

## 管理命令（bin/zn）

```bash
zn status                          # 全部协议状态
zn restart <proto|all>             # 重启
zn env [security|speed|compat]     # 环境检测报告
zn links                           # 链接/二维码/订阅
zn rotate <proto>                  # 轮换凭证
zn revoke <uuid>                   # 撤销用户
zn backup [口令] / zn restore <文件> [口令]
zn check / upgrade / pin <proto>   # 升级与版本锁定
zn config list|rollback <proto> [ver]
zn sub enable|disable|token|status [port]
zn api install|token|status [port]
zn watchdog status
zn logs [N]
```

---

## 目录结构

```text
zeronode/
├── install.sh          一键安装入口（美化 UI）
├── bin/zn              CLI 管理入口
├── bin/zn-daemon       Watchdog / API / 订阅服务
├── lib/                管理层 + 系统层 + 监控层 + 客户端层
├── protocols/          协议层（interface + hysteria2 + xray）
├── vendor/             vendored 官方安装器
├── docs/               分析/架构/安装/升级/恢复/排障
├── tests/              自动化测试
├── docker/Dockerfile   开发测试容器
└── api/openapi.yaml    API 规范
```

## 文档

- [Phase 1 现状分析](docs/PHASE1-analysis.md)
- [Phase 2 架构设计](docs/PHASE2-architecture.md)
- [安装文档](docs/INSTALL.md)
- [升级文档](docs/UPGRADE.md)
- [恢复文档](docs/RECOVERY.md)
- [故障排查](docs/TROUBLESHOOTING.md)

## License

MIT
