#!/bin/sh
# ============================================
# ChangeIP DDNS 更新脚本
# ============================================

################ Script Variables ###############################
CURRHOSTREC="" # DNS 记录中的 IP
HOSTIP=""      # 当前公网 IP
TEMP=/tmp/changeip_temp
TMPIP=/tmp/changeip_tmpIP
LOGFILE="@@DDNS_LOG_FILE@@"

# ===============================================================
# 模板变量
# ===============================================================
CIPUSER="@@DDNS_USER@@"
CIPPASS="@@DDNS_PASS@@"
CIPHOST="@@DDNS_HOST@@"

LOGMAX=1000    # 日志保留行数
UserTag="RackNerd-DDNS"
RETRY_COUNT=3  # 下载重试次数

#################################################################

log_message() {
    echo "$1" >> ${LOGFILE}
}

# 工具函数：带重试机制的 wget
wget_with_retry() {
    local url="$1"
    local output="$2"
    local retry=0
    
    while [ $retry -lt $RETRY_COUNT ]; do
        if wget -q -U ${UserTag} -O "$output" "$url" 2>/dev/null; then
            return 0
        fi
        
        retry=$((retry + 1))
        if [ $retry -lt $RETRY_COUNT ]; then
            log_message "下载失败，正在重试 ($retry/$RETRY_COUNT)..."
            sleep 5
        fi
    done
    
    return 1
}

# 获取当前公网 IP
if ! wget_with_retry "https://ip.changeip.com" "${TEMP}"; then
    log_message "--------------------------------------------------------------------"
    log_message "$(date)"
    log_message "[ERROR] 无法获取当前 IP"
    exit 1
fi

# 验证内容
if [ ! -s ${TEMP} ]; then
    log_message "--------------------------------------------------------------------"
    log_message "$(date)"
    log_message "[ERROR] 获取的 IP 信息为空"
    rm -f ${TEMP}
    exit 1
fi

# 解析 IP
grep IPADDR < ${TEMP} | cut -d= -s -f2 | cut -d- -s -f1 > ${TMPIP}
HOSTIP=$(cat ${TMPIP})

# 验证 IP 格式
if ! echo "$HOSTIP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
    log_message "--------------------------------------------------------------------"
    log_message "$(date)"
    log_message "[ERROR] 获取的 IP 格式无效: $HOSTIP"
    rm -f ${TEMP} ${TMPIP}
    exit 1
fi

# 获取 DNS 记录中的 IP
CURRHOSTREC=$(ping ${CIPHOST} -c 1 2>/dev/null | sed '1{s/[^(]*(//;s/).*//;q}')

# 对比并更新
if [ "$HOSTIP" != "$CURRHOSTREC" ]; then
    log_message "--------------------------------------------------------------------"
    log_message "$(date)"
    log_message "DNS 记录: ${CURRHOSTREC}"
    log_message "当前 IP: ${HOSTIP}"
    log_message "正在更新..."
    
    URL="https://nic.changeip.com/nic/update?system=dyndns&u=${CIPUSER}&p=${CIPPASS}&hostname=${CIPHOST}"
    
    if wget_with_retry "$URL" "$TEMP"; then
        RESPONSE=$(cat $TEMP)
        log_message "服务响应: ${RESPONSE}"
        
        case "$RESPONSE" in
            good*|nochg*)
                log_message "[SUCCESS] DDNS 更新成功"
                ;;
            *)
                log_message "[WARNING] DDNS 响应异常: $RESPONSE"
                ;;
        esac
    else
        log_message "[ERROR] DDNS 更新失败"
    fi
else
    log_message "--------------------------------------------------------------------"
    log_message "$(date)"
    log_message "IP 未变更: ${HOSTIP}"
fi

# 日志轮转
if [ ${LOGMAX} -ne 0 ]; then
    tail -n ${LOGMAX} ${LOGFILE} > ${TEMP}
    cp ${TEMP} ${LOGFILE}
fi

rm -f ${TEMP} ${TMPIP}
