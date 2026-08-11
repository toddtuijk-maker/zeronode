#!/usr/bin/env bash
#
# API 路由测试（本地管理 API + 订阅鉴权）
#

test_api_run(){
  source "$ZN_ROOT/lib/common.sh"
  source "$ZN_ROOT/lib/logging.sh"
  source "$ZN_ROOT/lib/credential.sh"
  source "$ZN_ROOT/lib/api.sh"
  cred_init

  local token
  token="$(api_token_generate)"
  t_assert "API Token 生成" test -n "$token"

  mkdir -p "$ZN_SUB_DIR"
  printf 'vless://test\n' > "$ZN_SUB_DIR/sub.txt"
  printf 'proxies:\n' > "$ZN_SUB_DIR/clash.yaml"
  printf '[]\n' > "$ZN_SUB_DIR/singbox.json"

  local resp
  resp="$(api_route GET /health "" "")"
  t_assert_contains "/health 返回 200" "$resp" "HTTP/1.1 200"
  t_assert_contains "/health 返回 ok" "$resp" '"ok":true'

  resp="$(api_route GET /links "type=plain" "wrongtoken")"
  t_assert_contains "错误 Token 返回 401" "$resp" "HTTP/1.1 401"

  resp="$(api_route GET /links "type=plain" "$token")"
  t_assert_contains "正确 Token 返回订阅" "$resp" "vless://test"

  resp="$(api_route GET /links "type=clash" "$token")"
  t_assert_contains "Clash 订阅 content-type" "$resp" "text/yaml"

  resp="$(api_route GET /links "type=singbox" "$token")"
  t_assert_contains "sing-box 订阅 content-type" "$resp" "application/json"

  resp="$(api_route GET /nope "" "$token")"
  t_assert_contains "未知路径返回 400" "$resp" "HTTP/1.1 400"

  # 订阅端点鉴权
  local st
  st="$(sub_token_generate)"
  resp="$(api_sub_handle <<< "GET /sub?token=$st&type=plain HTTP/1.1")"
  t_assert_contains "订阅端点正常返回" "$resp" "vless://test"
  resp="$(api_sub_handle <<< "GET /sub?token=bad HTTP/1.1")"
  t_assert_contains "订阅端点错误 Token 401" "$resp" "HTTP/1.1 401"
}
