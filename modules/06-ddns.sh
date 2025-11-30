#!/usr/bin/env bash
source lib/utils.sh


log ">>> [DDNS] 安装 ChangeIP 脚本..."

# 读取配置
USER=$(config_get "ddns" "user")
PASS=$(config_get "ddns" "password")
HOST=$(config_get "ddns" "hostname")

if [[ -z "$USER" || -z "$PASS" || -z "$HOST" ]]; then
    error "DDNS 配置缺失，请检查 config.ini [ddns] 部分"
fi

TARGET_SCRIPT="$SCRIPT_DDNS_CHANGEIP"

# 安装脚本并替换变量
install_template "scripts/changeip.sh" "$TARGET_SCRIPT" \
    "DDNS_USER=$USER" \
    "DDNS_PASS=$PASS" \
    "DDNS_HOST=$HOST" \
    "DDNS_LOG_FILE=$DDNS_LOG_FILE"

# 赋予执行权限
chmod +x "$TARGET_SCRIPT"

# 设置 Cron 定时任务 (每 15 分钟执行一次)
CRON_FILE="$CRON_DDNS_FILE"
# 使用模板生成 Cron 任务
install_template "cron/changeip.cron" "$CRON_FILE" \
    "SCRIPT_DDNS_CHANGEIP=$TARGET_SCRIPT"

log "✓ DDNS 安装完成，每15分钟检查一次 IP 变动"

# 立即运行一次测试
log "正在执行首次 DDNS 更新..."
bash "$TARGET_SCRIPT"
