#!/usr/bin/env bash
#
# 协议模块配置生成测试（不依赖真实二进制/systemd）
#

test_protocols_run(){
  source "$ZN_ROOT/lib/common.sh"
  source "$ZN_ROOT/lib/logging.sh"
  source "$ZN_ROOT/lib/credential.sh"
  source "$ZN_ROOT/lib/stealth.sh"
  cred_init

  # ---- Hysteria2 配置生成 ----
  source "$ZN_ROOT/protocols/hysteria2.sh"
  cred_set hysteria2.port "5678"
  cred_set hysteria2.password "testpass123"
  cred_set hysteria2.obfs "testobfs"
  cred_set hysteria2.site "en.snu.ac.kr"
  cred_set hysteria2.sni "www.bing.com"
  local hy2
  hy2="$(hy2_write_config)"
  t_assert "Hysteria2 配置生成非空" test -s "$hy2"
  t_assert_contains "Hysteria2 listen" "$(cat "$hy2")" "listen: :5678"
  t_assert_contains "Hysteria2 obfs salamander" "$(cat "$hy2")" "type: salamander"
  t_assert_contains "Hysteria2 masquerade" "$(cat "$hy2")" "https://en.snu.ac.kr"
  t_assert "Hysteria2 配置校验通过" proto_validate_hysteria2 "$hy2"

  # 非法配置校验应失败
  local bad
  bad="$(zn_tmp)"
  printf 'not a yaml: [\n' > "$bad"
  t_assert_eq "Hysteria2 非法配置被拒" "1" "$(proto_validate_hysteria2 "$bad"; echo $?)"

  # ---- Xray 配置生成（vision + xhttp + trojan） ----
  source "$ZN_ROOT/protocols/xray.sh"
  cred_set xray.uuid "11111111-2222-4333-8444-555555555555"
  cred_set xray.reality.private_key "PRIVKEY"
  cred_set xray.reality.public_key "PUBKEY"
  cred_set xray.reality.short_id "abcd1234"
  cred_set xray.dest "www.microsoft.com"
  cred_set xray.vision.port "443"
  cred_set xray.xhttp.port "8443"
  cred_set xray.xhttp.path "/abc123"
  cred_set xray.trojan.port "9443"
  cred_set xray.trojan.password "trojanpass"
  local xcfg
  xcfg="$(xray_gen_config "vision xhttp trojan")"
  t_assert_contains "Xray 配置含 Vision" "$(cat "$xcfg")" "xtls-rprx-vision"
  t_assert_contains "Xray 配置含 XHTTP" "$(cat "$xcfg")" '"network": "xhttp"'
  t_assert_contains "Xray 配置含 REALITY" "$(cat "$xcfg")" '"security": "reality"'
  t_assert_contains "Xray 配置含 Trojan" "$(cat "$xcfg")" '"protocol": "trojan"'
  t_assert_contains "Xray 配置含 dest" "$(cat "$xcfg")" "www.microsoft.com:443"
  t_assert_contains "Xray 配置含 bittorrent 屏蔽" "$(cat "$xcfg")" "bittorrent"

  # JSON 合法性（有 node 时校验）
  if command -v node >/dev/null 2>&1 || [[ -n "${ZN_NODE_BIN:-}" ]]; then
    local node="${ZN_NODE_BIN:-node}"
    if "$node" -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$xcfg" 2>/dev/null; then
      PASS=$((PASS + 1)); printf '  [PASS] Xray 配置为合法 JSON\n'
    else
      FAIL=$((FAIL + 1)); FAILED_TESTS+=("Xray JSON"); printf '  [FAIL] Xray 配置为合法 JSON\n'
    fi
  fi

  # 仅 vision
  local xcfg2
  xcfg2="$(xray_gen_config "vision")"
  t_assert_eq "单 inbound 配置无 trojan" "0" "$(grep -c trojan "$xcfg2" || true)"

  # ---- sing-box 内核配置生成 ----
  source "$ZN_ROOT/protocols/singbox.sh"
  local sbcfg
  sbcfg="$(sb_gen_config "vision xhttp trojan")"
  t_assert_contains "sing-box 配置含 vless" "$(cat "$sbcfg")" '"type": "vless"'
  t_assert_contains "sing-box 配置含 REALITY" "$(cat "$sbcfg")" '"reality"'
  t_assert_contains "sing-box 配置含 Vision flow" "$(cat "$sbcfg")" '"flow": "xtls-rprx-vision"'
  t_assert_contains "sing-box 配置含 XHTTP" "$(cat "$sbcfg")" '"type": "xhttp"'
  t_assert_contains "sing-box 配置含 Trojan" "$(cat "$sbcfg")" '"type": "trojan"'
  t_assert_contains "sing-box 配置含 short_id" "$(cat "$sbcfg")" "abcd1234"
  t_assert "sing-box 配置校验通过(grep路径)" proto_validate_singbox "$sbcfg"
  if command -v node >/dev/null 2>&1 || [[ -n "${ZN_NODE_BIN:-}" ]]; then
    local node="${ZN_NODE_BIN:-node}"
    if "$node" -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$sbcfg" 2>/dev/null; then
      PASS=$((PASS + 1)); printf '  [PASS] sing-box 配置为合法 JSON\n'
    else
      FAIL=$((FAIL + 1)); FAILED_TESTS+=("sing-box JSON"); printf '  [FAIL] sing-box 配置为合法 JSON\n'
    fi
  fi

  # 仅 vision（sing-box）
  local sbcfg2
  sbcfg2="$(sb_gen_config "vision")"
  t_assert_eq "sing-box 单 inbound 无 trojan" "0" "$(grep -c '"type": "trojan"' "$sbcfg2" || true)"
}
