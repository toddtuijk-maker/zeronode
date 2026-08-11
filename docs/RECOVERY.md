# 恢复文档

## 备份

```bash
zn backup                      # 普通备份（tar）
zn backup "你的口令"            # AES-256-CBC 加密备份
```

备份内容：协议配置与证书（`/etc/hysteria`、`/usr/local/etc/xray`）、ZeroNode 状态（SQLite、凭证库、订阅、日志）。

## 恢复

```bash
zn restore /var/lib/zeronode/backups/zeronode-xxxx.tar
zn restore /var/lib/zeronode/backups/zeronode-xxxx.tar.enc "你的口令"
```

恢复后自动重启协议服务，并修复关键文件权限（600/700）。

## 配置回滚

```bash
zn config list hysteria2        # 查看版本历史
zn config rollback hysteria2    # 回滚到最近版本
zn config rollback xray 3       # 回滚到指定版本
```

## 凭证恢复

```bash
# 单独恢复凭证库
cp /var/lib/zeronode/backups/credentials-xxxx /var/lib/zeronode/credentials
chmod 600 /var/lib/zeronode/credentials
```

## 彻底重装

```bash
zn backup
# 重新执行 install.sh，选择单协议安装即可重建
```
