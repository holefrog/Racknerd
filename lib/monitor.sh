#!/usr/bin/env bash
DOMAIN="$1"
RAW_SERVICES="$2"
CORE_PORTS="$3"
CHECK_WEBDAV="${4:-no}"

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'

# 系统（单行）
echo -e "\n${C}[系统]${NC} $(uname -sr) | CPU: $(nproc)核 | $(uptime -p | sed 's/up //')"

# BBR
BBR=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
[[ "$BBR" == "bbr" ]] && echo -e "${C}[网络]${NC} BBR: ${G}启用${NC}" || echo -e "${C}[网络]${NC} BBR: ${R}未启用${NC}"

# 资源
MEM=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
DISK=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
echo -e "${C}[资源]${NC} 内存: $MEM | 磁盘: $DISK"

# 证书
if [[ -n "$DOMAIN" ]] && [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    END_DATE=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" | cut -d= -f2)
    DAYS=$(( ($(date -d "$END_DATE" +%s 2>/dev/null || echo 0) - $(date +%s)) / 86400 ))
    [[ $DAYS -lt 7 ]] && COLOR=$R || [[ $DAYS -lt 30 ]] && COLOR=$Y || COLOR=$G
    echo -e "${C}[证书]${NC} ${COLOR}${DAYS} 天${NC} ($DOMAIN)"
fi

# 服务
echo -ne "${C}[服务]${NC} "
for svc in $RAW_SERVICES; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -ne "${G}${svc}${NC} "
    else
        echo -ne "${R}${svc}${NC} "
    fi
done
echo ""

# WebDAV
if [[ "$CHECK_WEBDAV" == "yes" && -n "$DOMAIN" ]]; then
    if [[ -f "/etc/nginx/conf.d/includes/webdav-locations.conf" ]]; then
        HEALTH=$(curl -k -s -o /dev/null -w "%{http_code}" "https://localhost/webdav-health" 2>/dev/null || echo "000")
        [[ "$HEALTH" == "200" ]] && STATUS="${G}正常${NC}" || STATUS="${R}异常${NC}"
        echo -e "${C}[WebDAV]${NC} $STATUS | https://${DOMAIN}/webdav"
    fi
fi

# 端口
PORTS=$(ss -tlnp | awk '$4 !~ /^127\.|^\[::1\]/ {split($4,a,":"); print a[length(a)]}' | sort -nu | xargs | tr ' ' ',')
echo -e "${C}[端口]${NC} 公网: $PORTS"
