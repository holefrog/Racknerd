#!/usr/bin/env bash
source lib/utils.sh

log ">>> [Auto-Update] 配置自动安全更新..."

# 【修复 18】安装并配置 dnf-automatic
dnf install -y dnf-automatic

# 配置自动更新（仅安全补丁）
sed -i 's/^apply_updates = no/apply_updates = yes/' "$DNF_AUTO_CONF"
sed -i 's/^upgrade_type = default/upgrade_type = security/' "$DNF_AUTO_CONF"

# 配置邮件通知（可选）
EMAIL=$(config_get "nginx" "email" "")
if [[ -n "$EMAIL" ]]; then
    sed -i "s/^email_to = root/email_to = $EMAIL/" "$DNF_AUTO_CONF"
    sed -i 's/^emit_via = stdio/emit_via = email/' "$DNF_AUTO_CONF"
    log "已配置邮件通知到: $EMAIL"
else
    log "未配置邮件通知（可在 $DNF_AUTO_CONF 中手动设置）"
fi

# 启用自动更新定时器
systemctl enable --now dnf-automatic.timer

# 验证状态
if systemctl is-active --quiet dnf-automatic.timer; then
    log "✓ 自动更新定时器已启动"
    
    # 显示下次运行时间
    NEXT_RUN=$(systemctl list-timers dnf-automatic.timer --no-pager | grep dnf-automatic.timer | awk '{print $1, $2}')
    log "下次自动更新时间: $NEXT_RUN"
else
    warn "自动更新定时器启动失败"
fi

log "✓ 自动安全更新配置完成"
log ""
log "配置文件位置: $DNF_AUTO_CONF"
log "查看更新历史: dnf history"
log "手动触发更新: dnf-automatic"
