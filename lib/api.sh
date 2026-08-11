#!/usr/bin/env bash
#
# api.sh - Local API（管理面，默认 127.0.0.1 + Bearer Token）
# 订阅端点默认关闭，`zn sub enable` 开启（独立端口，Token 鉴权）
#

api_token_get(){
  zn_conf_get api.token
}

api_token_generate(){
  local t
  t="$(zn_random_hex 24)"
  zn_conf_set api.token "$t"
  printf '%s' "$t"
}

sub_token_get(){
  zn_conf_get sub.token
}

sub_token_generate(){
  local t
  t="$(zn_random_hex 16)"
  zn_conf_set sub.token "$t"
  printf '%s' "$t"
}

api_response(){
  local code="$1" ctype="$2" body="$3"
  printf 'HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %s\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n%s' \
    "$code" "$ctype" "${#body}" "$body"
}

api_json_ok(){ api_response 200 "application/json" "{\"ok\":true,\"data\":$1}"; }
api_json_err(){ api_response 400 "application/json" "{\"ok\":false,\"error\":\"$1\"}"; }
api_unauthorized(){ api_response 401 "application/json" "{\"ok\":false,\"error\":\"unauthorized\"}"; }

api_auth_ok(){
  # 从 headers 中找 Authorization: Bearer xxx，或 query token
  local token="${1:-}"
  local expected
  expected="$(api_token_get)"
  [[ -n "$expected" && "$token" == "$expected" ]]
}

api_route(){
  local method="$1" path="$2" query="$3" token="${4:-}"
  case "$path" in
    /health)
      api_json_ok "\"ok\""
      ;;
    /status)
      local s
      s="{\"node\":\"$(hostname)\",\"protocols\":[$(api_protocols_json)]}"
      api_json_ok "$s"
      ;;
    /protocols)
      api_json_ok "[$(api_protocols_json)]"
      ;;
    /links)
      api_auth_ok "$token" || { api_unauthorized; return; }
      local type
      type="$(echo "$query" | sed -n 's/.*type=\([^&]*\).*/\1/p')"
      case "$type" in
        clash)   [[ -f "$ZN_SUB_DIR/clash.yaml" ]] && api_response 200 "text/yaml" "$(cat "$ZN_SUB_DIR/clash.yaml")" || api_json_err "no sub" ;;
        singbox) [[ -f "$ZN_SUB_DIR/singbox.json" ]] && api_response 200 "application/json" "$(cat "$ZN_SUB_DIR/singbox.json")" || api_json_err "no sub" ;;
        *)       [[ -f "$ZN_SUB_DIR/sub.txt" ]] && api_response 200 "text/plain" "$(cat "$ZN_SUB_DIR/sub.txt")" || api_json_err "no sub" ;;
      esac
      ;;
    /logs)
      api_auth_ok "$token" || { api_unauthorized; return; }
      local n
      n="$(echo "$query" | sed -n 's/.*lines=\([0-9]*\).*/\1/p')"
      [[ -n "$n" ]] || n=50
      api_response 200 "text/plain" "$(tail -n "$n" "$ZN_LOG_FILE" 2>/dev/null || echo 'no logs')"
      ;;
    /rotate/*)
      api_auth_ok "$token" || { api_unauthorized; return; }
      local proto
      proto="${path#/rotate/}"
      source "$ZN_ROOT/protocols/interface.sh"
      proto_load "$proto" 2>/dev/null || { api_json_err "unknown protocol"; return; }
      if proto_dispatch rotate "$proto" >/dev/null 2>&1; then
        api_json_ok "\"rotated\""
      else
        api_json_err "rotate failed"
      fi
      ;;
    /restart/*)
      api_auth_ok "$token" || { api_unauthorized; return; }
      local proto
      proto="${path#/restart/}"
      source "$ZN_ROOT/protocols/interface.sh"
      proto_load "$proto" 2>/dev/null || { api_json_err "unknown protocol"; return; }
      proto_dispatch restart "$proto" >/dev/null 2>&1 && api_json_ok "\"restarted\"" || api_json_err "restart failed"
      ;;
    *)
      api_json_err "not found"
      ;;
  esac
}

api_protocols_json(){
  source "$ZN_ROOT/protocols/interface.sh"
  local out="" proto
  for proto in $ZN_PROTOCOLS; do
    if proto_installed "$proto" 2>/dev/null; then
      out="$out{\"name\":\"$proto\",\"status\":\"$(proto_dispatch status "$proto")\",\"version\":\"$(proto_dispatch version "$proto")\"},"
    fi
  done
  printf '%s' "${out%,}"
}

# 从 stdin 读取 HTTP 请求并响应（供 socat EXEC 模式调用）
api_handle_request(){
  local method path query line token=""
  IFS= read -r line || return 1
  method="${line%% *}"
  path="${line#* }"
  path="${path% HTTP/*}"
  query="${path#*\?}"
  [[ "$query" == "$path" ]] && query=""
  path="${path%%\?*}"
  while IFS= read -r line; do
    [[ -z "${line//$'\r'/}" ]] && break
    if [[ "$line" =~ ^Authorization:\ Bearer\ (.+)$ ]]; then
      token="${BASH_REMATCH[1]}"
    fi
  done
  [[ -z "$token" ]] && token="$(echo "$query" | sed -n 's/.*token=\([^&]*\).*/\1/p')"
  api_route "$method" "$path" "$query" "$token"
}

api_serve(){
  local port="${1:-8080}" bind="${2:-127.0.0.1}"
  command -v socat >/dev/null 2>&1 || {
    zn_log_error "api" "需要 socat 提供 HTTP 服务（可执行: zn api install 自动安装）"
    return 1
  }
  zn_log_info "api" "管理 API 监听 $bind:$port（Token: $(api_token_get)）"
  socat "TCP-LISTEN:$port,bind=$bind,fork,reuseaddr" \
    "EXEC:$ZN_ROOT/bin/zn-daemon handle"
}

api_install_service(){
  local port="${1:-8080}" bind="${2:-127.0.0.1}"
  zn_require_root
  system_ensure_cmd socat socat
  cat > /etc/systemd/system/zeronode-api.service <<EOF
[Unit]
Description=ZeroNode Local API
After=network.target

[Service]
Type=simple
ExecStart=$ZN_ROOT/bin/zn-daemon api $port $bind
Environment=ZN_ROOT=$ZN_ROOT
Restart=on-failure
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now zeronode-api >/dev/null 2>&1 || true
  zn_log_info "api" "管理 API 服务已安装 ($bind:$port)"
}

# 订阅端点（可对外，Token 鉴权）
api_serve_sub(){
  local port="${1:-8081}"
  command -v socat >/dev/null 2>&1 || { zn_log_error "sub" "需要 socat"; return 1; }
  zn_log_info "sub" "订阅端点监听 0.0.0.0:$port（Token: $(sub_token_get)）"
  socat "TCP-LISTEN:$port,bind=0.0.0.0,fork,reuseaddr" \
    "EXEC:$ZN_ROOT/bin/zn-daemon sub-handle"
}

api_install_sub_service(){
  local port="${1:-8081}"
  zn_require_root
  system_ensure_cmd socat socat
  cat > /etc/systemd/system/zeronode-sub.service <<EOF
[Unit]
Description=ZeroNode Subscription Server
After=network.target

[Service]
Type=simple
ExecStart=$ZN_ROOT/bin/zn-daemon sub $port
Environment=ZN_ROOT=$ZN_ROOT
Restart=on-failure
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now zeronode-sub >/dev/null 2>&1 || true
  local t
  t="$(sub_token_get)"
  zn_log_info "sub" "订阅服务已安装: http://<IP>:$port/sub?token=$t&type=clash"
}

api_sub_handle(){
  local method path query line token=""
  IFS= read -r line || return 1
  path="${line#* }"
  path="${path% HTTP/*}"
  query="${path#*\?}"
  [[ "$query" == "$path" ]] && query=""
  path="${path%%\?*}"
  while IFS= read -r line; do
    [[ -z "${line//$'\r'/}" ]] && break
  done
  token="$(echo "$query" | sed -n 's/.*token=\([^&]*\).*/\1/p')"
  local expected
  expected="$(sub_token_get)"
  [[ -n "$expected" && "$token" == "$expected" ]] || { api_unauthorized; return; }
  case "$path" in
    /sub)
      local type
      type="$(echo "$query" | sed -n 's/.*type=\([^&]*\).*/\1/p')"
      case "$type" in
        clash)   api_response 200 "text/yaml" "$(cat "$ZN_SUB_DIR/clash.yaml" 2>/dev/null)" ;;
        singbox) api_response 200 "application/json" "$(cat "$ZN_SUB_DIR/singbox.json" 2>/dev/null)" ;;
        *)       api_response 200 "text/plain" "$(cat "$ZN_SUB_DIR/sub.txt" 2>/dev/null)" ;;
      esac
      ;;
    *)
      api_json_err "not found"
      ;;
  esac
}
