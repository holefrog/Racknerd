#!/usr/bin/env bash
source lib/utils.sh

log ">>> [系统] 更新与依赖..."
dnf -y update
dnf -y upgrade
dnf -y install epel-release wget unzip tar curl openssl policycoreutils-python-utils

# BBR 配置
if [[ "$(config_get "system" "enable_bbr")" == "yes" ]]; then
    log "检查 BBR 配置..."
    # 使用 append_config 自动处理查重
    append_config "/etc/sysctl.conf" "net.core.default_qdisc=fq"
    append_config "/etc/sysctl.conf" "net.ipv4.tcp_congestion_control=bbr"
    sysctl -p
fi
