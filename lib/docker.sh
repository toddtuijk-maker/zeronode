#!/usr/bin/env bash
#
# docker.sh - Docker 环境适配层
# 功能: 容器检测 / 网络模式识别 / 可出网(已映射)端口探测 / 端口发现
#

docker_detect(){
  [[ -f /.dockerenv ]] && return 0
  grep -qaE 'docker|kubepods|containerd' /proc/1/cgroup 2>/dev/null && return 0
  grep -q '/docker/' /proc/self/mountinfo 2>/dev/null && return 0
  return 1
}

docker_net_mode(){
  docker_detect || { echo "not-docker"; return 0; }
  local ip local_ips
  ip="$(zn_public_ipv4)"
  local_ips="$(ip -4 addr show 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}')"
  if [[ -n "$ip" ]] && echo "$local_ips" | grep -qx "$ip"; then
    echo "host"
  else
    echo "bridge"
  fi
}

docker_gateway(){
  ip route 2>/dev/null | awk '/default/{print $3; exit}'
}

# 探测某个 TCP 端口从外部（宿主机映射/公网）是否可达
# 原理: 容器内监听 0.0.0.0:port，再从容器内连接 公网IP:port 与 网关IP:port
# 任一成功即视为「可出网/已映射」；无 socat/nc 时返回 unknown
docker_probe_tcp(){
  local port="$1"
  local listener=""
  if command -v socat >/dev/null 2>&1; then
    socat "TCP-LISTEN:$port,bind=0.0.0.0,reuseaddr" - >> "$ZN_LOG_DIR/probe.log" 2>&1 &
    listener=$!
  elif command -v nc >/dev/null 2>&1; then
    nc -l -p "$port" >> "$ZN_LOG_DIR/probe.log" 2>&1 &
    listener=$!
  else
    echo "unknown"
    return 0
  fi
  sleep 0.3
  local ip gw ok=1
  ip="$(zn_public_ipv4)"
  gw="$(docker_gateway)"
  local target
  for target in "$ip" "$gw"; do
    if [[ -n "$target" ]] && timeout 1.5 bash -c "exec 3<>/dev/tcp/$target/$port" 2>/dev/null; then
      ok=0
      break
    fi
  done
  kill "$listener" 2>/dev/null || true
  wait "$listener" 2>/dev/null || true
  [[ $ok -eq 0 ]] && echo "reachable" || echo "blocked"
}

# 自动发现 N 个可出网 TCP 端口（探测有限随机候选，找不到则退回随机端口并告警）
docker_discover_tcp_ports(){
  local n="${1:-3}" tries="${2:-20}"
  local found=() tried=() port i
  for ((i = 0; i < tries && ${#found[@]} < n; i++)); do
    port="$(shuf -i 10000-65535 -n 1 2>/dev/null || echo $((10000 + RANDOM % 55535)))"
    # 跳过已尝试端口
    if [[ " ${tried[*]} " == *" $port "* ]]; then continue; fi
    tried+=("$port")
    if [[ "$(docker_probe_tcp "$port")" == "reachable" ]]; then
      found+=("$port")
    fi
  done
  if [[ ${#found[@]} -eq 0 ]]; then
    zn_log_warn "docker" "未发现已映射/可达端口，退回随机端口（请确认 docker run 已用 -p 映射或 --network host）"
    for ((i = 0; i < n; i++)); do
      echo "$(shuf -i 2000-65535 -n 1 2>/dev/null || echo $((2000 + RANDOM % 60000)))"
    done
  else
    printf '%s\n' "${found[@]}"
  fi
}

docker_env_report(){
  docker_detect || { echo "docker:no"; return 0; }
  echo "docker:yes"
  echo "net-mode:$(docker_net_mode)"
  echo "gateway:$(docker_gateway)"
}
