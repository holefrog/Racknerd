#!/usr/bin/env bash
# ============================================
# RackNerd VPS 部署工具 - 卸载脚本
# ============================================

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[UNINSTALL] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}" >&2; }

# 引入 lib/env.sh 以获取最新的绝对路径
if [[ -f "$(dirname "$0")/lib/env.sh" ]]; then
    source "$(dirname "$0")/lib/env.sh"
else
    # 安全回退定义（在非标准部署目录下运行时使用）
    export OS_SYSTEM_PATH="/etc/systemd/system"
    export NGINX_SITE_CONF_DIR="/etc/nginx/conf.d"
    export ARIA2_ROOT="/etc/aria2"
    export V2RAY_ROOT="/etc/v2ray"
    export LETSENCRYPT_ROOT="/etc/letsencrypt"
    export FAIL2BAN_JAIL_LOCAL="/etc/fail2ban/jail.local"
    export SCRIPT_RENEW_CERT="/usr/local/bin/renew-cert.sh"
    export CRON_CERT_RENEW_FILE="/etc/cron.d/certbot-renew"
    export SCRIPT_DDNS_CHANGEIP="/usr/local/bin/changeip.sh"
    export CRON_DDNS_FILE="/etc/cron.d/changeip"
    export CERT_RENEW_LOG_FILE="/var/log/cert-renew.log"
    export DDNS_LOG_FILE="/var/log/changeip.log"
    export LOGROTATE_DIR="/etc/logrotate.d"
    export SSHD_CONFIG_FILE="/etc/ssh/sshd_config"
    export INSTALL_ROOT="/tmp/racknerd_install"
fi


# 确认操作
echo ""
warn "=========================================="
warn "  警告：此操作将卸载所有已部署的服务"
warn "=========================================="
echo ""
warn "将要删除的内容："
warn "  - Nginx 及其配置"
warn "  - Aria2 及其配置"
warn "  - V2Ray 及其配置"
warn "  - SFTP 用户"
warn "  - SSL 证书"
warn "  - Fail2ban 配置"
warn "  - 所有日志文件"
echo ""
warn "此操作不可逆！"
echo ""

read -p "确定要继续吗？请输入 'YES' 确认: " CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
    log "已取消卸载"
    exit 0
fi

log "开始卸载..."

# 1. 停止所有服务
log "停止服务..."
systemctl stop nginx aria2 v2ray fail2ban dnf-automatic.timer 2>/dev/null || true
systemctl disable nginx aria2 v2ray fail2ban dnf-automatic.timer 2>/dev/null || true

# 2. 卸载软件包
log "卸载软件包..."
dnf remove -y nginx aria2 certbot python3-certbot-nginx fail2ban dnf-automatic 2>/dev/null || true

# 3. 删除配置文件
log "删除配置文件..."
rm -rf ${NGINX_SITE_CONF_DIR}/*
rm -rf ${ARIA2_ROOT}
rm -rf ${V2RAY_ROOT}
rm -f ${FAIL2BAN_JAIL_LOCAL}
rm -rf ${LETSENCRYPT_ROOT}

# 4. 删除 systemd 服务文件
log "删除服务文件..."
rm -f ${OS_SYSTEM_PATH}/aria2.service
rm -f ${OS_SYSTEM_PATH}/v2ray.service
systemctl daemon-reload

# 5. 删除用户和数据目录
log "删除 SFTP 用户..."
FTP_USER=$(grep "^ftpuser:" /etc/passwd | cut -d: -f1 2>/dev/null || echo "")
if [[ -n "$FTP_USER" ]]; then
    userdel -r "$FTP_USER" 2>/dev/null || true
    log "✓ 已删除用户: $FTP_USER"
fi

# 6. 删除数据目录（谨慎操作）
warn "是否删除数据目录 /var/ftp？(包含所有下载文件)"
read -p "输入 'YES' 确认删除: " CONFIRM_DATA

if [[ "$CONFIRM_DATA" == "YES" ]]; then
    rm -rf /var/ftp
    log "✓ 已删除数据目录"
else
    log "保留数据目录: /var/ftp"
fi

# 7. 删除脚本和日志
log "删除脚本和日志..."
rm -f ${SCRIPT_RENEW_CERT}
rm -f ${SCRIPT_DDNS_CHANGEIP}
rm -f ${CRON_CERT_RENEW_FILE}
rm -f ${CRON_DDNS_FILE}
rm -f ${CERT_RENEW_LOG_FILE}
rm -f ${DDNS_LOG_FILE}

# 8. 删除 logrotate 配置
log "删除日志轮转配置..."
rm -f ${LOGROTATE_DIR}/aria2
rm -f ${LOGROTATE_DIR}/v2ray
rm -f ${LOGROTATE_DIR}/cert-renew
rm -f ${LOGROTATE_DIR}/changeip

# 9. 清理防火墙规则（可选）
warn "是否清理防火墙规则？"
read -p "输入 'YES' 确认: " CONFIRM_FW

if [[ "$CONFIRM_FW" == "YES" ]]; then
    log "清理防火墙规则..."
    firewall-cmd --remove-service=http --permanent 2>/dev/null || true
    firewall-cmd --remove-service=https --permanent 2>/dev/null || true
    firewall-cmd --remove-port=6800/tcp --permanent 2>/dev/null || true
    firewall-cmd --remove-port=10086/tcp --permanent 2>/dev/null || true
    firewall-cmd --reload
    log "✓ 防火墙规则已清理"
else
    log "保留防火墙规则"
fi

# 10. 恢复 SSH 配置（可选）
warn "是否恢复 SSH 默认端口 22？"
read -p "输入 'YES' 确认: " CONFIRM_SSH

if [[ "$CONFIRM_SSH" == "YES" ]]; then
    log "恢复 SSH 配置..."
    sed -i 's/^Port .*/Port 22/' ${SSHD_CONFIG_FILE}
    
    # 移除 SFTP 配置 (使用 Match User 标记清理)
    sed -i '/# \[SFTP-CONFIG-MARKER-/,/^$/d' ${SSHD_CONFIG_FILE}
    
    systemctl restart sshd
    log "✓ SSH 端口已恢复为 22"
    warn "请立即使用端口 22 重新连接！"
else
    log "保留 SSH 配置"
fi

# 11. 清理临时文件
log "清理临时文件..."
rm -rf ${INSTALL_ROOT}
rm -rf /tmp/v2ray*

log ""
log "=========================================="
log "  ✅ 卸载完成！"
log "=========================================="
log ""
log "已删除的内容："
log "  ✓ 所有服务（Nginx, Aria2, V2Ray, Fail2ban）"
log "  ✓ 配置文件"
log "  ✓ SFTP 用户"
log "  ✓ SSL 证书"
log "  ✓ 定时任务"
echo ""

if [[ "$CONFIRM_DATA" != "YES" ]]; then
    warn "保留的数据目录: /var/ftp"
fi

if [[ "$CONFIRM_FW" != "YES" ]]; then
    warn "防火墙规则未清理，请手动检查"
fi

if [[ "$CONFIRM_SSH" != "YES" ]]; then
    warn "SSH 配置未恢复，请手动检查"
fi

log ""
log "建议执行以下命令清理残留："
log "  dnf autoremove"
log "  dnf clean all"
