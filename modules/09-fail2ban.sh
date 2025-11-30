#!/usr/bin/env bash
source lib/utils.sh

log ">>> [Fail2ban] 安装与配置..."

# 【修复 17】安装 Fail2ban
dnf install -y fail2ban fail2ban-firewalld

# 获取配置变量
SSH_PORT=$(config_get "ports" "ssh_new")
[[ -z "$SSH_PORT" ]] && SSH_PORT="22"

EMAIL=$(config_get "nginx" "email")

# 【FIX 9: V2Ray 端口和日志路径定义】
V2RAY_PORT=$(config_get "ports" "v2ray")
[[ -z "$V2RAY_PORT" ]] && V2RAY_PORT="10086"
# V2Ray 日志路径已在 modules/05-v2ray.sh 中修正到 /var/log/v2ray
V2RAY_LOG_ERROR="/var/log/v2ray/error.log" 

# 1. 部署 V2Ray Filter
log "部署 Fail2ban V2Ray Filter..."
install_template "configs/fail2ban.filter.v2ray" "/etc/fail2ban/filter.d/v2ray.conf"

# 2. 创建 Jail
log "创建本地配置: $FAIL2BAN_JAIL_LOCAL"
install_template "configs/fail2ban.jail.local" "$FAIL2BAN_JAIL_LOCAL" \
    "SSH_PORT=$SSH_PORT" \
    "EMAIL=$EMAIL" \
    "FAIL2BAN_LOG_SSH=$FAIL2BAN_LOG_SSH" \
    "NGINX_LOG_ERROR=$NGINX_LOG_ERROR" \
    "NGINX_LOG_ACCESS=$NGINX_LOG_ACCESS" \
    "V2RAY_PORT=$V2RAY_PORT" \
    "V2RAY_LOG_ERROR=$V2RAY_LOG_ERROR" # <-- 传入 V2Ray 变量

# 启动 Fail2ban
systemctl enable fail2ban
systemctl restart fail2ban

# 等待服务启动
sleep 2

# 验证状态
if systemctl is-active --quiet fail2ban; then
    log "✓ Fail2ban 已启动"
    
    # 显示已启用的监狱
    log "已启用的保护规则："
    fail2ban-client status 2>/dev/null | grep "Jail list:" || true
else
    warn "Fail2ban 启动失败，请检查日志: journalctl -u fail2ban"
fi

log "✓ Fail2ban 配置完成"
log ""
log "常用 Fail2ban 命令："
log "  fail2ban-client status              # 查看所有监狱状态"
log "  fail2ban-client status sshd         # 查看 SSH 监狱详情"
log "  fail2ban-client set sshd unbanip IP # 解封 IP"
