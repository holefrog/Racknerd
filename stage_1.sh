#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source lib/utils.sh

log "[Stage 1] 系统初始化..."
bash modules/01-system.sh
log "[Stage 1] 完成"
