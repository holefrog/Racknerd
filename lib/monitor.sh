#!/usr/bin/env bash
# lib/monitor.sh
# 参数: $1=域名, $2...=服务列表 (兼容单字符串或多个参数)

DOMAIN="${1:-}"
# 【关键修复】移除第一个参数(域名)，将剩下的所有参数合并给 SERVICES
# 这样无论参数是否被拆分，都能正确获取完整列表
shift
SERVICES="$*"

# 定义颜色
Y='\033[1;33m'; G='\033[0;32m'; R='\033[0;31m'; C='\033[0;36m'; NC='\033[0m'

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

# --- 🎯 增加可用硬盘监控 (兼容性修复版本) ---
echo -e "--- 磁盘使用情况 (非虚拟文件系统) ---"

# 使用 df -hT (包含文件系统类型) 来获取信息
df -hT | awk '
BEGIN {
    # 打印简洁的英文标题，确保对齐
    printf "%-18s %-10s %-8s %-8s %-8s %-6s %s\n", "Filesystem", "Type", "Size", "Used", "Avail", "Use%", "Mounted on"
}
NR>1 {
    # 兼容性过滤：跳过常见的虚拟文件系统类型（$2是文件系统类型）
    if ($2 !~ /(tmpfs|devtmpfs|cgroup|overlay|shm|fuse|squashfs|nfs|autofs)/) {
        # $1=文件系统, $2=类型, $3=Size, $4=Used, $5=Avail, $6=Use%, $7=Mounted on
        printf "%-18s %-10s %-8s %-8s %-8s %-6s %s\n", $1, $2, $3, $4, $5, $6, $7
    }
}
'
# ---------------------------------------------------

echo -e "\n${Y}=== 🔒 安全与证书 ===${NC}"
if [[ -n "$DOMAIN" ]]; then
    CERT_FILE="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    if [[ -f "$CERT_FILE" ]]; then
        END_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
        # 尝试使用 GNU date (Linux)
        if date --version >/dev/null 2>&1; then
            EXP_TIMESTAMP=$(date -d "$END_DATE" +%s)
        else
            # 兼容 Mac/BSD (例如 date -j -f "%b %d %T %Y %Z" "$END_DATE" +%s)
            EXP_TIMESTAMP=$(date -j -f "%b %d %T %Y %Z" "$END_DATE" +%s)
        fi
        NOW_TIMESTAMP=$(date +%s)
        DAYS_LEFT=$(( (EXP_TIMESTAMP - NOW_TIMESTAMP) / 86400 ))
        
        if [ $DAYS_LEFT -lt 7 ]; then CERT_COLOR=$R; elif [ $DAYS_LEFT -lt 30 ]; then CERT_COLOR=$Y; else CERT_COLOR=$G; fi
        echo -e "SSL 证书: ${CERT_COLOR}剩余 ${DAYS_LEFT} 天${NC} (域名: $DOMAIN)"
    else
        echo -e "SSL 证书: ${R}未找到证书文件${NC} ($DOMAIN)"
    fi
else
    echo -e "SSL 证书: ${Y}跳过 (未提供域名)${NC}"
fi

echo -e "\n${Y}=== 🚦 服务状态 ===${NC}"
for svc in $SERVICES; do
    # 只要 systemd 能找到这个单元文件（无论在哪里），就说明安装了
    if systemctl cat "${svc}.service" >/dev/null 2>&1; then
        if systemctl is-active --quiet "$svc"; then
            printf "%-10s \t${G}运行中${NC}\n" "$svc:"
        else
            printf "%-10s \t${R}已停止${NC}\n" "$svc:"
        fi
    else
        :
    fi
done

echo -e "\n${Y}=== 🛡️  最近失败登录 (Top 5) ===${NC}"
if command -v lastb &> /dev/null && [ $(lastb | wc -l) -gt 0 ]; then
    lastb -n 5 | head -n 5
else
    echo "无记录或无法读取"
fi
echo ""
