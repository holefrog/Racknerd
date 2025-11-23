#!/usr/bin/env bash
source lib/utils.sh

log ">>> [Nginx] 安装 Nginx & SSL..."
dnf -y install nginx certbot python3-certbot-nginx

DOMAIN=$(config_get "nginx" "domain")
EMAIL=$(config_get "nginx" "email")
CERT_PATH="${LETSENCRYPT_LIVE_DIR}/${DOMAIN}"

# 开放防火墙
log "开放 HTTP/HTTPS 端口..."
firewall-cmd --add-service=http --add-service=https --permanent
firewall-cmd --reload

# ============================================
# 【第一步】配置 Nginx 主配置文件
# ============================================
log "配置 Nginx 主配置..."

# 安装主配置文件
install_template "configs/nginx.conf" "$NGINX_MAIN_CONF"

# ============================================
# 【第二步：Upstream 配置】
# ============================================

# 读取端口变量
ARIA_PORT=$(config_get "ports" "aria2")
V2_PORT=$(config_get "ports" "v2ray")
V2_URL=$(config_get "v2ray" "path_url")

TARGET_CONF="${NGINX_SITE_CONF_DIR}/${DOMAIN}.conf"

# 【修复 1：主动删除旧文件】
if [[ -f "$TARGET_CONF" ]]; then
    log "检测到旧的站点配置文件，正在使用 safe_remove 确保纯净覆盖: $TARGET_CONF"
    safe_remove "$TARGET_CONF"
fi

# ============================================
# 【重构：集中处理 Upstream 逻辑】
# ============================================
USE_UPSTREAM=$(config_get "nginx" "use_upstream" "no")

# 定义 Nginx Connection Headers（使用换行符 \n）
# Aria2 RPC headers (Keep-Alive + WebSocket for WebUI)
ARIA2_HEADERS='proxy_http_version 1.1;\n        proxy_set_header Connection "";\n        proxy_set_header Upgrade $http_upgrade;\n        proxy_set_header Connection "Upgrade";'

# V2Ray WebSocket headers
V2RAY_HEADERS='proxy_http_version 1.1;\n        proxy_set_header Upgrade $http_upgrade;\n        proxy_set_header Connection "upgrade";'


if [[ "$USE_UPSTREAM" == "yes" ]]; then
    log "启用 Upstream 优化模式..."
    
    # 目标：使用 Upstream 名称
    ARIA2_PROXY_TARGET="aria2_backend"
    V2RAY_PROXY_TARGET="v2ray_backend"
    
    # 创建 Upstream 定义文件
    UPSTREAM_CONF="${NGINX_SITE_CONF_DIR}/00-upstream.conf"
    log "创建 Upstream 定义文件: $UPSTREAM_CONF"
    
    cat > "$UPSTREAM_CONF" << EOF
# Upstream 定义（必须在 http 块内）
upstream aria2_backend {
    server 127.0.0.1:${ARIA_PORT} max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream v2ray_backend {
    server 127.0.0.1:${V2_PORT} max_fails=3 fail_timeout=30s;
    keepalive 32;
}
EOF
    
    log "✓ Upstream 配置已生成"

else
    log "启用 Direct IP:Port 模式..."
    
    # 目标：使用 IP:Port
    ARIA2_PROXY_TARGET="127.0.0.1:${ARIA_PORT}"
    V2RAY_PROXY_TARGET="127.0.0.1:${V2_PORT}"
    
    # 如果 00-upstream.conf 存在，需要删除
    UPSTREAM_CONF="${NGINX_SITE_CONF_DIR}/00-upstream.conf"
    if [[ -f "$UPSTREAM_CONF" ]]; then
        log "Upstream 模式未启用，删除旧的 Upstream 配置: $UPSTREAM_CONF"
        rm -f "$UPSTREAM_CONF"
    fi
fi


# ============================================
# 【第三步：核心】Certbot 幂等性处理
# ============================================
# 标记：Certbot 是否需要运行
RUN_CERTBOT=false
if [[ ! -f "$CERT_PATH/fullchain.pem" ]]; then
    log "检测到证书文件不存在，将进入 Certbot 申请流程..."
    RUN_CERTBOT=true
else
    log "证书文件已存在，跳过 Certbot 申请，直接部署最终配置。"
fi

# 1. 部署初始或最终配置
# 无论是否需要申请证书，都先部署模板。
log "部署 Nginx 站点配置 ($TARGET_CONF)..."
install_template "configs/site.conf" "$TARGET_CONF" \
    "DOMAIN=$DOMAIN" \
    "CERT_PATH=$CERT_PATH" \
    "V2RAY_URL=$V2_URL" \
    "ARIA2_PROXY_TARGET=$ARIA2_PROXY_TARGET" \
    "V2RAY_PROXY_TARGET=$V2RAY_PROXY_TARGET" \
    "ARIA2_HEADERS=$ARIA2_HEADERS" \
    "V2RAY_HEADERS=$V2RAY_HEADERS"

if [[ "$RUN_CERTBOT" == "true" ]]; then
    # -------------------------------------------------------------
    # 阶段 A: 证书申请 (临时禁用 HTTPS)
    # -------------------------------------------------------------
    
    # 修复：临时修改站点配置，让 Nginx 能够启动（只监听 80 端口）
    log "临时注释掉 site.conf 中的 HTTPS 端口和证书路径以供 Certbot 申请证书..."
    
    # 使用 TEMP_CERT_FIX 标记进行临时注释
    # 注释所有监听 443 的行
    sed -i '/listen 443 ssl http2/s/^/# TEMP_CERT_FIX /' "$TARGET_CONF"
    # 注释所有 ssl_ 开头的行 (确保 Nginx 配置验证通过)
    sed -i '/ssl_/s/^/# TEMP_CERT_FIX /' "$TARGET_CONF"
    
    log "启动 Nginx 以供 Certbot 验证..."
    # Certbot 仅需要 Nginx 能够启动并通过 80 端口提供 .well-known
    systemctl start nginx || error "Nginx 启动失败，请检查配置和日志！"

    log "执行 SSL 证书申请..."
    # Certbot 成功后会自动取消注释 80 端口的重定向并插入正确的 443 配置
    if ! certbot certonly --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos -n; then
        error "SSL 证书申请失败！请检查：DNS 解析、防火墙 80/443 端口。"
    fi
    
    # -------------------------------------------------------------
    # 阶段 B: 部署最终优化配置 (覆盖 Certbot 的简单配置，确保幂等性)
    # -------------------------------------------------------------
    log "Certbot 成功，重新部署完整优化配置 (覆盖 Certbot 自动生成的配置)..."
    
    # 再次运行 install_template，这次证书已存在，将生成完整的优化配置。
    install_template "configs/site.conf" "$TARGET_CONF" \
        "DOMAIN=$DOMAIN" \
        "CERT_PATH=$CERT_PATH" \
        "V2RAY_URL=$V2_URL" \
        "ARIA2_PROXY_TARGET=$ARIA2_PROXY_TARGET" \
        "V2RAY_PROXY_TARGET=$V2RAY_PROXY_TARGET" \
        "ARIA2_HEADERS=$ARIA2_HEADERS" \
        "V2RAY_HEADERS=$V2RAY_HEADERS"

    # 证书文件验证
    if [[ ! -f "$CERT_PATH/fullchain.pem" ]]; then
        error "证书文件不存在: $CERT_PATH，Certbot 运行失败，请确保证书申请成功后再继续"
    fi
    log "✓ SSL 证书申请成功"
fi


# ============================================
# 【第四步】复制静态文件和配置证书续期
# ============================================

# 复制静态文件
log "部署静态文件..."
SITE_ROOT="${NGINX_WEB_ROOT_BASE}/${DOMAIN}"
mkdir -p "$SITE_ROOT"
cp templates/web/* "$SITE_ROOT/" 2>/dev/null || true

# 设置权限
chown -R nginx:nginx "$SITE_ROOT"

# 证书续期脚本
log "配置证书自动续期..."
install_template "scripts/renew-cert.sh" "$SCRIPT_RENEW_CERT" \
    "CERT_LOG_PATH=$CERT_RENEW_LOG_FILE" \
    "V2RAY_CERT_ROOT=$V2RAY_ROOT" \
    "LE_LIVE_DIR=$LETSENCRYPT_LIVE_DIR"
chmod +x "$SCRIPT_RENEW_CERT"

# 创建 cron 任务（每月 1 号凌晨 2 点）
echo "0 2 1 * * root $SCRIPT_RENEW_CERT >> $CERT_RENEW_LOG_FILE 2>&1" > "$CRON_CERT_RENEW_FILE"
chmod 644 "$CRON_CERT_RENEW_FILE"

# ============================================
# 测试并启动 Nginx (最终步骤)
# ============================================
log "测试 Nginx 配置..."
if ! nginx -t; then
    error "Nginx 配置错误！
    
请检查配置文件：
$NGINX_MAIN_CONF
${TARGET_CONF}
${UPSTREAM_CONF:-}

查看详细错误：
nginx -t"
fi

# 清理可能的僵尸进程
log "清理 Nginx 残留进程..."
pkill -9 nginx 2>/dev/null || true
sleep 2

# 确保端口已释放
if ss -tlnp | grep -q ":80 "; then
    warn "端口 80 仍被占用，尝试强制清理..."
    fuser -k 80/tcp 2>/dev/null || true
    sleep 2
fi

# 启动服务
log "启动 Nginx 服务..."
start_service "nginx"

# 验证服务状态
if systemctl is-active --quiet nginx; then
    log "✓ Nginx 已成功启动"
    
    # 显示监听端口
    log "监听端口："
    ss -tlnp | grep nginx || true
else
    error "Nginx 启动失败！
    
请检查：
1. 配置文件语法: nginx -t
2. 端口占用: ss -tlnp | grep ':80\\|:443'
3. 服务日志: journalctl -xeu nginx
4. 错误日志: tail -f /var/log/nginx/error.log"
fi

# ============================================
# 显示部署摘要
# ============================================
log ""
log "=========================================="
log "  ✅ Nginx 部署完成"
log "=========================================="
log ""
log "站点信息："
log "  域名: $DOMAIN"
log "  HTTPS: https://$DOMAIN"
log "  证书路径: $CERT_PATH"
log "  站点目录: $SITE_ROOT"
log ""
log "配置文件："
log "  主配置: $NGINX_MAIN_CONF"
log "  站点配置: ${TARGET_CONF}"
if [[ "$USE_UPSTREAM" == "yes" ]]; then
log "  Upstream: ${UPSTREAM_CONF}"
fi
log ""
log "证书管理："
log "  自动续期: 每月 1 号凌晨 2 点"
log "  续期脚本: $SCRIPT_RENEW_CERT"
log "  续期日志: $CERT_RENEW_LOG_FILE"
log ""
log "测试命令："
log "  curl -I https://$DOMAIN"
log "  openssl s_client -connect $DOMAIN:443 -servername $DOMAIN"
log ""
log "=========================================="
