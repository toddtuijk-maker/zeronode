#!/usr/bin/env bash
#
# uninstall.sh - 一键卸载（全部组件）
# 入口: 安装菜单「10. 一键卸载」 / zn uninstall / 独立 uninstall.sh
#

zn_uninstall_backup_prompt(){
  local has_data=0
  [[ -d "$ZN_STATE" ]] && has_data=1
  [[ -f /etc/hysteria/config.yaml ]] && has_data=1
  [[ -f /usr/local/etc/xray/config.json ]] && has_data=1
  [[ -f /etc/sing-box/config.json ]] && has_data=1
  [[ "$has_data" == "1" ]] || return 0
  if zn_confirm "卸载前是否先备份配置与数据？"; then
    source "$ZN_ROOT/lib/backup.sh"
    local bk
    bk="$(backup_full)"
    zn_green "备份完成: $bk"
  fi
}

zn_uninstall_all(){
  zn_require_root
  zn_confirm "确定要一键卸载全部 ZeroNode 组件吗？（协议服务、配置、程序本体、数据）" || { zn_green "已取消"; return 1; }
  zn_uninstall_backup_prompt

  source "$ZN_ROOT/lib/system.sh"
  source "$ZN_ROOT/lib/container.sh"

  local unit
  for unit in hysteria-server xray sing-box zeronode-watchdog zeronode-api zeronode-sub; do
    system_service_stop "$unit" 2>/dev/null || true
  done

  rm -f /etc/systemd/system/hysteria-server.service /etc/systemd/system/hysteria-server@.service \
        /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service \
        /etc/systemd/system/zeronode-watchdog.service /etc/systemd/system/zeronode-api.service \
        /etc/systemd/system/zeronode-sub.service
  system_has_systemd && systemctl daemon-reload >/dev/null 2>&1 || true

  rm -f /usr/local/bin/hysteria /usr/local/bin/xray /usr/local/bin/sing-box /usr/local/bin/zn
  rm -rf /etc/hysteria /usr/local/etc/xray /usr/local/share/xray /etc/sing-box /var/lib/hysteria

  # 容器模式残留 pidfile
  rm -rf "$CONTAINER_RUN_DIR" 2>/dev/null || true

  if zn_confirm "是否删除程序目录 /opt/zeronode？"; then
    rm -rf /opt/zeronode
  fi
  if zn_confirm "是否删除数据目录 $ZN_STATE（数据库/凭证/订阅/日志）？"; then
    rm -rf "$ZN_STATE"
  fi
  rm -f /etc/zeronode.conf

  zn_green "ZeroNode 已全部卸载完成"
  zn_yellow "提示: 云厂商安全组/ufw/firewalld 中手动放行的端口不会自动回收，请自行确认"
}
