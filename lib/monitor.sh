#!/usr/bin/env bash
# lib/monitor.sh
# 参数: $1=域名, $2=服务列表, $3=核心端口列表 (e.g., "80 443 22022 6800 10086")

DOMAIN="$1"
RAW_SERVICES="$2" # 接收传入的空格分隔字符串
CORE_PORTS="$3"
shift 3

# 定义颜色
Y='\033[1;33m'; G='\033[0;32m'; R='\033[0;31m'; C='\033[0;36m'; NC='\033[0m'

# ============================================
# 系统信息部分...
# ============================================

echo -e "\n${Y}=== 🖥️  硬件与系统 ===${NC}"
[ -f /etc/redhat-release ] && OS=$(cat /etc/redhat-release) || OS=$(uname -sr)
CPU_MODEL=$(grep 'model name' /proc/cpuinfo | head -1 | awk -F': ' '{print $2}' | sed 's/^[ \t]*//')
CPU_CORES=$(nproc)

echo "系统版本: $OS"
echo "内核版本: $(uname -r)"
echo "CPU 型号: ${CPU_MODEL:-未知}"
echo -e "CPU 核心: ${C}${CPU_CORES} 核${NC}"

BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
if [[ "$BBR_STATUS" == "bbr" ]]; then
    echo -e "拥塞控制: ${G}BBR 已启用${NC}"
else
    echo -e "拥塞控制: ${R}未启用 (当前: ${BBR_STATUS:-无})${NC}"
fi

echo -e "\n${Y}=== ⏱️  运行状态 ===${NC}"
uptime -p | sed 's/up /已运行: /'
echo "负载情况: $(uptime | awk -F'load average:' '{ print $2 }')"
TCP_EST=$(ss -an state established | wc -l)
echo -e "TCP 连接: ${C}${TCP_EST}${NC} 个活跃连接"

echo -e "\n${Y}=== 💾 资源使用 ===${NC}"
free -h | awk '/^Mem:/ {print "物理内存: 总计 " $2 " / 可用 " $7}'
free -h | awk '/^Swap:/ {print "交换分区: 总计 " $2 " / 已用 " $3}'

echo -e "--- 磁盘使用情况 (非虚拟文件系统) ---"

df -hT | awk '
BEGIN {
    printf "%-18s %-10s %-8s %-8s %-8s %-6s %s\n", "Filesystem", "Type", "Size", "Used", "Avail", "Use%", "Mounted on"
}
NR>1 {
    if ($2 !~ /(tmpfs|devtmpfs|cgroup|overlay|shm|fuse|squashfs|nfs|autofs)/) {
        printf "%-18s %-10s %-8s %-8s %-8s %-8s %s\n", $1, $2, $3, $4, $5, $6, $7
    }
}
'

echo -e "\n${Y}=== 🔒 安全与证书 ===${NC}"
if [[ -n "$DOMAIN" ]]; then
    CERT_FILE="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    if [[ -f "$CERT_FILE" ]]; then
        END_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
        if date --version >/dev/null 2>&1; then
            EXP_TIMESTAMP=$(date -d "$END_DATE" +%s)
        else
            if [[ "$OS" == *Darwin* ]] || [[ "$OS" == *BSD* ]]; then
                 EXP_TIMESTAMP=$(date -j -f "%b %d %T %Y %Z" "$END_DATE" +%s 2>/dev/null) || EXP_TIMESTAMP=$(date -j -f "%b %d %T %Y" "$END_DATE" +%s 2>/dev/null)
            else
                 EXP_TIMESTAMP=$(date -d "$END_DATE" +%s 2>/dev/null)
            fi
        fi

        NOW_TIMESTAMP=$(date +%s)
        if [[ -n "$EXP_TIMESTAMP" ]] && [[ "$EXP_TIMESTAMP" -gt "$NOW_TIMESTAMP" ]]; then
            DAYS_LEFT=$(( (EXP_TIMESTAMP - NOW_TIMESTAMP) / 86400 ))
        else
            DAYS_LEFT=0
        fi
        
        if [ $DAYS_LEFT -lt 7 ]; then CERT_COLOR=$R; elif [ $DAYS_LEFT -lt 30 ]; then CERT_COLOR=$Y; else CERT_COLOR=$G; fi
        echo -e "SSL 证书: ${CERT_COLOR}剩余 ${DAYS_LEFT} 天${NC} (域名: $DOMAIN)"
    else
        echo -e "SSL 证书: ${R}未找到证书文件${NC} ($DOMAIN)"
    fi
else
    echo -e "SSL 证书: ${Y}跳过 (未提供域名)${NC}"
fi

# ============================================
# 服务状态检查 (已修复参数解析)
# ============================================
echo -e "\n${Y}=== 🚦 服务状态 ===${NC}"
for svc in $RAW_SERVICES; do 
    if systemctl cat "${svc}.service" >/dev/null 2>&1; then
        if systemctl is-active --quiet "$svc"; then
            printf "%-10s \t${G}运行中${NC}\n" "$svc:"
        else
            printf "%-10s \t${R}已停止${NC}\n" "$svc:"
        fi
    else
        # 明确输出未安装或未找到的服务状态
        printf "%-10s \t${Y}未安装/未找到${NC}\n" "$svc:"
    fi
done

# ============================================
# 【重构】端口监听状态检查 (区分内部/外部 + 进程名分类)
# ============================================
echo -e "\n${Y}=== 🌐 端口监听状态 (TCP) ===${NC}"

# 定义核心进程名列表
CORE_PROCS="nginx sshd aria2c v2ray"

# 提取核心端口列表并去重
declare -a CORE_PORTS_ARRAY=()
echo "$CORE_PORTS" | tr -s '[:space:]' '\n' | sort -u | while read port_item; do
    [[ -n "$port_item" ]] && CORE_PORTS_ARRAY+=("$port_item")
done

# 使用 associative array (map) for quick core port lookup
declare -A CORE_PORT_MAP
for port in "${CORE_PORTS_ARRAY[@]}"; do
    CORE_PORT_MAP["$port"]=1
done

# 定义分类数组
declare -A PUBLIC_CORE_PORTS
declare -A LOCAL_CORE_PORTS
declare -A PUBLIC_OTHER_PORTS
declare -A LOCAL_OTHER_PORTS

# 获取所有监听端口及其地址和进程信息
# 格式: Addr Port ProcName
SS_OUTPUT=$(ss -tlnp | awk '
    NR > 1 {
        local_addr_port = $4;
        proc_info = $NF;
        
        # 提取端口号 (Port)
        n = split(local_addr_port, a, ":");
        port = a[n];
        
        # 提取监听地址 (Addr)
        addr = "";
        # 处理 IPv6 格式 [::]:443 或 :::443
        if (local_addr_port ~ /^\[/) {
            # 提取 [::]
            addr = substr(local_addr_port, 2, index(local_addr_port, "]") - 2);
        } else {
            # 提取 IPv4 格式 0.0.0.0:443 或 *:443
            # n-1 是地址部分的分隔符数量
            for (i=1; i<n; i++) {
                if (i > 1) { addr = addr ":"; }
                addr = addr a[i];
            }
            # 特殊处理 ::: 格式
            if (addr == "") { addr = "::"; } 
        }
        
        # 清理进程名 (Proc) - 从 users:(("name",pid,fd)) 中提取
        gsub(/^users:\(\(\"|\".*/, "", proc_info);
        split(proc_info, p_parts, ",");
        proc_name = p_parts[1];

        if (port ~ /^[0-9]+$/) {
            print addr, port, proc_name;
        }
    }
' | sort -u)

# 分类端口
while read -r ADDR PORT PROC; do
    # 确定端口是否为内部 (Local) 或外部 (Public)
    IS_INTERNAL=0
    # 检查本地回环地址
    if [[ "$ADDR" == "127.0.0.1" || "$ADDR" == "::1" ]]; then
        IS_INTERNAL=1
    fi
    
    # 检查端口是否为核心端口 (新逻辑：匹配配置端口或核心进程名)
    IS_CORE=0
    # 1. 匹配到配置文件中的端口号 (如 80, 443, 6800)
    if [[ "${CORE_PORT_MAP[$PORT]}" == "1" ]]; then
        IS_CORE=1
    # 2. 端口号不匹配配置，但进程名属于核心服务
    elif echo "$CORE_PROCS" | grep -qE "(^| )$PROC( |$)"; then
        IS_CORE=1
    fi

    # 归类并映射
    if [[ "$IS_CORE" == "1" ]]; then
        if [[ "$IS_INTERNAL" == "1" ]]; then
            LOCAL_CORE_PORTS["$PORT"]="$PROC ($ADDR:$PORT)"
        else
            PUBLIC_CORE_PORTS["$PORT"]="$PROC ($ADDR:$PORT)"
        fi
    else
        if [[ "$IS_INTERNAL" == "1" ]]; then
            LOCAL_OTHER_PORTS["$PORT"]="$PROC ($ADDR:$PORT)"
        else
            PUBLIC_OTHER_PORTS["$PORT"]="$PROC ($ADDR:$PORT)"
        fi
    fi
done <<< "$SS_OUTPUT"

# --- 打印结果 ---

# 1. 核心外部端口
echo "--- 核心服务外部端口 (Nginx/SSH) ---"
if [ ${#PUBLIC_CORE_PORTS[@]} -eq 0 ]; then
    echo -e "无监听或所有核心服务外部端口${R}未监听${NC}。"
else
    # Sort and print
    for PORT_KEY in $(echo "${!PUBLIC_CORE_PORTS[@]}" | tr ' ' '\n' | sort -n); do
        INFO=${PUBLIC_CORE_PORTS[$PORT_KEY]}
        PROC_NAME=$(echo "$INFO" | cut -d'(' -f1 | xargs)
        ADDR_PORT_FULL=$(echo "$INFO" | cut -d'(' -f2- | sed 's/)$//')
        printf "TCP %-5s \t${G}外部开放${NC} (%s, %s)\n" "$PORT_KEY" "$PROC_NAME" "$ADDR_PORT_FULL"
    done
fi


# 2. 核心内部端口
echo -e "\n--- 核心服务内部端口 (Aria2/V2Ray Proxy) ---"
if [ ${#LOCAL_CORE_PORTS[@]} -eq 0 ]; then
    echo -e "无监听或所有内部核心端口${R}未监听${NC}。"
else
    # Sort and print
    for PORT_KEY in $(echo "${!LOCAL_CORE_PORTS[@]}" | tr ' ' '\n' | sort -n); do
        INFO=${LOCAL_CORE_PORTS[$PORT_KEY]}
        PROC_NAME=$(echo "$INFO" | cut -d'(' -f1 | xargs)
        ADDR_PORT_FULL=$(echo "$INFO" | cut -d'(' -f2- | sed 's/)$//')
        printf "TCP %-5s \t${G}内部监听${NC} (%s, %s)\n" "$PORT_KEY" "$PROC_NAME" "$ADDR_PORT_FULL"
    done
fi

# 3. 其他开放端口
echo -e "\n--- 其他开放端口 (风险检查) ---"

# 3.1. 其他外部端口 (潜在安全风险)
echo "--- 外部 (0.0.0.0/公网) ---"
if [ ${#PUBLIC_OTHER_PORTS[@]} -eq 0 ]; then
    echo "无其他 TCP 端口对公网开放。"
else
    for PORT_KEY in $(echo "${!PUBLIC_OTHER_PORTS[@]}" | tr ' ' '\n' | sort -n); do
        INFO=${PUBLIC_OTHER_PORTS[$PORT_KEY]}
        PROC_NAME=$(echo "$INFO" | cut -d'(' -f1 | xargs)
        ADDR_PORT_FULL=$(echo "$INFO" | cut -d'(' -f2- | sed 's/)$//')
        printf "TCP %-5s \t${R}!! 外部开放 !!${NC} (%s, %s)\n" "$PORT_KEY" "$PROC_NAME" "$ADDR_PORT_FULL"
    done
fi

# 3.2. 其他内部端口 (内部服务发现)
echo -e "\n--- 内部 (127.0.0.1/localhost) ---"
if [ ${#LOCAL_OTHER_PORTS[@]} -eq 0 ]; then
    echo "无其他 TCP 端口内部监听。"
else
    for PORT_KEY in $(echo "${!LOCAL_OTHER_PORTS[@]}" | tr ' ' '\n' | sort -n); do
        INFO=${LOCAL_OTHER_PORTS[$PORT_KEY]}
        PROC_NAME=$(echo "$INFO" | cut -d'(' -f1 | xargs)
        ADDR_PORT_FULL=$(echo "$INFO" | cut -d'(' -f2- | sed 's/)$//')
        printf "TCP %-5s \t${Y}内部监听${NC} (%s, %s)\n" "$PORT_KEY" "$PROC_NAME" "$ADDR_PORT_FULL"
    done
fi

echo -e "\n${Y}=== 🛡️  最近失败登录 (Top 5) ===${NC}"
if command -v lastb &> /dev/null && [ $(lastb | wc -l) -gt 0 ]; then
    lastb -n 5 | head -n 5
else
    echo "无记录或无法读取"
fi
echo ""
