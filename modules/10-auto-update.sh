#!/usr/bin/env bash
source lib/utils.sh

log ">>> [Auto-Update] 开始配置系统自动安全更新..."

# 1. 安装自动更新工具
dnf install -y dnf-automatic

# 2. 修改配置：仅应用安全补丁，且自动执行
sed -i 's/^apply_updates = no/apply_updates = yes/' "$DNF_AUTO_CONF"
sed -i 's/^upgrade_type = default/upgrade_type = security/' "$DNF_AUTO_CONF"

# 3. 配置邮件通知（如果 config.ini 中设置了邮箱）
EMAIL=$(config_get "nginx" "email" "")
if [[ -n "$EMAIL" ]]; then
    sed -i "s/^email_to = root/email_to = $EMAIL/" "$DNF_AUTO_CONF"
    sed -i 's/^emit_via = stdio/emit_via = email/' "$DNF_AUTO_CONF"
fi

# 4. 启动定时任务
systemctl enable --now dnf-automatic.timer >/dev/null 2>&1

log ">>> [Auto-Update] 配置完成"
