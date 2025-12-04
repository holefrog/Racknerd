#!/usr/bin/env bash
source lib/utils.sh

log ">>> [DDNS] 开始配置动态域名解析 (ChangeIP)..."

USER=$(config_get "ddns" "user")
PASS=$(config_get "ddns" "password")
HOST=$(config_get "ddns" "hostname")

if [[ -z "$USER" || -z "$PASS" || -z "$HOST" ]]; then
    error "DDNS 配置不完整，跳过。"
fi

TARGET_SCRIPT="$SCRIPT_DDNS_CHANGEIP"

# 部署更新脚本
install_template "scripts/changeip.sh" "$TARGET_SCRIPT" \
    "DDNS_USER=$USER" \
    "DDNS_PASS=$PASS" \
    "DDNS_HOST=$HOST" \
    "DDNS_LOG_FILE=$DDNS_LOG_FILE"

chmod +x "$TARGET_SCRIPT"

# 设置定时任务
CRON_FILE="$CRON_DDNS_FILE"
install_template "cron/changeip.cron" "$CRON_FILE" \
    "SCRIPT_DDNS_CHANGEIP=$TARGET_SCRIPT"

# 立即执行一次
log "正在执行首次 IP 更新检查..."
bash "$TARGET_SCRIPT"

log ">>> [DDNS] 配置完成"
