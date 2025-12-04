#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source lib/local_utils.sh

VERBOSE=${VERBOSE:-0}
log "[Setup] 开始初始化安装程序..."

# 初始化连接参数
init_connection "deploy"

# 验证并获取必要配置
DOMAIN=$(validate_config "nginx" "domain")
EMAIL=$(validate_config "nginx" "email")
FTP_PASS=$(validate_config "ftp" "password")
ARIA_TOKEN=$(validate_config "aria2" "token")

# 基础安全检查
[[ ${#FTP_PASS} -lt 12 ]] && warn "警告：SFTP密码长度建议大于12位"
[[ ${#ARIA_TOKEN} -lt 16 ]] && warn "警告：Aria2 Token长度建议大于16位"
[[ "$DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] || error "错误：域名格式不正确"

# 清理旧的主机密钥记录
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$HOST" 2>/dev/null || true
[[ "$PORT" != "22" ]] && ssh-keygen -f "$HOME/.ssh/known_hosts" -R "[$HOST]:$PORT" 2>/dev/null || true

# 配置免密登录（如果使用密码认证）
if [[ "$AUTH_TYPE" == "密码" ]]; then
    [[ -z "$KEY" ]] && error "需要SSH密钥路径"
    LOCAL_KEY_PUB=$(get_config "ssh" "pub_key")
    [[ -z "$LOCAL_KEY_PUB" ]] && LOCAL_KEY_PUB="${KEY}.pub"
    if [[ ! -f "$LOCAL_KEY_PUB" ]]; then
        [[ ! -f "$KEY" ]] && error "SSH私钥不存在"
        # 生成临时密钥对
        ssh-keygen -y -f "$KEY" > "$LOCAL_KEY_PUB" 2>/dev/null || error "生成公钥失败"
    fi
    PUB_CONTENT=$(cat "$LOCAL_KEY_PUB")
    # 上传公钥到远程主机
    $SSH_CMD $SSH_OPTS "$REMOTE" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$PUB_CONTENT' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 2>/dev/null || error "安装SSH Key失败"
fi

log "[1/3] 正在上传安装文件..."
REMOTE_DIR="/tmp/racknerd_install"
# 清理并创建远程临时目录
$SSH_CMD $SSH_OPTS "$REMOTE" "rm -rf $REMOTE_DIR && mkdir -p $REMOTE_DIR" 2>/dev/null
# 上传所有必要文件
$SCP_CMD -P $PORT -o StrictHostKeyChecking=no -r lib modules templates stage_1.sh stage_2.sh config.ini "$REMOTE:$REMOTE_DIR/" 2>/dev/null
# 赋予执行权限
$SSH_CMD $SSH_OPTS "$REMOTE" "chmod +x $REMOTE_DIR/*.sh $REMOTE_DIR/modules/*.sh" 2>/dev/null

log "[2/3] 执行系统初始化 (Stage 1)..."
# 移除 grep 过滤，显示完整输出
$SSH_CMD $SSH_OPTS -t "$REMOTE" "cd $REMOTE_DIR && ./stage_1.sh"

log "系统初始化完成，正在重启 VPS..."
$SSH_CMD $SSH_OPTS "$REMOTE" "reboot" 2>/dev/null || true
sleep 10

printf "等待系统启动"
until $SSH_CMD $SSH_OPTS "$REMOTE" "echo ready" 2>/dev/null; do
    printf "."
    sleep 5
done
echo " ✓"

log "[3/3] 执行服务部署 (Stage 2)..."
# 移除 grep 过滤，显示完整输出
$SSH_CMD $SSH_OPTS -t "$REMOTE" "cd $REMOTE_DIR && ./stage_2.sh"

echo ""
echo "✅ 所有安装步骤已完成"
echo "访问地址: https://${DOMAIN}"
echo "状态检查: ./check_status.sh"
