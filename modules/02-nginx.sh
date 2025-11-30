#!/usr/bin/env bash
source lib/utils.sh

log ">>> [Nginx] 安装 Nginx & SSL..."
dnf -y install nginx certbot python3-certbot-nginx

DOMAIN=$(config_get "nginx" "domain")
EMAIL=$(config_get "nginx" "email")
CERT_PATH="${LETSENCRYPT_LIVE_DIR}/${DOMAIN}"
TARGET_CONF="${NGINX_SITE_CONF_DIR}/${DOMAIN}.conf"
SITE_ROOT="${NGINX_WEB_ROOT_BASE}/${DOMAIN}" 

# 开放防火墙
log "开放 HTTP/HTTPS 端口..."

# 【FIX 6: 确保 firewalld 运行并启用】
if ! systemctl is-active --quiet firewalld; then
    log "检测到 firewalld 未运行或未启用，正在尝试启动..."
    # start_service 会处理 enable 和 restart/start 逻辑
    start_service "firewalld"
    log "firewalld 已启动并启用。"
fi

firewall-cmd --add-service=http --add-service=https --permanent
firewall-cmd --reload

# ============================================
# 【第一步】配置 Nginx 主配置文件和通用 Include
# ============================================
log "配置 Nginx 主配置和通用 Include..."

# 读取 Upstream 路径变量
UPSTREAM_CONF="${NGINX_CONF_ROOT}/upstream.conf"

# 安装主配置文件
# 【FIX 3: 将动态的 UPSTREAM_CONF 路径传递给 nginx.conf 模板】
install_template "configs/nginx.conf" "$NGINX_MAIN_CONF" \
    "UPSTREAM_CONF=$UPSTREAM_CONF"

# 创建 Nginx Include 目录和文件
mkdir -p "${NGINX_CONF_ROOT}/includes"
install_template "configs/includes/ssl-params.conf" "${NGINX_CONF_ROOT}/includes/ssl-params.conf"
install_template "configs/includes/security-headers.conf" "${NGINX_CONF_ROOT}/includes/security-headers.conf"

# ============================================
# 【第二步：Upstream 配置】
# ============================================

# 读取端口变量
ARIA_PORT=$(config_get "ports" "aria2")
V2_PORT=$(config_get "ports" "v2ray")
V2_URL=$(config_get "v2ray" "path_url")
USE_UPSTREAM=$(config_get "nginx" "use_upstream" "no")

if [[ -f "$TARGET_CONF" ]]; then
    log "检测到旧的站点配置文件，正在使用 safe_remove 确保纯净覆盖: $TARGET_CONF"
    safe_remove "$TARGET_CONF"
fi

if [[ "$USE_UPSTREAM" == "yes" ]]; then
    log "启用 Upstream 优化模式..."
    ARIA2_PROXY_TARGET="aria2_backend"
    V2RAY_PROXY_TARGET="v2ray_backend"
    log "创建 Upstream 定义文件: $UPSTREAM_CONF"
    install_template "configs/nginx.upstream.conf" "$UPSTREAM_CONF" \
        "ARIA_PORT=$ARIA_PORT" \
        "V2_PORT=$V2_PORT"
    log "✓ Upstream 配置已生成"
else
    log "启用 Direct IP:Port 模式..."
    ARIA2_PROXY_TARGET="127.0.0.1:${ARIA_PORT}"
    V2RAY_PROXY_TARGET="127.0.0.1:${V2_PORT}"
    if [[ -f "$UPSTREAM_CONF" ]]; then
        log "Upstream 模式未启用，删除旧的 Upstream 配置: $UPSTREAM_CONF"
        rm -f "$UPSTREAM_CONF"
    fi
    touch "$UPSTREAM_CONF"
    log "创建空 Upstream 文件以避免 Nginx 报错: $UPSTREAM_CONF"
fi

# ============================================
# 【第三步：核心】证书申请与部署逻辑 (新算法)
# ============================================

# 标记：Certbot 是否需要运行
RUN_CERTBOT=false
if [[ ! -f "$CERT_PATH/fullchain.pem" ]]; then
    log "检测到证书文件不存在，将进入 Certbot 申请流程..."
    RUN_CERTBOT=true
else
    log "证书文件已存在，跳过 Certbot 申请。"
fi

# 确保站点根目录和静态文件存在
log "部署静态文件到站点根目录: $SITE_ROOT"
mkdir -p "$SITE_ROOT"
cp templates/web/* "$SITE_ROOT/" 2>/dev/null || true
chown -R nginx:nginx "$SITE_ROOT"

if [[ "$RUN_CERTBOT" == "true" ]]; then
    # -------------------------------------------------------------
    # 阶段 A: 部署临时 HTTP 配置并申请证书
    # -------------------------------------------------------------
    log "部署临时 HTTP 配置 ($TARGET_CONF)，确保 Nginx 可以启动..."
    
    # **新算法核心:** 部署一个只包含 HTTP 监听和 webroot 验证的配置文件
    cat > "$TARGET_CONF" << EOF
# ============================================
# Nginx 站点配置 (临时 Certbot 验证模式)
# ============================================
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    # 根目录指令 (应用于所有 location)
    root ${SITE_ROOT};
    
    # 【FIX 7: 确保 Certbot 验证不会受限于 client_max_body_size】
    client_max_body_size 0;
    
    # 仅允许 Certbot 验证
    location /.well-known/acme-challenge/ {
        # 【FIX 1: 显式指定 root 路径，确保 Certbot webroot 验证成功】
        root ${SITE_ROOT}; 
    }
    
    # 阻止所有其他访问，避免意外流量
    location / {
        return 404;
    }
}
EOF
    
    log "启动 Nginx 以供 Certbot 验证..."
    # 强制启动，如果失败则直接报错退出，避免 Certbot 尝试连接被拒
    systemctl start nginx || error "Nginx 启动失败！即使使用临时配置也无法启动，请检查系统和日志！"

    log "执行 SSL 证书申请 (使用 --webroot 模式)..."
    if ! certbot certonly --webroot -w "$SITE_ROOT" -d "$DOMAIN" --email "$EMAIL" --agree-tos -n; then
        # Certbot 失败，尝试停止 Nginx (如果还在运行)
        systemctl stop nginx 2>/dev/null || true
        error "SSL 证书申请失败！请检查：DNS 解析、防火墙 80 端口，并查看 Certbot 日志。"
    fi
    
    log "✓ SSL 证书申请成功"
fi

# -------------------------------------------------------------
# 阶段 B: 部署最终优化 HTTPS 配置 (无论是首次还是更新，都执行此步骤)
# -------------------------------------------------------------

log "部署最终优化站点配置 (含 HTTPS, Aria2, V2Ray)..."

# 重新部署完整的 site.conf，这次证书文件已存在或已跳过 Certbot
install_template "configs/site.conf" "$TARGET_CONF" \
    "DOMAIN=$DOMAIN" \
    "CERT_PATH=$CERT_PATH" \
    "V2RAY_URL=$V2_URL" \
    "ARIA2_PROXY_TARGET=$ARIA2_PROXY_TARGET" \
    "V2RAY_PROXY_TARGET=$V2RAY_PROXY_TARGET"

# 证书文件验证
if [[ ! -f "$CERT_PATH/fullchain.pem" ]]; then
    error "致命错误: 证书文件不存在，无法部署 HTTPS 配置！"
fi

# ============================================
# 【第四步】配置证书续期
# ============================================

log "配置证书自动续期..."
# 【FIX 4/5】确保脚本安装到绝对路径 $SCRIPT_RENEW_CERT，并使用正确的变量名
install_template "scripts/renew-cert.sh" "$SCRIPT_RENEW_CERT" \
    "CERT_LOG_PATH=$CERT_RENEW_LOG_FILE" \
    "V2RAY_CERT_ROOT=$V2RAY_ROOT" \
    "LETSENCRYPT_LIVE_DIR=$LETSENCRYPT_LIVE_DIR"
chmod +x "$SCRIPT_RENEW_CERT"

log "安装 Certbot Cron 定时任务: $CRON_CERT_RENEW_FILE"
# 【FIX 4】确保 Cron 模板替换时使用的是绝对路径
install_template "cron/certbot-renew.cron" "$CRON_CERT_RENEW_FILE" \
    "SCRIPT_RENEW_CERT=$SCRIPT_RENEW_CERT" \
    "CERT_RENEW_LOG_FILE=$CERT_RENEW_LOG_FILE"


# ============================================
# 测试并启动 Nginx (最终步骤)
# ============================================
log "测试 Nginx 配置..."
if ! nginx -t; then
    error "Nginx 最终配置错误！
    
请检查配置文件：
$NGINX_MAIN_CONF
${TARGET_CONF}
${UPSTREAM_CONF:-}

查看详细错误：
nginx -t"
fi

# 【FIX 2 核心】删除危险的 pkill -9 流程，依赖 systemctl restart 实现优雅切换
log "启动 Nginx 服务..."

# 使用 start_service 替换之前的 pkill -9/fuser/start 组合，start_service 内部执行 systemctl restart
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
log "  自动续期: 每月 1 号凌晨 2 点 (通过 renew-cert.sh)"
log "  续期脚本: $SCRIPT_RENEW_CERT"
log "  续期日志: $CERT_RENEW_LOG_FILE"
log ""
log "测试命令："
log "  curl -I https://$DOMAIN"
log "  openssl s_client -connect $DOMAIN:443 -servername $DOMAIN"
log ""
log "=========================================="
