#!/bin/bash
# install.sh - 安装并启动 Port Filter Script

set -euo pipefail

TARGET="/usr/local/bin/port-filter"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_SRC="$SCRIPT_DIR/port-filter.sh"

RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
NC='\033[0m'

log() {
    local color="$1"; shift
    echo -e "${color}$*${NC}"
}

if [[ $EUID -ne 0 ]]; then
    log "$RED" "请使用 root 权限运行此安装脚本"
    exit 1
fi

if [[ ! -f "$SCRIPT_SRC" ]]; then
    log "$RED" "未找到 port-filter.sh"
    exit 1
fi

log "$BLUE" "[1/3] 安装主脚本到 $TARGET"
install -m 0755 "$SCRIPT_SRC" "$TARGET"
log "$GREEN" "安装完成"

log "$BLUE" "[2/3] 检查依赖"
if ! command -v ipset >/dev/null 2>&1 || ! command -v iptables >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y ipset iptables curl >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y ipset iptables curl >/dev/null 2>&1 || true
    fi
fi
log "$GREEN" "依赖检测完成"

log "$BLUE" "[3/3] 启动 Port Filter Script"
"$TARGET"
