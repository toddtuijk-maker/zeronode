#!/usr/bin/env bash
#
# common.sh - ZeroNode 框架层：路径、加载器、错误处理、通用工具
#

# ---------- 基础路径 ----------
export ZN_ROOT="${ZN_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
export ZN_STATE="${ZN_STATE:-/var/lib/zeronode}"
export ZN_CONF="${ZN_CONF:-/etc/zeronode.conf}"
export ZN_LOG_DIR="$ZN_STATE/logs"
export ZN_CRED_FILE="$ZN_STATE/credentials"
export ZN_DB_FILE="$ZN_STATE/zeronode.db"
export ZN_SUB_DIR="$ZN_STATE/sub"
export ZN_HISTORY_DIR="$ZN_STATE/config-history"
export ZN_BACKUP_DIR="$ZN_STATE/backups"
export ZN_BIN_DIR="$ZN_STATE/bin-backup"

# ---------- 颜色 ----------
export ZN_RED=$'\033[31m' ZN_GREEN=$'\033[32m' ZN_YELLOW=$'\033[33m'
export ZN_BLUE=$'\033[34m' ZN_CYAN=$'\033[36m' ZN_BOLD=$'\033[1m' ZN_PLAIN=$'\033[0m'

zn_red(){   printf '%b%s%b\n' "$ZN_RED" "$*" "$ZN_PLAIN"; }
zn_green(){ printf '%b%s%b\n' "$ZN_GREEN" "$*" "$ZN_PLAIN"; }
zn_yellow(){ printf '%b%s%b\n' "$ZN_YELLOW" "$*" "$ZN_PLAIN"; }
zn_cyan(){  printf '%b%s%b\n' "$ZN_CYAN" "$*" "$ZN_PLAIN"; }
zn_bold(){  printf '%b%s%b\n' "$ZN_BOLD" "$*" "$ZN_PLAIN"; }

# ---------- 日志（见 logging.sh，这里提供无依赖的应急输出） ----------
zn_log_emergency(){
  printf '%s|EMERGENCY|%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# ---------- 加载器 ----------
zn_require(){
  local mod
  for mod in "$@"; do
    local f="$ZN_ROOT/lib/$mod.sh"
    if [[ ! -f "$f" ]]; then
      zn_log_emergency "缺少模块: $mod ($f)"
      return 1
    fi
    # shellcheck source=lib/logging.sh
    source "$f"
  done
}

# ---------- 错误处理 ----------
zn_die(){
  zn_log_emergency "$*"
  exit 1
}

zn_trap_cleanup(){
  local tmp
  for tmp in "${ZN_TMP_FILES[@]:-}"; do
    [[ -n "$tmp" && -e "$tmp" ]] && rm -f "$tmp" 2>/dev/null || true
  done
}

zn_trap_init(){
  ZN_TMP_FILES=()
  trap 'zn_trap_cleanup' EXIT
}

zn_tmp(){
  local t
  t="$(mktemp)"
  ZN_TMP_FILES+=("$t")
  printf '%s' "$t"
}

# ---------- 平台检测 ----------
zn_os(){
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s' "${ID:-linux}${VERSION_ID:+/$VERSION_ID}"
  else
    uname -s
  fi
}

zn_arch(){
  case "$(uname -m)" in
    x86_64|amd64)          echo amd64 ;;
    aarch64|arm64)         echo arm64 ;;
    i386|i686)             echo 386 ;;
    armv5tel|armv6l|armv7l|armv7) echo arm ;;
    mips*)                 echo mipsle ;;
    s390x)                 echo s390x ;;
    loongarch64)           echo loong64 ;;
    riscv64)               echo riscv64 ;;
    *)                     echo unknown ;;
  esac
}

zn_is_root(){
  [[ "$(id -u)" -eq 0 ]]
}

zn_require_root(){
  if ! zn_is_root; then
    zn_red "错误: 需要 root 权限执行"
    exit 1
  fi
}

# ---------- 随机与校验 ----------
zn_random_hex(){
  local n="${1:-16}"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$(((n + 1) / 2))" 2>/dev/null | cut -c1-"$n"
  else
    tr -dc 'a-f0-9' </dev/urandom | head -c "$n"
  fi
}

zn_random_password(){
  local len="${1:-16}"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 "$len" 2>/dev/null | tr -dc 'A-Za-z0-9!@%^*_\-+=.' | head -c "$len"
  else
    tr -dc 'A-Za-z0-9!@%^*_\-+=.' </dev/urandom | head -c "$len"
  fi
}

zn_random_uuid(){
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  elif command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    printf '%s-%s-%s-%s-%s' \
      "$(zn_random_hex 8)" "$(zn_random_hex 4)" "4$(zn_random_hex 3)" \
      "$(printf '%x' "$((8 + RANDOM % 4))")$(zn_random_hex 3)" "$(zn_random_hex 12)"
  fi
}

zn_valid_uuid(){
  [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

zn_valid_port(){
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 ))
}

# 密码强度/字符集校验（与 YAML/JSON/URL 安全字符集一致）
zn_valid_password(){
  local p="$1"
  [[ ${#p} -ge 8 ]] || return 1
  local allowed="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@%^*()_+=.,;-"
  local c
  local i
  for ((i = 0; i < ${#p}; i++)); do
    c="${p:i:1}"
    [[ "$allowed" == *"$c"* ]] || return 1
  done
  return 0
}

zn_random_port(){
  if command -v shuf >/dev/null 2>&1; then
    shuf -i 2000-65535 -n 1
  else
    echo $((2000 + RANDOM % 60000))
  fi
}

zn_valid_domain(){
  [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] && [[ "$1" != *".."* ]]
}

zn_urlencode(){
  local s="$1" encoded="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9._~-]) encoded+="$c" ;;
      *) printf -v encoded '%s%%%02X' "$encoded" "'$c" ;;
    esac
  done
  printf '%s' "$encoded"
}

zn_json_escape(){
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# ---------- 端口占用检测 ----------
zn_port_in_use_udp(){
  local p="$1" hex
  if command -v ss >/dev/null 2>&1; then
    ss -tunlp 2>/dev/null | awk '{print $5}' | sed 's/.*://' | grep -qx "$p"
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -ulnp 2>/dev/null | awk '{print $4}' | sed 's/.*://' | grep -qx "$p"
    return $?
  fi
  # 最后手段：解析 /proc/net/udp(+udp6)，端口为小端十六进制
  hex="$(printf '%02X%02X' $((p & 255)) $((p >> 8)))"
  grep -qi ":$hex " /proc/net/udp 2>/dev/null || grep -qi ":$hex " /proc/net/udp6 2>/dev/null
}

zn_port_in_use_tcp(){
  local p="$1" hex
  if command -v ss >/dev/null 2>&1; then
    ss -tlnp 2>/dev/null | awk '{print $4}' | sed 's/.*://' | grep -qx "$p"
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -tlnp 2>/dev/null | awk '{print $4}' | sed 's/.*://' | grep -qx "$p"
    return $?
  fi
  hex="$(printf '%02X%02X' $((p & 255)) $((p >> 8)))"
  grep -qi ":$hex " /proc/net/tcp 2>/dev/null || grep -qi ":$hex " /proc/net/tcp6 2>/dev/null
}

# ---------- 公网 IP 检测（HTTPS 多源，可被 WARP 干扰时由调用方处理） ----------
zn_public_ipv4(){
  local ip="" url
  for url in "https://api.ipify.org" "https://ip.sb" "https://ifconfig.me"; do
    ip="$(curl -fsS4 -m 8 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
    [[ -n "$ip" ]] && break
  done
  printf '%s' "$ip"
}

zn_public_ipv6(){
  local ip="" url
  for url in "https://api6.ipify.org" "https://ifconfig.co"; do
    ip="$(curl -fsS6 -m 8 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
    [[ -n "$ip" ]] && break
  done
  printf '%s' "$ip"
}

zn_public_ip(){
  local v4 v6
  v4="$(zn_public_ipv4)"
  v6="$(zn_public_ipv6)"
  printf 'ipv4=%s\nipv6=%s\n' "$v4" "$v6"
}

# ---------- 交互 ----------
zn_confirm(){
  local msg="$1" ans
  read -rp "$msg [y/N] " ans || return 1
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

zn_prompt(){
  local var="$1" msg="$2" def="${3:-}" val
  if [[ -n "$def" ]]; then
    read -rp "$msg（回车默认: $def）: " val || return 1
    [[ -z "$val" ]] && val="$def"
  else
    read -rp "$msg: " val || return 1
  fi
  printf -v "$var" '%s' "$val"
}

# ---------- 配置读写（/etc/zeronode.conf，0600） ----------
zn_conf_get(){
  local key="$1"
  [[ -f "$ZN_CONF" ]] || return 1
  grep -E "^${key}=" "$ZN_CONF" 2>/dev/null | head -1 | cut -d= -f2-
}

zn_conf_set(){
  local key="$1" val="$2" tmp
  mkdir -p "$(dirname "$ZN_CONF")"
  touch "$ZN_CONF"
  tmp="$(zn_tmp)"
  grep -vE "^${key}=" "$ZN_CONF" > "$tmp" || true
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$ZN_CONF"
  chmod 600 "$ZN_CONF"
}

# ---------- 数据目录初始化 ----------
zn_state_init(){
  local dirs=("$ZN_STATE" "$ZN_LOG_DIR" "$ZN_SUB_DIR" "$ZN_HISTORY_DIR" "$ZN_BACKUP_DIR" "$ZN_BIN_DIR")
  local d
  for d in "${dirs[@]}"; do
    mkdir -p "$d"
  done
  chmod 700 "$ZN_STATE"
  chmod 700 "$ZN_LOG_DIR" "$ZN_SUB_DIR" "$ZN_HISTORY_DIR" "$ZN_BACKUP_DIR" "$ZN_BIN_DIR"
}

# ---------- 完整性自检（防脚本被篡改） ----------
# 首次运行生成 sha256 清单；之后每次运行校验。清单被改动会告警（不阻断）。
zn_integrity_check(){
  local manifest="$ZN_STATE/manifest.sha256"
  if [[ ! -f "$manifest" ]]; then
    (cd "$ZN_ROOT" && find lib protocols bin install.sh -type f \( -name '*.sh' -o -name 'zn' -o -name 'zn-daemon' -o -name 'install.sh' \) 2>/dev/null \
      | sort | xargs sha256sum 2>/dev/null) > "$manifest" 2>/dev/null || true
    chmod 600 "$manifest"
    return 0
  fi
  if ! (cd "$ZN_ROOT" && sha256sum -c "$manifest" --quiet 2>/dev/null); then
    zn_log_emergency "完整性自检失败: 项目文件可能被篡改，请人工核对 $ZN_ROOT"
    return 1
  fi
  return 0
}

# ---------- 依赖检查 ----------
zn_need_cmd(){
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    zn_log_emergency "缺少命令: $cmd"
    return 1
  }
}

zn_need_cmd_or_install(){
  local cmd="$1" pkg="${2:-$1}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    zn_yellow "安装依赖: $pkg"
    # shellcheck source=lib/system.sh
    source "$ZN_ROOT/lib/system.sh"
    system_install_pkg "$pkg" >/dev/null 2>&1 || true
  fi
}
