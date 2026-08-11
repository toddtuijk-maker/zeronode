#!/usr/bin/env bash
#
# backup.sh - 备份管理器（全量/加密/恢复）
#

backup_full(){
  local pass="${1:-}" out
  out="$ZN_BACKUP_DIR/zeronode-$(date +%Y%m%d-%H%M%S).tar"
  mkdir -p "$ZN_BACKUP_DIR"
  # 备份范围：协议配置、证书、ZeroNode 状态（DB/凭证/订阅/日志），排除历史与自身备份
  local inc=()
  [[ -d /etc/hysteria ]] && inc+=(/etc/hysteria)
  [[ -d /usr/local/etc/xray ]] && inc+=(/usr/local/etc/xray)
  [[ -d /etc/sing-box ]] && inc+=(/etc/sing-box)
  inc+=("$ZN_STATE")
  local args=()
  local p
  for p in "${inc[@]}"; do
    args+=(--exclude="$ZN_BACKUP_DIR" --exclude="$ZN_HISTORY_DIR" "$p")
  done
  if ! tar -cf "$out" "${args[@]}" 2>/dev/null; then
    zn_log_error "backup" "备份打包失败"
    rm -f "$out"
    return 1
  fi
  if [[ -n "$pass" ]]; then
    openssl enc -aes-256-cbc -salt -pbkdf2 -pass "pass:$pass" -in "$out" -out "$out.enc" 2>/dev/null || return 1
    rm -f "$out"
    out="$out.enc"
  fi
  chmod 600 "$out"
  zn_log_info "backup" "备份完成: $out"
  printf '%s' "$out"
}

backup_restore(){
  local src="$1" pass="${2:-}" work
  [[ -f "$src" ]] || { zn_log_error "backup" "备份文件不存在: $src"; return 1; }
  work="$(mktemp -d)"
  if [[ "$src" == *.enc ]]; then
    openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass "pass:$pass" -in "$src" -out "$work/restore.tar" 2>/dev/null || {
      zn_log_error "backup" "解密失败（口令错误？）"
      rm -rf "$work"
      return 1
    }
  else
    cp -a "$src" "$work/restore.tar"
  fi
  zn_confirm "恢复将覆盖现有配置与数据库，确认继续？" || { rm -rf "$work"; return 1; }
  if ! tar -xf "$work/restore.tar" -C / 2>/dev/null; then
    zn_log_error "backup" "恢复解包失败"
    rm -rf "$work"
    return 1
  fi
  rm -rf "$work"
  # 恢复后修复权限
  chmod 700 "$ZN_STATE" 2>/dev/null || true
  chmod 600 "$ZN_CRED_FILE" "$ZN_DB_FILE" 2>/dev/null || true
  zn_log_info "backup" "恢复完成，建议重启协议服务"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart hysteria-server >/dev/null 2>&1 || true
  systemctl restart xray >/dev/null 2>&1 || true
}
