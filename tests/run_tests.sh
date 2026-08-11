#!/usr/bin/env bash
#
# run_tests.sh - ZeroNode 自动化测试入口
# 用法: bash tests/run_tests.sh [test名]
#

set -uo pipefail

export ZN_ROOT="${ZN_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
ZN_STATE="$(mktemp -d)"
export ZN_STATE
export ZN_CONF="$ZN_STATE/zeronode.conf"
export ZN_LOG_LEVEL=ERROR

PASS=0; FAIL=0; FAILED_TESTS=()

t_assert(){
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    printf '  [PASS] %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$desc")
    printf '  [FAIL] %s\n' "$desc"
  fi
}

t_assert_eq(){
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    printf '  [PASS] %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$desc")
    printf '  [FAIL] %s (expected=%q actual=%q)\n' "$desc" "$expected" "$actual"
  fi
}

t_assert_contains(){
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    printf '  [PASS] %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$desc")
    printf '  [FAIL] %s (missing: %s)\n' "$desc" "$needle"
  fi
}

run_suite(){
  local name="$1"
  local file="$ZN_ROOT/tests/test_$name.sh"
  [[ -f "$file" ]] || { printf '跳过不存在套件: %s\n' "$name"; return; }
  printf '\n== 套件: %s ==\n' "$name"
  # shellcheck source=tests/test_common.sh
  source "$file"
  "test_${name}_run"
}

if [[ $# -gt 0 ]]; then
  run_suite "$1"
else
  for suite in common credential config_manager clientgen protocols api docker; do
    run_suite "$suite"
  done
fi

printf '\n================ 结果 ================\n'
printf '通过: %d  失败: %d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf '失败项:\n'
  printf '  - %s\n' "${FAILED_TESTS[@]}"
  exit 1
fi
exit 0
