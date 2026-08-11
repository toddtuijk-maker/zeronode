#!/usr/bin/env bash
#
# deploy.sh - 智能部署编排（单协议 / 批量 / IP / 域名）
#

# 收集用户参数并写入凭证；全部回车可随机
deploy_collect_params(){
  local mode="$1" domain="${2:-}" protos="$3" subs="$4"
  source "$ZN_ROOT/lib/credential.sh"
  local proto

  if [[ -n "$domain" ]]; then
    cred_set "deploy.domain" "$domain"
  fi

  # UUID（VLESS 用户）
  local uuid
  uuid="$(cred_get deploy.uuid)"
  [[ -n "$uuid" ]] || {
    while true; do
      zn_prompt uuid "设置用户 UUID（回车随机生成）" "$(zn_random_uuid)" || return 1
      zn_valid_uuid "$uuid" && break
      zn_red "UUID 格式不正确，请重新输入"
    done
    cred_set "deploy.uuid" "$uuid"
    cred_set "xray.uuid" "$uuid"
  }

  # Hysteria2 端口
  if [[ "$protos" == *hysteria2* ]]; then
    local key="deploy.port.hysteria2"
    local p
    p="$(cred_get "$key")"
    if [[ -z "$p" ]]; then
      zn_prompt p "设置 hysteria2 端口（回车随机）" "$(zn_random_port)" || return 1
      cred_set "$key" "$p"
    fi
  fi

  # xray 子协议端口
  for proto in $subs; do
    local key="deploy.port.$proto"
    local p
    p="$(cred_get "$key")"
    if [[ -z "$p" ]]; then
      zn_prompt p "设置 $proto 端口（回车随机）" "$(zn_random_port)" || return 1
      cred_set "$key" "$p"
    fi
  done

  local pwd
  if [[ "$protos" == *hysteria2* ]]; then
    pwd="$(cred_get deploy.hysteria2.password)"
    [[ -n "$pwd" ]] || {
      while true; do
        zn_prompt pwd "设置 Hysteria2 密码（回车随机，至少 8 位）" "$(zn_random_password 16)" || return 1
        zn_valid_password "$pwd" && break
        zn_red "密码需至少 8 位，且只能包含字母数字和 !@%^*()_-+=.,; 等字符"
      done
      cred_set "deploy.hysteria2.password" "$pwd"
    }
    local obfs
    obfs="$(cred_get deploy.hysteria2.obfs)"
    [[ -n "$obfs" ]] || {
      while true; do
        zn_prompt obfs "设置 Hysteria2 obfs 密码（回车随机）" "$(zn_random_password 12)" || return 1
        zn_valid_password "$obfs" && break
        zn_red "obfs 密码需至少 8 位，且只能包含安全字符"
      done
      cred_set "deploy.hysteria2.obfs" "$obfs"
    }
  fi
  local tpwd
  if [[ "$subs" == *trojan* ]]; then
    tpwd="$(cred_get deploy.trojan.password)"
    [[ -n "$tpwd" ]] || {
      while true; do
        zn_prompt tpwd "设置 Trojan 密码（回车随机）" "$(zn_random_password 20)" || return 1
        zn_valid_password "$tpwd" && break
        zn_red "密码需至少 8 位，且只能包含安全字符"
      done
      cred_set "deploy.trojan.password" "$tpwd"
    }
  fi
}

# 将 deploy.* 参数映射到协议凭证
deploy_apply_params(){
  source "$ZN_ROOT/lib/credential.sh"
  # Docker 环境：自动探索可出网(已映射)端口作为默认
  # shellcheck source=lib/docker.sh
  source "$ZN_ROOT/lib/docker.sh"
  if docker_detect; then
    zn_yellow "检测到 Docker 环境，自动探测可出网端口 ..."
    if [[ "$(docker_net_mode)" == "host" ]]; then
      zn_yellow "host 网络模式：无需探测，直接使用随机端口"
    else
      local found tcp_defaults=() i
      while IFS= read -r found; do
        [[ -n "$found" ]] && tcp_defaults+=("$found")
      done < <(docker_discover_tcp_ports 3)
      for i in "${!tcp_defaults[@]}"; do
        case "$i" in
          0) [[ -z "$(cred_get xray.vision.port)" ]] && cred_set xray.vision.port "${tcp_defaults[0]}" ;;
          1) [[ -z "$(cred_get xray.xhttp.port)" ]] && cred_set xray.xhttp.port "${tcp_defaults[1]}" ;;
          2) [[ -z "$(cred_get xray.trojan.port)" ]] && cred_set xray.trojan.port "${tcp_defaults[2]}" ;;
        esac
      done
    fi
    zn_yellow "注意: Hysteria2 使用 UDP，Docker 需确保 -p <port>:<port>/udp 已映射"
  fi
  local domain uuid
  domain="$(cred_get deploy.domain)"
  uuid="$(cred_get deploy.uuid)"
  [[ -n "$uuid" ]] && cred_set "xray.uuid" "$uuid"

  local p
  p="$(cred_get deploy.port.hysteria2)";  [[ -n "$p" ]] && cred_set hysteria2.port "$p"
  p="$(cred_get deploy.port.vision)";     [[ -n "$p" ]] && cred_set xray.vision.port "$p"
  p="$(cred_get deploy.port.xhttp)";      [[ -n "$p" ]] && cred_set xray.xhttp.port "$p"
  p="$(cred_get deploy.port.trojan)";     [[ -n "$p" ]] && cred_set xray.trojan.port "$p"
  p="$(cred_get deploy.hysteria2.password)"; [[ -n "$p" ]] && cred_set hysteria2.password "$p"
  p="$(cred_get deploy.hysteria2.obfs)";     [[ -n "$p" ]] && cred_set hysteria2.obfs "$p"
  p="$(cred_get deploy.trojan.password)";    [[ -n "$p" ]] && cred_set xray.trojan.password "$p"
}

deploy_run(){
  local mode="${1:-security}" scope="${2:-batch}" domain="${3:-}"
  zn_require_root
  source "$ZN_ROOT/protocols/interface.sh"
  source "$ZN_ROOT/lib/envcheck.sh"
  source "$ZN_ROOT/lib/clientgen.sh"
  source "$ZN_ROOT/lib/config_manager.sh"
  source "$ZN_ROOT/lib/credential.sh"

  zn_log_info "deploy" "开始部署（模式: $mode, 范围: $scope, 域名: ${domain:-无}）"
  envcheck_run "$mode" || true
  envcheck_gate || { zn_log_error "deploy" "环境检查未通过"; return 1; }

  # 内核选择：默认 sing-box，可 ZN_KERNEL=xray 或凭据 deploy.kernel 覆盖
  local kernel subs="" protos="" tokens t has_vless=0
  kernel="${ZN_KERNEL:-$(cred_get deploy.kernel)}"
  [[ -n "$kernel" ]] || kernel="singbox"
  [[ "$kernel" == "singbox" || "$kernel" == "xray" ]] || kernel="singbox"
  cred_set "deploy.kernel" "$kernel"
  zn_yellow "当前 VLESS 内核: $kernel（默认推荐 sing-box，可在菜单/环境变量切换）"

  case "$scope" in
    hysteria2) protos="hysteria2" ;;
    vision)    subs="vision" ; protos="$kernel" ;;
    xhttp)     subs="xhttp" ; protos="$kernel" ;;
    trojan)    subs="trojan" ; protos="$kernel" ;;
    batch|*)
      tokens="$(policy_recommend "$mode")"
      for t in $tokens; do
        case "$t" in
          hysteria2) protos="$protos hysteria2" ;;
          vision|xhttp|trojan) subs="$subs $t" ; has_vless=1 ;;
        esac
      done
      [[ "$has_vless" == "1" ]] && protos="$protos $kernel"
      [[ -z "$protos" ]] && protos="hysteria2 $kernel"
      ;;
  esac
  subs="$(echo "$subs" | xargs)"

  # 交互收集参数（可全回车随机）
  if [[ -t 0 ]]; then
    deploy_collect_params "$mode" "$domain" "$protos" "$subs" || return 1
  fi
  deploy_apply_params

  local proto
  for proto in $protos; do
    case "$proto" in
      hysteria2)
        proto_load hysteria2
        if [[ -n "$domain" ]]; then
          proto_install_hysteria2 "domain" "$domain" || return 1
        else
          proto_install_hysteria2 "ip" || return 1
        fi
        ;;
      xray)
        proto_load xray
        if [[ -n "$domain" ]]; then
          proto_install_xray "domain" "$domain" "$subs" || return 1
        else
          proto_install_xray "ip" "" "$subs" || return 1
        fi
        ;;
      singbox)
        proto_load singbox
        if [[ -n "$domain" ]]; then
          proto_install_singbox "domain" "$domain" "$subs" || return 1
        else
          proto_install_singbox "ip" "" "$subs" || return 1
        fi
        ;;
    esac
  done

  clientgen_write_sub || true
  zn_audit "deploy" "all" "ok" "mode=$mode scope=$scope"
}
