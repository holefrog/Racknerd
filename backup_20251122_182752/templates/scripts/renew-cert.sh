#!/bin/bash
# ============================================
# SSL 证书自动续期脚本（修复版）
# ============================================

set -e

# 路径现在通过模板变量传入并替换
LOGFILE="${CERT_LOG_PATH}"
V2RAY_CERT_PATH="${V2RAY_CERT_ROOT}"
LETSENCRYPT_LIVE_DIR="${LE_LIVE_DIR}"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

log_message "=========================================="
log_message "开始证书续期流程"
log_message "=========================================="

# 停止 Nginx（释放 80 端口供 certbot 验证）
log_message "停止 Nginx 服务..."
systemctl stop nginx

# 续期证书（使用 renew 而不是 --force-renewal）
log_message "执行证书续期..."
if certbot renew --quiet --deploy-hook "echo 'Certificate renewed successfully'"; then
    log_message "✓ 证书续期成功"
    RENEWED=true
else
    log_message "✗ 证书续期失败或证书未到期"
    RENEWED=false
fi

# 启动 Nginx
log_message "启动 Nginx 服务..."
if systemctl start nginx; then
    log_message "✓ Nginx 已启动"
else
    log_message "✗ Nginx 启动失败！"
    exit 1
fi

# 【修复 7】如果证书更新，同步到 V2Ray 目录并重启服务
if [ "$RENEWED" = true ]; then
    log_message "同步证书到 V2Ray 目录..."
    
    # 查找所有域名的证书
    for domain_dir in ${LETSENCRYPT_LIVE_DIR}/*/; do
        if [ -d "$domain_dir" ] && [ -f "${domain_dir}fullchain.pem" ]; then
            domain=$(basename "$domain_dir")
            log_message "处理域名: $domain"
            
            # 复制证书到 V2Ray 目录
            cp "${domain_dir}fullchain.pem" "${V2RAY_CERT_PATH}/fullchain.pem"
            cp "${domain_dir}privkey.pem" "${V2RAY_CERT_PATH}/privkey.pem"
            
            # 设置权限
            chown nginx:nginx "${V2RAY_CERT_PATH}/fullchain.pem" "${V2RAY_CERT_PATH}/privkey.pem"
            chmod 600 "${V2RAY_CERT_PATH}/fullchain.pem" "${V2RAY_CERT_PATH}/privkey.pem"
            
            log_message "✓ 证书已同步到 V2Ray"
        fi
    done
    
    # 重启 V2Ray 服务
    if systemctl is-active v2ray &>/dev/null; then
        log_message "重启 V2Ray 服务..."
        if systemctl restart v2ray; then
            log_message "✓ V2Ray 已重启"
        else
            log_message "✗ V2Ray 重启失败！"
        fi
    else
        log_message "V2Ray 服务未运行，跳过重启"
    fi
fi

log_message "证书续期流程完成"
log_message "=========================================="

# 清理旧日志（保留最近 1000 行）
tail -n 1000 "$LOGFILE" > "${LOGFILE}.tmp"
mv "${LOGFILE}.tmp" "$LOGFILE"
