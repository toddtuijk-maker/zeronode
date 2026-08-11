#!/usr/bin/env bash
#
# entrypoint.sh - ZeroNode 生产容器入口
# 用法:
#   docker run -d --network host --name zeronode -v zeronode-data:/var/lib/zeronode zeronode
#   docker run -d -p 443:443 -p 8443:8443 -p 5678:5678/udp ... -e ZN_AUTO_INSTALL=1 zeronode
#

set -euo pipefail

export ZN_ROOT="${ZN_ROOT:-/opt/zeronode}"
export ZN_STATE="${ZN_STATE:-/var/lib/zeronode}"
export ZN_CONF="${ZN_CONF:-/etc/zeronode.conf}"

source "$ZN_ROOT/lib/common.sh"
source "$ZN_ROOT/lib/logging.sh"
source "$ZN_ROOT/lib/credential.sh"
source "$ZN_ROOT/lib/db.sh"
source "$ZN_ROOT/protocols/interface.sh"

zn_state_init
cred_init
db_init 2>/dev/null || true
zn_log_rotate

if [[ "${ZN_AUTO_INSTALL:-0}" == "1" ]]; then
  zn_log_info "container" "自动安装模式: mode=${ZN_DEPLOY_MODE:-security} scope=${ZN_DEPLOY_SCOPE:-batch} domain=${ZN_DOMAIN:-无}"
  source "$ZN_ROOT/lib/deploy.sh"
  deploy_run "${ZN_DEPLOY_MODE:-security}" "${ZN_DEPLOY_SCOPE:-batch}" "${ZN_DOMAIN:-}"
  source "$ZN_ROOT/lib/clientgen.sh"
  clientgen_write_sub || true
fi

exec "$ZN_ROOT/bin/zn-daemon" serve
