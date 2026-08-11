#!/usr/bin/env bash
#
# ZeroNode 一键安装入口（零号节点管理平台）
# 作者频道: 零号协议 @linghaoxieyi
#
# 支持两种方式：
#   1) 单文件模式：wget install.sh && bash install.sh（自动从仓库拉取完整组件并校验）
#   2) 完整仓库模式：在克隆/解压的项目目录内执行（直接安装到 /opt/zeronode）
#

set -euo pipefail

export ZN_ROOT="${ZN_ROOT:-/opt/zeronode}"
export ZN_REPO_URL="${ZN_REPO_URL:-https://github.com/toddtuijk-maker/zeronode}"
export ZN_BRANCH="${ZN_BRANCH:-main}"

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# 任何步骤失败都给出明确位置与日志，避免“静默退出”
trap 'echo "[ZeroNode] 安装/管理过程发生错误，已中止（脚本第 $LINENO 行）。"; echo "最近日志: /var/lib/zeronode/logs/zeronode.log"; tail -n 20 /var/lib/zeronode/logs/zeronode.log 2>/dev/null || true' ERR

# ---------- 引导：判断是完整项目目录还是单文件 ----------
zn_has_full_tree(){
  [[ -f "$SOURCE_DIR/lib/common.sh" ]] \
    && [[ -f "$SOURCE_DIR/protocols/interface.sh" ]] \
    && [[ -f "$SOURCE_DIR/bin/zn" ]] \
    && [[ -f "$SOURCE_DIR/protocols/hysteria2.sh" ]]
}

# 只复制项目文件（绝不整目录拷贝，避免把 /root 下的 .ssh 等无关内容带进去）
zn_install_tree(){
  local src="$1" dst="$2" f
  [[ "$dst" == /* ]] || { echo "错误: 安装目录必须是绝对路径: $dst"; return 1; }
  mkdir -p "$dst"
  if [[ "$dst" == "/opt/zeronode" ]]; then
    # 默认专用安装目录：整体清空，避免此前失败安装/误拷贝残留的脏文件
    rm -rf "${dst:?}"/{*,.[!.]*} 2>/dev/null || true
    mkdir -p "$dst"
  else
    # 自定义目录：只清理已知项目子目录，保留用户其他内容
    for d in bin lib protocols vendor docs tests docker api .github; do
      [[ -e "$dst/$d" ]] && rm -rf "${dst:?}/$d"
    done
  fi
  for f in install.sh uninstall.sh README.md LICENSE CHANGELOG.md .gitignore; do
    [[ -f "$src/$f" ]] && cp -a "$src/$f" "$dst/"
  done
  for d in bin lib protocols vendor docs tests docker api; do
    [[ -d "$src/$d" ]] && cp -a "$src/$d" "$dst/"
  done
  [[ -d "$src/.github" ]] && cp -a "$src/.github" "$dst/"
  chmod +x "$dst/install.sh" "$dst/bin/zn" "$dst/bin/zn-daemon" 2>/dev/null || true
  # 完整性自检：关键文件必须存在
  for f in lib/common.sh lib/logging.sh lib/db.sh protocols/interface.sh \
           protocols/hysteria2.sh protocols/singbox.sh protocols/xray.sh bin/zn bin/zn-daemon; do
    [[ -f "$dst/$f" ]] || { echo "错误: 安装文件缺失 $dst/$f"; return 1; }
  done
  # 关键脚本语法校验
  for f in install.sh lib/common.sh protocols/interface.sh; do
    bash -n "$dst/$f" || { echo "错误: $dst/$f 语法校验失败"; return 1; }
  done
  return 0
}

# 单文件模式：从 GitHub 下载仓库归档并校验结构
zn_bootstrap_download(){
  local tmp url extracted running_sh extracted_sh
  echo "检测到单文件安装模式，正在从 $ZN_REPO_URL (branch: $ZN_BRANCH) 获取完整组件 ..."
  tmp="$(mktemp -d)"
  url="${ZN_REPO_URL%/}/archive/refs/heads/$ZN_BRANCH.tar.gz"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -m 180 "$url" -o "$tmp/repo.tar.gz" || { echo "错误: 下载失败 $url"; exit 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp/repo.tar.gz" "$url" || { echo "错误: 下载失败 $url"; exit 1; }
  else
    echo "错误: 需要 curl 或 wget"; exit 1
  fi
  tar -xzf "$tmp/repo.tar.gz" -C "$tmp" || { echo "错误: 归档解压失败"; exit 1; }
  extracted="$(find "$tmp" -maxdepth 1 -type d -name 'zeronode-*' | head -1)"
  [[ -n "$extracted" && -f "$extracted/install.sh" ]] || { echo "错误: 下载内容结构异常"; exit 1; }

  # 校验：仓库内 install.sh 与当前运行版本一致性（有差异说明有新提交，以仓库为准）
  running_sh="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
  extracted_sh="$(sha256sum "$extracted/install.sh" | awk '{print $1}')"
  if [[ "$running_sh" != "$extracted_sh" ]]; then
    echo "警告: 仓库中的 install.sh 与当前运行版本不一致（可能刚有新提交），将以仓库版本继续"
  fi
  bash -n "$extracted/install.sh" || { echo "错误: 下载的安装脚本语法校验失败"; exit 1; }
  zn_install_tree "$extracted" "$ZN_ROOT" || exit 1
  rm -rf "$tmp"
}

# ---------- 安装到 /opt/zeronode ----------
if [[ "$(id -u)" -ne 0 ]]; then
  echo "需要 root 权限运行安装"
  exit 1
fi

if [[ "$SOURCE_DIR" != "$ZN_ROOT" ]]; then
  if zn_has_full_tree; then
    echo "检测到完整项目目录，正在安装到 $ZN_ROOT ..."
    zn_install_tree "$SOURCE_DIR" "$ZN_ROOT" || exit 1
  else
    zn_bootstrap_download
  fi
  ln -sf "$ZN_ROOT/bin/zn" /usr/local/bin/zn
  exec env ZN_ROOT="$ZN_ROOT" bash "$ZN_ROOT/install.sh" "$@"
fi

export ZN_STATE="${ZN_STATE:-/var/lib/zeronode}"
source "$ZN_ROOT/lib/common.sh"
source "$ZN_ROOT/lib/logging.sh"
source "$ZN_ROOT/lib/credential.sh"
source "$ZN_ROOT/lib/db.sh"
source "$ZN_ROOT/lib/ui.sh"
source "$ZN_ROOT/lib/policy.sh"
source "$ZN_ROOT/lib/uninstall.sh"

[[ "$(id -u)" -eq 0 ]] || zn_die "需要 root 权限运行"
zn_state_init
cred_init
db_init || true
zn_log_rotate

# 兼容常见 Linux：包名按发行版映射（sqlite3→sqlite on RHEL 系等）
# 先刷新软件源，避免新系统 apt 列表缺失导致装依赖失败
source "$ZN_ROOT/lib/system.sh"
system_update
for c in curl openssl sqlite3 qrencode socat; do
  zn_need_cmd_or_install "$c" "$c"
done

# systemd 前置检查（Hysteria/Xray 官方安装器均要求 systemd）
if [[ ! -d /run/systemd/system ]] && [[ -z "${ZN_FORCE_NO_SYSTEMD:-}" ]]; then
  # shellcheck source=lib/docker.sh
  source "$ZN_ROOT/lib/docker.sh"
  if docker_detect; then
    zn_yellow "检测到 Docker 容器环境：将以容器模式运行（进程守护代替 systemd，自动探测可出网端口）。"
  else
    zn_red "检测到非 systemd 系统（如 Alpine/OpenRC 容器）。"
    zn_red "Hysteria2 / Xray 需要 systemd 管理服务，建议使用 Debian/Ubuntu/CentOS/Alma/Rocky/Fedora。"
    exit 1
  fi
fi

# 安装 Watchdog 服务（自愈）
install_watchdog_service(){
  source "$ZN_ROOT/lib/system.sh"
  if ! system_has_systemd; then
    nohup "$ZN_ROOT/bin/zn-daemon" watchdog 60 >> "$ZN_LOG_DIR/watchdog.log" 2>&1 &
    zn_log_info "install" "Watchdog 自愈已启动（容器后台模式，PID $!）"
    return 0
  fi
  cat > /etc/systemd/system/zeronode-watchdog.service <<EOF
[Unit]
Description=ZeroNode Watchdog
After=network.target

[Service]
Type=simple
ExecStart=$ZN_ROOT/bin/zn-daemon watchdog 60
Environment=ZN_ROOT=$ZN_ROOT
Restart=always
RestartSec=30
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now zeronode-watchdog >/dev/null 2>&1 || true
  zn_log_info "install" "Watchdog 自愈服务已启用"
}

deploy_flow(){
  local mode="$1" scope="$2" domain="${3:-}"
  source "$ZN_ROOT/lib/deploy.sh"
  if deploy_run "$mode" "$scope" "$domain"; then
    # 安全策略：防火墙默认拒绝（自动保留 SSH）
    source "$ZN_ROOT/lib/system.sh"
    system_fw_default_deny
    system_selinux_fix
    install_watchdog_service
    ui_show_links
    zn_yellow "管理命令: zn status | zn links | zn rotate <proto> | zn backup"
  else
    zn_log_error "install" "部署失败，请查看日志: zn logs 50"
    return 1
  fi
}

uninstall_flow(){
  zn_uninstall_all
}

menu_single(){
  ui_title "选择要安装的协议（IP 一键，无需域名）"
  ui_item "1" "Hysteria 2 + TLS + obfs"
  ui_item "2" "VLESS + REALITY + XTLS Vision"
  ui_item "3" "VLESS + REALITY + XHTTP"
  ui_item "4" "Trojan + TLS"
  ui_item "0" "返回"
  local ans
  read -rp "请输入选项: " ans || return 1
  case "$ans" in
    1) deploy_flow security hysteria2 || true ;;
    2) deploy_flow security vision || true ;;
    3) deploy_flow security xhttp || true ;;
    4) deploy_flow compat trojan || true ;;
    *) return 0 ;;
  esac
}

choose_kernel(){
  ui_title "选择 VLESS 内核"
  ui_item "1" "sing-box（推荐：统一生态、配置简洁）"
  ui_item "2" "Xray（备选：生态成熟）"
  ui_item "0" "返回"
  local ans
  read -rp "请输入选项: " ans || return 1
  case "$ans" in
    1) cred_set deploy.kernel singbox; zn_green "已切换内核: sing-box（推荐）" ;;
    2) cred_set deploy.kernel xray; zn_green "已切换内核: Xray" ;;
    *) return 0 ;;
  esac
}

menu(){
  while true; do
    clear
    ui_banner
    ui_title "主菜单"
    ui_item "1" "一键部署 · 安全优先（IP 全家桶: Hysteria2 + Vision + XHTTP）"
    ui_item "2" "一键部署 · 域名版（输入域名，Hysteria2 申请正式证书）"
    ui_item "3" "一键部署 · 速度优先（Hysteria2 + Vision）"
    ui_item "4" "一键部署 · 兼容优先（Vision + Trojan）"
    ui_item "5" "单协议安装（IP 一键）"
    ui_item "6" "显示全部链接 / 二维码 / 订阅"
    ui_item "7" "环境检测报告"
    ui_item "8" "管理入口（配置回滚 / 轮换 / 备份 / 升级 / API）"
    ui_item "9" "切换 VLESS 内核（当前: $(cred_get deploy.kernel 2>/dev/null || echo singbox)）"
    ui_item "10" "一键卸载（全部组件与数据）"
    ui_item "0" "退出"
    ui_hr
    local ans
    read -rp "请输入选项 [0-10]: " ans || exit 1
    case "$ans" in
      1) deploy_flow security batch || true ;;
      2)
        local domain
        read -rp "请输入你的域名（用于 Hysteria2 正式证书）: " domain || continue
        if zn_valid_domain "$domain"; then
          deploy_flow security batch "$domain" || true
        else
          zn_red "域名格式不正确"
        fi
        ;;
      3) deploy_flow speed batch || true ;;
      4) deploy_flow compat batch || true ;;
      5) menu_single || true ;;
      6) ui_show_links || true ;;
      7) source "$ZN_ROOT/lib/envcheck.sh"; envcheck_run security ;;
      8) zn_yellow "请使用命令: zn help（例如 zn status / zn config rollback / zn rotate / zn backup / zn upgrade / zn api install）";;
      9) choose_kernel ;;
      10) uninstall_flow || true ;;
      0) exit 0 ;;
      *) zn_red "无效选项" ;;
    esac
    echo ""
    read -rp "按回车返回主菜单..." _
  done
}

menu
