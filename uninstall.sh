#!/usr/bin/env bash
#
# ZeroNode 一键卸载脚本（独立运行，无需先安装）
# 用法: wget -N https://raw.githubusercontent.com/toddtuijk-maker/zeronode/main/uninstall.sh && bash uninstall.sh
#
set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "需要 root 权限运行卸载"; exit 1; }

confirm(){
  local ans
  read -rp "$1 [y/N] " ans || return 1
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

echo "=============================================="
echo " ZeroNode 一键卸载"
echo " 作者频道: 零号协议 @linghaoxieyi"
echo "=============================================="

if ! confirm "确定要卸载全部 ZeroNode 组件吗？"; then
  echo "已取消"
  exit 0
fi

# 卸载前备份（有数据时）
if [[ -d /var/lib/zeronode ]] || [[ -f /etc/hysteria/config.yaml ]] \
   || [[ -f /usr/local/etc/xray/config.json ]] || [[ -f /etc/sing-box/config.json ]]; then
  if confirm "卸载前是否先备份配置与数据到 /var/lib/zeronode/backups？"; then
    if [[ -f /opt/zeronode/bin/zn ]]; then
      ZN_ROOT=/opt/zeronode bash /opt/zeronode/bin/zn backup || true
    elif command -v tar >/dev/null 2>&1; then
      mkdir -p /var/lib/zeronode/backups
      tar -czf "/var/lib/zeronode/backups/zeronode-$(date +%Y%m%d-%H%M%S).tar.gz" \
        /etc/hysteria /usr/local/etc/xray /etc/sing-box /var/lib/zeronode 2>/dev/null || true
      echo "备份完成: /var/lib/zeronode/backups/"
    fi
  fi
fi

echo "停止并移除服务 ..."
for unit in hysteria-server xray sing-box zeronode-watchdog zeronode-api zeronode-sub; do
  systemctl stop "$unit" 2>/dev/null || true
  systemctl disable "$unit" 2>/dev/null || true
done

rm -f /etc/systemd/system/hysteria-server.service /etc/systemd/system/hysteria-server@.service \
      /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service \
      /etc/systemd/system/zeronode-watchdog.service /etc/systemd/system/zeronode-api.service \
      /etc/systemd/system/zeronode-sub.service
systemctl daemon-reload 2>/dev/null || true

echo "移除二进制与配置 ..."
rm -f /usr/local/bin/hysteria /usr/local/bin/xray /usr/local/bin/sing-box /usr/local/bin/zn
rm -rf /etc/hysteria /usr/local/etc/xray /usr/local/share/xray /etc/sing-box /var/lib/hysteria
rm -f /etc/zeronode.conf

if confirm "是否删除程序目录 /opt/zeronode？"; then
  rm -rf /opt/zeronode
fi
if confirm "是否删除数据目录 /var/lib/zeronode（数据库/凭证/订阅/日志/备份）？"; then
  rm -rf /var/lib/zeronode
fi

echo "=============================================="
echo " ZeroNode 已全部卸载完成"
echo " 提示: 云厂商安全组/ufw/firewalld 手动放行的端口需自行回收"
echo "=============================================="
