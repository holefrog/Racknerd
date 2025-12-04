#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%T)] $*${NC}"; }
error() { echo -e "${RED}[$(date +%T)] $*${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}[$(date +%T)] $*${NC}"; }

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

escape_sed_replacement() {
    local str="$1"
    if command -v printf &>/dev/null; then
        printf '%s' "$str" | sed -e 's/[\/&]/\\&/g'
        return
    fi
    str="${str//\\/\\\\}"
    str="${str//&/\\&}"
    str="${str//|/\\|}"
    str="${str///\\/}"
    str="${str//$'\n'/\\n}"
    echo "$str"
}

install_template() {
    local src="$INSTALL_ROOT/templates/$1"
    local dest="$2"
    shift 2
    
    [[ ! -f "$src" ]] && [[ -f "templates/$1" ]] && src="templates/$1"
    [[ ! -f "$src" ]] && error "模板不存在: $src"

    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"

    if command -v python3 &>/dev/null; then
        local py_script="/tmp/tpl_$$.py"
        cat > "$py_script" << 'PYEOF'
import sys, re
def safe_replace(content, replacements):
    for key, value in replacements.items():
        pattern = re.escape('@@' + key + '@@')
        content = re.sub(pattern, value, content)
    return content

file_path, replacements = sys.argv[1], {}
for arg in sys.argv[2:]:
    if '=' in arg:
        key, value = arg.split('=', 1)
        replacements[key] = value

with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()
content = safe_replace(content, replacements)
with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
PYEOF
        python3 "$py_script" "$dest" "$@"
        rm -f "$py_script"
    else
        for pair in "$@"; do
            local key="${pair%%=*}"
            local val="${pair#*=}"
            local val_escaped=$(escape_sed_replacement "$val")
            sed -i "s|@@${key}@@|${val_escaped}|g" "$dest"
        done
    fi

    [[ "$dest" == "${OS_SYSTEM_PATH}/"* ]] && chmod 644 "$dest"
    [[ "$dest" == *.sh ]] || [[ "$dest" == */bin/* ]] && chmod +x "$dest"
}

start_service() {
    local service_name="$1"
    systemctl daemon-reload
    systemctl enable "$service_name"
    systemctl restart "$service_name"
    sleep 2
    systemctl is-active --quiet "$service_name" || error "$service_name 启动失败"
    log "✓ $service_name"
}

command_exists() { command -v "$1" &>/dev/null; }

append_config() {
    local file="$1"
    local line="$2"
    grep -qF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

safe_remove() {
    local path="$1"
    case "$path" in
        /|/bin|/boot|/dev|/etc|/lib|/proc|/root|/sbin|/sys|/usr|/var)
            error "拒绝删除系统目录: $path"
            ;;
        *)
            [[ -e "$path" ]] && rm -rf "$path"
            ;;
    esac
}
