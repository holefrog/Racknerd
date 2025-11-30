#!/bin/sh
# ============================================
# ChangeIP DDNS 更新脚本（最终修复版）
# ============================================

################ Script Variables ###############################
CURRHOSTREC="" # Current host ip record by ping
HOSTIP=""      # host ip by ip.changeip.com
TEMP=/tmp/changeip_temp
TMPIP=/tmp/changeip_tmpIP
LOGFILE="@@DDNS_LOG_FILE@@" # 外部模板变量

# ===============================================================
# Variables to be replaced by installer
# ===============================================================
CIPUSER="@@DDNS_USER@@" # 外部模板变量
CIPPASS="@@DDNS_PASS@@" # 外部模板变量
CIPHOST="@@DDNS_HOST@@" # 外部模板变量
# ===============================================================

LOGMAX=1000    # 【修复 8】增加日志保留行数
UserTag="RackNerd-DDNS"
RETRY_COUNT=3  # 【修复 8】添加重试次数
#################################################################

log_message() {
    # 内部 Shell 变量使用 $... 或 ${...}
    echo "$1" >> ${LOGFILE}
}

# 【修复 8】带重试的 wget 函数
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

# 获取当前 IP（带重试）
if ! wget_with_retry "https://ip.changeip.com" "${TEMP}"; then # 内部变量
    log_message "--------------------------------------------------------------------"
    log_message "$(date)"
    log_message "[ERROR] 无法获取当前 IP，已重试 ${RETRY_COUNT} 次"
    exit 1
fi

# 验证内容是否有效
if [ ! -s ${TEMP} ]; then # 内部变量
    log_message "--------------------------------------------------------------------"
    log_message "$(date)"
    log_message "[ERROR] 获取的 IP 信息为空"
    rm -f ${TEMP}
    exit 1
fi

# 解析 IP
grep IPADDR < ${TEMP} | cut -d= -s -f2 | cut -d- -s -f1 > ${TMPIP} # 内部变量
HOSTIP=$(cat ${TMPIP}) # 内部变量

# 验证 IP 格式
if ! echo "$HOSTIP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
    log_message "--------------------------------------------------------------------"
    log_message "$(date)"
    log_message "[ERROR] 获取的 IP 格式无效: $HOSTIP"
    rm -f ${TEMP} ${TMPIP}
    exit 1
fi

# 获取当前 DNS 记录
CURRHOSTREC=$(ping ${CIPHOST} -c 1 2>/dev/null | sed '1{s/[^(]*(//;s/).*//;q}') # 内部变量

# 比较并更新
if [ "$HOSTIP" != "$CURRHOSTREC" ]; then
    log_message "--------------------------------------------------------------------"
    log_message "$(date)"
    log_message "IP by ping: ${CURRHOSTREC}"
    log_message "IP from changeip.com: ${HOSTIP}"
    log_message "Updating to new IP: ${HOSTIP}"
    
    # 内部 Shell 变量使用 $... 或 ${...}
    URL="https://nic.changeip.com/nic/update?system=dyndns&u=${CIPUSER}&p=${CIPPASS}&hostname=${CIPHOST}"
    
    if wget_with_retry "$URL" "$TEMP"; then
        RESPONSE=$(cat $TEMP)
        log_message "Response: ${RESPONSE}"
        
        # 检查响应状态
        case "$RESPONSE" in
            good*|nochg*)
                log_message "[SUCCESS] DDNS 更新成功"
                ;;
            *)
                log_message "[WARNING] DDNS 响应异常: $RESPONSE"
                ;;
        esac
    else
        log_message "[ERROR] DDNS 更新失败，已重试 ${RETRY_COUNT} 次"
    fi
else
    log_message "--------------------------------------------------------------------"
    log_message "$(date)"
    log_message "IP no change: ${HOSTIP}"
fi

# 清理日志（保留最近 ${LOGMAX} 行）
if [ ${LOGMAX} -ne 0 ]; then
    tail -n ${LOGMAX} ${LOGFILE} > ${TEMP} # 内部变量
    cp ${TEMP} ${LOGFILE} # 内部变量
fi

# 清理临时文件
rm -f ${TEMP} ${TMPIP} # 内部变量

