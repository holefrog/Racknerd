#!/usr/bin/env bash
source lib/utils.sh

log ">>> [V2Ray] 安装..."

# 定义路径
V2RAY_PATH="$V2RAY_ROOT"
mkdir -p "$V2RAY_PATH"

# 【修复 5】版本锁定，避免使用 latest
V2RAY_VERSION="v5.40.0"
V2RAY_URL="https://github.com/v2fly/v2ray-core/releases/download/${V2RAY_VERSION}/v2ray-linux-64.zip"

# 下载 V2Ray（带重试机制）
if [ ! -f "$V2RAY_PATH/v2ray" ]; then
    log "下载 V2Ray Core (${V2RAY_VERSION})..."
    cd /tmp
    
    # 重试下载 3 次
    RETRY_COUNT=3
    for i in $(seq 1 $RETRY_COUNT); do
        if wget -q --show-progress -O v2ray.zip "$V2RAY_URL" 2>/dev/null; then
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

# 【修复 1】处理证书权限问题
# V2Ray 以 nginx 用户运行，无法读取 /etc/letsencrypt 的证书
# 解决方案：复制证书到 V2Ray 目录
LETSENCRYPT_CERT="${LETSENCRYPT_LIVE_DIR}/${DOMAIN}"

log "配置 TLS 证书..."
if [ -d "$LETSENCRYPT_CERT" ]; then
    # 复制证书到 V2Ray 目录
    cp "$LETSENCRYPT_CERT/fullchain.pem" "$V2RAY_PATH/fullchain.pem"
    cp "$LETSENCRYPT_CERT/privkey.pem" "$V2RAY_PATH/privkey.pem"
    
    # 设置权限，让 nginx 用户可读
    chown nginx:nginx "$V2RAY_PATH/fullchain.pem" "$V2RAY_PATH/privkey.pem"
    chmod 600 "$V2RAY_PATH/fullchain.pem" "$V2RAY_PATH/privkey.pem"
    
    CERT_FULLCHAIN="$V2RAY_PATH/fullchain.pem"
    CERT_PRIVKEY="$V2RAY_PATH/privkey.pem"
    
    log "✓ 证书已复制到 V2Ray 目录"
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
    "V2RAY_URL=$V2_URL"

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

# 开放防火墙
firewall-cmd --add-port=${PORT}/tcp --permanent
firewall-cmd --reload

# 【修复】关键：将 V2Ray 目录所有权移交给 nginx 用户
# 否则 V2Ray 无法创建日志文件，导致启动失败
log "设置 V2Ray 目录权限..."
chown -R nginx:nginx "$V2RAY_PATH"

# 启动服务
start_service "v2ray"

log "✓ V2Ray 安装完成"
log "  UUID: $UUID"
log "  端口: $PORT"
log "  路径: /$V2_URL"
log "  订阅文件: $FTP_PATH/v2ray_sub.txt"
