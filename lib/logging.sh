#!/usr/bin/env bash
#
# logging.sh - 分级日志 + 脱敏 + 轮转
# 级别: DEBUG < INFO < WARN < ERROR
# 输出: <ts>|<LEVEL>|<module>|<message>（消息内凭证自动替换为 ***）
#

export ZN_LOG_LEVEL="${ZN_LOG_LEVEL:-INFO}"
export ZN_LOG_FILE="$ZN_LOG_DIR/zeronode.log"
export ZN_LOG_ROTATE_SIZE="${ZN_LOG_ROTATE_SIZE:-10485760}"   # 10MB
export ZN_LOG_ROTATE_KEEP="${ZN_LOG_ROTATE_KEEP:-7}"

_zn_level_num(){
  case "${1:-INFO}" in
    DEBUG) echo 0 ;; INFO) echo 1 ;; WARN) echo 2 ;; ERROR) echo 3 ;;
    *) echo 1 ;;
  esac
}

# 构建脱敏词表：从凭证文件与常用字段名生成 sed 表达式
_zn_mask_expr(){
  local expr=""
  if [[ -f "$ZN_CRED_FILE" ]]; then
    while IFS='=' read -r _k v; do
      [[ -z "$v" || "$v" == \#* ]] && continue
      expr="${expr}s#${v}#***#g;"
    done < "$ZN_CRED_FILE"
  fi
  # 常见敏感字段兜底
  expr="${expr}s#(password|auth|uuid|token|private[_-]?key|short[_-]?id|obfs[_-]?password)=[^ &|]*#\1=***#g;"
  printf '%s' "$expr"
}

zn_log(){
  local level="$1" module="$2" msg="$3"
  if (( $(_zn_level_num "$level") < $(_zn_level_num "$ZN_LOG_LEVEL") )); then
    return 0
  fi
  local ts line masked
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  line="$ts|$level|$module|$msg"
  masked="$(printf '%s' "$line" | sed -E "$(_zn_mask_expr)")"
  if [[ "$level" == "ERROR" ]]; then
    printf '%b%s%b\n' "$ZN_RED" "$masked" "$ZN_PLAIN" >&2
  elif [[ "$level" == "WARN" ]]; then
    printf '%b%s%b\n' "$ZN_YELLOW" "$masked" "$ZN_PLAIN" >&2
  else
    printf '%s\n' "$masked"
  fi
  mkdir -p "$ZN_LOG_DIR"
  printf '%s\n' "$masked" >> "$ZN_LOG_FILE"
  chmod 640 "$ZN_LOG_FILE"
}

zn_log_debug(){ zn_log DEBUG "$1" "$2"; }
zn_log_info(){  zn_log INFO  "$1" "$2"; }
zn_log_warn(){  zn_log WARN  "$1" "$2"; }
zn_log_error(){ zn_log ERROR "$1" "$2"; }

zn_log_rotate(){
  local f="$ZN_LOG_FILE"
  [[ -f "$f" ]] || return 0
  local size
  size="$(stat -c %s "$f" 2>/dev/null || echo 0)"
  if (( size >= ZN_LOG_ROTATE_SIZE )); then
    local i
    for ((i = ZN_LOG_ROTATE_KEEP - 1; i >= 1; i--)); do
      [[ -f "$f.$i" ]] && mv -f "$f.$i" "$f.$((i + 1))" 2>/dev/null || true
    done
    mv -f "$f" "$f.1" 2>/dev/null || true
    : > "$f"
    chmod 640 "$f"
    zn_log_info "logging" "日志轮转完成"
  fi
}

# 审计操作记录（写 DB + 日志）
zn_audit(){
  local action="$1" target="$2" result="$3" detail="${4:-}"
  zn_log_info "audit" "$action $target -> $result"
  if [[ -f "$ZN_DB_FILE" ]]; then
    # shellcheck source=lib/db.sh
    source "$ZN_ROOT/lib/db.sh" 2>/dev/null || true
    db_insert operations "actor=cli,action='$action',target='$target',result='$result',detail='$detail'" 2>/dev/null || true
  fi
}
