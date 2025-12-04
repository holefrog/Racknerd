#!/bin/bash
# ============================================
# Certbot Deploy Hook for V2Ray
# 自动生成于 $(date '+%Y-%m-%d %H:%M:%S')
# ============================================

CERT_DIR="@@V2RAY_ROOT@@"
SERVICE="v2ray"
DOMAIN_NAME="@@DOMAIN@@"
LOG_FILE="@@CERT_RENEW_LOG_FILE@@"

echo "[V2Ray Hook] Starting sync process for domain: $DOMAIN_NAME" | tee -a "$LOG_FILE"

# 检查证书是否已续期并且是当前域名的证书
# $RENEWED_DOMAINS 是一个空格分隔的域名列表
if [ -f "$RENEWED_LINEAGE/fullchain.pem" ]; then
    # 查找当前域名是否在续期列表中
    if echo "$RENEWED_DOMAINS" | grep -qE "(^| )$DOMAIN_NAME( |$)"; then
        echo "[V2Ray Hook] Certificate for $DOMAIN_NAME renewed. Syncing..." | tee -a "$LOG_FILE"
        
        # 复制证书
        cp "$RENEWED_LINEAGE/fullchain.pem" "$CERT_DIR/fullchain.pem"
        cp "$RENEWED_LINEAGE/privkey.pem" "$CERT_DIR/privkey.pem"
        
        # 设置权限，让 nginx 用户可读
        chown nginx:nginx "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem"
        chmod 600 "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem"
        
        # 重启 V2Ray
        if systemctl is-active --quiet $SERVICE; then
            echo "[V2Ray Hook] Restarting $SERVICE..." | tee -a "$LOG_FILE"
            systemctl restart $SERVICE
        else
            echo "[V2Ray Hook] $SERVICE is not active. Skipping restart." | tee -a "$LOG_FILE"
        fi
    else
        echo "[V2Ray Hook] Certificate renewed, but not for $DOMAIN_NAME. Skipping V2Ray restart." | tee -a "$LOG_FILE"
    fi
fi
