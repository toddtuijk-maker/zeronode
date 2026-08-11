#!/usr/bin/env bash
#
# xray.sh - Xray 协议模块
# 支持子协议: vision (VLESS+REALITY+XTLS Vision) / xhttp (VLESS+REALITY+XHTTP) / trojan (Trojan+TLS)
# 单一 xray 服务，config.json 可含多个 inbound
#

XRAY_CONFIG="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
XRAY_UNIT="xray"
XRAY_VENDOR="$ZN_ROOT/vendor/xray-install-release.sh"
XRAY_TLS_DIR="/usr/local/etc/xray/tls"

proto_meta_xray_needs_domain(){ echo 0; }
proto_meta_xray_display_name(){ echo "Xray (VLESS REALITY Vision/XHTTP + Trojan)"; }
proto_meta_xray_transport(){ echo "tcp"; }
proto_meta_xray_systemd_unit(){ echo "$XRAY_UNIT"; }
proto_meta_xray_run_cmd(){ echo "$XRAY_BIN run -c $XRAY_CONFIG"; }
proto_meta_xray_config_perms(){ echo 644; }
proto_meta_xray_config_owner(){ echo "root:xray"; }
proto_meta_xray_deps(){
  echo "$XRAY_TLS_DIR/cert.crt $XRAY_TLS_DIR/private.key"
}

proto_config_path_xray(){ echo "$XRAY_CONFIG"; }

proto_version_xray(){
  [[ -x "$XRAY_BIN" ]] || return 1
  "$XRAY_BIN" version 2>/dev/null | awk 'NR==1{print $2}'
}

xray_installed(){
  [[ -x "$XRAY_BIN" ]] && [[ -f "$XRAY_CONFIG" ]]
}

proto_restart_xray(){
  # shellcheck source=lib/system.sh
  source "$ZN_ROOT/lib/system.sh"
  system_service_restart "$XRAY_UNIT" $XRAY_BIN run -c "$XRAY_CONFIG"
}

proto_status_xray(){
  if xray_installed; then
    # shellcheck source=lib/system.sh
    source "$ZN_ROOT/lib/system.sh"
    system_service_active "$XRAY_UNIT" && echo active || echo inactive
  else
    echo not-installed
  fi
}

proto_health_xray(){
  # shellcheck source=lib/system.sh
  source "$ZN_ROOT/lib/system.sh"
  if ! system_service_active "$XRAY_UNIT"; then
    zn_log_error "xray" "健康检查失败: 服务未运行"
    systemctl status xray --no-pager -l 2>/dev/null | tail -n 8 || true
    return 1
  fi
  local port p
  for p in vision xhttp trojan; do
    port="$(cred_get "xray.$p.port")"
    if [[ -n "$port" ]]; then
      if ! zn_port_in_use_tcp "$port"; then
        zn_log_error "xray" "健康检查失败: $p 端口 $port/tcp 未检测到监听"
        return 1
      fi
    fi
  done
  return 0
}

proto_validate_xray(){
  local f="$1"
  [[ -f "$f" && -s "$f" ]] || return 1
  if [[ -x "$XRAY_BIN" ]]; then
    "$XRAY_BIN" run -test -config "$f" >/dev/null 2>&1 || return 1
  else
    # 无二进制时做基础 JSON 校验
    if command -v python3 >/dev/null 2>&1; then
      python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null || return 1
    fi
  fi
  return 0
}

xray_install_core(){
  source "$ZN_ROOT/lib/system.sh"
  if system_has_systemd; then
    [[ -f "$XRAY_VENDOR" ]] || zn_die "缺少 vendor/xray-install-release.sh（Xray 官方安装器）"
    zn_log_info "xray" "使用官方安装器安装 Xray ..."
    if ! bash "$XRAY_VENDOR" install; then
      zn_log_error "xray" "官方安装器执行失败"
      return 1
    fi
  else
    zn_log_info "xray" "容器模式：手动下载官方二进制 ..."
    xray_container_install || return 1
  fi
  [[ -x "$XRAY_BIN" ]]
}

xray_latest_version(){
  curl -fsSL -m 30 -H 'Accept: application/vnd.github.v3+json' \
    'https://api.github.com/repos/XTLS/Xray-core/releases/latest' 2>/dev/null \
    | grep '"tag_name"' | head -1 | sed -E 's/.*"(v[0-9.]+)".*/\1/'
}

xray_container_install(){
  local ver asset url tmp dgst expected actual extract
  ver="$(xray_latest_version)"
  [[ -n "$ver" ]] || return 1
  case "$(zn_arch)" in
    amd64) asset="Xray-linux-64.zip" ;;
    arm64) asset="Xray-linux-arm64-v8a.zip" ;;
    arm)   asset="Xray-linux-arm32-v7a.zip" ;;
    386)   asset="Xray-linux-32.zip" ;;
    *) zn_log_error "xray" "容器模式暂不支持该架构: $(zn_arch)"; return 1 ;;
  esac
  source "$ZN_ROOT/lib/system.sh"
  system_ensure_cmd unzip unzip
  url="https://github.com/XTLS/Xray-core/releases/download/$ver/$asset"
  tmp="$(zn_tmp)"
  dgst="$(zn_tmp)"
  zn_log_info "xray" "下载 $url"
  curl -fL --retry 3 -m 180 -o "$tmp" "$url" || return 1
  curl -fL --retry 3 -m 60 -o "$dgst" "$url.dgst" || return 1
  expected="$(awk -F '= ' '/SHA2-256=/{print $2}' "$dgst" | tr -d '\r')"
  actual="$(sha256sum "$tmp" | awk '{print $1}')"
  [[ -n "$expected" && "$expected" == "$actual" ]] || {
    zn_log_error "xray" "下载校验失败"
    return 1
  }
  extract="$(mktemp -d)"
  unzip -o -q "$tmp" -d "$extract" || { rm -rf "$extract"; return 1; }
  install -m755 "$extract/xray" "$XRAY_BIN"
  rm -rf "$extract"
}

xray_gen_keys(){
  local out priv pub sid uuid
  out="$("$XRAY_BIN" x25519 2>/dev/null)"
  priv="$(echo "$out" | grep 'Private key:' | awk '{print $3}' | tr -d '\r')"
  pub="$(echo "$out" | grep 'Public key:' | awk '{print $3}' | tr -d '\r')"
  sid="$(zn_random_hex 8)"
  uuid="$("$XRAY_BIN" uuid 2>/dev/null | tr -d '\r')"
  [[ -n "$uuid" ]] || uuid="$(zn_random_uuid)"
  cred_set "xray.reality.private_key" "$priv"
  cred_set "xray.reality.public_key" "$pub"
  cred_set "xray.reality.short_id" "$sid"
  cred_set "xray.uuid" "$uuid"
}

# 自签证书（Trojan TLS 使用；域名模式可后续替换为正式证书）
xray_issue_tls_cert(){
  mkdir -p "$XRAY_TLS_DIR"
  if [[ ! -f "$XRAY_TLS_DIR/private.key" ]]; then
    zn_need_cmd_or_install openssl openssl
    openssl ecparam -genkey -name prime256v1 -out "$XRAY_TLS_DIR/private.key"
    openssl req -new -x509 -days 36500 -key "$XRAY_TLS_DIR/private.key" \
      -out "$XRAY_TLS_DIR/cert.crt" -subj "/CN=www.bing.com"
  fi
  chown -R root:xray "$XRAY_TLS_DIR" 2>/dev/null || true
  chmod 640 "$XRAY_TLS_DIR/private.key"
  chmod 644 "$XRAY_TLS_DIR/cert.crt"
}

xray_inbound_json_vision(){
  local port dest priv sid uuid
  port="$(cred_get xray.vision.port)"
  dest="$(cred_get xray.dest)"
  priv="$(cred_get xray.reality.private_key)"
  sid="$(cred_get xray.reality.short_id)"
  uuid="$(cred_get xray.uuid)"
  printf '{
    "listen": "0.0.0.0",
    "port": %s,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "%s", "flow": "xtls-rprx-vision"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "%s:443",
        "xver": 0,
        "serverNames": ["%s"],
        "privateKey": "%s",
        "shortIds": ["%s"]
      }
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
  }' "$port" "$uuid" "$dest" "$dest" "$priv" "$sid"
}

xray_inbound_json_xhttp(){
  local port dest priv sid uuid path
  port="$(cred_get xray.xhttp.port)"
  dest="$(cred_get xray.dest)"
  priv="$(cred_get xray.reality.private_key)"
  sid="$(cred_get xray.reality.short_id)"
  uuid="$(cred_get xray.uuid)"
  path="$(cred_get xray.xhttp.path)"
  printf '{
    "listen": "0.0.0.0",
    "port": %s,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "%s"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "xhttp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "%s:443",
        "xver": 0,
        "serverNames": ["%s"],
        "privateKey": "%s",
        "shortIds": ["%s"]
      },
      "xhttpSettings": {
        "path": "%s",
        "host": "%s",
        "mode": "auto"
      }
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
  }' "$port" "$uuid" "$dest" "$dest" "$priv" "$sid" "$path" "$dest"
}

xray_inbound_json_trojan(){
  local port pwd
  port="$(cred_get xray.trojan.port)"
  pwd="$(cred_get xray.trojan.password)"
  printf '{
    "listen": "0.0.0.0",
    "port": %s,
    "protocol": "trojan",
    "settings": {
      "clients": [{"password": "%s"}]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "tls",
      "tlsSettings": {
        "certificates": [
          {
            "certificateFile": "%s/cert.crt",
            "keyFile": "%s/private.key"
          }
        ],
        "minVersion": "1.2"
      }
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
  }' "$port" "$pwd" "$XRAY_TLS_DIR" "$XRAY_TLS_DIR"
}

xray_gen_config(){
  local subs="$1" tmp first=true
  tmp="$(zn_tmp)"
  printf '{\n  "log": {"loglevel": "warning", "access": "none"},\n  "inbounds": [\n' > "$tmp"
  local sub
  for sub in $subs; do
    if [[ "$first" == true ]]; then
      first=false
    else
      printf ',\n' >> "$tmp"
    fi
    "xray_inbound_json_$sub" >> "$tmp"
  done
  printf '\n  ],\n  "outbounds": [\n    {"protocol": "freedom", "tag": "direct"},\n    {"protocol": "blackhole", "tag": "block"}\n  ],\n  "routing": {\n    "domainStrategy": "IPIfNonMatch",\n    "rules": [\n      {"type": "field", "outboundTag": "block", "protocol": ["bittorrent"]}\n    ]\n  }\n}\n' >> "$tmp"
  printf '%s' "$tmp"
}

proto_install_xray(){
  local mode="${1:-ip}" domain="${2:-}" subs="${3:-vision xhttp trojan}"
  zn_require_root
  source "$ZN_ROOT/lib/config_manager.sh"
  source "$ZN_ROOT/lib/credential.sh"
  source "$ZN_ROOT/lib/stealth.sh"

  zn_log_info "xray" "开始安装 Xray（模式: $mode, 域名: ${domain:-无}, 子协议: $subs）"
  xray_install_core || return 1

  local dest
  dest="$(cred_get xray.dest)"
  [[ -n "$dest" ]] || dest="$(stealth_pick reality_dest)"
  cred_set "xray.dest" "$dest"
  xray_gen_keys

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

  if [[ "$subs" == *trojan* ]]; then
    xray_issue_tls_cert
  fi

  local tmp
  tmp="$(xray_gen_config "$subs")"
  cm_apply xray "$tmp" "install" || return 1

  source "$ZN_ROOT/lib/system.sh"
  local p
  for sub in $subs; do
    p="$(cred_get "xray.$sub.port")"
    system_fw_allow_tcp "$p"
  done
  system_service_enable "$XRAY_UNIT" $XRAY_BIN run -c "$XRAY_CONFIG"
  proto_mark_installed xray
  proto_mark_installed vless
  cred_set "kernel.vless" "xray"
  zn_audit "install" "xray" "ok" "subs=$subs"
  zn_log_info "xray" "Xray 安装完成，版本 $(proto_version_xray)"
}

proto_remove_xray(){
  zn_require_root
  zn_confirm "确认卸载 Xray？（配置与证书将备份到历史目录）" || return 1
  source "$ZN_ROOT/lib/config_manager.sh"
  cm_backup xray
  # shellcheck source=lib/system.sh
  source "$ZN_ROOT/lib/system.sh"
  system_service_stop "$XRAY_UNIT"
  if system_has_systemd; then
    rm -f /etc/systemd/system/xray.service
  fi
  rm -f "$XRAY_BIN"
  rm -rf /usr/local/etc/xray /usr/local/share/xray
  system_has_systemd && systemctl daemon-reload >/dev/null 2>&1 || true
  proto_mark_installed xray 0
  proto_mark_installed vless 0
  zn_audit "remove" "xray" "ok"
}

proto_links_xray(){
  source "$ZN_ROOT/lib/credential.sh"
  source "$ZN_ROOT/lib/clientgen.sh"
  local subs ip
  subs="$(cred_get xray.subs)"
  ip="$(zn_public_ipv4)"
  [[ -n "$ip" ]] || ip="$(zn_public_ipv6)"
  clientgen_xray "$ip" "$subs"
}

# 轮换 UUID 与 REALITY 密钥（走 Config Manager 全流程）
proto_rotate_xray(){
  zn_require_root
  source "$ZN_ROOT/lib/config_manager.sh"
  local newuuid subs tmp
  newuuid="$(zn_random_uuid)"
  cred_rotate xray.uuid "$newuuid"
  xray_gen_keys
  subs="$(cred_get xray.subs)"
  tmp="$(xray_gen_config "$subs")"
  if ! cm_apply xray "$tmp" "rotate-keys"; then
    zn_log_error "xray" "密钥轮换失败"
    return 1
  fi
  zn_audit "rotate" "xray" "ok"
  zn_log_info "xray" "UUID/REALITY 密钥已轮换"
}
