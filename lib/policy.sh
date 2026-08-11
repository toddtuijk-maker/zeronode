#!/usr/bin/env bash
#
# policy.sh - 策略层：安全/速度/兼容 → 推荐协议与参数
#

# 输出推荐协议集（空格分隔），格式: hysteria2|vision|xhttp|trojan
policy_recommend(){
  local mode="${1:-security}"
  case "$mode" in
    security)
      echo "hysteria2 vision xhttp"
      ;;
    speed)
      echo "hysteria2 vision"
      ;;
    compat)
      echo "vision trojan"
      ;;
    *)
      echo "hysteria2 vision xhttp"
      ;;
  esac
}

# 模式说明
policy_describe(){
  local mode="${1:-security}"
  case "$mode" in
    security) echo "安全优先：REALITY(Vision+XHTTP) + Hysteria2+obfs，全部无需域名，隐蔽性最高" ;;
    speed)    echo "速度优先：Hysteria2+obfs(UDP 高吞吐) + REALITY Vision(低开销)" ;;
    compat)   echo "兼容优先：REALITY Vision + Trojan+TLS，客户端生态最广" ;;
    *)        echo "未知模式" ;;
  esac
}

# 为协议集分配互不冲突的随机端口
policy_allocate_ports(){
  local protos="$1"
  local -A used=()
  local p proto
  for proto in $protos; do
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      p="$(zn_random_port)"
      if [[ -z "${used[$p]:-}" ]] && ! zn_port_in_use_tcp "$p" && ! zn_port_in_use_udp "$p"; then
        used[$p]="$proto"
        break
      fi
    done
  done
  local k
  for k in "${!used[@]}"; do
    printf '%s:%s\n' "$k" "${used[$k]}"
  done
}

# 按协议取已分配端口（从 policy_allocate_ports 输出中过滤）
policy_port_of(){
  local lines="$1" proto="$2"
  echo "$lines" | grep ":${proto}$" | cut -d: -f1
}
