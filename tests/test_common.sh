#!/usr/bin/env bash
#
# 公共工具函数测试
#

test_common_run(){
  source "$ZN_ROOT/lib/common.sh"

  local enc
  enc="$(zn_urlencode 'p@ss word/?#')"
  t_assert_contains "urlencode 编码 @ 和空格" "$enc" "%40"
  t_assert_contains "urlencode 编码空格" "$enc" "%20"

  local uuid
  uuid="$(zn_random_uuid)"
  t_assert "UUID 生成合法" zn_valid_uuid "$uuid"

  t_assert "端口 443 合法" zn_valid_port 443
  t_assert_eq "端口 70000 非法" "1" "$(zn_valid_port 70000; echo $?)"
  t_assert_eq "端口 abc 非法" "1" "$(zn_valid_port abc; echo $?)"

  t_assert "域名合法" zn_valid_domain "example.com"
  t_assert_eq "域名非法" "1" "$(zn_valid_domain 'bad..com'; echo $?)"

  local j
  j="$(zn_json_escape 'a"b\c')"
  t_assert_contains "JSON 转义引号" "$j" 'a\"b'

  local pwd
  pwd="$(zn_random_password 16)"
  t_assert_eq "随机密码长度 16" "16" "${#pwd}"
  t_assert "随机密码通过强度校验" zn_valid_password "$pwd"
  t_assert "密码校验通过(含特殊字符)" zn_valid_password "Abcd1234!@%^*()_+=.,;"
  t_assert_eq "密码过短被拒" "1" "$(zn_valid_password 'short12'; echo $?)"
  t_assert_eq "密码含空格被拒" "1" "$(zn_valid_password 'has space1'; echo $?)"
  t_assert_eq "密码含#被拒" "1" "$(zn_valid_password 'bad#pass1'; echo $?)"

  local hex
  hex="$(zn_random_hex 8)"
  t_assert_eq "随机 hex 长度 8" "8" "${#hex}"
}
