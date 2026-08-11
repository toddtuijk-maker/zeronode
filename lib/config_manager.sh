#!/usr/bin/env bash
#
# config_manager.sh - 配置管理器（安全核心）
# 强制流程: 备份 → 生成临时配置 → 校验 → 原子应用 → 重启 → 健康检查 → 失败自动回滚
#

# shellcheck source=protocols/interface.sh
source "$ZN_ROOT/protocols/interface.sh"

cm_current_version(){
  local proto="$1"
  source "$ZN_ROOT/protocols/interface.sh"
  proto_dispatch config_path "$proto"
}

cm_checksum(){
  sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

_cm_restart(){
  local proto="$1" unit run
  source "$ZN_ROOT/lib/system.sh"
  unit="$(proto_meta "$proto" systemd_unit)"
  run="$(proto_meta "$proto" run_cmd 2>/dev/null)"
  if [[ -n "$run" ]]; then
    system_service_restart "$unit" $run
  else
    system_service_restart "$unit"
  fi
}

# 备份当前配置到 config-history/<ts>-<proto>/；返回备份路径
cm_backup(){
  local proto="$1" cfg
  cfg="$(cm_current_version "$proto")"
  [[ -n "$cfg" && -f "$cfg" ]] || return 0
  local dir
  dir="$ZN_HISTORY_DIR/$(date +%Y%m%d-%H%M%S)-$proto"
  mkdir -p "$dir"
  cp -a "$cfg" "$dir/config" 2>/dev/null
  # 同时备份该协议依赖的证书/私钥（如果位于 /etc 下）
  local dep
  for dep in $(proto_dispatch deps "$proto" 2>/dev/null); do
    [[ -f "$dep" ]] && cp -a "$dep" "$dir/$(basename "$dep")" 2>/dev/null || true
  done
  chmod 700 "$dir"
  printf '%s' "$dir"
}

# 应用新配置（newfile 必须是已生成的临时文件）
cm_apply(){
  local proto="$1" newfile="$2" reason="${3:-update}"
  local cfg restarter health_checker backup_dir tmp_target
  cfg="$(cm_current_version "$proto")"
  [[ -n "$cfg" ]] || zn_die "协议 $proto 未定义配置路径"
  [[ -f "$newfile" ]] || zn_die "临时配置不存在: $newfile"

  zn_log_info "config" "应用 $proto 配置（原因: $reason）"
  backup_dir="$(cm_backup "$proto")"

  # 1. 校验
  if ! proto_dispatch validate "$proto" "$newfile"; then
    zn_log_error "config" "$proto 配置校验失败，拒绝应用"
    return 1
  fi

  # 2. 原子替换（先写同目录临时文件再 mv）
  tmp_target="$(dirname "$cfg")/.$(basename "$cfg").new.$$"
  cp -a "$newfile" "$tmp_target"
  chmod "$(proto_meta "$proto" config_perms 2>/dev/null || echo 644)" "$tmp_target"
  local owner
  owner="$(proto_meta "$proto" config_owner 2>/dev/null || echo root:root)"
  chown "$owner" "$tmp_target" 2>/dev/null || true
  mv -f "$tmp_target" "$cfg"

  # 3. 重启 + 健康检查
  restarter="proto_restart_${proto}"
  health_checker="proto_health_${proto}"
  if [[ "$(type -t "$restarter")" == "function" ]]; then
    "$restarter" || true
  else
    _cm_restart "$proto" >/dev/null 2>&1 || true
  fi
  sleep 2

  if [[ "$(type -t "$health_checker")" == "function" ]]; then
    "$health_checker"
  else
    systemctl is-active "$(proto_meta "$proto" systemd_unit)" >/dev/null 2>&1
  fi

  if [[ $? -ne 0 ]]; then
    zn_log_error "config" "$proto 健康检查失败，自动回滚"
    zn_log_error "config" "$proto 最近日志:"
    journalctl -u "$(proto_meta "$proto" systemd_unit)" -n 20 --no-pager 2>/dev/null | tail -n 20 || true
    zn_log_error "config" "$proto 监听状态: $(ss -tunlp 2>/dev/null | head -n 8 | tr '\n' ' ' || true)"
    if [[ -n "$backup_dir" && -f "$backup_dir/config" ]]; then
      cp -a "$backup_dir/config" "$cfg"
      if [[ "$(type -t "$restarter")" == "function" ]]; then
        "$restarter" || true
      else
        _cm_restart "$proto" >/dev/null 2>&1 || true
      fi
      sleep 2
    fi
    return 1
  fi

  # 4. 记录版本
  if [[ -f "$ZN_DB_FILE" ]]; then
    source "$ZN_ROOT/lib/db.sh" 2>/dev/null || true
    if db_available 2>/dev/null; then
      local ver
      ver="$(db_scalar "SELECT COALESCE(MAX(version),0)+1 FROM config_versions WHERE protocol='$proto'")"
      db_insert config_versions "protocol='$proto',version=$ver,checksum='$(cm_checksum "$cfg")',backup_path='$backup_dir',reason='$reason',applied=1"
    fi
  fi
  zn_log_info "config" "$proto 配置应用成功 (checksum $(cm_checksum "$cfg"))"
  return 0
}

cm_list(){
  local proto="$1"
  source "$ZN_ROOT/lib/db.sh" 2>/dev/null || true
  if db_available 2>/dev/null; then
    db_rows "SELECT version, created_at, reason, checksum FROM config_versions WHERE protocol='$proto' ORDER BY version DESC"
  else
    ls -1dt "$ZN_HISTORY_DIR/"*"-$proto" 2>/dev/null || true
  fi
}

cm_rollback(){
  local proto="$1" target_ver="${2:-}"
  local cfg backup_dir
  cfg="$(cm_current_version "$proto")"
  source "$ZN_ROOT/lib/db.sh" 2>/dev/null || true

  if [[ -z "$target_ver" ]]; then
    # 默认回滚到最近一次备份目录（config-history 时间序）
    backup_dir="$(ls -1dt "$ZN_HISTORY_DIR/"*"-$proto" 2>/dev/null | head -1)"
  else
    if db_available 2>/dev/null; then
      backup_dir="$(db_scalar "SELECT backup_path FROM config_versions WHERE protocol='$proto' AND version=$target_ver")"
    fi
    [[ -n "$backup_dir" ]] || backup_dir="$(ls -1dt "$ZN_HISTORY_DIR/"*"-$proto" 2>/dev/null | sed -n "${target_ver}p")"
  fi

  [[ -n "$backup_dir" && -f "$backup_dir/config" ]] || zn_die "未找到可回滚的配置版本"
  cp -a "$backup_dir/config" "$cfg"
  # 恢复备份中携带的依赖文件（证书等）
  local dep
  for dep in $(proto_meta "$proto" deps 2>/dev/null); do
    [[ -f "$backup_dir/$(basename "$dep")" ]] && cp -a "$backup_dir/$(basename "$dep")" "$dep"
  done
  local restarter="proto_restart_${proto}"
  if [[ "$(type -t "$restarter")" == "function" ]]; then
    "$restarter" || true
  else
    _cm_restart "$proto" >/dev/null 2>&1 || true
  fi
  zn_log_info "config" "$proto 已回滚到 $backup_dir"
  zn_audit "rollback" "$proto" "ok" "$backup_dir"
}
