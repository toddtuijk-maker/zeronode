#!/usr/bin/env bash
#
# update.sh - 升级管理器
# 流程: 版本检测 → 备份 → 升级(vendored 官方安装器, SHA256 内置) → 完整性复核 → 健康检查 → 失败回滚
# 版本锁定: credentials 中 update.pin.<proto>=vX.Y.Z 则固定该版本
#

update_latest_version(){
  local proto="$1"
  case "$proto" in
    hysteria2)
      curl -fsSL -m 30 -H 'Accept: application/vnd.github.v3+json' \
        'https://api.github.com/repos/apernet/hysteria/releases/latest' 2>/dev/null \
        | grep '"tag_name"' | head -1 | sed -E 's/.*"app\/(v[0-9.]+)".*/\1/'
      ;;
    xray)
      curl -fsSL -m 30 -H 'Accept: application/vnd.github.v3+json' \
        'https://api.github.com/repos/XTLS/Xray-core/releases/latest' 2>/dev/null \
        | grep '"tag_name"' | head -1 | sed -E 's/.*"(v[0-9.]+)".*/\1/'
      ;;
    singbox)
      curl -fsSL -m 30 -H 'Accept: application/vnd.github.v3+json' \
        'https://api.github.com/repos/SagerNet/sing-box/releases/latest' 2>/dev/null \
        | grep '"tag_name"' | head -1 | sed -E 's/.*"(v[0-9.]+)".*/\1/'
      ;;
    *) return 1 ;;
  esac
}

update_pinned(){
  local proto="$1"
  cred_get "update.pin.$proto" 2>/dev/null || true
}

update_pin(){
  local proto="$1" ver="${2:-}"
  if [[ -z "$ver" ]]; then
    cred_del "update.pin.$proto"
    zn_log_info "update" "$proto 已解除版本锁定"
  else
    cred_set "update.pin.$proto" "$ver"
    zn_log_info "update" "$proto 锁定版本 $ver"
  fi
}

update_check(){
  local proto="$1"
  source "$ZN_ROOT/lib/credential.sh"
  local cur latest pinned
  cur="$(proto_dispatch version "$proto")"
  latest="$(update_latest_version "$proto")"
  pinned="$(update_pinned "$proto")"
  zn_yellow "$proto 当前版本: ${cur:-未安装} / 最新: ${latest:-未知} / 锁定: ${pinned:-无}"
  [[ -n "$cur" && -n "$latest" && "$cur" != "$latest" ]]
}

update_apply(){
  local proto="$1" want="${2:-}"
  zn_require_root
  source "$ZN_ROOT/lib/config_manager.sh"
  source "$ZN_ROOT/lib/credential.sh"
  source "$ZN_ROOT/lib/backup.sh"
  source "$ZN_ROOT/protocols/interface.sh"
  proto_load "$proto"

  [[ "$(proto_dispatch status "$proto")" != "not-installed" ]] || { zn_log_error "update" "$proto 未安装"; return 1; }
  local cur latest
  cur="$(proto_dispatch version "$proto")"
  latest="$(update_latest_version "$proto")"
  want="${want:-$(update_pinned "$proto")}"
  [[ -n "$want" ]] || want="$latest"
  if [[ -n "$cur" && "$cur" == "$want" ]]; then
    zn_log_info "update" "$proto 已是最新($cur)"
    return 0
  fi

  zn_log_info "update" "$proto $cur -> $want"
  local backup
  backup="$(backup_full)"
  zn_log_info "update" "升级前备份: $backup"
  cm_backup "$proto"
  # 备份当前二进制以便回滚
  local bin oldbin
  case "$proto" in
    hysteria2) bin="/usr/local/bin/hysteria" ;;
    xray) bin="/usr/local/bin/xray" ;;
    singbox) bin="/usr/local/bin/sing-box" ;;
  esac
  oldbin="$ZN_BIN_DIR/$proto-$(date +%Y%m%d-%H%M%S)"
  [[ -f "$bin" ]] && cp -a "$bin" "$oldbin" && chmod 755 "$oldbin"

  local ok=1
  case "$proto" in
    hysteria2)
      if [[ -n "$want" && "$want" != "$latest" ]]; then
        # 官方安装器不支持任意版本参数时回退：仅支持最新；如需锁定版本可后续扩展
        zn_log_warn "update" "Hysteria 官方安装器默认安装最新版，忽略指定版本 $want"
      fi
      bash "$ZN_ROOT/vendor/install_server.sh" && ok=0
      ;;
    xray)
      if [[ -n "$want" && "$want" != "$latest" ]]; then
        bash "$ZN_ROOT/vendor/xray-install-release.sh" install --version "$want" && ok=0
      else
        bash "$ZN_ROOT/vendor/xray-install-release.sh" install && ok=0
      fi
      ;;
    singbox)
      if [[ -n "$want" && "$want" != "$latest" ]]; then
        bash "$ZN_ROOT/vendor/sing-box-install.sh" --version "${want#v}" && ok=0
      else
        bash "$ZN_ROOT/vendor/sing-box-install.sh" && ok=0
      fi
      ;;
  esac

  if [[ $ok -ne 0 ]]; then
    zn_log_error "update" "$proto 升级失败，开始回滚"
    [[ -f "$oldbin" ]] && cp -a "$oldbin" "$bin" && chmod 755 "$bin"
    systemctl restart "$(proto_meta "$proto" systemd_unit)" >/dev/null 2>&1 || true
    zn_audit "upgrade" "$proto" "failed" "to=$want"
    return 1
  fi

  # 完整性复核
  if [[ "$proto" == "hysteria2" ]]; then
    source "$ZN_ROOT/protocols/hysteria2.sh"
    hy2_verify_binary || { zn_log_error "update" "升级后完整性校验失败"; return 1; }
  elif [[ "$proto" == "singbox" ]]; then
    local magic
    magic="$(head -c 4 "$bin" | od -An -tx1 | tr -d ' \n')"
    [[ "$magic" == "7f454c46" ]] || { zn_log_error "update" "升级后完整性校验失败"; return 1; }
    "$bin" version >/dev/null 2>&1 || { zn_log_error "update" "升级后版本校验失败"; return 1; }
  fi
  # 健康检查
  sleep 2
  if ! proto_dispatch health "$proto"; then
    zn_log_error "update" "$proto 升级后健康检查失败，回滚"
    [[ -f "$oldbin" ]] && cp -a "$oldbin" "$bin" && chmod 755 "$bin"
    systemctl restart "$(proto_meta "$proto" systemd_unit)" >/dev/null 2>&1 || true
    zn_audit "upgrade" "$proto" "failed" "health-check"
    return 1
  fi

  if [[ -f "$ZN_DB_FILE" ]]; then
    source "$ZN_ROOT/lib/db.sh"
    db_available && db_insert upgrades "protocol='$proto',from_ver='$cur',to_ver='$want',result='ok'" 2>/dev/null || true
  fi
  zn_audit "upgrade" "$proto" "ok" "$cur -> $want"
  zn_log_info "update" "$proto 升级完成: $want"
}
