#!/bin/bash
# install.sh - 安装并启动 Port Filter Script

set -euo pipefail

TARGET="/usr/local/bin/port-filter"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SCRIPT_SRC="$SCRIPT_DIR/port-filter.sh"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main}"
SCRIPT_URL="$REPO_BASE/port-filter.sh"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

log() {
    local color="$1"; shift
    echo -e "${color}$*${NC}"
}

download_remote_script() {
    local tmpfile
    tmpfile="$(mktemp)"
    if curl -fsSL "$SCRIPT_URL" -o "$tmpfile"; then
        echo "$tmpfile"
        return 0
    else
        rm -f "$tmpfile"
        return 1
    fi
}

if [[ $EUID -ne 0 ]]; then
    log "$RED" "请使用 root 权限运行此安装脚本"
    exit 1
fi

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_package_manager() {
    if command_exists apt-get; then
        echo "apt"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists yum; then
        echo "yum"
    elif command_exists pacman; then
        echo "pacman"
    else
        echo ""
    fi
}

package_for_command() {
    local cmd="$1" pm="$2"
    case "$pm" in
        apt)
            case "$cmd" in
                crontab) echo "cron" ;;
                *) echo "$cmd" ;;
            esac
            ;;
        yum|dnf)
            case "$cmd" in
                crontab) echo "cronie" ;;
                *) echo "$cmd" ;;
            esac
            ;;
        pacman)
            case "$cmd" in
                crontab) echo "cronie" ;;
                iptables) echo "iptables-nft" ;;
                *) echo "$cmd" ;;
            esac
            ;;
        *)
            echo ""
            ;;
    esac
}

install_packages() {
    local pm="$1"; shift
    local packages=("$@")
    [[ ${#packages[@]} -eq 0 ]] && return 0

    case "$pm" in
        apt)
            log "$BLUE" "正在安装依赖: ${packages[*]}"
            if ! DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1; then
                log "$YELLOW" "apt-get 更新失败，请检查网络或软件源"
            fi
            if DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" >/dev/null 2>&1; then
                log "$GREEN" "依赖安装完成"
                return 0
            fi
            ;;
        yum)
            log "$BLUE" "正在安装依赖: ${packages[*]}"
            if yum install -y "${packages[@]}" >/dev/null 2>&1; then
                log "$GREEN" "依赖安装完成"
                return 0
            fi
            ;;
        dnf)
            log "$BLUE" "正在安装依赖: ${packages[*]}"
            if dnf install -y "${packages[@]}" >/dev/null 2>&1; then
                log "$GREEN" "依赖安装完成"
                return 0
            fi
            ;;
        pacman)
            log "$BLUE" "正在安装依赖: ${packages[*]}"
            if pacman -Sy --noconfirm "${packages[@]}" >/dev/null 2>&1; then
                log "$GREEN" "依赖安装完成"
                return 0
            fi
            ;;
    esac

    log "$YELLOW" "自动安装失败，请手动安装: ${packages[*]}"
    return 1
}

collect_missing_dependencies() {
    local deps=("$@")
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then
            missing+=("$dep")
        fi
    done
    echo "${missing[*]}"
}

log "$BLUE" "[1/4] 准备主脚本"
SOURCE_PATH=""
if [[ -f "$SCRIPT_SRC" ]]; then
    SOURCE_PATH="$SCRIPT_SRC"
    log "$GREEN" "检测到本地 port-filter.sh，将使用本地版本"
else
    if SOURCE_PATH="$(download_remote_script)"; then
        log "$GREEN" "已从仓库下载最新 port-filter.sh"
    else
        log "$RED" "无法获取 port-filter.sh，请检查网络连接或脚本地址"
        exit 1
    fi
fi

log "$BLUE" "[2/4] 安装主脚本到 $TARGET"
install -m 0755 "$SOURCE_PATH" "$TARGET"
if [[ "$SOURCE_PATH" != "$SCRIPT_SRC" ]]; then
    rm -f "$SOURCE_PATH"
fi
log "$GREEN" "安装完成"

log "$BLUE" "[3/4] 检查依赖"
deps=(ipset iptables curl crontab)
missing_cmds=($(collect_missing_dependencies "${deps[@]}"))

if [[ ${#missing_cmds[@]} -gt 0 ]]; then
    pm="$(detect_package_manager)"
    packages=()
    if [[ -n "$pm" ]]; then
        for cmd in "${missing_cmds[@]}"; do
            pkg="$(package_for_command "$cmd" "$pm")"
            if [[ -n "$pkg" ]]; then
                if [[ " ${packages[*]} " != *" $pkg "* ]]; then
                    packages+=("$pkg")
                fi
            fi
        done
        install_packages "$pm" "${packages[@]}" || true
    else
        log "$YELLOW" "检测到缺失依赖: ${missing_cmds[*]}，请手动安装后重试"
    fi
fi

missing_cmds=($(collect_missing_dependencies "${deps[@]}"))
if [[ ${#missing_cmds[@]} -gt 0 ]]; then
    log "$RED" "缺少依赖: ${missing_cmds[*]}。请手动安装后重新运行安装脚本"
    exit 1
fi

log "$GREEN" "依赖检测完成"

log "$BLUE" "[4/4] 启动 Port Filter Script"
"$TARGET"
