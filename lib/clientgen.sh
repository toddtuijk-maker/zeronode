#!/usr/bin/env bash
#
# clientgen.sh - 客户端生成层（多客户端兼容）
# 输出: 分享链接(vless:// hysteria2:// trojan://) / 二维码 / sing-box / Clash Meta / 订阅文件
# 兼容: v2rayN/v2rayNG/小火箭(Shadowrocket)/Stash/Loon/Karing/sing-box/Clash Meta(mihomo)
#

export ZN_CHANNEL_NAME="零号协议"
export ZN_CHANNEL_HANDLE="@linghaoxieyi"

# ---------- 分享链接 ----------
clientgen_vless_vision(){
  local ip="$1" uuid="$2" port="$3" dest="$4" pbk="$5" sid="$6" name="${7:-$ZN_CHANNEL_NAME-Vision}"
  printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp&headerType=none#%s' \
    "$uuid" "$ip" "$port" "$dest" "$pbk" "$sid" "$(zn_urlencode "$name")"
}

clientgen_vless_xhttp(){
  local ip="$1" uuid="$2" port="$3" dest="$4" pbk="$5" sid="$6" path="$7" name="${8:-$ZN_CHANNEL_NAME-XHTTP}"
  printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=xhttp&mode=auto&path=%s&host=%s#%s' \
    "$uuid" "$ip" "$port" "$dest" "$pbk" "$sid" "$(zn_urlencode "$path")" "$dest" "$(zn_urlencode "$name")"
}

clientgen_trojan(){
  local ip="$1" port="$2" pwd="$3" sni="${4:-www.bing.com}" name="${5:-$ZN_CHANNEL_NAME-Trojan}"
  printf 'trojan://%s@%s:%s?security=tls&sni=%s&allowInsecure=1&type=tcp#%s' \
    "$(zn_urlencode "$pwd")" "$ip" "$port" "$sni" "$(zn_urlencode "$name")"
}

clientgen_hysteria2(){
  local ip="$1" port="$2" pwd="$3" obfs="$4" sni="${5:-www.bing.com}" name="${6:-$ZN_CHANNEL_NAME-Hysteria2}"
  printf 'hysteria2://%s@%s:%s/?insecure=1&sni=%s&obfs=salamander&obfs-password=%s#%s' \
    "$(zn_urlencode "$pwd")" "$ip" "$port" "$sni" "$(zn_urlencode "$obfs")" "$(zn_urlencode "$name")"
}

clientgen_qr(){
  if command -v qrencode >/dev/null 2>&1; then
    qrencode -t ANSIUTF8 "$1" 2>/dev/null || qrencode -t UTF8 "$1" 2>/dev/null || true
  else
    zn_yellow "未安装 qrencode，跳过二维码（可执行: zn client qr <链接>）"
  fi
}

# ---------- sing-box outbound ----------
clientgen_singbox_vless(){
  local ip="$1" uuid="$2" port="$3" dest="$4" pbk="$5" sid="$6" flow="${7:-}" tag="${8:-$ZN_CHANNEL_NAME}"
  printf '{"type":"vless","tag":"%s","server":"%s","server_port":%s,"uuid":"%s","packet_encoding":"xudp"' \
    "$(zn_json_escape "$tag")" "$ip" "$port" "$uuid"
  [[ -n "$flow" ]] && printf ',"flow":"%s"' "$flow"
  printf ',"tls":{"enabled":true,"server_name":"%s","utls":{"enabled":true,"fingerprint":"chrome"},"reality":{"enabled":true,"public_key":"%s","short_id":"%s"}}' \
    "$dest" "$pbk" "$sid"
  printf '}'
}

clientgen_singbox_xhttp(){
  local ip="$1" uuid="$2" port="$3" dest="$4" pbk="$5" sid="$6" path="$7" tag="${8:-$ZN_CHANNEL_NAME}"
  printf '{"type":"vless","tag":"%s","server":"%s","server_port":%s,"uuid":"%s","packet_encoding":"xudp","tls":{"enabled":true,"server_name":"%s","utls":{"enabled":true,"fingerprint":"chrome"},"reality":{"enabled":true,"public_key":"%s","short_id":"%s"}},"transport":{"type":"xhttp","host":"%s","path":"%s","mode":"auto"}}' \
    "$(zn_json_escape "$tag")" "$ip" "$port" "$uuid" "$dest" "$pbk" "$sid" "$dest" "$path"
}

clientgen_singbox_trojan(){
  local ip="$1" port="$2" pwd="$3" sni="${4:-www.bing.com}" tag="${5:-$ZN_CHANNEL_NAME-Trojan}"
  printf '{"type":"trojan","tag":"%s","server":"%s","server_port":%s,"password":"%s","tls":{"enabled":true,"server_name":"%s","insecure":true}}' \
    "$(zn_json_escape "$tag")" "$ip" "$port" "$pwd" "$sni"
}

clientgen_singbox_hysteria2(){
  local ip="$1" port="$2" pwd="$3" obfs="$4" sni="${5:-www.bing.com}" tag="${6:-$ZN_CHANNEL_NAME-Hysteria2}"
  printf '{"type":"hysteria2","tag":"%s","server":"%s","server_port":%s,"password":"%s","tls":{"enabled":true,"server_name":"%s","insecure":true},"obfs":{"type":"salamander","password":"%s"}}' \
    "$(zn_json_escape "$tag")" "$ip" "$port" "$pwd" "$sni" "$obfs"
}

# ---------- Clash Meta proxy ----------
clientgen_clash_vless(){
  local name="$1" ip="$2" port="$3" uuid="$4" dest="$5" pbk="$6" sid="$7" flow="$8"
  cat <<EOF
  - name: "$name"
    type: vless
    server: $ip
    port: $port
    uuid: $uuid
    network: tcp
    udp: true
    tls: true
    flow: $flow
    servername: $dest
    client-fingerprint: chrome
    reality-opts:
      public-key: $pbk
      short-id: $sid
EOF
}

clientgen_clash_xhttp(){
  local name="$1" ip="$2" port="$3" uuid="$4" dest="$5" pbk="$6" sid="$7" path="$8"
  cat <<EOF
  - name: "$name"
    type: vless
    server: $ip
    port: $port
    uuid: $uuid
    network: xhttp
    udp: true
    tls: true
    servername: $dest
    client-fingerprint: chrome
    reality-opts:
      public-key: $pbk
      short-id: $sid
    xhttp-opts:
      path: $path
      host: $dest
      mode: auto
EOF
}

clientgen_clash_trojan(){
  local name="$1" ip="$2" port="$3" pwd="$4" sni="${5:-www.bing.com}"
  cat <<EOF
  - name: "$name"
    type: trojan
    server: $ip
    port: $port
    password: $pwd
    sni: $sni
    skip-cert-verify: true
    udp: true
EOF
}

clientgen_clash_hysteria2(){
  local name="$1" ip="$2" port="$3" pwd="$4" obfs="$5" sni="${6:-www.bing.com}"
  cat <<EOF
  - name: "$name"
    type: hysteria2
    server: $ip
    port: $port
    password: $pwd
    obfs: salamander
    obfs-password: $obfs
    sni: $sni
    skip-cert-verify: true
    up: "100 Mbps"
    down: "300 Mbps"
EOF
}

# ---------- 汇总生成（读凭证，写 sub 目录） ----------
clientgen_all_links(){
  source "$ZN_ROOT/lib/credential.sh"
  local ip uri
  ip="$(zn_public_ipv4)"
  [[ -n "$ip" ]] || ip="$(zn_public_ipv6)"
  [[ -n "$ip" ]] || { zn_log_error "clientgen" "无法获取公网 IP"; return 1; }
  ZN_LINKS=()
  ZN_LINK_NAMES=()

  if proto_installed hysteria2 2>/dev/null; then
    uri="$(clientgen_hysteria2 "$ip" "$(cred_get hysteria2.port)" "$(cred_get hysteria2.password)" \
      "$(cred_get hysteria2.obfs)" "$(cred_get hysteria2.sni)")"
    ZN_LINKS+=("$uri"); ZN_LINK_NAMES+=("hysteria2")
  fi
  if proto_installed vless 2>/dev/null; then
    local subs uuid pbk sid dest
    subs="$(cred_get xray.subs)"
    uuid="$(cred_get xray.uuid)"; pbk="$(cred_get xray.reality.public_key)"
    sid="$(cred_get xray.reality.short_id)"; dest="$(cred_get xray.dest)"
    local sub
    for sub in $subs; do
      case "$sub" in
        vision)
          uri="$(clientgen_vless_vision "$ip" "$uuid" "$(cred_get xray.vision.port)" "$dest" "$pbk" "$sid")"
          ZN_LINKS+=("$uri"); ZN_LINK_NAMES+=("vision")
          ;;
        xhttp)
          uri="$(clientgen_vless_xhttp "$ip" "$uuid" "$(cred_get xray.xhttp.port)" "$dest" "$pbk" "$sid" "$(cred_get xray.xhttp.path)")"
          ZN_LINKS+=("$uri"); ZN_LINK_NAMES+=("xhttp")
          ;;
        trojan)
          uri="$(clientgen_trojan "$ip" "$(cred_get xray.trojan.port)" "$(cred_get xray.trojan.password)")"
          ZN_LINKS+=("$uri"); ZN_LINK_NAMES+=("trojan")
          ;;
      esac
    done
  fi
  printf '%s\n' "${ZN_LINKS[@]:-}"
}

clientgen_display_name(){
  case "$1" in
    hysteria2) echo "$ZN_CHANNEL_NAME-Hysteria2" ;;
    vision)    echo "$ZN_CHANNEL_NAME-Vision" ;;
    xhttp)     echo "$ZN_CHANNEL_NAME-XHTTP" ;;
    trojan)    echo "$ZN_CHANNEL_NAME-Trojan" ;;
    *)         echo "$ZN_CHANNEL_NAME-$1" ;;
  esac
}

clientgen_write_sub(){
  local ip
  source "$ZN_ROOT/lib/credential.sh"
  ip="$(zn_public_ipv4)"
  [[ -n "$ip" ]] || ip="$(zn_public_ipv6)"
  mkdir -p "$ZN_SUB_DIR"
  # 必须在当前 shell 填充数组（命令替换会丢失）
  clientgen_all_links >/dev/null || { zn_log_warn "clientgen" "无法生成链接"; return 1; }
  [[ ${#ZN_LINKS[@]} -gt 0 ]] || { zn_log_warn "clientgen" "没有已安装协议可生成订阅"; return 1; }

  local i name uri label singbox

  # 纯链接订阅（v2ray/小火箭等）
  printf '# %s %s\n# 更新: %s\n' "$ZN_CHANNEL_NAME" "$ZN_CHANNEL_HANDLE" "$(date '+%Y-%m-%d %H:%M:%S')" > "$ZN_SUB_DIR/sub.txt"
  for uri in "${ZN_LINKS[@]}"; do
    printf '%s\n' "$uri" >> "$ZN_SUB_DIR/sub.txt"
  done
  chmod 600 "$ZN_SUB_DIR/sub.txt"

  # Clash Meta
  printf '# %s %s\n# 更新: %s\nproxies:\n' "$ZN_CHANNEL_NAME" "$ZN_CHANNEL_HANDLE" "$(date '+%Y-%m-%d %H:%M:%S')" > "$ZN_SUB_DIR/clash.yaml"
  for ((i = 0; i < ${#ZN_LINK_NAMES[@]}; i++)); do
    name="${ZN_LINK_NAMES[$i]}"
    label="$(clientgen_display_name "$name")"
    case "$name" in
      hysteria2)
        clientgen_clash_hysteria2 "$label" "$ip" "$(cred_get hysteria2.port)" "$(cred_get hysteria2.password)" "$(cred_get hysteria2.obfs)" "$(cred_get hysteria2.sni)" >> "$ZN_SUB_DIR/clash.yaml"
        ;;
      vision)
        clientgen_clash_vless "$label" "$ip" "$(cred_get xray.vision.port)" "$(cred_get xray.uuid)" "$(cred_get xray.dest)" "$(cred_get xray.reality.public_key)" "$(cred_get xray.reality.short_id)" xtls-rprx-vision >> "$ZN_SUB_DIR/clash.yaml"
        ;;
      xhttp)
        clientgen_clash_xhttp "$label" "$ip" "$(cred_get xray.xhttp.port)" "$(cred_get xray.uuid)" "$(cred_get xray.dest)" "$(cred_get xray.reality.public_key)" "$(cred_get xray.reality.short_id)" "$(cred_get xray.xhttp.path)" >> "$ZN_SUB_DIR/clash.yaml"
        ;;
      trojan)
        clientgen_clash_trojan "$label" "$ip" "$(cred_get xray.trojan.port)" "$(cred_get xray.trojan.password)" >> "$ZN_SUB_DIR/clash.yaml"
        ;;
    esac
  done
  cat >> "$ZN_SUB_DIR/clash.yaml" <<'EOF'

proxy-groups:
  - name: "🚀 节点选择"
    type: select
    proxies:
      - "♻️ 自动选择"
      - "DIRECT"
  - name: "♻️ 自动选择"
    type: url-test
    url: "http://www.gstatic.com/generate_204"
    interval: 300
    proxies:
EOF
  for name in "${ZN_LINK_NAMES[@]}"; do
    printf '      - "%s"\n' "$(clientgen_display_name "$name")" >> "$ZN_SUB_DIR/clash.yaml"
  done
  cat >> "$ZN_SUB_DIR/clash.yaml" <<'EOF'
rules:
  - "MATCH,🚀 节点选择"
EOF
  chmod 600 "$ZN_SUB_DIR/clash.yaml"

  # sing-box
  singbox=""
  for ((i = 0; i < ${#ZN_LINK_NAMES[@]}; i++)); do
    name="${ZN_LINK_NAMES[$i]}"
    [[ $i -gt 0 ]] && singbox+=","
    case "$name" in
      hysteria2)
        singbox+="$(clientgen_singbox_hysteria2 "$ip" "$(cred_get hysteria2.port)" "$(cred_get hysteria2.password)" "$(cred_get hysteria2.obfs)" "$(cred_get hysteria2.sni)" "$(clientgen_display_name "$name")")"
        ;;
      vision)
        singbox+="$(clientgen_singbox_vless "$ip" "$(cred_get xray.uuid)" "$(cred_get xray.vision.port)" "$(cred_get xray.dest)" "$(cred_get xray.reality.public_key)" "$(cred_get xray.reality.short_id)" xtls-rprx-vision "$(clientgen_display_name "$name")")"
        ;;
      xhttp)
        singbox+="$(clientgen_singbox_xhttp "$ip" "$(cred_get xray.uuid)" "$(cred_get xray.xhttp.port)" "$(cred_get xray.dest)" "$(cred_get xray.reality.public_key)" "$(cred_get xray.reality.short_id)" "$(cred_get xray.xhttp.path)" "$(clientgen_display_name "$name")")"
        ;;
      trojan)
        singbox+="$(clientgen_singbox_trojan "$ip" "$(cred_get xray.trojan.port)" "$(cred_get xray.trojan.password)" www.bing.com "$(clientgen_display_name "$name")")"
        ;;
    esac
  done
  printf '[\n%s\n]\n' "$singbox" > "$ZN_SUB_DIR/singbox.json"
  chmod 600 "$ZN_SUB_DIR/singbox.json"

  zn_log_info "clientgen" "订阅已生成到 $ZN_SUB_DIR (sub.txt / clash.yaml / singbox.json)"
}
