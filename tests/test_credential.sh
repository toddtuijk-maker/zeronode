#!/usr/bin/env bash
#
# 凭证管理器测试
#

test_credential_run(){
  source "$ZN_ROOT/lib/common.sh"
  source "$ZN_ROOT/lib/credential.sh"
  cred_init

  cred_set test.key "secret123"
  t_assert_eq "凭证写入" "secret123" "$(cred_get test.key)"

  cred_rotate test.key "newsecret"
  t_assert_eq "凭证轮换后新值" "newsecret" "$(cred_get test.key)"
  t_assert "轮换保留旧值(revoked 记录)" grep -q "revoked.*test.key.*secret123" "$ZN_CRED_FILE"

  cred_del test.key
  t_assert_eq "凭证删除后为空" "" "$(cred_get test.key)"

  local bak
  bak="$(cred_backup "$ZN_STATE/cred.bak")"
  t_assert "凭证备份文件存在" test -f "$bak"

  local enc
  enc="$(cred_backup_encrypted "pass123" "$ZN_STATE/cred.enc")"
  t_assert "凭证加密备份存在" test -f "$enc"
  cred_restore_encrypted "$enc" "pass123"
  t_assert "加密恢复成功" test -f "$ZN_CRED_FILE"
}
