#!/usr/bin/env bash
#
# watchdog.sh - 监控与自愈
# 周期健康检查；异常自动重启；连续失败进入保护模式（停止自愈，等待冷却）
#

export ZN_WATCHDOG_MAX_FAILS="${ZN_WATCHDOG_MAX_FAILS:-3}"
export ZN_WATCHDOG_COOLDOWN="${ZN_WATCHDOG_COOLDOWN:-1800}"   # 保护模式冷却秒数

watchdog_check_proto(){
  local proto="$1"
  source "$ZN_ROOT/protocols/interface.sh"
  proto_load "$proto" 2>/dev/null || return 0
  local fails t0 t1 ms
  fails="$(cred_get "watchdog.$proto.fails" 2>/dev/null || echo 0)"
  t0="$(date +%s)"
  if proto_dispatch health "$proto" >/dev/null 2>&1; then
    t1="$(date +%s)"
    ms="$(( (t1 - t0) * 1000 ))"
    cred_set "watchdog.$proto.fails" "0"
    zn_log_info "watchdog" "$proto 健康 (${ms}ms)"
    source "$ZN_ROOT/lib/db.sh" 2>/dev/null || true
    db_available 2>/dev/null && db_record_health "$proto" 1 "$ms" "" 2>/dev/null || true
    return 0
  fi

  fails=$((fails + 1))
  cred_set "watchdog.$proto.fails" "$fails"
  if (( fails >= ZN_WATCHDOG_MAX_FAILS )); then
    zn_log_error "watchdog" "$proto 连续失败 ${fails} 次，进入保护模式（冷却 ${ZN_WATCHDOG_COOLDOWN}s）"
    cred_set "watchdog.$proto.cooldown_until" "$(( $(date +%s) + ZN_WATCHDOG_COOLDOWN ))"
    source "$ZN_ROOT/lib/db.sh" 2>/dev/null || true
    db_available 2>/dev/null && db_record_health "$proto" 0 "" "protection-mode" 2>/dev/null || true
    return 1
  fi
  zn_log_warn "watchdog" "$proto 异常，自动重启 (第 ${fails} 次)"
  proto_dispatch restart "$proto" >/dev/null 2>&1 || true
  source "$ZN_ROOT/lib/db.sh" 2>/dev/null || true
  db_available 2>/dev/null && db_record_health "$proto" 0 "" "restarted" 2>/dev/null || true
  return 1
}

watchdog_check_all(){
  local proto
  source "$ZN_ROOT/protocols/interface.sh"
  for proto in $ZN_PROTOCOLS; do
    proto_installed "$proto" 2>/dev/null || continue
    # 保护模式冷却中则跳过
    local until
    until="$(cred_get "watchdog.$proto.cooldown_until" 2>/dev/null || echo 0)"
    if (( $(date +%s) < until )); then
      zn_log_warn "watchdog" "$proto 处于保护模式冷却中，跳过自愈"
      continue
    fi
    watchdog_check_proto "$proto"
  done
}

watchdog_loop(){
  local interval="${1:-60}"
  zn_log_info "watchdog" "Watchdog 启动，周期 ${interval}s"
  while true; do
    watchdog_check_all
    sleep "$interval"
  done
}

watchdog_status(){
  local proto
  source "$ZN_ROOT/protocols/interface.sh"
  for proto in $ZN_PROTOCOLS; do
    local fails until
    fails="$(cred_get "watchdog.$proto.fails" 2>/dev/null || echo 0)"
    until="$(cred_get "watchdog.$proto.cooldown_until" 2>/dev/null || echo 0)"
    printf '%-12s fails=%-2s cooldown_until=%s\n' "$proto" "$fails" "$until"
  done
}
