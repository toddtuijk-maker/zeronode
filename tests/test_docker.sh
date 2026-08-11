#!/usr/bin/env bash
#
# Docker 适配层测试（非容器环境下验证检测与降级路径）
#

test_docker_run(){
  source "$ZN_ROOT/lib/common.sh"
  source "$ZN_ROOT/lib/docker.sh"

  # 当前环境不是 Docker 容器
  t_assert_eq "非容器环境 docker_detect=false" "1" "$(docker_detect; echo $?)"
  t_assert_eq "网络模式识别为 not-docker" "not-docker" "$(docker_net_mode)"

  # 无 socat/nc 时探测应优雅降级为 unknown
  local probe
  probe="$(docker_probe_tcp 19999)"
  t_assert_eq "无监听工具时探测降级 unknown" "unknown" "$probe"

  # 发现接口应始终返回指定数量的端口
  local ports
  ports="$(docker_discover_tcp_ports 3 5)"
  t_assert_eq "发现接口返回 3 个端口" "3" "$(echo "$ports" | grep -cE '^[0-9]+$')"

  # 端口探测结果须合法
  local p
  for p in $ports; do
    t_assert "发现端口 $p 合法" zn_valid_port "$p"
  done
}
