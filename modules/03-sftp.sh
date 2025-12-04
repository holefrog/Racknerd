#!/usr/bin/env bash
source lib/utils.sh

log ">>> [SFTP] 开始配置独立 SFTP 服务..."

# 读取用户配置
FTP_USER=$(config_get "ftp" "user")
FTP_PASS=$(config_get "ftp" "password")
FTP_PATH=$(config_get "ftp" "path")
CHROOT_DIR=$(dirname "$FTP_PATH")

# 创建或更新 SFTP 用户
if id "$FTP_USER" &>/dev/null; then
    usermod -d "$CHROOT_DIR" -s /sbin/nologin "$FTP_USER"
else
    useradd -m -d "$CHROOT_DIR" -s /sbin/nologin "$FTP_USER"
fi

# 设置密码和目录权限
echo "${FTP_USER}:${FTP_PASS}" | chpasswd
mkdir -p "$FTP_PATH"
# Chroot 目录要求属主必须是 root
chown root:root "$CHROOT_DIR"
chmod 755 "$CHROOT_DIR"
# 数据目录赋予用户权限
chown "$FTP_USER:nginx" "$FTP_PATH"
chmod 2775 "$FTP_PATH"

# 备份 SSH 配置
SSHD_CONFIG="$SSHD_CONFIG_FILE"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%s)"

# 辅助函数：更新 SSHD 配置项
update_ssh_config() {
    sed -i "/^[[:space:]]*#*[[:space:]]*$1[[:space:]]/d" "$SSHD_CONFIG"
    if grep -qn "^Match " "$SSHD_CONFIG"; then
        local line=$(grep -n "^Match " "$SSHD_CONFIG" | head -1 | cut -d: -f1)
        sed -i "${line}i $1 $2" "$SSHD_CONFIG"
    else
        echo "$1 $2" >> "$SSHD_CONFIG"
    fi
}

# 优化 SSH 加密算法
update_ssh_config "Ciphers" "aes128-gcm@openssh.com,aes256-gcm@openssh.com,chacha20-poly1305@openssh.com"
update_ssh_config "MACs" "hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com"
update_ssh_config "Compression" "no"
update_ssh_config "MaxSessions" "100"

# 注入 SFTP Match 块配置
MARKER="# SFTP-${FTP_USER}"
sed -i "/${MARKER}/,/^$/d" "$SSHD_CONFIG"

TEMP_FILE="/tmp/sftp_$$.conf"
install_template "configs/sshd.sftp-match.conf" "$TEMP_FILE" "FTP_USER=$FTP_USER" "CHROOT_DIR=$CHROOT_DIR"
echo "" >> "$SSHD_CONFIG"
echo "$MARKER" >> "$SSHD_CONFIG"
cat "$TEMP_FILE" >> "$SSHD_CONFIG"
rm -f "$TEMP_FILE"

# 应用内核参数优化
install_template "sysctl/99-ssh-performance.conf" "$SYSCTL_SSH_PERF_CONF"
sysctl -p "$SYSCTL_SSH_PERF_CONF" >/dev/null 2>&1

# 重启 SSH 服务
sshd -t || error "SSHD 配置校验失败"
systemctl restart >/dev/null 2>&1 || systemctl restart sshd

log ">>> [SFTP] 配置完成 - 端口: $(config_get 'ports' 'ssh_new' '22')"
