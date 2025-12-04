#!/usr/bin/env bash
# 基础路径定义
export OS_SYSTEM_PATH="/etc/systemd/system"
export OS_USR_BIN="/usr/local/bin"
export INSTALL_ROOT="/tmp/racknerd_install"

# ============================================
# 核心服务路径 (Core Service Paths)
# ============================================

# Nginx
export NGINX_CONF_ROOT="/etc/nginx"
export NGINX_MAIN_CONF="${NGINX_CONF_ROOT}/nginx.conf"
export NGINX_SITE_CONF_DIR="${NGINX_CONF_ROOT}/conf.d"
export NGINX_WEB_ROOT_BASE="/usr/share/nginx"
export NGINX_LOG_ERROR="/var/log/nginx/error.log"
export NGINX_LOG_ACCESS="/var/log/nginx/access.log"

# Aria2
export ARIA2_ROOT="/etc/aria2"

# V2Ray
export V2RAY_ROOT="/etc/v2ray"

# SSL/Certbot
export LETSENCRYPT_ROOT="/etc/letsencrypt"
export LETSENCRYPT_LIVE_DIR="${LETSENCRYPT_ROOT}/live"
export CERT_RENEW_LOG_FILE="/var/log/cert-renew.log"
export CRON_CERT_RENEW_FILE="/etc/cron.d/certbot-renew"
export SCRIPT_RENEW_CERT="${OS_USR_BIN}/renew-cert.sh"

# DDNS
export SCRIPT_DDNS_CHANGEIP="${OS_USR_BIN}/changeip.sh"
export DDNS_LOG_FILE="/var/log/changeip.log"
export CRON_DDNS_FILE="/etc/cron.d/changeip"

# SSH / SFTP
export SSHD_CONFIG_FILE="/etc/ssh/sshd_config"
export SYSCTL_SSH_PERF_CONF="/etc/sysctl.d/99-ssh-performance.conf"

# 安全 / 监控
export FAIL2BAN_JAIL_LOCAL="/etc/fail2ban/jail.local"
export FAIL2BAN_LOG_SSH="/var/log/secure"
export DNF_AUTO_CONF="/etc/dnf/automatic.conf"

# Logrotate
export LOGROTATE_DIR="/etc/logrotate.d"
