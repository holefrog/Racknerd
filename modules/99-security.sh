#!/usr/bin/env bash
source lib/utils.sh

log ">>> [Security] 开始应用最终安全加固..."

NEW_PORT=$(config_get "ports" "ssh_new")

if [[ "$NEW_PORT" != "22" && -n "$NEW_PORT" ]]; then
    log "修改 SSH 端口为: $NEW_PORT"
    
    # 修改 SSH 配置
    sed -i "s/^#Port 22/Port ${NEW_PORT}/" "$SSHD_CONFIG_FILE"
    sed -i "s/^Port .*/Port ${NEW_PORT}/" "$SSHD_CONFIG_FILE"

    # 开放 SELinux 端口
    semanage port -a -t ssh_port_t -p tcp "$NEW_PORT" || true

    # 防火墙放行
    firewall-cmd --add-port=${NEW_PORT}/tcp --permanent
    firewall-cmd --reload 
    
    systemctl restart sshd
fi

log ">>> [Security] 安全加固完成"
