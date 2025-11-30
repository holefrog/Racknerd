#!/usr/bin/env bash
source lib/utils.sh

log ">>> [安全] 端口配置..."
NEW_PORT=$(config_get "ports" "ssh_new")

if [[ "$NEW_PORT" == "22" ]]; then
    log "SSH 端口未变，跳过"
    exit 0
fi

sed -i "s/^#Port 22/Port ${NEW_PORT}/" "$SSHD_CONFIG_FILE"
sed -i "s/^Port .*/Port ${NEW_PORT}/" "$SSHD_CONFIG_FILE"

# SELinux
semanage port -a -t ssh_port_t -p tcp "$NEW_PORT" || true

firewall-cmd --add-port=${NEW_PORT}/tcp --permanent
firewall-cmd --reload

systemctl restart sshd
log "SSH 端口已修改为: $NEW_PORT"
