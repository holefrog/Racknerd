#!/usr/bin/env bash
source lib/utils.sh

log ">>> [Aria2] 开始安装下载服务..."

# 安装 Aria2
dnf -y install aria2 unzip

ARIA_PATH="$ARIA2_ROOT"
FTP_PATH=$(config_get "ftp" "path")
PORT=$(config_get "ports" "aria2")
TOKEN=$(config_get "aria2" "token")

# 初始化配置目录
mkdir -p "$ARIA_PATH"
touch "${ARIA_PATH}/aria2.log" "${ARIA_PATH}/session.dat"

# 权限设置：确保 Nginx 用户可读写
chown -R nginx:nginx "$ARIA_PATH"

# 生成配置文件
install_template "configs/aria2.conf" "${ARIA_PATH}/aria2.conf" \
    "ARIA2_PATH=$ARIA_PATH" \
    "FTP_PATH=$FTP_PATH" \
    "ARIA2_PORT=$PORT" \
    "ARIA2_TOKEN=$TOKEN"

# 禁用 IPv6 (防止连接问题)
append_config "${ARIA_PATH}/aria2.conf" "disable-ipv6=true"

# 安装 Systemd 服务
install_template "services/aria2.service" "${OS_SYSTEM_PATH}/aria2.service" \
    "ARIA2_PATH=$ARIA_PATH" \
    "ARIA2_CONFIG=aria2.conf" \
    "FTP_PATH=$FTP_PATH"

# 启动服务
start_service "aria2"

log ">>> [Aria2] 安装配置完成"
