#!/usr/bin/env bash
#
# ui.sh - 终端 UI（横幅 / 菜单 / 进度 / 作者频道）
#

ui_banner(){
  printf '%b\n' "$ZN_CYAN"
  cat <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║    ███████╗███████╗██████╗  ██████╗ ███╗   ██╗ ██████╗ ██████╗ ███████╗
║    ╚══███╔╝██╔════╝██╔══██╗██╔═══██╗████╗  ██║██╔════╝██╔═══██╗██╔════╝
║      ███╔╝ █████╗  ██████╔╝██║   ██║██╔██╗ ██║██║     ██║   ██║█████╗
║     ███╔╝  ██╔══╝  ██╔══██╗██║   ██║██║╚██╗██║██║     ██║   ██║██╔══╝
║    ███████╗███████╗██║  ██║╚██████╔╝██║ ╚████║╚██████╗╚██████╔╝███████╗
║    ╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝
║                                                              ║
║               ZeroNode · 零号节点管理平台                      ║
║    ──────────────────────────────────────────────────────     ║
║    作者频道: 零号协议 @linghaoxieyi                           ║
║    安全 · 稳定 · 隐蔽 · 易扩展                                ║
╚══════════════════════════════════════════════════════════════╝
EOF
  printf '%b\n' "$ZN_PLAIN"
}

ui_title(){
  printf '%b\n' "${ZN_BOLD}${ZN_GREEN}──────────────── $1 ────────────────${ZN_PLAIN}"
}

ui_item(){
  printf '  %b[%s]%b %s\n' "$ZN_CYAN" "$1" "$ZN_PLAIN" "$2"
}

ui_hr(){
  printf '%s\n' "──────────────────────────────────────────────────"
}

ui_channel_line(){
  printf '%b\n' "${ZN_YELLOW}──────────────────────────────────────────────────${ZN_PLAIN}"
  printf '%b\n' "${ZN_BOLD}${ZN_RED}  作者频道: 零号协议 @linghaoxieyi ${ZN_PLAIN}"
  printf '%b\n' "${ZN_YELLOW}──────────────────────────────────────────────────${ZN_PLAIN}"
}

# 显示全部链接 + 二维码
ui_show_links(){
  source "$ZN_ROOT/lib/clientgen.sh"
  source "$ZN_ROOT/lib/credential.sh"
  local links names i uri
  links="$(clientgen_all_links)"
  [[ -n "$links" ]] || { zn_yellow "暂无已安装协议"; return 1; }
  names=("${ZN_LINK_NAMES[@]:-}")
  ui_channel_line
  i=0
  while IFS= read -r uri; do
    local label="${names[$i]:-node$i}"
    printf '%b%s: %b%s%b\n' "$ZN_GREEN" "$label" "$ZN_CYAN" "$uri" "$ZN_PLAIN"
    clientgen_qr "$uri"
    echo ""
    i=$((i + 1))
  done <<< "$links"
  ui_channel_line
}
