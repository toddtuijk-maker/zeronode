# Phase 2：ZeroNode 架构设计

> 目标：高安全、高稳定、高隐蔽、易维护、易扩展的节点部署管理系统
> 原则排序：安全性 > 稳定性 > 易用性 > 性能 > 新功能

---

## 1. 目录结构

```text
zeronode/
├── install.sh              # 一键安装入口（美化 UI + 作者频道 + 模式选择）
├── bin/
│   ├── zn                  # CLI 管理入口（status/restart/config/rotate/backup/upgrade/logs/sub/api）
│   └── zn-daemon           # 监控/自愈守护进程（Watchdog）
├── lib/
│   ├── common.sh           # 框架：加载器、错误处理、JSON 工具、输入校验
│   ├── logging.sh          # 分级日志（ERROR/WARN/INFO/DEBUG）+ 脱敏 + 轮转清理
│   ├── envcheck.sh         # 环境检测报告 + 推荐方案
│   ├── system.sh           # 系统层：包管理/服务/防火墙/BBR/时间同步/DNS/网络调优
│   ├── db.sh               # SQLite 数据层（Schema 初始化 + CRUD + 迁移钩子）
│   ├── credential.sh       # 凭证管理器（生成/轮换/撤销/备份/恢复/脱敏）
│   ├── config_manager.sh   # 配置管理器（备份→临时配置→校验→测试→应用→回滚 + 版本记录）
│   ├── stealth.sh          # 隐蔽策略引擎（REALITY/TLS/伪装/未授权响应）
│   ├── policy.sh           # 策略层（安全/速度/兼容 → 推荐协议与参数）
│   ├── deploy.sh           # 智能部署编排（单协议/批量/IP/域名）
│   ├── watchdog.sh         # 监控与自愈（健康检查/保护模式）
│   ├── update.sh           # 升级管理器（版本锁定/备份/升级/验证/回滚）
│   ├── backup.sh           # 备份管理器（全量备份/加密/恢复）
│   ├── clientgen.sh        # 客户端生成（URI/QR/sing-box/Clash Meta/订阅文件）
│   ├── api.sh              # Local API（127.0.0.1 + Token）+ 可选订阅端点
│   └── ui.sh               # 终端 UI（横幅/菜单/进度/作者频道）
├── protocols/
│   ├── interface.sh        # Protocol Interface 契约 + 分发器
│   ├── hysteria2.sh        # Hysteria2（TLS + obfs）
│   ├── singbox.sh          # sing-box 内核（默认推荐）：VLESS+REALITY+Vision/XHTTP + Trojan
│   └── xray.sh             # Xray 内核（备选）：VLESS+REALITY+Vision/XHTTP + Trojan
│   └── _template.sh        # 新协议模板
├── vendor/
│   ├── install_server.sh        # apernet 官方 Hysteria 安装器（SHA256 校验内置）
│   └── xray-install-release.sh  # XTLS 官方 Xray 安装器（SHA256 校验内置 + 版本锁定）
├── docs/                   # PHASE1 / PHASE2 / INSTALL / UPGRADE / RECOVERY / TROUBLESHOOTING
├── tests/                  # 自动化测试（bash + shellcheck + 函数级冒烟）
├── docker/Dockerfile       # 开发/测试容器
├── api/openapi.yaml        # API 规范（管理面 + 订阅端点）
└── README.md
```

运行期状态（install.sh 自动创建，0600/0700）：

```text
/opt/zeronode           # 程序本体（lib/protocols/vendor）
/var/lib/zeronode/
├── zeronode.db         # SQLite
├── credentials         # 凭证库（0600 root）
├── config-history/     # 配置版本历史（按协议/时间戳目录）
├── backups/            # 全量备份
├── sub/                # 生成的订阅文件
└── logs/zeronode.log   # 分级日志（含轮转）
/etc/zeronode.conf      # 全局配置（API token、订阅开关、端口等）
```

---

## 2. 数据层设计（SQLite）

```sql
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);

CREATE TABLE nodes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  hostname TEXT, ipv4 TEXT, ipv6 TEXT,
  os TEXT, arch TEXT, kernel TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE protocols (
  name TEXT PRIMARY KEY,          -- hysteria2 | xray
  enabled INTEGER DEFAULT 1,
  status TEXT DEFAULT 'unknown',  -- active | inactive | failed | unknown
  port INTEGER, transport TEXT, stealth TEXT,
  installed_at TEXT, updated_at TEXT
);

CREATE TABLE users (
  id TEXT PRIMARY KEY,            -- UUID
  name TEXT,                      -- 显示名/用户名
  created_at TEXT DEFAULT (datetime('now')),
  revoked INTEGER DEFAULT 0,
  revoked_at TEXT
);
-- 真实凭证（UUID/密码/私钥/公钥/shortId/obfs）存于 0600 的 credentials 文件，DB 仅存引用

CREATE TABLE config_versions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  protocol TEXT NOT NULL,
  version INTEGER NOT NULL,
  checksum TEXT, backup_path TEXT,
  reason TEXT, applied INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE operations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT DEFAULT (datetime('now')),
  actor TEXT, action TEXT, target TEXT, result TEXT, detail TEXT
);

CREATE TABLE health (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT DEFAULT (datetime('now')),
  protocol TEXT, ok INTEGER, latency_ms INTEGER, detail TEXT
);

CREATE TABLE upgrades (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT DEFAULT (datetime('now')),
  protocol TEXT, from_ver TEXT, to_ver TEXT, result TEXT
);
```

迁移策略：`db_migrate()` 读取 `meta.schema_version`，按版本递增执行 `db_migrate_<N>()`，为未来 PostgreSQL 预留抽象（`db_query`/`db_exec` 为唯一 SQL 入口）。

---

## 3. 安全设计

### 3.1 最小权限

- Hysteria2 / Xray 均以独立低权限用户运行（官方安装器已实现，ZeroNode 复核并写入 systemd 加固参数：`NoNewPrivileges`、`CapabilityBoundingSet`、`PrivateTmp`）。
- 管理命令不常驻 root：`bin/zn` 检测权限，必要时经 `sudo` 重执行（与官方安装器一致的策略）。
- 管理 API 默认只监听 `127.0.0.1`；订阅端点默认关闭，启用需显式执行 `zn sub enable --port N`。

### 3.2 Credential Manager

凭证存储：`/var/lib/zeronode/credentials`（root:root 0600），键值格式：

```text
hysteria2.auth_password=xxx
hysteria2.obfs_password=xxx
xray.uuid=<UUID>
xray.reality.private_key=xxx
xray.reality.public_key=xxx
xray.reality.short_id=xxx
xray.trojan.password=xxx
```

功能：

- 强随机：`openssl rand`（密码 ≥16 字节，UUID 用 `xray uuid`/`/proc/sys/kernel/random/uuid`，X25519 用 `xray x25519`）。
- 轮换：`zn rotate <protocol>` → 生成新凭证 → 走 Config Manager 全流程 → 旧凭证进入 revoked 记录。
- 撤销：`zn revoke <user>` → 从协议配置中移除该用户 → 重启并健康检查。
- 备份/恢复：备份时可用口令做 AES-256-CBC 加密（`openssl enc`）。
- 脱敏：logging 层加载凭证清单，日志输出自动替换为 `***`。

### 3.3 Config Manager（核心安全流程）

任何配置变更（安装/改端口/改密码/换证书/升级）都必须走：

```text
1. backup      保存当前配置与凭证快照 → config-history/<ts>-<proto>/
2. generate    生成临时配置（不落正式路径）
3. validate    协议级校验（xray: xray run -test；hysteria2: YAML 解析+字段检查）
4. test-start  可选：临时端口试运行（仅当协议支持）
5. apply       原子替换正式配置（写临时文件 → chown/chmod → mv）
6. health      服务 active + 端口监听检查
7. 成功 → 记录 config_versions；失败 → 自动恢复旧配置 + 重启 + 报告
```

禁止任何「改完直接 restart」的路径。

---

## 4. 隐蔽策略引擎（Stealth Engine）

`lib/stealth.sh` 负责按环境与模式选择方案：

| 维度 | 选项 |
| --- | --- |
| REALITY dest | 内置可信目标站清单（支持 TLS1.3+H2），按节点随机稳定选取，可自定义 |
| 伪装网站 | 内置伪装站清单，随机默认、可自定义（Hysteria2 masquerade） |
| 未授权访问响应 | REALITY：转发至 dest（借证书）；Hysteria2：masquerade 代理；可配置为自定义页面 |
| 指纹 | 默认 chrome（REALITY `fp=chrome`），可配置 |
| XHTTP 路径 | 随机生成，防固定指纹 |

原则：不堆叠无意义混淆；优先「协议本身携带的隐身能力」（REALITY/TLS/HTTP 伪装），保持性能。

---

## 5. 智能部署模式（Policy）

| 模式 | 推荐组合 | 理由 |
| --- | --- | --- |
| 安全优先（默认） | REALITY Vision + REALITY XHTTP + Hysteria2+obfs | 三层互补：TCP 高隐蔽 / XHTTP 抗封锁 / UDP 高性能；全部无需域名 |
| 速度优先 | Hysteria2+obfs + REALITY Vision | Hysteria2 UDP 吞吐极高；Vision 低开销 |
| 兼容优先 | REALITY Vision + Trojan+TLS | 客户端生态最广；Trojan 老牌兼容 |

部署入口（install.sh）：

- 一键 IP 版（单协议）：Hysteria2 / Vision / XHTTP / Trojan
- 一键 IP 全家桶：Hysteria2 + Vision + XHTTP（+ Trojan 可选）
- 一键域名版：输入域名 → Hysteria2 用 acme 正式证书；REALITY 继续借用目标站证书
- 自定义：逐项选择协议、端口、域名、伪装

所有参数（端口/UUID/密码/伪装站）默认回车随机。

---

## 6. Protocol Interface（协议层契约）

每个协议模块（`protocols/<name>.sh`）必须实现：

```bash
proto_meta_<name>_name          # 显示名
proto_meta_<name>_needs_domain  # 0/1
proto_install_<name> <domain|""> # 安装（含配置生成，走 config_manager）
proto_remove_<name>             # 卸载
proto_restart_<name>            # 重启
proto_status_<name>             # 状态
proto_health_<name>             # 健康检查（返回 0/1）
proto_validate_<name> <file>    # 配置校验
proto_links_<name>              # 输出客户端链接/配置（调 clientgen）
proto_version_<name>            # 版本
proto_config_path_<name>        # 配置文件路径
```

`protocols/interface.sh` 提供 `proto_dispatch <fn> <name>` 分发器与注册表，新协议 = 复制 `_template.sh` + 实现契约。

---

## 7. 监控与自愈（Watchdog）

`bin/zn-daemon`（systemd 服务 `zeronode-watchdog`，60s 周期）：

1. 对每个已安装协议执行 `proto_health`（systemctl active + 端口监听 + 可选 TCP/UDP 探测）。
2. 记录 `health` 表。
3. 异常 → 自动 restart（最多连续 3 次）。
4. 连续失败 ≥3 → **保护模式**：停止自动重启，ERROR 告警日志，等待人工或冷却期（30min）后重试。
5. 支持 `zn watchdog status` 查看。

---

## 8. 升级系统（Update Manager）

```text
zn upgrade <protocol> [--version vX.Y.Z]
1. 版本检测（本地 + GitHub 官方 API）
2. 备份（配置 + 凭证 + DB）
3. 执行 vendored 官方安装器（Hysteria: install_server.sh；Xray: install-release.sh [--version]）
   - 两者均内置 SHA256 校验；Xray 支持版本锁定
4. 二进制完整性复核（hysteria 对照官方 hashes.txt）
5. 健康检查
6. 失败 → 恢复备份二进制 + 配置，回滚并记录 upgrades 表
```

禁止 `curl ... | bash` 式升级；版本可锁定于 `/etc/zeronode.conf`。

---

## 9. 客户端生成与订阅（多客户端兼容）

`lib/clientgen.sh` 对每个协议输出：

- 分享链接：`vless://`、`hysteria2://`、`trojan://`（v2rayN/v2rayNG/小火箭/Stash/Loon/Karing 等通用）
- 二维码：qrencode ANSI/UTF8
- sing-box：JSON outbounds 数组
- Clash Meta：YAML（proxies + proxy-groups + rules）
- 订阅文件：`sub.txt`（纯链接列表）/ `clash.yaml` / `singbox.json`

订阅端点（默认关闭，`zn sub enable` 开启）：

```text
GET http://IP:PORT/sub?token=<TOKEN>&type=plain|clash|singbox
```

Content-Type 按 type 切换；plain 兼容 v2ray/小火箭等，clash 兼容 Clash Meta/mihomo/ClashX，singbox 兼容 sing-box/Karing。

---

## 10. Local API（管理面）

绑定 `127.0.0.1`，Bearer Token 鉴权（Token 存 `/etc/zeronode.conf`，0600）：

```text
GET  /health          # 各协议健康
GET  /status          # 节点与服务状态
GET  /protocols       # 已安装协议列表
GET  /links?type=...  # 链接/订阅（需 token）
POST /rotate/<proto>  # 轮换凭证
POST /restart/<proto>
GET  /logs?level=...  # 日志（脱敏）
```

实现：`lib/api.sh` 用 socat/python3 提供轻量 HTTP 服务；未来可替换为 Go/Python 管理端而保持端点不变（openapi.yaml 为契约）。

---

## 11. 日志系统

- 级别：DEBUG < INFO < WARN < ERROR；文件轮转（保留 7×10MB）。
- 脱敏：加载凭证清单，输出前替换；结构化 `ts|level|module|msg`。
- 操作审计：写入 `operations` 表（actor/action/target/result）。

---

## 12. Docker / 测试 / 文档

- `docker/Dockerfile`：Debian slim + bash/sqlite3/openssl/qrencode/jq + 本仓库，用于开发与 CI 测试（不用于生产节点，生产保持裸机 systemd）。
- `tests/`：shellcheck（零告警）+ `bash -n` + 函数级测试（凭证生成、config_manager 回滚、clientgen URI、协议配置生成、envcheck 报告）。
- 文档：INSTALL / UPGRADE / RECOVERY / TROUBLESHOOTING。

---

## 13. 里程碑

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| M1-M2 | 地基 + 安全核心（common/logging/db/credential/config_manager） | 本轮实现 |
| M3 | 系统层 + 环境检测（system/envcheck） | 本轮实现 |
| M4 | 策略层（stealth/policy） | 本轮实现 |
| M5 | 协议层（interface + hysteria2 + xray[Vision/XHTTP/Trojan]） | 本轮实现 |
| M6 | 客户端层（clientgen 多客户端订阅） | 本轮实现 |
| M7 | 稳定层（watchdog/update/backup） | 本轮实现 |
| M8 | 管理面（install.sh 美化 UI / bin/zn / api.sh） | 本轮实现 |
| M9 | 测试 + 文档 + Docker | 本轮实现 |
| M10 | 扩展协议：WS+TLS(CDN)、gRPC+REALITY、SS2022、TUIC | 下轮迭代 |
| M11 | Web UI + 订阅服务器独立化 + PostgreSQL 适配 | 规划 |
