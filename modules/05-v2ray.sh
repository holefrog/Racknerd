#!/usr/bin/env bash
source lib/utils.sh

log ">>> [V2Ray] 开始安装代理服务..."

# 检查并安装二维码生成工具
if ! command_exists qrencode; then
    log "正在安装 qrencode..."
    dnf install -y qrencode
fi

V2RAY_PATH="$V2RAY_ROOT"
V2RAY_LOG_DIR="/var/log/v2ray"
mkdir -p "$V2RAY_PATH"

# 确定版本
V2RAY_VERSION=$(config_get "v2ray" "version")
if [[ -z "$V2RAY_VERSION" ]]; then
    V2RAY_VERSION="v5.40.0"
fi
V2RAY_URL="https://github.com/v2fly/v2ray-core/releases/download/${V2RAY_VERSION}/v2ray-linux-64.zip"

# 下载 Core (含重试机制)
if [ ! -f "$V2RAY_PATH/v2ray" ]; then
    log "正在下载 V2Ray Core (${V2RAY_VERSION})..."
    cd /tmp
    
    RETRY_COUNT=3
    for i in $(seq 1 $RETRY_COUNT); do
        if wget --show-progress -O v2ray.zip "$V2RAY_URL" 2>/dev/null; then
            log "下载成功"
            break
        else
            if [ $i -lt $RETRY_COUNT ]; then
                warn "下载失败，正在重试 ($i/$RETRY_COUNT)..."
                sleep 5
            else
                error "下载失败，请检查网络。"
            fi
        fi
    done
    
    unzip -o v2ray.zip -d "$V2RAY_PATH" >/dev/null
    chmod +x "$V2RAY_PATH/v2ray"
    rm -f v2ray.zip
fi

# 准备配置参数
PORT=$(config_get "ports" "v2ray")
UUID=$(config_get "v2ray" "uuid")
[[ -z "$UUID" ]] && UUID=$(uuidgen)
DOMAIN=$(config_get "nginx" "domain")
V2_URL=$(config_get "v2ray" "path_url")

# 证书处理
LETSENCRYPT_CERT="${LETSENCRYPT_LIVE_DIR}/${DOMAIN}"
CERT_FULLCHAIN="$V2RAY_PATH/fullchain.pem"
CERT_PRIVKEY="$V2RAY_PATH/privkey.pem"

log "配置 TLS 证书..."
if [ -d "$LETSENCRYPT_CERT" ]; then
    cp "$LETSENCRYPT_CERT/fullchain.pem" "$CERT_FULLCHAIN"
    cp "$LETSENCRYPT_CERT/privkey.pem" "$CERT_PRIVKEY"
    
    # 确保证书权限正确
    chown nginx:nginx "$CERT_FULLCHAIN" "$CERT_PRIVKEY"
    chmod 600 "$CERT_FULLCHAIN" "$CERT_PRIVKEY"
    
    # 安装 Certbot Hook 实现证书自动同步
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    HOOK_SCRIPT="/etc/letsencrypt/renewal-hooks/deploy/sync-v2ray-cert.sh"
    install_template "scripts/v2ray-cert-hook.sh" "$HOOK_SCRIPT" \
        "V2RAY_ROOT=$V2RAY_ROOT" \
        "DOMAIN=$DOMAIN" \
        "CERT_RENEW_LOG_FILE=$CERT_RENEW_LOG_FILE"
    
    chmod +x "$HOOK_SCRIPT"
else
    error "未找到 SSL 证书: $LETSENCRYPT_CERT"
fi

# 生成服务端配置
install_template "configs/v2ray.json" "${V2RAY_PATH}/v2ray.json" \
    "V2RAY_PATH=$V2RAY_PATH" \
    "V2RAY_PORT=$PORT" \
    "V2RAY_UUID=$UUID" \
    "DOMAIN=$DOMAIN" \
    "CERT_FULLCHAIN=$CERT_FULLCHAIN" \
    "CERT_PRIVKEY=$CERT_PRIVKEY" \
    "V2RAY_URL=$V2_URL" \
    "V2RAY_LOG_DIR=$V2RAY_LOG_DIR"

# 生成客户端配置（用于订阅）
install_template "configs/vmess_client.json" "${V2RAY_PATH}/vmess_client.json" \
    "DOMAIN=$DOMAIN" \
    "V2RAY_PORT=$PORT" \
    "V2RAY_UUID=$UUID" \
    "V2RAY_URL=$V2_URL"

# 创建订阅文件及二维码
FTP_PATH=$(config_get "ftp" "path")
mkdir -p "$FTP_PATH"

# 1. 生成 Base64 订阅文本
# 将 VMess JSON 转换为 Base64 字符串 (注意 -w0 禁止换行)
VMESS_CODE=$(base64 -w0 "${V2RAY_PATH}/vmess_client.json")
# 手动拼接 'vmess://' 前缀并写入文件
echo "vmess://${VMESS_CODE}" > "$FTP_PATH/v2ray_sub.txt"
chmod 644 "$FTP_PATH/v2ray_sub.txt"

# 2. 生成二维码图片
log "生成订阅二维码..."
cat "$FTP_PATH/v2ray_sub.txt" | qrencode -o "$FTP_PATH/v2ray_sub.png" -s 10
chmod 644 "$FTP_PATH/v2ray_sub.png"

# 安装 Systemd 服务
install_template "services/v2ray.service" "${OS_SYSTEM_PATH}/v2ray.service" \
    "V2RAY_PATH=$V2RAY_PATH" \
    "V2RAY_CONFIG=v2ray.json"

# 修正权限
chown -R nginx:nginx "$V2RAY_PATH"
mkdir -p "$V2RAY_LOG_DIR"
chown -R nginx:nginx "$V2RAY_LOG_DIR"
# 确保 FTP 目录下的生成文件权限正确
chown nginx:nginx "$FTP_PATH/v2ray_sub.txt" "$FTP_PATH/v2ray_sub.png"

# 启动服务
start_service "v2ray"

log ">>> [V2Ray] 安装配置完成"
