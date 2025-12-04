#!/usr/bin/env bash
source lib/utils.sh

log ">>> [Nginx] 开始安装 Web 服务器及配置 SSL..."

# 安装 Nginx 和 Certbot
log "安装 Nginx 软件包..."
dnf -y install nginx certbot python3-certbot-nginx

# 读取配置参数
DOMAIN=$(config_get "nginx" "domain")
EMAIL=$(config_get "nginx" "email")
CERT_PATH="${LETSENCRYPT_LIVE_DIR}/${DOMAIN}"
TARGET_CONF="${NGINX_SITE_CONF_DIR}/${DOMAIN}.conf"
SITE_ROOT="${NGINX_WEB_ROOT_BASE}/${DOMAIN}"

# 开放防火墙端口
systemctl is-active --quiet firewalld || start_service "firewalld"
firewall-cmd --add-service=http --add-service=https --permanent >/dev/null 2>&1
firewall-cmd --reload >/dev/null 2>&1

# 部署基础配置结构
mkdir -p "${NGINX_CONF_ROOT}/includes"
install_template "configs/nginx.conf" "$NGINX_MAIN_CONF" "UPSTREAM_CONF=${NGINX_CONF_ROOT}/upstream.conf"
install_template "configs/includes/ssl-params.conf" "${NGINX_CONF_ROOT}/includes/ssl-params.conf"
install_template "configs/includes/security-headers.conf" "${NGINX_CONF_ROOT}/includes/security-headers.conf"

# 预创建 WebDAV 包含文件，防止 Nginx 启动报错
WEBDAV_INCLUDE_FILE="${NGINX_SITE_CONF_DIR}/includes/webdav-locations.conf"
mkdir -p "$(dirname "$WEBDAV_INCLUDE_FILE")"
[[ ! -f "$WEBDAV_INCLUDE_FILE" ]] && touch "$WEBDAV_INCLUDE_FILE"

# 配置反向代理 Upstream
ARIA_PORT=$(config_get "ports" "aria2")
V2_PORT=$(config_get "ports" "v2ray")
USE_UPSTREAM=$(config_get "nginx" "use_upstream" "no")

if [[ "$USE_UPSTREAM" == "yes" ]]; then
    install_template "configs/nginx.upstream.conf" "${NGINX_CONF_ROOT}/upstream.conf" "ARIA_PORT=$ARIA_PORT" "V2_PORT=$V2_PORT"
    ARIA2_TARGET="aria2_backend"
    V2RAY_TARGET="v2ray_backend"
else
    touch "${NGINX_CONF_ROOT}/upstream.conf"
    ARIA2_TARGET="127.0.0.1:${ARIA_PORT}"
    V2RAY_TARGET="127.0.0.1:${V2_PORT}"
fi

# 部署默认站点文件
mkdir -p "$SITE_ROOT"
cp templates/web/* "$SITE_ROOT/" 2>/dev/null || true
chown -R nginx:nginx "$SITE_ROOT"

# 申请 SSL 证书
if [[ ! -f "$CERT_PATH/fullchain.pem" ]]; then
    log "正在申请 Let's Encrypt SSL 证书..."
    # 创建临时验证站点配置
    cat > "$TARGET_CONF" << EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root ${SITE_ROOT};
    location /.well-known/acme-challenge/ { root ${SITE_ROOT}; }
    location / { return 404; }
}
EOF
    systemctl start nginx
    # 执行证书申请
    certbot certonly --webroot -w "$SITE_ROOT" -d "$DOMAIN" --email "$EMAIL" --agree-tos -n || {
        systemctl stop nginx 2>/dev/null
        error "证书申请失败，请检查域名解析是否正确"
    }
fi

# 部署正式站点配置
install_template "configs/site.conf" "$TARGET_CONF" \
    "DOMAIN=$DOMAIN" \
    "CERT_PATH=$CERT_PATH" \
    "V2RAY_URL=$(config_get "v2ray" "path_url")" \
    "ARIA2_PROXY_TARGET=$ARIA2_TARGET" \
    "V2RAY_PROXY_TARGET=$V2RAY_TARGET"

# 配置证书自动续期脚本
install_template "scripts/renew-cert.sh" "$SCRIPT_RENEW_CERT" \
    "CERT_LOG_PATH=$CERT_RENEW_LOG_FILE" \
    "V2RAY_CERT_ROOT=$V2RAY_ROOT" \
    "LETSENCRYPT_LIVE_DIR=$LETSENCRYPT_LIVE_DIR"
chmod +x "$SCRIPT_RENEW_CERT"

install_template "cron/certbot-renew.cron" "$CRON_CERT_RENEW_FILE" \
    "SCRIPT_RENEW_CERT=$SCRIPT_RENEW_CERT" \
    "CERT_RENEW_LOG_FILE=$CERT_RENEW_LOG_FILE"

# 验证并启动
nginx -t || error "Nginx 配置文件校验失败"
start_service "nginx"

log ">>> [Nginx] 安装配置完成 - https://${DOMAIN}"
