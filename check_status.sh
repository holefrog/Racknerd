#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# 引用公共库
source lib/local_utils.sh

# 1. 初始化连接 (默认 Manage 模式：优先使用新端口)
init_connection

# 2. 准备参数
# 从 config.ini 获取域名
DOMAIN=$(get_config "nginx" "domain")
# 使用公共库中定义的核心服务列表
SERVICES="$CORE_SERVICES"

echo -e "${GREEN}>>> 正在连接 $HOST (端口: $PORT)...${NC}"

# 3. 远程执行
# 使用重定向将 lib/monitor.sh 的内容传给 SSH 的 bash 执行
# 注意 -- 用于分隔 bash 的选项和传递给脚本的参数
# 引号将整个列表作为一个参数传递给远程 $2
$SSH_CMD $SSH_OPTS "$REMOTE" "bash -s" -- "$DOMAIN" "$SERVICES" < lib/monitor.sh
