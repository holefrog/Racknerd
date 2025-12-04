#!/usr/bin/env bash
source lib/utils.sh

log ">>> [System] 开始系统更新与基础环境初始化..."

# 更新系统软件包
log "正在更新软件包 (dnf update)..."
dnf -y update

# 安装基础依赖工具
log "安装常用工具 (curl, wget, tar, etc)..."
dnf -y install epel-release wget unzip tar curl openssl policycoreutils-python-utils

# BBR 拥塞控制配置
if [[ "$(config_get "system" "enable_bbr")" == "yes" ]]; then
    log "正在启用 TCP BBR..."
    append_config "/etc/sysctl.conf" "net.core.default_qdisc=fq"
    append_config "/etc/sysctl.conf" "net.ipv4.tcp_congestion_control=bbr"
    sysctl -p
fi

log ">>> [System] 系统初始化完成"
