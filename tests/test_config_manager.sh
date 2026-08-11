#!/usr/bin/env bash
#
# 配置管理器测试（备份 → 校验 → 应用 → 健康检查 → 失败回滚）
#

TEST_CFG="$ZN_STATE/testproto.conf"
TEST_RESTART_LOG="$ZN_STATE/restarts"
TEST_HEALTH_OK=1

proto_config_path_testproto(){ echo "$TEST_CFG"; }
proto_meta_testproto_systemd_unit(){ echo "testproto"; }
proto_meta_testproto_config_perms(){ echo 644; }
proto_meta_testproto_config_owner(){ echo "root:root"; }
proto_validate_testproto(){
  local f="$1"
  grep -q "valid: true" "$f"
}
proto_restart_testproto(){ echo "restart" >> "$TEST_RESTART_LOG"; }
proto_health_testproto(){ [[ "$TEST_HEALTH_OK" == "1" ]]; }

test_config_manager_run(){
  source "$ZN_ROOT/lib/common.sh"
  source "$ZN_ROOT/lib/logging.sh"
  source "$ZN_ROOT/lib/credential.sh"
  source "$ZN_ROOT/lib/config_manager.sh"
  cred_init
  # 无 sqlite 时跳过 DB 记录
  db_available(){ return 1; }

  printf 'listen: :1000\nvalid: true\n' > "$TEST_CFG"
  : > "$TEST_RESTART_LOG"

  local tmp
  tmp="$(zn_tmp)"
  printf 'listen: :2000\nvalid: true\n' > "$tmp"
  t_assert "配置应用成功" cm_apply testproto "$tmp" "test"
  t_assert_contains "新配置已应用" "$(cat "$TEST_CFG")" ":2000"
  t_assert "服务已重启" grep -q restart "$TEST_RESTART_LOG"
  t_assert "生成了配置历史" bash -c "ls -1d '$ZN_HISTORY_DIR'/*-testproto >/dev/null 2>&1"

  # 失败回滚：健康检查失败时应恢复旧配置
  TEST_HEALTH_OK=0
  local tmp2
  tmp2="$(zn_tmp)"
  printf 'listen: :3000\nvalid: true\n' > "$tmp2"
  t_assert_eq "健康失败时应用返回 1" "1" "$(cm_apply testproto "$tmp2" "bad"; echo $?)"
  t_assert_contains "失败后回滚到旧配置" "$(cat "$TEST_CFG")" ":2000"

  # 校验失败：不应用
  TEST_HEALTH_OK=1
  local tmp3
  tmp3="$(zn_tmp)"
  printf 'listen: :4000\nvalid: false\n' > "$tmp3"
  t_assert_eq "校验失败时拒绝应用" "1" "$(cm_apply testproto "$tmp3" "invalid"; echo $?)"
  t_assert_contains "校验失败后配置未变" "$(cat "$TEST_CFG")" ":2000"
}
