#!/usr/bin/env bash
#
# db.sh - SQLite 数据层（唯一 SQL 入口，预留 PostgreSQL 适配点）
#

export ZN_SQLITE_BIN="${ZN_SQLITE_BIN:-sqlite3}"

db_available(){
  command -v "$ZN_SQLITE_BIN" >/dev/null 2>&1
}

db_ensure_bin(){
  if ! db_available; then
    # shellcheck source=lib/system.sh
    source "$ZN_ROOT/lib/system.sh"
    system_install_pkg sqlite3 >/dev/null 2>&1 || true
  fi
  if ! db_available; then
    zn_log_warn "db" "SQLite3 不可用，数据库功能降级（可执行 apt/dnf 安装 sqlite3）"
    return 1
  fi
  return 0
}

db_schema(){
  cat <<'SQL'
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT
);
CREATE TABLE IF NOT EXISTS nodes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  hostname TEXT, ipv4 TEXT, ipv6 TEXT,
  os TEXT, arch TEXT, kernel TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS protocols (
  name TEXT PRIMARY KEY,
  enabled INTEGER DEFAULT 1,
  status TEXT DEFAULT 'unknown',
  port INTEGER, transport TEXT, stealth TEXT,
  installed_at TEXT, updated_at TEXT
);
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  name TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  revoked INTEGER DEFAULT 0,
  revoked_at TEXT
);
CREATE TABLE IF NOT EXISTS config_versions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  protocol TEXT NOT NULL,
  version INTEGER NOT NULL,
  checksum TEXT, backup_path TEXT,
  reason TEXT, applied INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS operations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT DEFAULT (datetime('now')),
  actor TEXT, action TEXT, target TEXT, result TEXT, detail TEXT
);
CREATE TABLE IF NOT EXISTS health (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT DEFAULT (datetime('now')),
  protocol TEXT, ok INTEGER, latency_ms INTEGER, detail TEXT
);
CREATE TABLE IF NOT EXISTS upgrades (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT DEFAULT (datetime('now')),
  protocol TEXT, from_ver TEXT, to_ver TEXT, result TEXT
);
SQL
}

db_init(){
  db_ensure_bin || return 1
  mkdir -p "$(dirname "$ZN_DB_FILE")"
  if [[ ! -f "$ZN_DB_FILE" ]]; then
    : > "$ZN_DB_FILE"
    chmod 600 "$ZN_DB_FILE"
  fi
  db_schema | "$ZN_SQLITE_BIN" "$ZN_DB_FILE"
  local ver
  ver="$(db_scalar "SELECT value FROM meta WHERE key='schema_version'")"
  if [[ -z "$ver" ]]; then
    "$ZN_SQLITE_BIN" "$ZN_DB_FILE" "INSERT INTO meta(key,value) VALUES('schema_version','1')"
  fi
}

db_quote(){
  printf '%s' "$1" | sed "s/'/''/g"
}

db_exec(){
  db_ensure_bin || return 1
  "$ZN_SQLITE_BIN" "$ZN_DB_FILE" "$1"
}

db_scalar(){
  db_ensure_bin || return 1
  "$ZN_SQLITE_BIN" "$ZN_DB_FILE" "$1" 2>/dev/null | head -1
}

db_rows(){
  db_ensure_bin || return 1
  "$ZN_SQLITE_BIN" "$ZN_DB_FILE" "$1" 2>/dev/null
}

# db_insert <table> "col=val,col=val,..."  (值自动单引号转义)
db_insert(){
  local table="$1" kv="$2"
  local cols="" vals="" item k v
  local IFS_old="$IFS"
  IFS=','
  for item in $kv; do
    IFS="$IFS_old"
    k="${item%%=*}"
    v="${item#*=}"
    cols="$cols,$k"
    vals="$vals,'$(db_quote "$v")'"
  done
  IFS="$IFS_old"
  db_exec "INSERT INTO $table (${cols#,}) VALUES (${vals#,})"
}

# 记录节点信息
db_upsert_node(){
  local host ip4 ip6 os arch kernel
  host="$(hostname 2>/dev/null || echo unknown)"
  ip4="${ZN_IPV4:-}"
  ip6="${ZN_IPV6:-}"
  os="$(zn_os)"
  arch="$(zn_arch)"
  kernel="$(uname -r 2>/dev/null || echo unknown)"
  db_exec "DELETE FROM nodes"
  db_insert nodes "hostname='$host',ipv4='$ip4',ipv6='$ip6',os='$os',arch='$arch',kernel='$kernel'"
}

db_record_health(){
  local proto="$1" ok="$2" latency="${3:-}" detail="${4:-}"
  db_insert health "protocol='$proto',ok=$ok,latency_ms='$latency',detail='$detail'"
  db_exec "UPDATE protocols SET status='$( [[ "$ok" == "1" ]] && echo active || echo failed )' WHERE name='$proto'"
}
