#!/usr/bin/env bash
source lib/utils.sh

log ">>> [Fail2ban] 开始配置入侵防御服务..."

dnf install -y fail2ban fail2ban-firewalld

# 获取配置
SSH_PORT=$(config_get "ports" "ssh_new")
[[ -z "$SSH_PORT" ]] && SSH_PORT="22"
EMAIL=$(config_get "nginx" "email")
V2RAY_PORT=$(config_get "ports" "v2ray")
[[ -z "$V2RAY_PORT" ]] && V2RAY_PORT="10086"
V2RAY_LOG_ERROR="/var/log/v2ray/error.log"

# 部署 V2Ray 过滤规则
install_template "configs/fail2ban.filter.v2ray" "/etc/fail2ban/filter.d/v2ray.conf"

# 创建 Jail 保护规则
install_template "configs/fail2ban.jail.local" "$FAIL2BAN_JAIL_LOCAL" \
    "SSH_PORT=$SSH_PORT" \
    "EMAIL=$EMAIL" \
    "FAIL2BAN_LOG_SSH=$FAIL2BAN_LOG_SSH" \
    "NGINX_LOG_ERROR=$NGINX_LOG_ERROR" \
    "NGINX_LOG_ACCESS=$NGINX_LOG_ACCESS" \
    "V2RAY_PORT=$V2RAY_PORT" \
    "V2RAY_LOG_ERROR=$V2RAY_LOG_ERROR"

# 启动服务
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban

log ">>> [Fail2ban] 配置完成"
