#!/usr/bin/env bash
source lib/utils.sh

log ">>> [Logrotate] 开始配置日志轮转策略..."

# 变量定义
ARIA_LOG_FILE="${ARIA2_ROOT}/aria2.log"
V2RAY_LOGS="/var/log/v2ray/access.log /var/log/v2ray/error.log"
CERT_RENEW_LOG="$CERT_RENEW_LOG_FILE"
CHANGEIP_LOG="$DDNS_LOG_FILE"
SERVICE_USER="nginx"
SERVICE_GROUP="nginx"

# 检查依赖
if ! command_exists logrotate; then
    dnf install -y logrotate
fi
systemctl is-active --quiet crond || systemctl enable --now crond

# 部署轮转规则
install_template "logrotate/aria2" "${LOGROTATE_DIR}/aria2" \
    "ARIA_LOG_FILE=${ARIA_LOG_FILE}" \
    "SERVICE_USER=${SERVICE_USER}" \
    "SERVICE_GROUP=${SERVICE_GROUP}"

install_template "logrotate/v2ray" "${LOGROTATE_DIR}/v2ray" \
    "V2RAY_LOGS=${V2RAY_LOGS}" \
    "SERVICE_USER=${SERVICE_USER}" \
    "SERVICE_GROUP=${SERVICE_GROUP}"

install_template "logrotate/cert-renew" "${LOGROTATE_DIR}/cert-renew" \
    "CERT_RENEW_LOG=${CERT_RENEW_LOG}"

install_template "logrotate/changeip" "${LOGROTATE_DIR}/changeip" \
    "CHANGEIP_LOG=${CHANGEIP_LOG}"

# 验证
logrotate -d "${LOGROTATE_DIR}/aria2" 

log ">>> [Logrotate] 配置完成"
