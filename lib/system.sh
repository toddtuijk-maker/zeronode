#!/usr/bin/env bash
#
# system.sh - 系统层：包管理 / 服务 / 防火墙 / BBR / 时间同步 / DNS / 网络调优
#

system_pm(){
  if command -v apt-get >/dev/null 2>&1; then echo apt
  elif command -v dnf >/dev/null 2>&1; then echo dnf
  elif command -v yum >/dev/null 2>&1; then echo yum
  elif command -v zypper >/dev/null 2>&1; then echo zypper
  elif command -v pacman >/dev/null 2>&1; then echo pacman
  elif command -v apk >/dev/null 2>&1; then echo apk
  else echo none; fi
}

# 常见包名的发行版差异映射（安装时按实际 PM 翻译）
system_pkg_name(){
  local generic="$1"
  case "$(system_pm)" in
    dnf|yum)
      case "$generic" in
        sqlite3) echo sqlite ;;
        cron)    echo cronie ;;
        iproute2) echo iproute ;;
        *)       echo "$generic" ;;
      esac
      ;;
    pacman)
      case "$generic" in
        sqlite3) echo sqlite ;;
        cron)    echo cronie ;;
        *)       echo "$generic" ;;
      esac
      ;;
    apk)
      case "$generic" in
        sqlite3) echo sqlite ;;
        socat)   echo socat ;;
        *)       echo "$generic" ;;
      esac
      ;;
    *)
      echo "$generic"
      ;;
  esac
}

system_update(){
  case "$(system_pm)" in
    apt) apt-get update >/dev/null 2>&1 || true ;;
    dnf) dnf check-update -q >/dev/null 2>&1 || true ;;
  esac
}

system_install_pkg(){
  local pkgs=("$@")
  local mapped=() p
  for p in "${pkgs[@]}"; do
    mapped+=("$(system_pkg_name "$p")")
  done
  case "$(system_pm)" in
    apt)   apt-get -y --no-install-recommends install "${mapped[@]}" ;;
    dnf)   dnf -y install "${mapped[@]}" ;;
    yum)   yum -y install "${mapped[@]}" ;;
    zypper) zypper --non-interactive install "${mapped[@]}" ;;
    pacman) pacman -S --noconfirm --needed "${mapped[@]}" ;;
    apk)   apk add --no-cache "${mapped[@]}" ;;
    *)     zn_log_error "system" "不支持的包管理器"; return 1 ;;
  esac
}

system_ensure_cmd(){
  local cmd="$1" pkg="${2:-$1}"
  command -v "$cmd" >/dev/null 2>&1 || system_install_pkg "$pkg" >/dev/null 2>&1 || true
}

system_service_active(){
  if system_has_systemd; then
    systemctl is-active "$1" >/dev/null 2>&1
  else
    # shellcheck source=lib/container.sh
    source "$ZN_ROOT/lib/container.sh"
    container_active "$1"
  fi
}

system_service_restart(){
  local unit="$1"
  shift
  if system_has_systemd; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl restart "$unit"
  else
    # shellcheck source=lib/container.sh
    source "$ZN_ROOT/lib/container.sh"
    container_restart "$unit" "$@"
  fi
}

system_service_enable(){
  local unit="$1"
  shift
  if system_has_systemd; then
    systemctl enable "$unit" >/dev/null 2>&1 || true
    systemctl start "$unit" >/dev/null 2>&1 || true
  else
    # shellcheck source=lib/container.sh
    source "$ZN_ROOT/lib/container.sh"
    container_start "$unit" "$@"
  fi
}

system_service_stop(){
  local unit="$1"
  if system_has_systemd; then
    systemctl stop "$unit" >/dev/null 2>&1 || true
    systemctl disable "$unit" >/dev/null 2>&1 || true
  else
    # shellcheck source=lib/container.sh
    source "$ZN_ROOT/lib/container.sh"
    container_stop "$unit"
  fi
}

system_has_systemd(){
  command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]
}

# ---------- 防火墙：默认拒绝 + 显式放行 ----------
system_fw_status(){
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    echo "ufw:active"
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    echo "firewalld:active"
  elif command -v nft >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1; then
    echo "nftables:active"
  else
    echo "none"
  fi
}

system_fw_allow_udp(){
  local p="$1"
  local ufw_range="$p"
  [[ "$p" == *-* ]] && ufw_range="${p/-/:}"
  case "$(system_fw_status)" in
    ufw:active)
      ufw allow "$ufw_range/udp" >/dev/null 2>&1 || true
      zn_log_info "system" "ufw 放行 $ufw_range/udp"
      ;;
    firewalld:active)
      firewall-cmd --permanent --add-port="$p/udp" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
      zn_log_info "system" "firewalld 放行 $p/udp"
      ;;
  esac
}

system_fw_allow_tcp(){
  local p="$1"
  local ufw_range="$p"
  [[ "$p" == *-* ]] && ufw_range="${p/-/:}"
  case "$(system_fw_status)" in
    ufw:active)
      ufw allow "$ufw_range/tcp" >/dev/null 2>&1 || true
      zn_log_info "system" "ufw 放行 $ufw_range/tcp"
      ;;
    firewalld:active)
      firewall-cmd --permanent --add-port="$p/tcp" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
      zn_log_info "system" "firewalld 放行 $p/tcp"
      ;;
  esac
}

# 默认拒绝入站（安全策略）。自动保留 SSH 会话端口，防止把自己锁在外面。
system_fw_default_deny(){
  # 检测当前 sshd 监听端口
  local ssh_port
  ssh_port="$(ss -tlnp 2>/dev/null | grep -i sshd | sed -E 's/.*:([0-9]+) .*/\1/' | head -1)"
  [[ -n "$ssh_port" ]] || ssh_port=22
  case "$(system_fw_status)" in
    ufw:active)
      ufw allow "$ssh_port/tcp" >/dev/null 2>&1 || true
      ufw default deny incoming >/dev/null 2>&1 || true
      zn_log_info "system" "ufw 默认拒绝入站（已保留 SSH $ssh_port/tcp）"
      ;;
    firewalld:active)
      firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1 || true
      firewall-cmd --permanent --add-port="$ssh_port/tcp" >/dev/null 2>&1 || true
      firewall-cmd --permanent --set-default-zone=drop >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
      zn_log_info "system" "firewalld 默认拒绝入站（已保留 SSH $ssh_port/tcp）"
      ;;
  esac
}

# SELinux 兼容：对已安装的 systemd 单元与二进制恢复上下文（RHEL 系）
system_selinux_fix(){
  command -v restorecon >/dev/null 2>&1 || return 0
  restorecon -R /etc/systemd/system/hysteria-server.service /etc/systemd/system/hysteria-server@.service \
    /etc/systemd/system/xray.service /usr/local/bin/hysteria /usr/local/bin/xray 2>/dev/null || true
}

# ---------- BBR ----------
system_bbr_status(){
  local algo
  algo="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  if [[ "$algo" == "bbr" ]]; then echo "bbr:on"; else echo "bbr:off($algo)"; fi
}

system_bbr_enable(){
  if system_bbr_status | grep -q "bbr:on"; then
    zn_log_info "system" "BBR 已启用"
    return 0
  fi
  modprobe tcp_bbr >/dev/null 2>&1 || true
  cat > /etc/sysctl.d/99-zeronode-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl -p /etc/sysctl.d/99-zeronode-bbr.conf >/dev/null 2>&1 || true
  zn_log_info "system" "BBR 已启用（/etc/sysctl.d/99-zeronode-bbr.conf）"
}

# ---------- 网络调优（保守） ----------
system_net_tune(){
  cat > /etc/sysctl.d/99-zeronode-net.conf <<'EOF'
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_fastopen=3
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
  sysctl -p /etc/sysctl.d/99-zeronode-net.conf >/dev/null 2>&1 || true
  zn_log_info "system" "网络参数已调优"
}

# ---------- 时间同步 ----------
system_time_status(){
  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl 2>/dev/null | grep -i "synchronized" || echo "unknown"
  else
    echo "unknown"
  fi
}

system_time_sync(){
  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-ntp true >/dev/null 2>&1 || true
  fi
  if ! system_time_status | grep -qi "yes"; then
    system_ensure_cmd chronyd chrony
    systemctl enable --now chronyd >/dev/null 2>&1 || \
    systemctl enable --now systemd-timesyncd >/dev/null 2>&1 || true
  fi
  zn_log_info "system" "时间同步已配置"
}

# ---------- DNS 检测（防污染基础检查） ----------
system_dns_check(){
  local domain="${1:-www.google.com}"
  local result
  result="$(getent ahosts "$domain" 2>/dev/null | awk 'NR==1{print $1}')"
  if [[ -n "$result" ]]; then
    zn_log_info "system" "DNS 解析 $domain -> $result"
    printf '%s' "$result"
  else
    zn_log_warn "system" "DNS 解析 $domain 失败"
    return 1
  fi
}
