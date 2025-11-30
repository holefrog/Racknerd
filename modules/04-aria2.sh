#!/usr/bin/env bash
source lib/utils.sh

log ">>> [Aria2] 安装..."
dnf -y install aria2 unzip

ARIA_PATH="$ARIA2_ROOT"
FTP_PATH=$(config_get "ftp" "path")
PORT=$(config_get "ports" "aria2")
TOKEN=$(config_get "aria2" "token")

# 创建配置目录和空文件
mkdir -p "$ARIA_PATH"
touch "${ARIA_PATH}/aria2.log" "${ARIA_PATH}/session.dat"

# 【修复 1】关键权限设置
# 将 /etc/aria2 目录的所有权移交给 nginx 用户
log "设置 Aria2 目录权限..."
chown -R nginx:nginx "$ARIA_PATH"

# 生成配置文件
install_template "configs/aria2.conf" "${ARIA_PATH}/aria2.conf" \
    "ARIA2_PATH=$ARIA_PATH" \
    "FTP_PATH=$FTP_PATH" \
    "ARIA2_PORT=$PORT" \
    "ARIA2_TOKEN=$TOKEN"

# 【修复 2】强制禁用 IPv6
# 防止在不支持 IPv6 的 VPS 上启动失败
append_config "${ARIA_PATH}/aria2.conf" "disable-ipv6=true"

# 安装 Systemd 服务文件
install_template "services/aria2.service" "${OS_SYSTEM_PATH}/aria2.service" \
    "ARIA2_PATH=$ARIA_PATH" \
    "ARIA2_CONFIG=aria2.conf" \
    "FTP_PATH=$FTP_PATH" # <-- 【已修复】添加 FTP_PATH 变量替换

# 配置防火墙
# 【修复 4】Aria2 RPC 端口 (6800) 仅监听本地 (127.0.0.1)，通过 Nginx 反代对外，不应开放防火墙端口
log "警告：Aria2 RPC 端口 $PORT 仅监听本地，跳过防火墙开放。"
# firewall-cmd --add-port=${PORT}/tcp --permanent
# firewall-cmd --reload

# 启动服务
start_service "aria2"

# ============================================
# 【新增】安装 AriaNg Web 前端
# (已注释 - 移除 AriaNg UI)
# ============================================
# log ">>> [AriaNg] 安装 Web 前端..."

# DOMAIN=$(config_get "nginx" "domain")
# Nginx 默认站点目录（由 modules/02-nginx.sh 创建）
# WEB_ROOT="${NGINX_WEB_ROOT_BASE}/${DOMAIN}"

# if [[ -z "$DOMAIN" ]]; then
#     warn "未找到域名配置，跳过 AriaNg 安装"
# else
#     # 确保目录存在
#     # mkdir -p "$WEB_ROOT"

#     # log "下载 AriaNg (AllInOne)..."
#     # ARIANG_URL="https://github.com/mayswind/AriaNg/releases/download/1.3.7/AriaNg-1.3.7-AllInOne.zip"
    
#     # 下载并解压
#     # if wget -q -O /tmp/ariang.zip "$ARIANG_URL"; then
#     #     log "部署到网站根目录..."
#     #     # 解压会覆盖目录下的 index.html
#     #     unzip -o /tmp/ariang.zip -d "$WEB_ROOT"
#     #     rm -f /tmp/ariang.zip
        
#     #     # 设置权限
#     #     chown -R nginx:nginx "$WEB_ROOT"
        
#     #     log "✓ AriaNg 安装完成"
#     #     log "  访问地址: https://${DOMAIN}"
#     # else
#     #     warn "AriaNg 下载失败，请检查网络连接"
#     # fi
# fi
