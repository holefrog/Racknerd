#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# 引用公共库
source lib/local_utils.sh

# ============================================
# 1. 前置检查与配置
# ============================================
log ">>> [Setup] 开始部署流程..."

# 初始化连接 (Deploy 模式：强制使用原始端口)
init_connection "deploy"

# 读取部署特有配置
DOMAIN=$(validate_config "nginx" "domain")
EMAIL=$(validate_config "nginx" "email")
FTP_PASS=$(validate_config "ftp" "password")
ARIA_TOKEN=$(validate_config "aria2" "token")
V2_PATH_URL=$(validate_config "v2ray" "path_url")

# 强度检查
if [[ ${#FTP_PASS} -lt 12 ]]; then
    warn "警告: SFTP 密码较短，建议加长"
fi
if [[ ${#ARIA_TOKEN} -lt 16 ]]; then
    warn "警告: Aria2 Token 较短，建议加长"
fi

# 域名格式检查
if ! echo "$DOMAIN" | grep -qE '^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'; then
    error "域名格式错误: $DOMAIN"
fi

# ============================================
# 2. 连接准备
# ============================================
log "维护 known_hosts 记录..."
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$HOST" >/dev/null 2>&1 || true
if [[ "$PORT" != "22" ]]; then
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R "[$HOST]:$PORT" >/dev/null 2>&1 || true
fi

# 自动安装 SSH 公钥 (仅在密码模式下且有本地公钥)
if [[ "$AUTH_TYPE" == "密码" ]]; then
    LOCAL_KEY_PUB="./rpi_keys/id_rsa.pub"
    if [[ -f "$LOCAL_KEY_PUB" ]]; then
        log "正在自动安装 SSH 公钥..."
        PUB_CONTENT=$(cat "$LOCAL_KEY_PUB")
        # 远程执行命令写入 authorized_keys
        if $SSH_CMD $SSH_OPTS "$REMOTE" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$PUB_CONTENT' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"; then
             log "✓ SSH 公钥安装成功"
        else
             warn "SSH 公钥安装失败"
        fi
    fi
fi

# ============================================
# 3. 执行部署
# ============================================
log ">>> 目标主机: $HOST (端口: $PORT)"
REMOTE_DIR="/tmp/racknerd_install"

log "正在上传安装文件..."
if ! $SSH_CMD $SSH_OPTS "$REMOTE" "mkdir -p $REMOTE_DIR" 2>/dev/null; then
    error "无法连接到 VPS ($HOST)\n可能原因：\n1. config.ini 密码错误\n2. IP或端口错误\n3. sshpass 未安装"
fi

# 上传文件 (使用 SCP)
$SSH_CMD $SSH_OPTS "$REMOTE" "rm -rf $REMOTE_DIR && mkdir -p $REMOTE_DIR"
$SCP_CMD -P $PORT -o StrictHostKeyChecking=no -r lib modules templates stage_1.sh stage_2.sh config.ini "$REMOTE:$REMOTE_DIR/"
$SSH_CMD $SSH_OPTS "$REMOTE" "chmod +x $REMOTE_DIR/*.sh $REMOTE_DIR/modules/*.sh"

# 执行 Stage 1
log ">>> 执行阶段 1: 系统更新..."
$SSH_CMD $SSH_OPTS -t "$REMOTE" "cd $REMOTE_DIR && ./stage_1.sh"

# 重启处理
log ">>> 系统正在重启..."
$SSH_CMD $SSH_OPTS "$REMOTE" "reboot" >/dev/null 2>&1 || true
sleep 10

log "等待系统上线..."
until $SSH_CMD $SSH_OPTS "$REMOTE" "echo ready" >/dev/null 2>&1; do
    printf "."
    sleep 5
done
echo ""

# 执行 Stage 2
log ">>> 执行阶段 2: 应用部署..."
$SSH_CMD $SSH_OPTS -t "$REMOTE" "cd $REMOTE_DIR && ./stage_2.sh"

log ""
log "=========================================="
log "  ✅ 部署完成！"
log "=========================================="
