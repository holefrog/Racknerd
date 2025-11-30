#!/usr/bin/env bash
# ============================================
# 工具函数库（修复版 - 健壮的特殊字符处理）
# ============================================

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { 
    echo -e "${GREEN}[$(date +%T)] [INFO] $*${NC}"
}

error() { 
    echo -e "${RED}[$(date +%T)] [ERROR] $*${NC}" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[$(date +%T)] [WARN] $*${NC}"
}

debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "\033[0;36m[$(date +%T)] [DEBUG] $*${NC}"
    fi
}

# 读取 config.ini
# 【修复 1】改进的 config.ini 解析函数（兼容等号周围的空格）
config_get() {
    local section="$1"
    local key="$2"
    local default="${3:-}"
    local val
    val=$(awk -F= -v s="$section" -v k="$key" '
        /^\[.*\]$/ { in_section=0 }
        $0 ~ "^\\[" s "\\]" { in_section=1; next }
        in_section && $1 ~ "^[ \t]*" k "[ \t]*$" { 
            val=$2; gsub(/^[ \t]+|[ \t]+$/, "", val); print val; exit
        }
    ' "$INSTALL_ROOT/config.ini")
    echo "${val:-$default}"
}

# ============================================
# 【修复 3】改进的特殊字符转义函数
# ============================================
# 用途：安全地转义字符串中的特殊字符，防止 sed 替换时出错
# 参数：$1 - 需要转义的字符串
# 返回：转义后的字符串
escape_sed_replacement() {
    local str="$1"
    
    # 方法 1：使用 printf %q（推荐，但不是所有系统都支持）
    if command -v printf &>/dev/null; then
        # printf %q 会自动转义 shell 特殊字符
        printf '%s' "$str" | sed -e 's/[\/&]/\\&/g'
        return
    fi
    
    # 方法 2：手动转义关键字符
    # 转义顺序很重要：先转义反斜杠，再转义其他字符
    str="${str//\\/\\\\}"     # 反斜杠 \ -> \\
    str="${str//&/\\&}"       # & -> \&
    str="${str//|/\\|}"       # | -> \|
    str="${str///\\/}"        # / -> \/
    str="${str//$'\n'/\\n}"   # 换行符 -> \n
    str="${str//$'\r'/\\r}"   # 回车符 -> \r
    str="${str//$'\t'/\\t}"   # 制表符 -> \t
    
    echo "$str"
}

# ============================================
# 【修复 3】改进的特殊字符转义函数（用于正则）
# ============================================
# 用途：转义正则表达式中的特殊字符
# 参数：$1 - 需要转义的字符串
# 返回：转义后的字符串
escape_sed_pattern() {
    local str="$1"
    
    # 转义所有正则特殊字符
    # . * [ ] ^ $ \ /
    str="${str//\\/\\\\}"     # \ -> \\
    str="${str//./\\.}"       # . -> \.
    str="${str//\*/\\*}"      # * -> \*
    str="${str//\[/\\[}"      # [ -> \[
    str="${str//\]/\\]}"      # ] -> \]
    str="${str//^/\\^}"       # ^ -> \^
    str="${str//$/\\$}"       # $ -> \$
    str="${str///\\/}"        # / -> \/
    str="${str//&/\\&}"       # & -> \&
    
    echo "$str"
}

# ============================================
# 【修复 3】统一命名：模板替换并安装（改进版）
# ============================================
# 用法: install_template "源文件相对路径" "目标绝对路径" "VAR1=VAL1" "VAR2=VAL2" ...
# 
# 改进：
# 1. 使用 Python 或 Perl 进行更健壮的替换（如果可用）
# 2. 回退到改进的 sed 方案
# 3. 增加替换前后的验证
install_template() {
    local src="$INSTALL_ROOT/templates/$1"
    local dest="$2"
    shift 2
    
    # 检查源文件是否存在
    if [[ ! -f "$src" ]]; then
        # 尝试回退到相对路径检查（双重保险）
        if [[ -f "templates/$1" ]]; then
             src="templates/$1"
        else
             error "模板文件不存在: $src"
        fi
    fi

    # 确保目标目录存在
    mkdir -p "$(dirname "$dest")"
    
    debug "复制模板: $src -> $dest"
    cp "$src" "$dest"

    # ============================================
    # 【新修复】选择最佳的替换方法 - 使用 @@VAR@@ 作为模板分隔符
    # ============================================
    
    # 方法 1：使用 Python（最健壮）
    if command -v python3 &>/dev/null; then
        debug "使用 Python 进行模板替换"
        
        # 创建临时 Python 脚本
        local py_script="/tmp/template_replace_$$.py"
        cat > "$py_script" << 'PYEOF'
import sys
import re

def safe_replace(content, replacements):
    """安全地替换模板变量，处理所有特殊字符"""
    for key, value in replacements.items():
        # 使用正则表达式精确匹配 @@KEY@@
        pattern = re.escape('@@' + key + '@@')
        content = re.sub(pattern, value, content)
    return content

if __name__ == '__main__':
    file_path = sys.argv[1]
    replacements = {}
    
    # 解析参数
    for arg in sys.argv[2:]:
        if '=' in arg:
            key, value = arg.split('=', 1)
            replacements[key] = value
    
    # 读取文件
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    
    # 执行替换
    content = safe_replace(content, replacements)
    
    # 写回文件
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
PYEOF
        
        # 执行 Python 脚本
        python3 "$py_script" "$dest" "$@"
        rm -f "$py_script"
        
    # 方法 2：使用 Perl（次优，但比 sed 更可靠）
    elif command -v perl &>/dev/null; then
        debug "使用 Perl 进行模板替换"
        
        for pair in "$@"; do
            local key="${pair%%=*}"
            local val="${pair#*=}"
            
            # Perl 的 quotemeta Q...E 自动转义 $val 中的特殊字符
            perl -i -pe "s/@@$key@@/Q$valE/g" "$dest"
            
            debug "替换变量: @@${key}@@ -> ${val:0:50}..."
        done
        
    # 方法 3：改进的 sed 方案（回退方案）
    else
        debug "使用改进的 sed 进行模板替换"
        
        # 循环处理替换变量
        for pair in "$@"; do
            local key="${pair%%=*}"
            local val="${pair#*=}"
            
            # 【修复 3】使用改进的转义函数
            local val_escaped=$(escape_sed_replacement "$val")
            local key_escaped=$(escape_sed_pattern "$key")
            
            debug "替换变量: @@${key}@@ -> ${val:0:50}..."
            
            # 替换模式从 \${${key_escaped}} 变为 @@${key_escaped}@@
            sed -i "s|@@${key_escaped}@@|${val_escaped}|g" "$dest"
        done
    fi

    # ============================================
    # 验证替换结果
    # ============================================
    # 检查是否还有未替换的变量
    # 模式从 ${[A-Z_]+} 变为 @@[A-Z_]+@@
    local remaining_vars=$(grep -oP '@@[A-Z_]+@@' "$dest" 2>/dev/null || true)
    if [[ -n "$remaining_vars" ]]; then
        warn "配置文件中存在未替换的变量: $dest"
        warn "未替换的变量: $(echo "$remaining_vars" | tr '
' ' ')"
    fi

    # ============================================
    # 【安全修复】权限设置
    # ============================================
    # 如果是系统服务文件，强制设置为 644 权限
    if [[ "$dest" == "${OS_SYSTEM_PATH}/"* ]] || [[ "$dest" == "/usr/lib/systemd/system/"* ]]; then
        chmod 644 "$dest"
        debug "修正服务文件权限: 644 -> $dest"
    fi
    
    # 如果是脚本文件，设置可执行权限
    if [[ "$dest" == *.sh ]] || [[ "$dest" == */bin/* ]]; then
        chmod +x "$dest"
        debug "设置脚本可执行权限: +x -> $dest"
    fi

    log "配置文件已生成: $dest"
}

# ============================================
# 改进的服务启动函数
# ============================================
start_service() {
    local service_name="$1"
    
    log "启用服务: $service_name"
    systemctl daemon-reload
    systemctl enable "$service_name"
    
    log "启动服务: $service_name"
    if systemctl restart "$service_name"; then
        sleep 2
        if systemctl is-active --quiet "$service_name"; then
            log "✓ 服务已成功启动: $service_name"
            return 0
        else
            error "服务启动失败: $service_name
            
请检查日志：
journalctl -xeu $service_name

常见问题：
1. 检查配置文件语法
2. 检查文件权限
3. 检查端口占用: ss -tlnp"
        fi
    else
        error "服务启动命令失败: $service_name"
    fi
}

# 检查命令是否存在
command_exists() {
    command -v "$1" &> /dev/null
}

# 检查端口是否被占用
check_port() {
    local port="$1"
    if ss -tlnp | grep -q ":${port} "; then
        warn "端口 ${port} 已被占用"
        return 1
    fi
    return 0
}

# 备份文件
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.bak.$(date +%s)"
        cp "$file" "$backup"
        log "已备份文件: $file -> $backup"
    fi
}

# 验证文件权限
verify_permissions() {
    local file="$1"
    local expected_mode="$2"
    local actual_mode=$(stat -c "%a" "$file" 2>/dev/null || echo "000")
    
    if [[ "$actual_mode" != "$expected_mode" ]]; then
        warn "文件权限不匹配: $file (期望: $expected_mode, 实际: $actual_mode)"
        return 1
    fi
    return 0
}

# ============================================
# 【改进】幂等追加配置函数
# ============================================
# 用途：向配置文件追加内容（避免重复）
# 参数：$1 - 目标文件, $2 - 要追加的行, $3 - 匹配模式（可选）
append_config() {
    local file="$1"
    local line="$2"
    local pattern="${3:-$line}"
    
    # 转义特殊字符用于 grep
    local escaped_pattern=$(echo "$pattern" | sed 's/[]\/$*.^[]/\\&/g')
    
    # 检查是否已存在
    if ! grep -qF "$pattern" "$file" 2>/dev/null; then
        echo "$line" >> "$file"
        log "添加配置: ${line:0:60}... → $file"
    else
        debug "配置已存在，跳过: ${line:0:60}..."
    fi
}

# ============================================
# 【新增】验证配置文件语法
# ============================================
validate_config_syntax() {
    local file="$1"
    local validator="${2:-}"
    
    if [[ -z "$validator" ]]; then
        # 根据文件类型自动选择验证器
        case "$file" in
            *.json)
                if command_exists jq; then
                    jq . "$file" >/dev/null 2>&1 && return 0 || return 1
                elif command_exists python3; then
                    python3 -m json.tool "$file" >/dev/null 2>&1 && return 0 || return 1
                fi
                ;;
            */nginx*.conf|*/site.conf)
                nginx -t -c "$file" 2>&1 | grep -q "successful" && return 0 || return 1
                ;;
            */sshd_config)
                sshd -t -f "$file" 2>&1 && return 0 || return 1
                ;;
        esac
    else
        # 使用指定的验证器
        $validator "$file" && return 0 || return 1
    fi
    
    warn "无法验证配置文件语法: $file"
    return 0
}

# ============================================
# 【新增】安全删除文件
# ============================================
safe_remove() {
    local path="$1"
    
    # 防止误删根目录或重要系统目录
    case "$path" in
        /|/bin|/boot|/dev|/etc|/lib|/proc|/root|/sbin|/sys|/usr|/var)
            error "拒绝删除系统关键目录: $path"
            ;;
        *)
            if [[ -e "$path" ]]; then
                rm -rf "$path"
                log "已删除: $path"
            fi
            ;;
    esac
}
