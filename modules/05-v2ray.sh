#!/usr/bin/env bash
source lib/utils.sh

log ">>> [V2Ray] 安装..."

# 定义路径
V2RAY_PATH="$V2RAY_ROOT"
V2RAY_LOG_DIR="/var/log/v2ray" # <--- 【FIX 8】定义新的日志目录
mkdir -p "$V2RAY_PATH"

# 【修复 5】版本锁定，避免使用 latest
# 【修复 19】允许在 config.ini 中指定版本
V2RAY_VERSION=$(config_get "v2ray" "version")
if [[ -z "$V2RAY_VERSION" ]]; then
    V2RAY_VERSION="v5.40.0" # 默认稳定版本
fi
V2RAY_URL="https://github.com/v2fly/v2ray-core/releases/download/${V2RAY_VERSION}/v2ray-linux-64.zip"

# 下载 V2Ray（带重试机制）
if [ ! -f "$V2RAY_PATH/v2ray" ]; then
    log "下载 V2Ray Core (${V2RAY_VERSION})..."
    log "URL: ${V2RAY_URL}"
    
    cd /tmp
    
    # 重试下载 3 次
    RETRY_COUNT=3
    for i in $(seq 1 $RETRY_COUNT); do
        if wget --show-progress -O v2ray.zip "$V2RAY_URL" 2>/dev/null; then
            log "✓ 下载成功"
            break
        else
            if [ $i -lt $RETRY_COUNT ]; then
                warn "下载失败，正在重试 ($i/$RETRY_COUNT)..."
                sleep 5
            else
                error "下载失败，已重试 $RETRY_COUNT 次。请检查网络连接。"
            fi
        fi
    done
    
    unzip -o v2ray.zip -d "$V2RAY_PATH"
    chmod +x "$V2RAY_PATH/v2ray"
    rm -f v2ray.zip
fi

# 读取配置变量
PORT=$(config_get "ports" "v2ray")
UUID=$(config_get "v2ray" "uuid")
[[ -z "$UUID" ]] && UUID=$(uuidgen)
DOMAIN=$(config_get "nginx" "domain")
V2_URL=$(config_get "v2ray" "path_url")

# 【修复 1】处理证书权限问题 (新方案：首次复制 + Certbot Hook 自动同步)
LETSENCRYPT_CERT="${LETSENCRYPT_LIVE_DIR}/${DOMAIN}"
CERT_FULLCHAIN="$V2RAY_PATH/fullchain.pem"
CERT_PRIVKEY="$V2RAY_PATH/privkey.pem"

log "配置 TLS 证书..."
if [ -d "$LETSENCRYPT_CERT" ]; then
    # 首次安装：复制证书到 V2Ray 目录
    cp "$LETSENCRYPT_CERT/fullchain.pem" "$CERT_FULLCHAIN"
    cp "$LETSENCRYPT_CERT/privkey.pem" "$CERT_PRIVKEY"
    
    # 设置权限，让 nginx 用户可读
    chown nginx:nginx "$CERT_FULLCHAIN" "$CERT_PRIVKEY"
    chmod 600 "$CERT_FULLCHAIN" "$CERT_PRIVKEY"
    
    log "✓ 证书已复制到 V2Ray 目录"
    
    # 【修复 2】创建 Certbot Hook 脚本以实现证书自动同步
    log "创建 Certbot Hook 脚本以实现证书自动同步..."
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    
    HOOK_SCRIPT="/etc/letsencrypt/renewal-hooks/deploy/sync-v2ray-cert.sh"
    # 使用模板生成 Hook 脚本
    install_template "scripts/v2ray-cert-hook.sh" "$HOOK_SCRIPT" \
        "V2RAY_ROOT=$V2RAY_ROOT" \
        "DOMAIN=$DOMAIN" \
        "CERT_RENEW_LOG_FILE=$CERT_RENEW_LOG_FILE"
    
    chmod +x "$HOOK_SCRIPT"
    log "✓ Certbot Hook 已创建"
    
else
    error "找不到 SSL 证书: $LETSENCRYPT_CERT
请确保 Nginx 模块已成功运行并申请了证书。"
fi


# 写入服务端配置（修复了 TLS 配置）
install_template "configs/v2ray.json" "${V2RAY_PATH}/v2ray.json" \
    "V2RAY_PATH=$V2RAY_PATH" \
    "V2RAY_PORT=$PORT" \
    "V2RAY_UUID=$UUID" \
    "DOMAIN=$DOMAIN" \
    "CERT_FULLCHAIN=$CERT_FULLCHAIN" \
    "CERT_PRIVKEY=$CERT_PRIVKEY" \
    "V2RAY_URL=$V2_URL" \
    "V2RAY_LOG_DIR=$V2RAY_LOG_DIR" # <--- 【FIX 8】传递新的日志目录变量

# 写入客户端配置（供下载）
install_template "configs/vmess_client.json" "${V2RAY_PATH}/vmess_client.json" \
    "DOMAIN=$DOMAIN" \
    "V2RAY_PORT=$PORT" \
    "V2RAY_UUID=$UUID" \
    "V2RAY_URL=$V2_URL"

# 生成订阅
FTP_PATH=$(config_get "ftp" "path")
base64 -w0 "${V2RAY_PATH}/vmess_client.json" > "$FTP_PATH/v2ray_sub.txt"
chmod 644 "$FTP_PATH/v2ray_sub.txt"

# 安装服务
install_template "services/v2ray.service" "${OS_SYSTEM_PATH}/v2ray.service" \
    "V2RAY_PATH=$V2RAY_PATH" \
    "V2RAY_CONFIG=v2ray.json"

# 【安全修复】V2Ray 端口仅监听 127.0.0.1，不应对公网开放防火墙。
log "安全警告：V2Ray 端口 $PORT 仅监听本地，跳过防火墙开放。"
# firewall-cmd --add-port=${PORT}/tcp --permanent
# firewall-cmd --reload


# 【修复】关键：设置 V2Ray 目录所有权，并创建日志目录
log "设置 V2Ray 目录权限..."
# 确保配置目录权限正确
chown -R nginx:nginx "$V2RAY_PATH"
# 【FIX 8】创建日志目录并设置权限
mkdir -p "$V2RAY_LOG_DIR"
chown -R nginx:nginx "$V2RAY_LOG_DIR"

# 启动服务
start_service "v2ray"

log "✓ V2Ray 安装完成"
log "  UUID: $UUID"
log "  端口: $PORT"
log "  路径: /$V2_URL"
log "  订阅文件: $FTP_PATH/v2ray_sub.txt"
