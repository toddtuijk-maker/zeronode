# Changelog

## v1.0.4 (2026-08-12)

### 修复

- **健康检查端口检测依赖 `ss`（iproute2）**：部分精简 VPS 未安装 iproute2 导致所有协议“健康检查失败→回滚→部署失败”。端口检测改为多手段回退（`ss` → `netstat` → 解析 `/proc/net/{tcp,udp}`），安装时自动补装 iproute2。
- 健康检查/配置回滚失败时，日志会附上 systemd 状态、`journalctl` 最近日志与监听状态，便于直接定位真实原因。

## v1.0.3 (2026-08-12)

### 修复

- **Hysteria2 配置校验误报失败（导致安装中断）**：原校验依赖 `python3 -c "import yaml"`，但 Debian 默认不带 PyYAML 模块，导致所有 Hysteria2 安装在校验阶段被拒。已改为纯 shell 校验（必填字段 + 制表符检查），不再依赖任何 Python 模块。
- 部署时用户输入的 UUID/密码/obfs 密码增加格式校验（非法会重新提示，不再写入坏配置）。

## v1.0.2 (2026-08-12)

### 新增

- **一键卸载**：安装菜单新增「10. 一键卸载」；`zn uninstall` 命令；独立 `uninstall.sh`（`wget .../uninstall.sh && bash uninstall.sh` 即可，无需先安装）。卸载前可选备份，逐项确认删除程序/数据目录。

### 修复与加固

- 任何安装/管理步骤失败时，明确提示脚本行号并展示最近日志，不再“静默退出”；
- 安装依赖前自动刷新软件源（`apt-get update`），避免新系统 apt 列表缺失导致装不上 sqlite3 等依赖而中断；
- 数据库初始化失败不再中断安装（降级继续）；
- 菜单内部署失败返回主菜单而不是直接退出脚本。

## v1.0.1 (2026-08-12)

### 修复

- **一键安装单文件模式失效**：`wget install.sh && bash install.sh` 之前只会下载单个文件，旧引导逻辑误将当前目录（如 `/root`）整体拷贝到 `/opt/zeronode` 导致缺文件报错；现在单文件模式会自动从仓库拉取完整组件、校验结构与语法后再安装。
- **整目录拷贝安全隐患**：修复前 `cp -a <当前目录>/. /opt/zeronode/` 可能把用户目录中的 `.ssh`、`.bash_history` 等无关内容一并拷贝；现在只拷贝项目白名单文件（install.sh/bin/lib/protocols/vendor/docs/tests/docker/api/.github 等）。
- 支持 fork 仓库：`export ZN_REPO_URL=https://github.com/<账号>/zeronode` 后安装。

## v1.0.0 (2026-08-11)

首个正式版，基于 flame1ce/hysteria2-install 全量重构为多协议节点管理平台。

### 协议与内核

- Hysteria 2 + TLS + obfs(salamander)（官方原生内核）
- VLESS + REALITY + XTLS Vision / VLESS + REALITY + XHTTP / Trojan + TLS
- 服务端内核可选：默认 **sing-box**，备选 Xray（`ZN_KERNEL` / 菜单 9 切换）
- 协议插件化：`protocols/_template.sh.example` 即插即用

### 架构

- 六层架构：用户层（CLI/API/Web 规划）/ 管理层 / 策略层 / 协议层 / 系统层 / 监控层
- SQLite 数据层（节点/协议/用户/配置版本/操作审计/健康/升级记录）
- Protocol Interface 统一契约（install/remove/restart/status/health/validate/links/rotate/version）

### 安全

- 凭证库 0600 + 日志脱敏 + 轮换/撤销/加密备份
- 配置变更强制「备份→临时配置→校验→原子应用→健康检查→失败自动回滚」
- vendored 官方安装器（Hysteria/Xray/sing-box）+ SHA256 复核 + 版本锁定
- 管理 API 默认 127.0.0.1 + Token；订阅端点默认关闭
- 防火墙默认拒绝（自动保留 SSH）；SELinux restorecon；完整性自检

### 稳定

- Watchdog 自愈（连续失败 3 次进入保护模式）
- 配置版本历史与回滚（`zn config list/rollback`）
- 升级自动备份/验证/回滚（`zn upgrade` / `zn pin`）
- 全量备份与恢复（可选 AES-256 加密）

### 客户端

- 分享链接（vless:// hysteria2:// trojan://）+ 二维码
- sing-box JSON / Clash Meta YAML / 纯文本订阅
- 兼容 v2rayN/v2rayNG/小火箭/Stash/Loon/Karing/Clash Meta/sing-box
- Token 鉴权订阅端点（`zn sub enable`）

### 系统兼容

- Debian/Ubuntu/CentOS/Alma/Rocky/Fedora/Amazon Linux/openSUSE/Arch
- 包名按发行版自动映射；RHEL 系 SELinux 自动处理
- Docker：自动识别容器、探测可出网(已映射)端口、无 systemd 进程守护、生产镜像

### 质量

- 88 项自动化测试全通过；shellcheck 零告警；bash -n 全过
