#!/usr/bin/env bash
source lib/utils.sh

log ">>> [Logrotate] 配置日志轮转 (使用模板修复硬编码)..."

# ============================================
# 0. 动态获取配置 (用于模板替换)
# ============================================

# 使用环境变量
ARIA_LOG_FILE="${ARIA2_ROOT}/aria2.log"
# 【已修复】V2Ray 日志路径已移至 /var/log/v2ray
V2RAY_LOGS="/var/log/v2ray/access.log /var/log/v2ray/error.log"

# 脚本日志路径
CERT_RENEW_LOG="$CERT_RENEW_LOG_FILE"
CHANGEIP_LOG="$DDNS_LOG_FILE"

# 服务运行用户 (本项目中通常是 nginx，用于 Aria2/V2Ray)
SERVICE_USER="nginx"
SERVICE_GROUP="nginx"

log "配置参数:"
log "  Aria2 日志: $ARIA_LOG_FILE"
log "  V2Ray 日志: $V2RAY_LOGS"
log "  运行用户:   $SERVICE_USER:$SERVICE_GROUP"


# ============================================
# 1. 检查与安装
# ============================================
if ! command_exists logrotate; then
    log "Logrotate 未安装，正在安装..."
    dnf install -y logrotate
fi

if ! systemctl is-active --quiet crond; then
    log "启动 Crond 服务 (依赖项)..."
    systemctl enable --now crond
fi

# ============================================
# 2. 配置各服务轮转规则 (使用 install_template)
# ============================================

# 1. Aria2 日志轮转
install_template "logrotate/aria2" "${LOGROTATE_DIR}/aria2" \
    "ARIA_LOG_FILE=${ARIA_LOG_FILE}" \
    "SERVICE_USER=${SERVICE_USER}" \
    "SERVICE_GROUP=${SERVICE_GROUP}"

log "✓ Aria2 日志轮转配置完成"

# 2. V2Ray 日志轮转
install_template "logrotate/v2ray" "${LOGROTATE_DIR}/v2ray" \
    "V2RAY_LOGS=${V2RAY_LOGS}" \
    "SERVICE_USER=${SERVICE_USER}" \
    "SERVICE_GROUP=${SERVICE_GROUP}"
log "✓ V2Ray 日志轮转配置完成"

# 3. 证书续期日志轮转
install_template "logrotate/cert-renew" "${LOGROTATE_DIR}/cert-renew" \
    "CERT_RENEW_LOG=${CERT_RENEW_LOG}"
log "✓ 证书续期日志轮转配置完成"

# 4. DDNS 日志轮转
install_template "logrotate/changeip" "${LOGROTATE_DIR}/changeip" \
    "CHANGEIP_LOG=${CHANGEIP_LOG}"
log "✓ DDNS 日志轮转配置完成"


# ============================================
# 3. 验证配置
# ============================================
if logrotate -d "${LOGROTATE_DIR}/aria2" &>/dev/null; then
    log "✓ Logrotate 配置验证通过"
else
    warn "Logrotate 配置验证可能有误，建议手动检查: logrotate -d ${LOGROTATE_DIR}/aria2"
fi

log "✓ 所有日志轮转配置完成"
