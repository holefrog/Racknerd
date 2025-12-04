#!/bin/bash
# ============================================
# SSL 证书自动续期脚本（最终修复版 - 依赖 Certbot Hook）
# ============================================

set -e

# 路径现在通过模板变量传入并替换
# 外部模板变量使用 @@...@@
CERT_RENEW_LOG_PATH="@@CERT_LOG_PATH@@"
V2RAY_CERT_PATH="@@V2RAY_CERT_ROOT@@"
LETSENCRYPT_LIVE_DIR_PATH="@@LETSENCRYPT_LIVE_DIR@@"

log_message() {
    # 内部 Shell 变量使用 $... 或 ${...}
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$CERT_RENEW_LOG_PATH"
}

log_message "=========================================="
log_message "开始证书续期流程 (非中断模式)"
log_message "=========================================="

# 【修复 6】移除停止/启动 Nginx 的步骤，使用 Certbot Hooks

log_message "执行证书续期..."

# 使用 renew-hook 重载 Nginx，deploy-hook 触发 V2Ray 证书同步和重启
if certbot renew --quiet --renew-hook "systemctl reload nginx"; then
    log_message "✓ 证书续期成功或证书未到期"
    RENEWED=true
else
    log_message "✗ 证书续期失败"
    RENEWED=false
fi

# 移除手动同步 V2Ray 证书和重启的逻辑 (已移至 Certbot Hook)
if [ "$RENEWED" = true ]; then
    log_message "同步 V2Ray 证书和重启 V2Ray 的操作已转移到 Certbot 的 Deploy Hook 中，跳过手动执行。"
fi

log_message "证书续期流程完成"
log_message "=========================================="

# 清理旧日志（保留最近 1000 行）
# 确保日志清理使用正确的 Shell 变量扩展 ${...}.tmp，防止模板检查误报
tail -n 1000 "$CERT_RENEW_LOG_PATH" > "${CERT_RENEW_LOG_PATH}.tmp"
mv "${CERT_RENEW_LOG_PATH}.tmp" "$CERT_RENEW_LOG_PATH"

