#!/usr/bin/env bash
source lib/utils.sh

log ">>> [WebDAV] 开始配置 WebDAV 文件服务..."

DOMAIN=$(config_get "nginx" "domain")
FTP_PATH=$(config_get "ftp" "path")
WEBDAV_USER=$(config_get "webdav" "user")
WEBDAV_PASS=$(config_get "webdav" "password")
FTP_USER=$(config_get "ftp" "user")

if [[ -z "$WEBDAV_USER" || -z "$WEBDAV_PASS" ]]; then
    warn "未检测到 WebDAV 配置，跳过。"
    exit 0
fi

# 安装 htpasswd 工具
dnf install -y httpd-tools

# 生成密码文件
HTPASSWD_FILE="/etc/nginx/.htpasswd_webdav"
safe_remove "$HTPASSWD_FILE"
htpasswd -cb "$HTPASSWD_FILE" "$WEBDAV_USER" "$WEBDAV_PASS"
chmod 600 "$HTPASSWD_FILE"
chown nginx:nginx "$HTPASSWD_FILE"

# 创建临时缓冲目录
WEBDAV_TEMP="/var/lib/nginx/webdav"
mkdir -p "$WEBDAV_TEMP"
chown -R nginx:nginx "$WEBDAV_TEMP"
chmod 755 "$WEBDAV_TEMP"

# 部署浏览器端功能脚本 (支持删除按钮)
SITE_ROOT="${NGINX_WEB_ROOT_BASE}/${DOMAIN}"
mkdir -p "$SITE_ROOT"
install_template "web/webdav_footer.html" "${SITE_ROOT}/webdav_footer.html"
chown nginx:nginx "${SITE_ROOT}/webdav_footer.html"
chmod 644 "${SITE_ROOT}/webdav_footer.html"

# 生成 Nginx Location 配置片段
WEBDAV_INCLUDE_DIR="${NGINX_SITE_CONF_DIR}/includes"
WEBDAV_INCLUDE_FILE="${WEBDAV_INCLUDE_DIR}/webdav-locations.conf"
mkdir -p "$WEBDAV_INCLUDE_DIR"

install_template "configs/includes/webdav-locations.conf" "$WEBDAV_INCLUDE_FILE" \
    "FTP_PATH=$FTP_PATH" \
    "HTPASSWD_FILE=$HTPASSWD_FILE" \
    "WEBDAV_TEMP=$WEBDAV_TEMP"

# 更新主站点配置以包含 WebDAV
TARGET_CONF="${NGINX_SITE_CONF_DIR}/${DOMAIN}.conf"
CERT_PATH="${LETSENCRYPT_LIVE_DIR}/${DOMAIN}"
V2_URL=$(config_get "v2ray" "path_url")
ARIA_PORT=$(config_get "ports" "aria2")
V2_PORT=$(config_get "ports" "v2ray")
USE_UPSTREAM=$(config_get "nginx" "use_upstream" "no")

if [[ "$USE_UPSTREAM" == "yes" ]]; then
    ARIA2_PROXY_TARGET="aria2_backend"
    V2RAY_PROXY_TARGET="v2ray_backend"
else
    ARIA2_PROXY_TARGET="127.0.0.1:${ARIA_PORT}"
    V2RAY_PROXY_TARGET="127.0.0.1:${V2_PORT}"
fi

install_template "configs/site.conf" "$TARGET_CONF" \
    "DOMAIN=$DOMAIN" \
    "CERT_PATH=$CERT_PATH" \
    "V2RAY_URL=$V2_URL" \
    "ARIA2_PROXY_TARGET=$ARIA2_PROXY_TARGET" \
    "V2RAY_PROXY_TARGET=$V2RAY_PROXY_TARGET"

# 调整目录权限以支持 WebDAV 和 Aria2 共同写入
chmod o+x /var 2>/dev/null || true
chmod o+x /var/ftp 2>/dev/null || true
chown -R "$FTP_USER:nginx" "$FTP_PATH"
# 设置 SGID 和组写入权限
find "$FTP_PATH" -type d -exec chmod 775 {} \; 2>/dev/null || true
find "$FTP_PATH" -type f -exec chmod 664 {} \; 2>/dev/null || true
chmod 2775 "$FTP_PATH"

# 重载 Nginx
if nginx -t; then
    systemctl reload nginx
else
    error "Nginx 配置校验失败，请检查配置文件。"
fi

log ">>> [WebDAV] 配置完成"
