#!/usr/bin/env bash
# ============================================
# Stage 2: 服务部署（修复版）
# ============================================

set -euo pipefail
cd "$(dirname "$0")"
source lib/utils.sh

log ">>> [Stage 2] 开始部署服务..."

# 1. 先安装 Nginx (创建 nginx 用户和组)
log ">>> 步骤 1/8: 安装 Nginx..."
bash modules/02-nginx.sh

# 2. 配置 SFTP (依赖 nginx 组设置权限)
log ">>> 步骤 2/8: 配置 SFTP..."
bash modules/03-sftp.sh

# 3. 安装 Aria2
log ">>> 步骤 3/8: 安装 Aria2..."
bash modules/04-aria2.sh

# 4. 安装 V2Ray
log ">>> 步骤 4/8: 安装 V2Ray..."
bash modules/05-v2ray.sh

# 5. 配置 DDNS
log ">>> 步骤 5/8: 配置 DDNS..."
if bash modules/06-ddns.sh; then
    log "✓ DDNS 配置完成"
else
    warn "DDNS 配置失败或未启用"
fi

# 【新增 12, 13】配置日志轮转
log ">>> 步骤 6/8: 配置日志轮转..."
bash modules/08-logrotate.sh

# 【新增 17】安装 Fail2ban（可选）
log ">>> 步骤 7/8: 安装 Fail2ban..."
if bash modules/09-fail2ban.sh 2>/dev/null; then
    log "✓ Fail2ban 安装完成"
else
    warn "Fail2ban 安装失败或已跳过"
fi

# 【新增 18】配置自动更新（可选）
log ">>> 步骤 8/8: 配置自动更新..."
if bash modules/10-auto-update.sh 2>/dev/null; then
    log "✓ 自动更新配置完成"
else
    warn "自动更新配置失败或已跳过"
fi

# 最后执行安全加固（修改端口）
# 放在最后以防止配置过程中断连
log ">>> 最后步骤: 安全加固..."
bash modules/99-security.sh

log ">>> [Stage 2] 全部完成"

# ============================================
# 服务状态检查
# ============================================
log ">>> [检查] 验证服务状态..."

check_service() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        log "✓ $service 运行正常"
        return 0
    else
        log "✗ $service 启动失败"
        systemctl status "$service" --no-pager || true
        return 1
    fi
}

FAILED_SERVICES=()

# 检查核心服务
check_service "nginx" || FAILED_SERVICES+=("nginx")
check_service "aria2" || FAILED_SERVICES+=("aria2")
check_service "v2ray" || FAILED_SERVICES+=("v2ray")

# 检查可选服务
if systemctl list-unit-files | grep -q "fail2ban"; then
    check_service "fail2ban" || warn "Fail2ban 未运行（可选服务）"
fi

log ">>> [检查] 验证端口监听..."
ARIA2_PORT=$(config_get 'ports' 'aria2')
V2RAY_PORT=$(config_get 'ports' 'v2ray')

# 检查端口监听
if ss -tlnp | grep -qE ":(443|${ARIA2_PORT}|${V2RAY_PORT})"; then
    log "✓ 核心端口监听正常"
else
    warn "警告：部分端口未监听，请检查服务状态"
fi

# 最终结果
if [ ${#FAILED_SERVICES[@]} -eq 0 ]; then
    log ""
    log "=========================================="
    log "  ✅ 所有核心服务运行正常"
    log "=========================================="
else
    error "以下服务启动失败: ${FAILED_SERVICES[*]}
    
请检查日志：
journalctl -xeu <服务名>

常见问题排查：
1. Nginx: 检查域名解析和证书
2. Aria2: 检查目录权限
3. V2Ray: 检查证书路径和端口冲突"
fi

# 【修复 9】清理包含敏感信息的安装文件
log ">>> [清理] 删除临时安装文件..."
rm -rf /tmp/racknerd_install

log ">>> [Stage 2] 部署流程结束"
