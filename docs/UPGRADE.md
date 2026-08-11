# 升级文档

## 核心升级（协议二进制）

```bash
zn check hysteria2      # 检查更新
zn upgrade hysteria2    # 升级到最新
zn upgrade xray v26.3.27 # 升级到指定版本（Xray 支持版本锁定）
```

升级流程（自动）：

1. 检测当前版本与最新版本；
2. 全量备份（配置/凭证/DB/旧二进制）；
3. 执行 vendored 官方安装器（内置 SHA256 校验）；
4. 完整性复核（Hysteria2 对照官方 hashes.txt）；
5. 健康检查（服务 active + 端口监听）；
6. 任一步失败 → 自动恢复旧二进制与配置，记录升级日志。

## 版本锁定

```bash
zn pin xray v26.3.27   # 锁定版本
zn pin xray            # 解除锁定
```

## 升级 ZeroNode 本体

```bash
cd /opt/zeronode
# 拉取新版本后
cp -a /opt/zeronode /opt/zeronode.bak.$(date +%Y%m%d)
# 覆盖更新，然后执行完整性自检
zn status
```

> 升级本体前务必先 `zn backup`。
