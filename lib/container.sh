#!/usr/bin/env bash
#
# container.sh - 无 systemd 环境（Docker 容器）的进程守护
# 用 pidfile + 前台日志管理协议进程，兼容 SIGTERM 优雅退出
#

export CONTAINER_RUN_DIR="${CONTAINER_RUN_DIR:-$ZN_STATE/run}"

container_init(){
  mkdir -p "$CONTAINER_RUN_DIR" "$ZN_LOG_DIR"
  chmod 700 "$CONTAINER_RUN_DIR"
}

container_pidfile(){
  printf '%s/%s.pid' "$CONTAINER_RUN_DIR" "$1"
}

container_active(){
  local pidfile
  pidfile="$(container_pidfile "$1")"
  [[ -f "$pidfile" ]] || return 1
  local pid
  pid="$(cat "$pidfile" 2>/dev/null)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

container_start(){
  local name="$1"
  shift
  container_init
  if container_active "$name"; then
    zn_log_info "container" "$name 已在运行"
    return 0
  fi
  zn_log_info "container" "启动 $name: $*"
  nohup "$@" >> "$ZN_LOG_DIR/svc-$name.log" 2>&1 &
  echo $! > "$(container_pidfile "$name")"
  sleep 1
  container_active "$name"
}

container_stop(){
  local name="$1" pidfile pid
  pidfile="$(container_pidfile "$name")"
  if [[ -f "$pidfile" ]]; then
    pid="$(cat "$pidfile" 2>/dev/null)"
    if [[ -n "$pid" ]]; then
      kill -TERM "$pid" 2>/dev/null || true
      for _ in 1 2 3 4 5; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
      done
      kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -f "$pidfile"
  fi
  zn_log_info "container" "$name 已停止"
}

container_restart(){
  local name="$1"
  shift
  container_stop "$name"
  container_start "$name" "$@"
}

# 前台监督模式：启动所有已安装协议并等待信号（Docker ENTRYPOINT 使用）
container_supervise(){
  local proto cmd
  source "$ZN_ROOT/protocols/interface.sh"
  trap 'container_shutdown' TERM INT
  for proto in $ZN_PROTOCOLS; do
    if proto_installed "$proto" 2>/dev/null; then
      cmd="$(proto_meta "$proto" run_cmd 2>/dev/null)"
      if [[ -n "$cmd" ]]; then
        # 直接前台执行：由本循环监督，异常退出由外层重启
        ( exec bash -c "$cmd" >> "$ZN_LOG_DIR/svc-$proto.log" 2>&1 ) &
        echo $! > "$(container_pidfile "$proto")"
        zn_log_info "container" "监督 $proto: $cmd"
      fi
    fi
  done
  while true; do
    sleep 10
  done
}

container_shutdown(){
  zn_log_info "container" "收到退出信号，正在停止全部协议 ..."
  local proto
  for proto in $ZN_PROTOCOLS; do
    container_stop "$proto" 2>/dev/null || true
  done
  exit 0
}
