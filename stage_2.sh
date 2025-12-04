#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source lib/utils.sh

log "[Stage 2] 开始安装应用服务..."

# 依次执行各模块，移除 tail 过滤以显示详细日志
bash modules/02-nginx.sh
bash modules/03-sftp.sh
bash modules/04-aria2.sh
bash modules/05-v2ray.sh

# 可选模块（如果配置存在则执行）
bash modules/06-ddns.sh 2>/dev/null || true
bash modules/07-webdav.sh 2>/dev/null || true
bash modules/08-logrotate.sh 2>/dev/null || true
bash modules/09-fail2ban.sh 2>/dev/null || true
bash modules/10-auto-update.sh 2>/dev/null || true
bash modules/99-security.sh 2>/dev/null || true

# 最终服务状态检查
FAILED=()
for svc in nginx aria2 v2ray; do
    systemctl is-active --quiet "$svc" || FAILED+=("$svc")
done

if [[ ${#FAILED[@]} -eq 0 ]]; then
    DOMAIN=$(config_get "nginx" "domain")
    log "✅ [Stage 2] 部署全部完成"
    log "您的站点已准备就绪: https://${DOMAIN}"
else
    error "部分服务启动失败: ${FAILED[*]}，请检查上方日志"
fi

# 清理安装文件
rm -rf /tmp/racknerd_install 2>/dev/null || true
