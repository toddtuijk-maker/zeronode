#!/usr/bin/env bash
#
# hysteria2.sh - Hysteria 2 协议模块（Hysteria2 + TLS + obfs salamander）
#

HY2_CONFIG="/etc/hysteria/config.yaml"
HY2_BIN="/usr/local/bin/hysteria"
HY2_UNIT="hysteria-server"
HY2_VENDOR="$ZN_ROOT/vendor/install_server.sh"

proto_meta_hysteria2_needs_domain(){ echo 0; }
proto_meta_hysteria2_display_name(){ echo "Hysteria 2 + TLS + obfs"; }
proto_meta_hysteria2_transport(){ echo "udp"; }
proto_meta_hysteria2_systemd_unit(){ echo "$HY2_UNIT"; }
proto_meta_hysteria2_run_cmd(){ echo "$HY2_BIN server -c $HY2_CONFIG"; }
proto_meta_hysteria2_config_perms(){ echo 640; }
proto_meta_hysteria2_config_owner(){ echo "root:hysteria"; }
proto_meta_hysteria2_deps(){
  echo "/etc/hysteria/cert.crt /etc/hysteria/private.key"
}

proto_config_path_hysteria2(){ echo "$HY2_CONFIG"; }

proto_version_hysteria2(){
  [[ -x "$HY2_BIN" ]] || return 1
  "$HY2_BIN" version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

hy2_installed(){
  [[ -x "$HY2_BIN" ]] && [[ -f "$HY2_CONFIG" ]]
}

proto_restart_hysteria2(){
  # shellcheck source=lib/system.sh
  source "$ZN_ROOT/lib/system.sh"
  system_service_restart "$HY2_UNIT" $HY2_BIN server -c "$HY2_CONFIG"
}

proto_status_hysteria2(){
  if hy2_installed; then
    # shellcheck source=lib/system.sh
    source "$ZN_ROOT/lib/system.sh"
    system_service_active "$HY2_UNIT" && echo active || echo inactive
  else
    echo not-installed
  fi
}

proto_health_hysteria2(){
  # shellcheck source=lib/system.sh
  source "$ZN_ROOT/lib/system.sh"
  system_service_active "$HY2_UNIT" || return 1
  local port
  port="$(cred_get hysteria2.port)"
  [[ -n "$port" ]] && zn_port_in_use_udp "$port" || return 1
  return 0
}

proto_validate_hysteria2(){
  local f="$1"
  [[ -f "$f" && -s "$f" ]] || { zn_log_error "hysteria2" "配置校验失败: 文件不存在或为空 ($f)"; return 1; }
  # 必填字段检查
  grep -qE '^listen:' "$f" || { zn_log_error "hysteria2" "配置校验失败: 缺少 listen"; return 1; }
  grep -qE '^  cert:' "$f" || { zn_log_error "hysteria2" "配置校验失败: 缺少 cert"; return 1; }
  grep -qE '^  key:' "$f" || { zn_log_error "hysteria2" "配置校验失败: 缺少 key"; return 1; }
  grep -qE '^  password:' "$f" || { zn_log_error "hysteria2" "配置校验失败: 缺少 password"; return 1; }
  grep -qE '^  type: salamander' "$f" || { zn_log_error "hysteria2" "配置校验失败: 缺少 obfs"; return 1; }
  # 基础 YAML 健康检查：不允许制表符，不允许明显未闭合的引号
  if grep -q "$(printf '\t')" "$f"; then
    zn_log_error "hysteria2" "配置校验失败: 存在制表符"
    return 1
  fi
  return 0
}

# 校验已下载二进制与官方 hashes.txt 一致 + ELF 魔数
hy2_verify_binary(){
  [[ -x "$HY2_BIN" ]] || return 1
  local magic
  magic="$(head -c 4 "$HY2_BIN" | od -An -tx1 | tr -d ' \n')"
  [[ "$magic" == "7f454c46" ]] || return 1
  local ver arch hf expected actual
  ver="$(proto_version_hysteria2)"
  arch="$(zn_arch)"
  [[ -n "$ver" && "$arch" != "unknown" ]] || return 0
  hf="$(zn_tmp)"
  if ! curl -fsSL --retry 3 -m 60 -o "$hf" \
      "https://github.com/apernet/hysteria/releases/download/app/$ver/hashes.txt" 2>/dev/null; then
    zn_log_warn "hysteria2" "无法获取官方 hashes.txt，跳过哈希校验"
    return 0
  fi
  expected="$(grep -E "build/hysteria-linux-$arch([[:space:]]|$)" "$hf" | awk '{print $1}' | head -1)"
  actual="$(sha256sum "$HY2_BIN" | awk '{print $1}')"
  if [[ -z "$expected" ]]; then
    zn_log_warn "hysteria2" "官方清单无对应条目，跳过哈希校验"
    return 0
  fi
  [[ "$expected" == "$actual" ]]
}

hy2_install_core(){
  source "$ZN_ROOT/lib/system.sh"
  if system_has_systemd; then
    [[ -f "$HY2_VENDOR" ]] || zn_die "缺少 vendor/install_server.sh（Hysteria 官方安装器）"
    zn_log_info "hysteria2" "使用官方安装器安装 Hysteria 2 ..."
    if ! bash "$HY2_VENDOR"; then
      zn_log_error "hysteria2" "官方安装器执行失败"
      return 1
    fi
  else
    zn_log_info "hysteria2" "容器模式：手动下载官方二进制 ..."
    hy2_container_install || return 1
  fi
  hy2_verify_binary || {
    zn_log_error "hysteria2" "二进制完整性校验失败"
    return 1
  }
}

hy2_latest_version(){
  curl -fsSL -m 30 -H 'Accept: application/vnd.github.v3+json' \
    'https://api.github.com/repos/apernet/hysteria/releases/latest' 2>/dev/null \
    | grep '"tag_name"' | head -1 | sed -E 's/.*"app\/(v[0-9.]+)".*/\1/'
}

hy2_container_install(){
  local ver arch url tmp
  ver="$(hy2_latest_version)"
  arch="$(zn_arch)"
  [[ -n "$ver" && "$arch" != "unknown" ]] || return 1
  url="https://github.com/apernet/hysteria/releases/download/app/$ver/hysteria-linux-$arch"
  tmp="$(zn_tmp)"
  zn_log_info "hysteria2" "下载 $url"
  curl -fL --retry 3 -m 120 -o "$tmp" "$url" || return 1
  install -m755 "$tmp" "$HY2_BIN"
}

# 证书：ip → 自签；domain → acme 正式证书
hy2_issue_cert(){
  local mode="$1" domain="${2:-}"
  if [[ "$mode" == "domain" && -n "$domain" ]]; then
    zn_need_cmd_or_install openssl openssl
    local ip
    ip="$(zn_public_ipv4)"
    local domain_ip
    domain_ip="$(getent ahosts "$domain" 2>/dev/null | awk 'NR==1{print $1}')"
    if [[ -n "$ip" && -n "$domain_ip" && "$domain_ip" != "$ip" ]]; then
      zn_log_error "hysteria2" "域名 $domain 解析到 $domain_ip，与当前公网 IP $ip 不匹配"
      return 1
    fi
    mkdir -p /etc/hysteria
    # acme 自动续期依赖 cron（包名按发行版映射）
    source "$ZN_ROOT/lib/system.sh"
    system_ensure_cmd crontab cron || system_ensure_cmd crontab cronie || true
    # acme.sh 安装（下载到本地校验后再执行）
    local installer
    installer="$(zn_tmp)"
    curl -fsSL -m 60 https://get.acme.sh -o "$installer" || return 1
    grep -q "acme.sh" "$installer" || return 1
    bash "$installer" "email=$(zn_random_hex 16)@gmail.com"
    bash /root/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1 || true
    bash /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
    if [[ -n "$(zn_public_ipv6)" ]]; then
      bash /root/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 --listen-v6 --insecure \
        || bash /root/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 --insecure
    else
      bash /root/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 --insecure
    fi
    bash /root/.acme.sh/acme.sh --install-cert -d "$domain" \
      --key-file /etc/hysteria/private.key --fullchain-file /etc/hysteria/cert.crt --ecc
    bash /root/.acme.sh/acme.sh --install-cronjob >/dev/null 2>&1 || true
    printf '%s\n' "$domain" > /etc/hysteria/.domain
    chgrp hysteria /etc/hysteria/cert.crt 2>/dev/null || true
    chgrp hysteria /etc/hysteria/private.key 2>/dev/null || true
    chmod 644 /etc/hysteria/cert.crt
    chmod 640 /etc/hysteria/private.key
    cred_set "hysteria2.sni" "$domain"
  else
    zn_need_cmd_or_install openssl openssl
    mkdir -p /etc/hysteria
    openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/private.key
    openssl req -new -x509 -days 36500 -key /etc/hysteria/private.key \
      -out /etc/hysteria/cert.crt -subj "/CN=www.bing.com"
    chgrp hysteria /etc/hysteria/private.key 2>/dev/null || true
    chmod 640 /etc/hysteria/private.key
    chmod 644 /etc/hysteria/cert.crt
    cred_set "hysteria2.sni" "www.bing.com"
  fi
}

hy2_write_config(){
  local port pwd obfs site sni
  port="$(cred_get hysteria2.port)"
  pwd="$(cred_get hysteria2.password)"
  obfs="$(cred_get hysteria2.obfs)"
  site="$(cred_get hysteria2.site)"
  sni="$(cred_get hysteria2.sni)"
  local tmp
  tmp="$(zn_tmp)"
  printf 'listen: :%s\n\ntls:\n  cert: /etc/hysteria/cert.crt\n  key: /etc/hysteria/private.key\n\nobfs:\n  type: salamander\n  salamander:\n    password: %s\n\nauth:\n  type: password\n  password: %s\n\nmasquerade:\n  type: proxy\n  proxy:\n    url: https://%s\n    rewriteHost: true\n' \
    "$port" "$obfs" "$pwd" "$site" > "$tmp"
  printf '%s' "$tmp"
}

proto_install_hysteria2(){
  local mode="${1:-ip}" domain="${2:-}"
  zn_require_root
  source "$ZN_ROOT/lib/config_manager.sh"
  source "$ZN_ROOT/lib/credential.sh"
  source "$ZN_ROOT/lib/stealth.sh"

  zn_log_info "hysteria2" "开始安装 Hysteria 2（模式: $mode）"
  hy2_install_core || return 1

  local port pwd obfs site
  port="$(cred_get hysteria2.port)";   [[ -n "$port" ]] || port="$(zn_random_port)"
  pwd="$(cred_get hysteria2.password)"; [[ -n "$pwd" ]] || pwd="$(zn_random_password 16)"
  obfs="$(cred_get hysteria2.obfs)";   [[ -n "$obfs" ]] || obfs="$(zn_random_password 12)"
  site="$(cred_get hysteria2.site)";   [[ -n "$site" ]] || site="$(stealth_pick masquerade)"
  zn_yellow "端口: $port  密码: $pwd  obfs: $obfs  伪装: $site"
  cred_set "hysteria2.port" "$port"
  cred_set "hysteria2.password" "$pwd"
  cred_set "hysteria2.obfs" "$obfs"
  cred_set "hysteria2.site" "$site"

  hy2_issue_cert "$mode" "$domain" || return 1

  local tmp
  tmp="$(hy2_write_config)"
  cm_apply hysteria2 "$tmp" "install" || return 1

  source "$ZN_ROOT/lib/system.sh"
  system_fw_allow_udp "$port"
  system_service_enable "$HY2_UNIT" $HY2_BIN server -c "$HY2_CONFIG"
  proto_mark_installed hysteria2
  zn_audit "install" "hysteria2" "ok" "port=$port mode=$mode"
  zn_log_info "hysteria2" "Hysteria 2 安装完成，版本 $(proto_version_hysteria2)"
}

proto_remove_hysteria2(){
  zn_require_root
  zn_confirm "确认卸载 Hysteria 2？（配置与证书将备份到历史目录）" || return 1
  source "$ZN_ROOT/lib/config_manager.sh"
  cm_backup hysteria2
  # shellcheck source=lib/system.sh
  source "$ZN_ROOT/lib/system.sh"
  system_service_stop "$HY2_UNIT"
  if system_has_systemd; then
    rm -f /etc/systemd/system/hysteria-server.service /etc/systemd/system/hysteria-server@.service
  fi
  rm -f "$HY2_BIN"
  rm -rf /etc/hysteria
  system_has_systemd && systemctl daemon-reload >/dev/null 2>&1 || true
  proto_mark_installed hysteria2 0
  zn_audit "remove" "hysteria2" "ok"
}

proto_links_hysteria2(){
  source "$ZN_ROOT/lib/credential.sh"
  source "$ZN_ROOT/lib/clientgen.sh"
  local port pwd obfs site sni ip
  port="$(cred_get hysteria2.port)"
  pwd="$(cred_get hysteria2.password)"
  obfs="$(cred_get hysteria2.obfs)"
  site="$(cred_get hysteria2.site)"
  sni="$(cred_get hysteria2.sni)"
  ip="$(zn_public_ipv4)"
  [[ -n "$ip" ]] || ip="$(zn_public_ipv6)"
  clientgen_hysteria2 "$ip" "$port" "$pwd" "$obfs" "$sni"
}

# 轮换密码（走 Config Manager 全流程，失败自动回滚）
proto_rotate_hysteria2(){
  zn_require_root
  source "$ZN_ROOT/lib/config_manager.sh"
  local newpwd tmp
  newpwd="$(zn_random_password 16)"
  cred_rotate hysteria2.password "$newpwd"
  tmp="$(hy2_write_config)"
  if ! cm_apply hysteria2 "$tmp" "rotate-password"; then
    zn_log_error "hysteria2" "密码轮换失败"
    return 1
  fi
  zn_audit "rotate" "hysteria2" "ok"
  zn_log_info "hysteria2" "密码已轮换"
}
