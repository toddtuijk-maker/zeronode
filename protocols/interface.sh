#!/usr/bin/env bash
#
# interface.sh - Protocol Interface 契约与分发器
#
# 每个协议模块必须实现（<name> 为模块名）:
#   proto_install_<name> <mode:ip|domain> [domain]
#   proto_remove_<name>
#   proto_restart_<name>
#   proto_status_<name>
#   proto_health_<name>          # 0=ok 1=fail
#   proto_validate_<name> <file> # 0=valid
#   proto_config_path_<name>
#   proto_version_<name>
#   proto_links_<name>
#   proto_meta_<name>_needs_domain  # 输出 0/1
#   proto_meta_<name>_display_name
#   proto_meta_<name>_transport
#   proto_meta_<name>_systemd_unit
# 可选:
#   proto_meta_<name>_deps          # 依赖文件（备份用）
#   proto_meta_<name>_config_perms  # 默认 644
#   proto_meta_<name>_config_owner  # 默认 root:root
#

export ZN_PROTOCOLS="${ZN_PROTOCOLS:-}"

proto_register(){
  local name="$1"
  [[ " $ZN_PROTOCOLS " == *" $name "* ]] || ZN_PROTOCOLS="$ZN_PROTOCOLS $name"
}

proto_load(){
  local name="$1"
  local f="$ZN_ROOT/protocols/$name.sh"
  if [[ ! -f "$f" ]]; then
    zn_log_error "protocol" "协议模块不存在: $name"
    return 1
  fi
  # shellcheck source=protocols/hysteria2.sh
  source "$f"
  proto_register "$name"
}

proto_dispatch(){
  local action="$1" name="$2"
  shift 2
  local fn="proto_${action}_${name}"
  if [[ "$(type -t "$fn")" == "function" ]]; then
    "$fn" "$@"
  elif [[ "$action" == "meta" ]]; then
    # meta 走独立字段函数
    local field="$1"
    fn="proto_meta_${name}_${field}"
    if [[ "$(type -t "$fn")" == "function" ]]; then
      "$fn"
    fi
  else
    zn_log_error "protocol" "协议 $name 未实现 $action"
    return 1
  fi
}

proto_meta(){
  local name="$1" field="$2"
  proto_dispatch meta "$name" "$field"
}

proto_installed(){
  local name="$1"
  source "$ZN_ROOT/lib/credential.sh"
  [[ "$(cred_get "state.$name.installed" 2>/dev/null)" == "1" ]]
}

proto_mark_installed(){
  local name="$1" val="${2:-1}"
  source "$ZN_ROOT/lib/credential.sh"
  cred_set "state.$name.installed" "$val"
}

proto_list_available(){
  # 扫描 protocols/ 目录（排除 interface/_template）
  local f
  for f in "$ZN_ROOT"/protocols/*.sh; do
    local b
    b="$(basename "$f" .sh)"
    [[ "$b" == "interface" || "$b" == "_template" ]] && continue
    printf '%s\n' "$b"
  done
}

proto_load_all(){
  local name
  for name in $(proto_list_available); do
    proto_load "$name" 2>/dev/null || true
  done
}

proto_show_meta(){
  local name="$1"
  printf '%-12s %-8s %-8s %s\n' \
    "$name" \
    "$(proto_meta "$name" transport)" \
    "$( [[ "$(proto_meta "$name" needs_domain)" == "1" ]] && echo 需域名 || echo IP即可 )" \
    "$(proto_meta "$name" display_name)"
}
