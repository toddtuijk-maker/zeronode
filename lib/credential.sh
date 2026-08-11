#!/usr/bin/env bash
#
# credential.sh - 凭证管理器
# 存储: $ZN_STATE/credentials (root:root 0600)
# 功能: 生成/读取/轮换/撤销/备份恢复；日志自动脱敏
#

cred_init(){
  mkdir -p "$ZN_STATE"
  touch "$ZN_CRED_FILE"
  chown root:root "$ZN_CRED_FILE" 2>/dev/null || true
  chmod 600 "$ZN_CRED_FILE"
}

cred_get(){
  local key="$1"
  [[ -f "$ZN_CRED_FILE" ]] || return 1
  grep -E "^${key}=" "$ZN_CRED_FILE" 2>/dev/null | head -1 | cut -d= -f2-
}

cred_set(){
  local key="$1" val="$2" tmp
  cred_init
  tmp="$(zn_tmp)"
  grep -vE "^${key}=" "$ZN_CRED_FILE" > "$tmp" 2>/dev/null || true
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  mv -f "$tmp" "$ZN_CRED_FILE"
  chown root:root "$ZN_CRED_FILE" 2>/dev/null || true
  chmod 600 "$ZN_CRED_FILE"
}

cred_del(){
  local key="$1" tmp
  cred_init
  tmp="$(zn_tmp)"
  grep -vE "^${key}=" "$ZN_CRED_FILE" > "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$ZN_CRED_FILE"
  chmod 600 "$ZN_CRED_FILE"
}

# 轮换：旧值追加到 revoked 记录（同文件 #revoked 段），新值写入
cred_rotate(){
  local key="$1" newval="$2"
  local old
  old="$(cred_get "$key")"
  if [[ -n "$old" ]]; then
    printf '#revoked %s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$key" "$old" >> "$ZN_CRED_FILE"
  fi
  cred_set "$key" "$newval"
}

# 撤销某个用户/凭证：从配置中移除由调用方（协议模块）执行，这里记录撤销事件
cred_revoke_user(){
  local uuid="$1"
  cred_init
  printf '#revoked-user %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$uuid" >> "$ZN_CRED_FILE"
  # shellcheck source=lib/db.sh
  source "$ZN_ROOT/lib/db.sh" 2>/dev/null || true
  db_exec "UPDATE users SET revoked=1, revoked_at=datetime('now') WHERE id='$uuid'" 2>/dev/null || true
  zn_log_info "credential" "用户 $uuid 已撤销"
}

cred_backup(){
  local dest="${1:-$ZN_BACKUP_DIR/credentials-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$(dirname "$dest")"
  cp -a "$ZN_CRED_FILE" "$dest" 2>/dev/null || return 1
  chmod 600 "$dest"
  printf '%s' "$dest"
}

cred_restore(){
  local src="$1"
  [[ -f "$src" ]] || return 1
  cp -a "$src" "$ZN_CRED_FILE"
  chown root:root "$ZN_CRED_FILE" 2>/dev/null || true
  chmod 600 "$ZN_CRED_FILE"
}

# 加密备份（AES-256-CBC，口令来自 stdin 或参数）
cred_backup_encrypted(){
  local pass="${1:-}" out="${2:-$ZN_BACKUP_DIR/credentials-$(date +%Y%m%d-%H%M%S).enc}"
  mkdir -p "$(dirname "$out")"
  if [[ -z "$pass" ]]; then
    read -rsp "请输入备份加密口令: " pass || return 1
    echo >&2
  fi
  openssl enc -aes-256-cbc -salt -pbkdf2 -pass "pass:$pass" -in "$ZN_CRED_FILE" -out "$out" 2>/dev/null || return 1
  chmod 600 "$out"
  printf '%s' "$out"
}

cred_restore_encrypted(){
  local src="$1" pass="${2:-}"
  [[ -f "$src" ]] || return 1
  if [[ -z "$pass" ]]; then
    read -rsp "请输入备份解密口令: " pass || return 1
    echo >&2
  fi
  openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass "pass:$pass" -in "$src" -out "$ZN_CRED_FILE" 2>/dev/null || return 1
  chown root:root "$ZN_CRED_FILE" 2>/dev/null || true
  chmod 600 "$ZN_CRED_FILE"
}

# 敏感字段清单（供日志脱敏使用）
cred_mask_values(){
  [[ -f "$ZN_CRED_FILE" ]] || return 0
  while IFS='=' read -r _k v; do
    [[ -z "$v" || "$v" == \#* ]] && continue
    printf '%s\n' "$v"
  done < "$ZN_CRED_FILE"
}
