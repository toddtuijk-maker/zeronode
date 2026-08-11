#!/usr/bin/env bash
#
# 客户端生成测试（URI / sing-box / Clash，多客户端兼容）
#

test_clientgen_run(){
  source "$ZN_ROOT/lib/common.sh"
  source "$ZN_ROOT/lib/clientgen.sh"

  local uri
  uri="$(clientgen_vless_vision "1.2.3.4" "11111111-2222-4333-8444-555555555555" "443" "www.microsoft.com" "PUBKEY" "abcd1234" "测试节点")"
  t_assert_contains "Vision URI 协议头" "$uri" "vless://"
  t_assert_contains "Vision URI reality" "$uri" "security=reality"
  t_assert_contains "Vision URI flow" "$uri" "flow=xtls-rprx-vision"
  t_assert_contains "Vision URI pbk" "$uri" "pbk=PUBKEY"
  t_assert_contains "Vision URI sid" "$uri" "sid=abcd1234"
  t_assert_contains "Vision URI 中文名已编码" "$uri" "%E6%B5%8B"

  uri="$(clientgen_vless_xhttp "1.2.3.4" "11111111-2222-4333-8444-555555555555" "8443" "www.apple.com" "PUBKEY2" "deadbeef" "/abc123" "XHTTP节点")"
  t_assert_contains "XHTTP URI type" "$uri" "type=xhttp"
  t_assert_contains "XHTTP URI path" "$uri" "path=%2Fabc123"
  t_assert_contains "XHTTP URI host" "$uri" "host=www.apple.com"
  t_assert_eq "XHTTP 不应含 flow" "0" "$(echo "$uri" | grep -c 'flow=')"

  uri="$(clientgen_hysteria2 "1.2.3.4" "5678" "pwd123" "obfs456" "www.bing.com")"
  t_assert_contains "Hysteria2 URI 协议头" "$uri" "hysteria2://"
  t_assert_contains "Hysteria2 URI obfs" "$uri" "obfs=salamander"
  t_assert_contains "Hysteria2 URI obfs-password" "$uri" "obfs-password=obfs456"
  t_assert_contains "Hysteria2 URI insecure" "$uri" "insecure=1"

  uri="$(clientgen_trojan "1.2.3.4" "443" "trojanpass")"
  t_assert_contains "Trojan URI 协议头" "$uri" "trojan://"
  t_assert_contains "Trojan URI allowInsecure" "$uri" "allowInsecure=1"

  # sing-box / clash 片段
  local sb
  sb="$(clientgen_singbox_hysteria2 "1.2.3.4" "5678" "pwd123" "obfs456" "www.bing.com")"
  t_assert_contains "sing-box hysteria2 type" "$sb" '"type":"hysteria2"'
  t_assert_contains "sing-box obfs salamander" "$sb" '"type":"salamander"'

  local cl
  cl="$(clientgen_clash_hysteria2 "节点A" "1.2.3.4" "5678" "pwd123" "obfs456" "www.bing.com")"
  t_assert_contains "Clash hysteria2 type" "$cl" "type: hysteria2"
  t_assert_contains "Clash obfs" "$cl" "obfs: salamander"

  cl="$(clientgen_clash_vless "节点B" "1.2.3.4" "443" "11111111-2222-4333-8444-555555555555" "www.microsoft.com" "PBK" "SID" "xtls-rprx-vision")"
  t_assert_contains "Clash vless reality-opts" "$cl" "reality-opts:"
  t_assert_contains "Clash vless flow" "$cl" "flow: xtls-rprx-vision"
}
