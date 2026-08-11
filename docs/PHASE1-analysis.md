# Phase 1：现有项目分析与重构方案

> 项目：ZeroNode（零号节点管理平台，基于 flame1ce/hysteria2-install 重构）
> 阶段：第一阶段 · 分析现有项目 / 输出架构问题、安全问题、重构方案

---

## 1. 现状盘点

被重构对象是单脚本项目 `hysteria2-install`（2023-09 停更，33 个提交全部集中在同一天），核心资产：

- `hysteria.sh`：Hysteria 2 一键安装/卸载/改配置的交互菜单（约 600 行）
- `install_server.sh`：apernet 官方 Hysteria 安装器（运行时从第三方仓库拉取执行）
- `sing-hy2.json`：残留的硬编码第三方节点客户端配置（已在前一轮二开中删除）
- `README.md`：安装说明

此前的二开版本已经修复了原版的安全缺陷（私钥 777、iptables 全局清空、heredoc 注入、弱密码、供应链投毒面等），
但**项目形态仍然是「单协议脚本」**，无法支撑用户提出的多协议、可扩展、商业级管理平台目标。

---

## 2. 架构问题（Architecture Issues）

| 编号 | 问题 | 影响 |
| --- | --- | --- |
| A1 | **单协议绑定**：所有逻辑内聚在一个脚本里，Hysteria 2 的证书、端口、伪装网站、服务管理与安装流程耦合 | 无法复用；新增 VLESS/REALITY/Trojan 只能复制粘贴 |
| A2 | **无分层**：没有用户层/管理层/策略层/协议层/系统层/监控层的概念 | 职责不分，改一处影响全局，无法独立测试 |
| A3 | **无统一协议接口**：没有定义「安装/卸载/校验/健康检查/生成链接」的标准契约 | 每种协议一套私有写法，扩展成本随协议数线性增长 |
| A4 | **无配置版本管理**：配置修改 = 直接 sed 替换 + restart | 改错即炸，无回滚能力 |
| A5 | **无状态持久化**：节点、用户、凭证、操作记录散落在内存变量和零散文件 | 无法审计、无法恢复、无法管理多用户 |
| A6 | **无监控/自愈**：服务挂了只能靠用户手动发现 | 违背稳定运行优先目标 |
| A7 | **无升级体系**：原版不提供核心升级；二开版虽提供，但缺少版本锁定与失败回滚 | 无法保证版本可控、升级失败可恢复 |
| A8 | **无客户端生态**：只输出 IP/端口/密码与单个分享链接 | 不满足多客户端订阅（v2ray/Clash/小火箭）需求 |
| A9 | **无环境适配**：固定流程，不做系统检测与推荐 | 用户在弱鸡 VPS/无 BBR/防火墙未放行等场景反复踩坑 |
| A10 | **无管理面**：只有交互菜单，无 CLI 子命令、无 API、无 Web UI | 无法自动化、无法集成监控/告警 |

---

## 3. 安全问题（Security Issues）

| 编号 | 问题 | 现状（重构前） | 目标 |
| --- | --- | --- | --- |
| S1 | 服务运行身份 | Hysteria 官方安装器以 `hysteria` 用户运行；但脚本自身管理操作全部 root | 所有服务独立低权限用户；管理命令仅在必要时提权 |
| S2 | 敏感信息存储 | 密码/私钥落在 `/root/hy`、`/etc/hysteria`，依赖文件权限 | 统一 Credential Manager，600 权限，日志脱敏，备份可加密 |
| S3 | 配置变更安全 | 无备份、无校验、无回滚 | 强制「备份→临时配置→语法校验→启动测试→健康检查→失败回滚」 |
| S4 | 管理面暴露 | 无管理面（原版）；若后续加 Web/API 易直接暴露公网 | 管理 API 默认绑定 127.0.0.1 + Token 鉴权 |
| S5 | 防火墙 | 依赖云厂商安全组；本机防火墙无默认策略 | 防火墙默认拒绝 + 仅放行所选端口（可开关） |
| S6 | 供应链 | 运行时下载第三方脚本/二进制 | 官方安装器 vendored + SHA256 校验 + 版本锁定 |
| S7 | 凭证轮换 | 无 | 支持 UUID/密码/私钥轮换与撤销 |
| S8 | 日志泄露 | 无结构化日志 | 分级日志 + 自动脱敏 + 自动清理 |

---

## 4. 重构方案（Refactor Plan）

### 4.1 总体策略

保留 Bash 作为部署/管理核心（VPS 环境零依赖、`wget | bash` 简单安装不变），
但按软件工程标准分层、模块化、插件化重写；数据层用 SQLite；未来可平滑替换为 Go/Python 实现的管理端。

### 4.2 分层架构

```text
用户层      Web UI（规划）   CLI (bin/zn)   Local API (127.0.0.1)
              │                 │                │
管理层      Node Manager · Config Manager · Credential Manager
             Update Manager · Backup Manager · Log Manager
              │                 │                │
策略层      Security Policy · Stealth Policy · Performance Policy
              │                 │
协议层      Protocol Interface（插件式）
             hysteria2 | xray(vless+reality+vision/xhttp) | trojan | 未来: ss2022/tuic/ws
              │                 │
系统层      OS 检测 · 包管理 · systemd · 防火墙 · BBR · DNS · 时间同步 · 网络调优
              │                 │
监控层      Watchdog · 健康检查 · 端口监听 · 延迟 · 资源 · 自愈 · 保护模式
```

### 4.3 迁移步骤（对应第三~五阶段）

1. **M1 地基**：`lib/common.sh`（框架/日志/脱敏）、`lib/db.sh`（SQLite 数据层）、目录与文档骨架。
2. **M2 安全核心**：`lib/credential.sh`、`lib/config_manager.sh`（备份/校验/回滚）。
3. **M3 系统层**：`lib/system.sh`、`lib/envcheck.sh`（环境检测报告与推荐）。
4. **M4 策略层**：`lib/stealth.sh`、`lib/policy.sh`（安全/速度/兼容模式）。
5. **M5 协议层**：`protocols/interface.sh` 契约 + `hysteria2.sh` + `xray.sh`（Vision/XHTTP/Trojan）。
6. **M6 客户端层**：`lib/clientgen.sh`（URI/QR/sing-box/Clash Meta/订阅，多客户端兼容）。
7. **M7 稳定层**：`lib/watchdog.sh`、`lib/update.sh`、`lib/backup.sh`。
8. **M8 管理面**：`bin/zn` CLI、`lib/api.sh`（localhost API + 订阅端点）、UI 美化入口 `install.sh`。
9. **M9 测试与文档**：tests/ 自动化测试、INSTALL/UPGRADE/RECOVERY/TROUBLESHOOTING、Docker 支持。

### 4.4 协议扩展矩阵（新增协议组合规划）

| 协议组合 | 内核 | 是否需域名 | 隐蔽性 | 性能 | 客户端生态 | 阶段 |
| --- | --- | --- | --- | --- | --- | --- |
| VLESS + REALITY + XTLS Vision | Xray | 否（借用目标站证书） | 高 | 高 | 广 | 本轮实现 |
| VLESS + REALITY + XHTTP | Xray | 否 | 高 | 中高（抗封锁较好） | 中（新客户端） | 本轮实现 |
| Hysteria 2 + TLS + obfs(salamander) | Hysteria2 | 否（自签） | 中高 | 极高（UDP） | 广 | 本轮实现 |
| Trojan + TLS（自签/正式证书） | Xray | 可选 | 中 | 中高 | 极广（老牌） | 本轮实现 |
| Trojan + WS + TLS（CDN） | Xray | 是 | 中（CDN 隐藏） | 中 | 极广 | 规划（M5.2） |
| VLESS + WS + TLS（CDN） | Xray | 是 | 中 | 中 | 极广 | 规划（M5.2） |
| VLESS + gRPC + REALITY | Xray | 否 | 高 | 中 | 中 | 规划 |
| Shadowsocks 2022（AEAD） | Xray/sing-box | 否 | 低 | 高 | 极广 | 规划（M5.3） |
| TUIC v5 | TUIC | 否（自签） | 中 | 高（UDP） | 中 | 规划（M5.3） |
| VLESS + XHTTP + TLS（CDN） | Xray | 是 | 中高 | 中高 | 中 | 规划 |

> 选型原则：优先「无域名可用 + 高隐蔽 + 客户端生态好」的组合；CDN 类组合（WS/XHTTP+TLS）作为特殊场景（被封 IP 后的逃生通道）提供。

---

## 5. 结论

现有项目无法通过「继续打补丁」达到商业级目标，必须按上述分层架构重写。
Phase 2 将输出完整的架构设计（模块契约、数据库 Schema、API 设计、部署模式、Stealth/Watchdog/升级设计），
Phase 3 起按 M1→M9 顺序逐模块实现并测试。
