#!/usr/bin/env bash
#
# singbox.sh - sing-box 内核协议模块（默认推荐内核）
# 支持子协议: vision (VLESS+REALITY+XTLS Vision) / xhttp (VLESS+REALITY+XHTTP) / trojan (Trojan+TLS)
# 与 xray.sh 共享 VLESS 家族凭证命名空间（xray.* 键），客户端链接/订阅完全复用
#

SB_CONFIG="/etc/sing-box/config.json"
SB_BIN="/usr/local/bin/sing-box"
SB_UNIT="sing-box"
SB_VENDOR="$ZN_ROOT/vendor/sing-box-install.sh"
SB_TLS_DIR="/etc/sing-box/tls"

proto_meta_singbox_needs_domain(){ echo 0; }
proto_meta_singbox_display_name(){ echo "VLESS+REALITY+XTLS Vision/XHTTP + Trojan [sing-box 内核]"; }
proto_meta_singbox_transport(){ echo "tcp"; }
proto_meta_singbox_systemd_unit(){ echo "$SB_UNIT"; }
proto_meta_singbox_run_cmd(){ echo "$SB_BIN run -c $SB_CONFIG"; }
proto_meta_singbox_config_perms(){ echo 644; }
proto_meta_singbox_config_owner(){ echo "root:root"; }
proto_meta_singbox_deps(){
  echo "$SB_TLS_DIR/cert.crt $SB_TLS_DIR/private.key"
}

proto_config_path_singbox(){ echo "$SB_CONFIG"; }

proto_version_singbox(){
  [[ -x "$SB_BIN" ]] || return 1
  "$SB_BIN" version 2>/dev/null | grep -oE 'sing-box version [0-9.]+' | awk '{print $3}'
}

sb_installed(){
  [[ -x "$SB_BIN" ]] && [[ -f "$SB_CONFIG" ]]
}

proto_restart_singbox(){
  # shellcheck source=lib/system.sh
  source "$ZN_ROOT/lib/system.sh"
  system_service_restart "$SB_UNIT" $SB_BIN run -c "$SB_CONFIG"
}

proto_status_singbox(){
  if sb_installed; then
    # shellcheck source=lib/system.sh
    source "$ZN_ROOT/lib/system.sh"
    system_service_active "$SB_UNIT" && echo active || echo inactive
  else
    echo not-installed
  fi
}

proto_health_singbox(){
  # shellcheck source=lib/system.sh
  source "$ZN_ROOT/lib/system.sh"
  if ! system_service_active "$SB_UNIT"; then
    zn_log_error "singbox" "健康检查失败: 服务未运行"
    systemctl status sing-box --no-pager -l 2>/dev/null | tail -n 8 || true
    return 1
  fi
  local port p
  for p in vision xhttp trojan; do
    port="$(cred_get "xray.$p.port")"
    if [[ -n "$port" ]]; then
      if ! zn_port_in_use_tcp "$port"; then
        zn_log_error "singbox" "健康检查失败: $p 端口 $port/tcp 未检测到监听"
        return 1
      fi
    fi
  done
  return 0
}

proto_validate_singbox(){
  local f="$1"
  [[ -f "$f" && -s "$f" ]] || return 1
  if [[ -x "$SB_BIN" ]]; then
    "$SB_BIN" check -c "$f" >/dev/null 2>&1 || return 1
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null || return 1
  else
    grep -q '"inbounds"' "$f" || return 1
    grep -q '"outbounds"' "$f" || return 1
  fi
  return 0
}

sb_install_core(){
  source "$ZN_ROOT/lib/system.sh"
  if system_has_systemd; then
    [[ -f "$SB_VENDOR" ]] || zn_die "缺少 vendor/sing-box-install.sh（sing-box 官方安装脚本）"
    zn_log_info "singbox" "使用官方安装脚本安装 sing-box ..."
    if ! bash "$SB_VENDOR"; then
      zn_log_error "singbox" "sing-box 安装失败"
      return 1
    fi
  else
    zn_log_info "singbox" "容器模式：手动下载官方二进制 ..."
    sb_container_install || return 1
  fi
  [[ -x "$SB_BIN" ]] || { zn_log_error "singbox" "未找到 $SB_BIN"; return 1; }
  # sing-box 官方发布无独立校验文件，复核 ELF + 版本
  local magic
  magic="$(head -c 4 "$SB_BIN" | od -An -tx1 | tr -d ' \n')"
  [[ "$magic" == "7f454c46" ]] || { zn_log_error "singbox" "二进制非 ELF"; return 1; }
  [[ -n "$(proto_version_singbox)" ]] || { zn_log_error "singbox" "二进制版本校验失败"; return 1; }
}

sb_latest_version(){
  curl -fsSL -m 30 -H 'Accept: application/vnd.github.v3+json' \
    'https://api.github.com/repos/SagerNet/sing-box/releases/latest' 2>/dev/null \
    | grep '"tag_name"' | head -1 | sed -E 's/.*"(v[0-9.]+)".*/\1/'
}

sb_container_install(){
  local ver asset url tmp extract
  ver="$(sb_latest_version)"
  [[ -n "$ver" ]] || return 1
  case "$(zn_arch)" in
    amd64) asset="sing-box-${ver#v}-linux-amd64.tar.gz" ;;
    arm64) asset="sing-box-${ver#v}-linux-arm64.tar.gz" ;;
    arm)   asset="sing-box-${ver#v}-linux-armv7.tar.gz" ;;
    386)   asset="sing-box-${ver#v}-linux-386.tar.gz" ;;
    *) zn_log_error "singbox" "容器模式暂不支持该架构: $(zn_arch)"; return 1 ;;
  esac
  source "$ZN_ROOT/lib/system.sh"
  system_ensure_cmd tar tar
  url="https://github.com/SagerNet/sing-box/releases/download/$ver/$asset"
  tmp="$(zn_tmp)"
  zn_log_info "singbox" "下载 $url"
  curl -fL --retry 3 -m 180 -o "$tmp" "$url" || return 1
  extract="$(mktemp -d)"
  tar -xzf "$tmp" -C "$extract" || { rm -rf "$extract"; return 1; }
  local bin
  bin="$(find "$extract" -type f -name sing-box | head -1)"
  [[ -n "$bin" ]] || { rm -rf "$extract"; return 1; }
  install -m755 "$bin" "$SB_BIN"
  rm -rf "$extract"
}

sb_gen_keys(){
  local out priv pub sid uuid
  out="$("$SB_BIN" generate reality-keypair 2>/dev/null)"
  priv="$(echo "$out" | grep 'PrivateKey:' | awk '{print $2}' | tr -d '\r')"
  pub="$(echo "$out" | grep 'PublicKey:' | awk '{print $2}' | tr -d '\r')"
  sid="$(zn_random_hex 8)"
  uuid="$("$SB_BIN" generate uuid 2>/dev/null | tr -d '\r')"
  [[ -n "$uuid" ]] || uuid="$(zn_random_uuid)"
  cred_set "xray.reality.private_key" "$priv"
  cred_set "xray.reality.public_key" "$pub"
  cred_set "xray.reality.short_id" "$sid"
  cred_set "xray.uuid" "$uuid"
}

sb_issue_tls_cert(){
  mkdir -p "$SB_TLS_DIR"
  if [[ ! -f "$SB_TLS_DIR/private.key" ]]; then
    zn_need_cmd_or_install openssl openssl
    openssl ecparam -genkey -name prime256v1 -out "$SB_TLS_DIR/private.key"
    openssl req -new -x509 -days 36500 -key "$SB_TLS_DIR/private.key" \
      -out "$SB_TLS_DIR/cert.crt" -subj "/CN=www.bing.com"
  fi
  chmod 640 "$SB_TLS_DIR/private.key"
  chmod 644 "$SB_TLS_DIR/cert.crt"
}

sb_inbound_json_vision(){
  local port dest priv sid uuid
  port="$(cred_get xray.vision.port)"
  dest="$(cred_get xray.dest)"
  priv="$(cred_get xray.reality.private_key)"
  sid="$(cred_get xray.reality.short_id)"
  uuid="$(cred_get xray.uuid)"
  printf '{
    "type": "vless",
    "tag": "vless-vision-in",
    "listen": "::",
    "listen_port": %s,
    "users": [{"uuid": "%s", "flow": "xtls-rprx-vision"}],
    "tls": {
      "enabled": true,
      "server_name": ["%s"],
      "reality": {
        "enabled": true,
        "handshake": {"server": "%s", "port": 443},
        "private_key": "%s",
        "short_id": ["%s"]
      }
    }
  }' "$port" "$uuid" "$dest" "$dest" "$priv" "$sid"
}

sb_inbound_json_xhttp(){
  local port dest priv sid uuid path
  port="$(cred_get xray.xhttp.port)"
  dest="$(cred_get xray.dest)"
  priv="$(cred_get xray.reality.private_key)"
  sid="$(cred_get xray.reality.short_id)"
  uuid="$(cred_get xray.uuid)"
  path="$(cred_get xray.xhttp.path)"
  printf '{
    "type": "vless",
    "tag": "vless-xhttp-in",
    "listen": "::",
    "listen_port": %s,
    "users": [{"uuid": "%s"}],
    "tls": {
      "enabled": true,
      "server_name": ["%s"],
      "reality": {
        "enabled": true,
        "handshake": {"server": "%s", "port": 443},
        "private_key": "%s",
        "short_id": ["%s"]
      }
    },
    "transport": {"type": "xhttp", "host": "%s", "path": "%s", "mode": "auto"}
  }' "$port" "$uuid" "$dest" "$dest" "$priv" "$sid" "$dest" "$path"
}

sb_inbound_json_trojan(){
  local port pwd
  port="$(cred_get xray.trojan.port)"
  pwd="$(cred_get xray.trojan.password)"
  printf '{
    "type": "trojan",
    "tag": "trojan-in",
    "listen": "::",
    "listen_port": %s,
    "users": [{"password": "%s"}],
    "tls": {
      "enabled": true,
      "certificate_path": "%s/cert.crt",
      "key_path": "%s/private.key"
    }
  }' "$port" "$pwd" "$SB_TLS_DIR" "$SB_TLS_DIR"
}

sb_gen_config(){
  local subs="$1" tmp first=true
  tmp="$(zn_tmp)"
  printf '{\n  "log": {"level": "warn", "timestamp": true},\n  "inbounds": [\n' > "$tmp"
  local sub
  for sub in $subs; do
    if [[ "$first" == true ]]; then
      first=false
    else
      printf ',\n' >> "$tmp"
    fi
    "sb_inbound_json_$sub" >> "$tmp"
  done
  printf '\n  ],\n  "outbounds": [\n    {"type": "direct", "tag": "direct"}\n  ]\n}\n' >> "$tmp"
  printf '%s' "$tmp"
}

proto_install_singbox(){
  local mode="${1:-ip}" domain="${2:-}" subs="${3:-vision xhttp trojan}"
  zn_require_root
  source "$ZN_ROOT/lib/config_manager.sh"
  source "$ZN_ROOT/lib/credential.sh"
  source "$ZN_ROOT/lib/stealth.sh"

  zn_log_info "singbox" "开始安装 sing-box 内核（模式: $mode, 域名: ${domain:-无}, 子协议: $subs）"
  sb_install_core || return 1

  local dest
  dest="$(cred_get xray.dest)"
  [[ -n "$dest" ]] || dest="$(stealth_pick reality_dest)"
  cred_set "xray.dest" "$dest"
  sb_gen_keys

  local port sub path
  for sub in $subs; do
    port="$(cred_get "xray.$sub.port")"
    [[ -n "$port" ]] || port="$(zn_random_port)"
    cred_set "xray.$sub.port" "$port"
    if [[ "$sub" == "xhttp" ]]; then
      path="$(cred_get xray.xhttp.path)"
      [[ -n "$path" ]] || path="$(stealth_xhttp_path)"
      cred_set "xray.xhttp.path" "$path"
    fi
    if [[ "$sub" == "trojan" ]]; then
      local tpwd
      tpwd="$(cred_get xray.trojan.password)"
      [[ -n "$tpwd" ]] || tpwd="$(zn_random_password 20)"
      cred_set "xray.trojan.password" "$tpwd"
    fi
  done
  cred_set "xray.subs" "$subs"
  cred_set "kernel.vless" "singbox"

  if [[ "$subs" == *trojan* ]]; then
    sb_issue_tls_cert
  fi

  local tmp
  tmp="$(sb_gen_config "$subs")"
  cm_apply singbox "$tmp" "install" || return 1

  source "$ZN_ROOT/lib/system.sh"
  local p
  for sub in $subs; do
    p="$(cred_get "xray.$sub.port")"
    system_fw_allow_tcp "$p"
  done
  system_service_enable "$SB_UNIT" $SB_BIN run -c "$SB_CONFIG"
  proto_mark_installed singbox
  proto_mark_installed vless
  zn_audit "install" "singbox" "ok" "subs=$subs kernel=sing-box"
  zn_log_info "singbox" "sing-box 安装完成，版本 $(proto_version_singbox)"
}

proto_remove_singbox(){
  zn_require_root
  zn_confirm "确认卸载 sing-box？（配置与证书将备份到历史目录）" || return 1
  source "$ZN_ROOT/lib/config_manager.sh"
  cm_backup singbox
  source "$ZN_ROOT/lib/system.sh"
  system_service_stop "$SB_UNIT"
  if system_has_systemd; then
    rm -f /etc/systemd/system/sing-box.service
  fi
  rm -f "$SB_BIN"
  rm -rf /etc/sing-box
  system_has_systemd && systemctl daemon-reload >/dev/null 2>&1 || true
  proto_mark_installed singbox 0
  proto_mark_installed vless 0
  zn_audit "remove" "singbox" "ok"
}

proto_links_singbox(){
  source "$ZN_ROOT/lib/credential.sh"
  source "$ZN_ROOT/lib/clientgen.sh"
  local subs ip
  subs="$(cred_get xray.subs)"
  ip="$(zn_public_ipv4)"
  [[ -n "$ip" ]] || ip="$(zn_public_ipv6)"
  clientgen_xray "$ip" "$subs"
}

proto_rotate_singbox(){
  zn_require_root
  source "$ZN_ROOT/lib/config_manager.sh"
  local newuuid subs tmp
  newuuid="$(zn_random_uuid)"
  cred_rotate xray.uuid "$newuuid"
  sb_gen_keys
  subs="$(cred_get xray.subs)"
  tmp="$(sb_gen_config "$subs")"
  if ! cm_apply singbox "$tmp" "rotate-keys"; then
    zn_log_error "singbox" "密钥轮换失败"
    return 1
  fi
  zn_audit "rotate" "singbox" "ok"
  zn_log_info "singbox" "UUID/REALITY 密钥已轮换"
}
