#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# 引用公共库
source lib/local_utils.sh

# 1. 初始化连接 (默认 Manage 模式：优先使用新端口)
init_connection

log "维护 known_hosts 记录..."
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$HOST" >/dev/null 2>&1 || true
# 【关键修复】同时删除带端口的记录格式 [IP]:PORT
if [[ "$PORT" != "22" ]]; then
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R "[$HOST]:$PORT" >/dev/null 2>&1 || true
fi


# 2. 准备参数
# 从 config.ini 获取域名
DOMAIN=$(get_config "nginx" "domain")

# 获取所有关键端口配置
SSH_PORT=$(get_config "ports" "ssh_new" "22")
ARIA2_PORT=$(get_config "ports" "aria2" "6800")
V2RAY_PORT=$(get_config "ports" "v2ray" "10086")

# 构造核心服务端口列表 (用于远程显示)
CORE_PORTS="80 443 22 ${SSH_PORT} ${ARIA2_PORT} ${V2RAY_PORT}"

# 【更新】核心服务列表（新增 WebDAV 相关检查）
# WebDAV 本身不是独立服务，而是 Nginx 的一部分，所以保持原有服务列表
SERVICES="$CORE_SERVICES"

# 【新增】WebDAV 状态检查标志
CHECK_WEBDAV="yes"

echo -e "${GREEN}>>> 正在连接 $HOST (端口: $PORT)...${NC}"

# 3. 远程执行
# 使用手动转义引号构造远程命令，确保 $DOMAIN, $SERVICES, $CORE_PORTS 和 $CHECK_WEBDAV
# 被远程的 bash -s 准确接收为独立、完整的参数字符串。
REMOTE_CMD="bash -s -- \"$DOMAIN\" \"$SERVICES\" \"$CORE_PORTS\" \"$CHECK_WEBDAV\""

$SSH_CMD $SSH_OPTS "$REMOTE" "$REMOTE_CMD" < lib/monitor.sh
