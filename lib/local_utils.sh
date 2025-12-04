#!/usr/bin/env bash
# lib/local_utils.sh - 本地脚本公共库
# 用于 setup.sh 和 check_status.sh 的通用逻辑

# ============================================
# 1. 全局定义
# ============================================
# 定义要检查的核心服务列表 (避免硬编码，check_status.sh 会用到)
CORE_SERVICES="aria2 fail2ban nginx v2ray"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log() { echo -e "${GREEN}[LOCAL] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }

# ============================================
# 2. 环境检查
# ============================================
check_requirements() {
    local missing=0
    for cmd in ssh scp awk sed; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}[✗] 未找到命令: $cmd${NC}"
            ((missing++))
        fi
    done
    if [ $missing -ne 0 ]; then
        error "本地环境缺少必要工具 (ssh, scp, awk, sed)，请先安装。"
    fi
}

# ============================================
# 3. 配置读取
# ============================================
check_config_file() {
    if [[ ! -f "config.ini" ]]; then
        error "config.ini 不存在！请先 cp config.ini.example config.ini 并修改。"
    fi
}

# 读取单个配置项 (支持等号周围有空格的健壮写法)
get_config() {
    local section="$1"
    local key="$2"
    awk -F= -v s="$section" -v k="$key" '
        /^\[.*\]$/ { in_section=0 }
        $0 ~ "^\\[" s "\\]" { in_section=1; next }
        in_section && $1 ~ "^[ \t]*" k "[ \t]*$" { 
            val=$2; gsub(/^[ \t]+|[ \t]+$/, "", val); print val; exit 
        }
    ' "config.ini"
}

# 验证配置项必填
validate_config() {
    local section="$1"
    local key="$2"
    local val=$(get_config "$section" "$key")
    
    if [[ -z "$val" ]]; then
        error "配置缺失: [$section] $key"
    fi
    if [[ "$val" == "YOUR_"* ]] || [[ "$val" == "CHANGE_"* ]] || [[ "$val" == "example.com" ]]; then
        error "请修改 config.ini 中的配置: [$section] $key"
    fi
    echo "$val"
}

# ============================================
# 4. 连接初始化
# ============================================
# 用法: init_connection [port_mode] [terminal_opt]
# port_mode="deploy": 强制使用 config.ini [ssh] port (用于首次安装阶段)
# port_mode="manage": 优先使用 [ports] ssh_new (用于日常状态检查，默认)
# terminal_opt="t": 添加 -t (伪终端，用于交互式)
# terminal_opt="T": 添加 -T (禁止伪终端，用于非交互式)
init_connection() {
    local port_mode="${1:-manage}"
    local terminal_opt="${2:-}" # 新增参数

    check_requirements
    check_config_file

    # 读取基础信息
    HOST=$(validate_config "ssh" "host")
    USER=$(validate_config "ssh" "user")
    
    # 端口逻辑
    local orig_port=$(get_config "ssh" "port")
    local new_port=$(get_config "ports" "ssh_new")
    
    # 如果是管理模式，且配置了新端口(非22)，则优先使用新端口
    if [[ "$port_mode" == "manage" && -n "$new_port" && "$new_port" != "22" ]]; then
        PORT="$new_port"
    else
        # 否则（部署模式或无新端口）使用原始端口，默认为 22
        PORT="${orig_port:-22}"
    fi

    # 认证逻辑
    SSH_PASS=$(get_config "ssh" "password")
    KEY=$(get_config "ssh" "key")

    # 如果 key 路径是相对路径，转换为基于当前目录的路径
    if [[ "$KEY" == ./* ]]; then
        KEY="$(pwd)/${KEY#./}"
    fi

    local BASE_SSH_CMD="ssh"
    local BASE_SCP_CMD="scp"
    AUTH_TYPE="密钥"

    if [[ -n "$SSH_PASS" ]]; then
        # 密码模式
        if ! command -v sshpass &> /dev/null; then
            error "检测到 config.ini 配置了密码，但未找到 sshpass 命令！\n请先安装：brew/apt/yum install sshpass"
        fi
        BASE_SSH_CMD="sshpass -p $SSH_PASS ssh"
        BASE_SCP_CMD="sshpass -p $SSH_PASS scp"
        AUTH_TYPE="密码"
    elif [[ -n "$KEY" ]]; then
        # 密钥模式
        if [[ ! -f "$KEY" ]]; then
             error "未找到 SSH Key ($KEY) 且 config.ini 未配置密码。"
        fi
        # 确保密钥权限正确
        chmod 600 "$KEY"
        BASE_SSH_CMD="ssh -i $KEY"
        BASE_SCP_CMD="scp -i $KEY"
    else
        error "config.ini 必须配置 [ssh] key 或 password。"
    fi

    # 设置通用的 SSH 选项
    # -o StrictHostKeyChecking=no: 避免第一次连接时的 yes/no 询问
    # -o ConnectTimeout=10: 防止连接超时卡住太久
    
    local TERMINAL_OPTION=""
    if [[ -n "$terminal_opt" ]]; then
        TERMINAL_OPTION="-${terminal_opt}"
    fi

    # 最终构建命令和选项
    SSH_OPTS="${TERMINAL_OPTION} -p $PORT -o StrictHostKeyChecking=no -o ConnectTimeout=10"
    SSH_CMD="$BASE_SSH_CMD"
    SCP_CMD="$BASE_SCP_CMD"
    REMOTE="$USER@$HOST"
}
