#!/usr/bin/env bash
#
# stealth.sh - 隐蔽策略引擎
# 职责：选择 REALITY dest / 伪装网站 / XHTTP 路径；未授权访问响应策略
#

# 可信目标站清单（支持 TLS1.3 + HTTP/2，REALITY 借用其证书）
STEALTH_REALITY_DESTS=(
  "www.microsoft.com"
  "www.apple.com"
  "www.cloudflare.com"
  "www.samsung.com"
  "dl.google.com"
  "www.amazon.com"
  "swdist.apple.com"
)

# 伪装网站清单（Hysteria2 masquerade / 未授权响应）
STEALTH_MASQUERADE_SITES=(
  "en.snu.ac.kr"
  "www.bing.com"
  "www.wikipedia.org"
  "www.office.com"
  "www.gstatic.com"
  "news.ycombinator.com"
)

# 稳定随机选取：结果写入 credentials（stealth.<kind>），节点不变则结果不变；可被用户覆盖
stealth_pick(){
  local kind="$1"
  local key="stealth.$kind" val list
  # shellcheck source=lib/credential.sh
  source "$ZN_ROOT/lib/credential.sh"
  val="$(cred_get "$key")"
  if [[ -n "$val" ]]; then
    printf '%s' "$val"
    return 0
  fi
  case "$kind" in
    reality_dest) list=("${STEALTH_REALITY_DESTS[@]}") ;;
    masquerade)   list=("${STEALTH_MASQUERADE_SITES[@]}") ;;
    *) zn_die "未知 stealth 类型: $kind" ;;
  esac
  val="${list[$((RANDOM % ${#list[@]}))]}"
  cred_set "$key" "$val"
  printf '%s' "$val"
}

# 覆盖默认选取（用户自定义）
stealth_set(){
  local kind="$1" val="$2"
  source "$ZN_ROOT/lib/credential.sh"
  cred_set "stealth.$kind" "$val"
}

# 生成随机 XHTTP 路径（防固定指纹）
stealth_xhttp_path(){
  printf '/%s' "$(zn_random_hex 8)"
}

# 未授权访问响应策略描述（可配置）
stealth_response_policy(){
  local proto="$1"
  case "$proto" in
    xray)
      # REALITY 内置：未授权连接转发到 dest，客户端看到目标站证书/页面，无明显错误特征
      echo "reality-forward"
      ;;
    hysteria2)
      echo "masquerade-proxy"
      ;;
    *)
      echo "default"
      ;;
  esac
}

# 指纹（客户端伪装指纹，默认 chrome）
stealth_fingerprint(){
  echo "chrome"
}

# 证书策略说明（安装界面展示）
stealth_cert_policy(){
  local mode="${1:-ip}"
  if [[ "$mode" == "domain" ]]; then
    echo "域名模式：Hysteria2 使用 acme.sh 申请 Let's Encrypt 正式证书（可信）"
  else
    echo "IP 模式：REALITY 借用目标站证书（客户端可信）；Hysteria2 使用自签证书（客户端 insecure=1，属协议预期）"
  fi
}
