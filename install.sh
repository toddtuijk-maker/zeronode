#!/usr/bin/env bash
#
# ZeroNode 一键安装入口（零号节点管理平台）
# 作者频道: 零号协议 @linghaoxieyi
#

export ZN_ROOT="${ZN_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"

# ---------- 自安装到 /opt/zeronode ----------
if [[ "$ZN_ROOT" != "/opt/zeronode" ]]; then
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "需要 root 权限运行安装"
    exit 1
  fi
  mkdir -p /opt/zeronode
  cp -a "$ZN_ROOT"/. /opt/zeronode/
  chmod +x /opt/zeronode/install.sh /opt/zeronode/bin/zn /opt/zeronode/bin/zn-daemon
  ln -sf /opt/zeronode/bin/zn /usr/local/bin/zn
  exec env ZN_ROOT=/opt/zeronode bash /opt/zeronode/install.sh "$@"
fi

export ZN_STATE="${ZN_STATE:-/var/lib/zeronode}"
source "$ZN_ROOT/lib/common.sh"
source "$ZN_ROOT/lib/logging.sh"
source "$ZN_ROOT/lib/credential.sh"
source "$ZN_ROOT/lib/db.sh"
source "$ZN_ROOT/lib/ui.sh"
source "$ZN_ROOT/lib/policy.sh"

[[ "$(id -u)" -eq 0 ]] || zn_die "需要 root 权限运行"
zn_state_init
cred_init
db_init
zn_log_rotate

# 兼容常见 Linux：包名按发行版映射（sqlite3→sqlite on RHEL 系等）
for c in curl openssl sqlite3 qrencode socat; do
  zn_need_cmd_or_install "$c" "$c"
done

# systemd 前置检查（Hysteria/Xray 官方安装器均要求 systemd）
if [[ ! -d /run/systemd/system ]] && [[ -z "${ZN_FORCE_NO_SYSTEMD:-}" ]]; then
  # shellcheck source=lib/docker.sh
  source "$ZN_ROOT/lib/docker.sh"
  if docker_detect; then
    zn_yellow "检测到 Docker 容器环境：将以容器模式运行（进程守护代替 systemd，自动探测可出网端口）。"
  else
    zn_red "检测到非 systemd 系统（如 Alpine/OpenRC 容器）。"
    zn_red "Hysteria2 / Xray 需要 systemd 管理服务，建议使用 Debian/Ubuntu/CentOS/Alma/Rocky/Fedora。"
    exit 1
  fi
fi

# 安装 Watchdog 服务（自愈）
install_watchdog_service(){
  source "$ZN_ROOT/lib/system.sh"
  if ! system_has_systemd; then
    nohup "$ZN_ROOT/bin/zn-daemon" watchdog 60 >> "$ZN_LOG_DIR/watchdog.log" 2>&1 &
    zn_log_info "install" "Watchdog 自愈已启动（容器后台模式，PID $!）"
    return 0
  fi
  cat > /etc/systemd/system/zeronode-watchdog.service <<EOF
[Unit]
Description=ZeroNode Watchdog
After=network.target

[Service]
Type=simple
ExecStart=$ZN_ROOT/bin/zn-daemon watchdog 60
Environment=ZN_ROOT=$ZN_ROOT
Restart=always
RestartSec=30
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now zeronode-watchdog >/dev/null 2>&1 || true
  zn_log_info "install" "Watchdog 自愈服务已启用"
}

deploy_flow(){
  local mode="$1" scope="$2" domain="${3:-}"
  source "$ZN_ROOT/lib/deploy.sh"
  if deploy_run "$mode" "$scope" "$domain"; then
    # 安全策略：防火墙默认拒绝（自动保留 SSH）
    source "$ZN_ROOT/lib/system.sh"
    system_fw_default_deny
    system_selinux_fix
    install_watchdog_service
    ui_show_links
    zn_yellow "管理命令: zn status | zn links | zn rotate <proto> | zn backup"
  else
    zn_log_error "install" "部署失败，请查看日志: zn logs 50"
    return 1
  fi
}

menu_single(){
  ui_title "选择要安装的协议（IP 一键，无需域名）"
  ui_item "1" "Hysteria 2 + TLS + obfs"
  ui_item "2" "VLESS + REALITY + XTLS Vision"
  ui_item "3" "VLESS + REALITY + XHTTP"
  ui_item "4" "Trojan + TLS"
  ui_item "0" "返回"
  local ans
  read -rp "请输入选项: " ans || return 1
  case "$ans" in
    1) deploy_flow security hysteria2 ;;
    2) deploy_flow security vision ;;
    3) deploy_flow security xhttp ;;
    4) deploy_flow compat trojan ;;
    *) return 0 ;;
  esac
}

choose_kernel(){
  ui_title "选择 VLESS 内核"
  ui_item "1" "sing-box（推荐：统一生态、配置简洁）"
  ui_item "2" "Xray（备选：生态成熟）"
  ui_item "0" "返回"
  local ans
  read -rp "请输入选项: " ans || return 1
  case "$ans" in
    1) cred_set deploy.kernel singbox; zn_green "已切换内核: sing-box（推荐）" ;;
    2) cred_set deploy.kernel xray; zn_green "已切换内核: Xray" ;;
    *) return 0 ;;
  esac
}

menu(){
  while true; do
    clear
    ui_banner
    ui_title "主菜单"
    ui_item "1" "一键部署 · 安全优先（IP 全家桶: Hysteria2 + Vision + XHTTP）"
    ui_item "2" "一键部署 · 域名版（输入域名，Hysteria2 申请正式证书）"
    ui_item "3" "一键部署 · 速度优先（Hysteria2 + Vision）"
    ui_item "4" "一键部署 · 兼容优先（Vision + Trojan）"
    ui_item "5" "单协议安装（IP 一键）"
    ui_item "6" "显示全部链接 / 二维码 / 订阅"
    ui_item "7" "环境检测报告"
    ui_item "8" "管理入口（配置回滚 / 轮换 / 备份 / 升级 / API）"
    ui_item "9" "切换 VLESS 内核（当前: $(cred_get deploy.kernel 2>/dev/null || echo singbox)）"
    ui_item "0" "退出"
    ui_hr
    local ans
    read -rp "请输入选项 [0-9]: " ans || exit 1
    case "$ans" in
      1) deploy_flow security batch ;;
      2)
        local domain
        read -rp "请输入你的域名（用于 Hysteria2 正式证书）: " domain || continue
        if zn_valid_domain "$domain"; then
          deploy_flow security batch "$domain"
        else
          zn_red "域名格式不正确"
        fi
        ;;
      3) deploy_flow speed batch ;;
      4) deploy_flow compat batch ;;
      5) menu_single ;;
      6) ui_show_links ;;
      7) source "$ZN_ROOT/lib/envcheck.sh"; envcheck_run security ;;
      8) zn_yellow "请使用命令: zn help（例如 zn status / zn config rollback / zn rotate / zn backup / zn upgrade / zn api install）";;
      9) choose_kernel ;;
      0) exit 0 ;;
      *) zn_red "无效选项" ;;
    esac
    echo ""
    read -rp "按回车返回主菜单..." _
  done
}

menu
