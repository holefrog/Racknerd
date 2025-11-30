#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# 引用公共库
source lib/local_utils.sh

# 1. 初始化连接 (默认 Manage 模式：优先使用新端口)
init_connection

log "维护 known_hosts 记录..."
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$HOST" >/dev/null 2>&1 || true


# 2. 准备参数
# 从 config.ini 获取域名
DOMAIN=$(get_config "nginx" "domain")

# 获取所有关键端口配置
# 使用默认值确保 CORE_PORTS 不为空，如果用户没有配置 Aria2/V2Ray 端口
SSH_PORT=$(get_config "ports" "ssh_new" "22")
ARIA2_PORT=$(get_config "ports" "aria2" "6800")
V2RAY_PORT=$(get_config "ports" "v2ray" "10086")

# 构造核心服务端口列表 (用于远程显示)
# 注意：即使 SSH 端口被修改，默认 22 和自定义端口都应包含在检查列表中
CORE_PORTS="80 443 22 ${SSH_PORT} ${ARIA2_PORT} ${V2RAY_PORT}"

# 使用公共库中定义的核心服务列表
SERVICES="$CORE_SERVICES"

echo -e "${GREEN}>>> 正在连接 $HOST (端口: $PORT)...${NC}"

# 3. 远程执行
# 【关键修复】使用手动转义引号构造远程命令，确保 $DOMAIN, $SERVICES 和 $CORE_PORTS
# 被远程的 bash -s 准确接收为三个独立、完整的参数字符串。
REMOTE_CMD="bash -s -- \"$DOMAIN\" \"$SERVICES\" \"$CORE_PORTS\""

$SSH_CMD $SSH_OPTS "$REMOTE" "$REMOTE_CMD" < lib/monitor.sh
