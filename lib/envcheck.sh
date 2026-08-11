#!/usr/bin/env bash
#
# envcheck.sh - 环境检测报告与推荐方案
#

envcheck_mem(){
  if [[ -r /proc/meminfo ]]; then
    awk '/MemTotal/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo
  else
    echo "unknown"
  fi
}

envcheck_disk(){
  df -h / 2>/dev/null | awk 'NR==2{print $4 " free / " $2 " total"}'
}

# 出站 UDP 可用性（DNS 走 UDP，能解析即视为可用；再加端口绑定测试）
envcheck_udp(){
  local bindtest
  if getent ahosts www.google.com >/dev/null 2>&1; then
    bindtest="$(timeout 2 bash -c 'exec 3<>/dev/udp/8.8.8.8/53' 2>/dev/null && echo ok || echo no)"
    if [[ "$bindtest" == "ok" ]]; then
      echo "udp:ok"
    else
      echo "udp:partial(DNS ok, raw send failed)"
    fi
  else
    echo "udp:unknown(DNS failed)"
  fi
}

envcheck_port_free(){
  local p="$1"
  if zn_port_in_use_tcp "$p" || zn_port_in_use_udp "$p"; then
    echo "in-use"
  else
    echo "free"
  fi
}

envcheck_warp(){
  local v4
  v4="$(curl -fsS4 -m 8 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep '^warp=' | cut -d= -f2 || true)"
  [[ "$v4" == "on" || "$v4" == "plus" ]] && echo "warp:on($v4)" || echo "warp:off"
}

envcheck_bbr(){
  # shellcheck source=lib/system.sh
  source "$ZN_ROOT/lib/system.sh"
  system_bbr_status
}

envcheck_time(){
  # shellcheck source=lib/system.sh
  source "$ZN_ROOT/lib/system.sh"
  system_time_status
}

envcheck_dns(){
  local r
  r="$(system_dns_check 2>/dev/null)"
  [[ -n "$r" ]] && echo "dns:ok($r)" || echo "dns:fail"
}

envcheck_systemd(){
  if [[ -d /run/systemd/system ]]; then
    echo "systemd:ok"
  else
    echo "systemd:missing"
  fi
}

envcheck_docker(){
  # shellcheck source=lib/docker.sh
  source "$ZN_ROOT/lib/docker.sh"
  local rep
  rep="$(docker_env_report | tr '\n' ' ')"
  echo "$rep"
}

envcheck_cpu(){
  local n
  n="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)"
  echo "$n cores"
}

# 完整检测报告
envcheck_run(){
  local mode="${1:-security}"
  local ipv4 ipv6 os arch kernel mem disk udp bbr dns time warp
  ipv4="$(zn_public_ipv4)"
  ipv6="$(zn_public_ipv6)"
  os="$(zn_os)"
  arch="$(zn_arch)"
  kernel="$(uname -r 2>/dev/null || echo unknown)"
  mem="$(envcheck_mem)"
  disk="$(envcheck_disk)"
  udp="$(envcheck_udp)"
  bbr="$(envcheck_bbr)"
  dns="$(envcheck_dns)"
  time="$(envcheck_time)"
  warp="$(envcheck_warp)"
  export ZN_IPV4="$ipv4" ZN_IPV6="$ipv6"

  {
    echo "==================== 环境检测报告 ===================="
    printf "%-16s %s\n" "OS:" "$os"
    printf "%-16s %s\n" "Architecture:" "$arch"
    printf "%-16s %s\n" "Kernel:" "$kernel"
    printf "%-16s %s\n" "CPU:" "$(envcheck_cpu)"
    printf "%-16s %s\n" "Memory:" "$mem"
    printf "%-16s %s\n" "Disk:" "$disk"
    printf "%-16s %s\n" "IPv4:" "${ipv4:-无}"
    printf "%-16s %s\n" "IPv6:" "${ipv6:-无}"
    printf "%-16s %s\n" "UDP:" "$udp"
    printf "%-16s %s\n" "BBR:" "$bbr"
    printf "%-16s %s\n" "DNS:" "$dns"
    printf "%-16s %s\n" "TimeSync:" "$time"
    printf "%-16s %s\n" "WARP:" "$warp"
    printf "%-16s %s\n" "Firewall:" "$(system_fw_status)"
    printf "%-16s %s\n" "Systemd:" "$(envcheck_systemd)"
    printf "%-16s %s\n" "Docker:" "$(envcheck_docker)"
    echo "------------------------------------------------------"
    printf "%-16s %s\n" "推荐方案:" "$(policy_recommend "$mode")"
    echo "======================================================"
  } | tee /dev/stderr

  # 落库节点信息
  source "$ZN_ROOT/lib/db.sh" 2>/dev/null || true
  if db_available 2>/dev/null; then
    db_init 2>/dev/null || true
    db_upsert_node 2>/dev/null || true
  fi
}

# 简易环境风险检查（部署前），有硬伤返回 1
envcheck_gate(){
  local fatal=0
  if [[ -z "$(zn_public_ipv4)" && -z "$(zn_public_ipv6)" ]]; then
    zn_log_error "envcheck" "无法获取公网 IP"
    fatal=1
  fi
  if ! envcheck_udp | grep -q "udp:ok"; then
    zn_log_warn "envcheck" "UDP 可用性存疑，Hysteria2 可能受影响"
  fi
  if envcheck_time | grep -qi "no"; then
    zn_log_warn "envcheck" "系统时间未同步，TLS 证书可能失效"
  fi
  return "$fatal"
}
