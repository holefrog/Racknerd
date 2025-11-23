#!/usr/bin/env bash
# stage_1.sh
set -euo pipefail
cd "$(dirname "$0")"
source lib/utils.sh

log ">>> [Stage 1] 开始..."

# 执行系统基础模块
bash modules/01-system.sh

log ">>> [Stage 1] 完成，准备重启。"
