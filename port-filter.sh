#!/bin/bash
# port-filter.sh - 端口访问控制脚本（国内来源）
# 功能：
#   1. 指定端口禁止中国大陆来源访问
#   2. 指定端口仅允许中国大陆来源访问
#   3. 支持 TCP / UDP / 双协议
#   4. 支持多源国内 IP 列表 + 定时更新
#   5. SSH 终端彩色交互界面

set -euo pipefail

VERSION="3.0.0"
if command -v realpath >/dev/null 2>&1; then
    SCRIPT_PATH="$(realpath "$0")"
else
    SCRIPT_PATH="$(readlink -f "$0")"
fi
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
CONFIG_DIR="/etc/port-filter"
RULES_FILE="$CONFIG_DIR/rules.conf"
CACHE_DIR="$CONFIG_DIR/cache"
AUTO_UPDATE_CRON="/etc/cron.d/port-filter"
AUTO_UPDATE_LOG="$CONFIG_DIR/auto-update.log"
CN_IPSET_NAME="pf_cn_ipv4"
IPTABLES_CHAIN="PORT_FILTER"

CN_IP_SOURCES=(
    "https://raw.githubusercontent.com/metowolf/iplist/master/data/cn/china.txt"
    "https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt"
    "https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt"
)

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

RULES=()
AUTO_UPDATE_TIME=""

log() {
    local level="$1"; shift
    local color
    case "$level" in
        INFO) color="$BLUE" ;;
        SUCCESS) color="$GREEN" ;;
        WARN) color="$YELLOW" ;;
        ERROR) color="$RED" ;;
        *) color="$NC" ;;
    esac
    echo -e "${color}[$level]${NC} $*"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "请使用 root 权限运行此脚本"
        exit 1
    fi
}

init_environment() {
    mkdir -p "$CONFIG_DIR" "$CACHE_DIR"
    touch "$RULES_FILE"
    if [[ ! -f "$AUTO_UPDATE_LOG" ]]; then
        touch "$AUTO_UPDATE_LOG"
    fi
}

install_dependencies() {
    local missing=()
    local deps=(ipset iptables curl)

    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        if command_exists apt-get; then
            log INFO "正在安装依赖: ${missing[*]}"
            DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
            if DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" >/dev/null 2>&1; then
                log SUCCESS "依赖安装完成"
            else
                log WARN "自动安装失败，请手动安装: ${missing[*]}"
            fi
        elif command_exists yum; then
            log INFO "正在安装依赖: ${missing[*]}"
            if yum install -y "${missing[@]}" >/dev/null 2>&1; then
                log SUCCESS "依赖安装完成"
            else
                log WARN "自动安装失败，请手动安装: ${missing[*]}"
            fi
        else
            log WARN "检测到缺失依赖: ${missing[*]}，请手动安装"
        fi
    fi
}

load_config() {
    RULES=()
    AUTO_UPDATE_TIME=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" == RULE* ]]; then
            RULES+=("${line#RULE }")
        elif [[ "$line" == AUTO_UPDATE* ]]; then
            AUTO_UPDATE_TIME="${line#AUTO_UPDATE }"
        fi
    done < "$RULES_FILE"
}

save_config() {
    {
        for rule in "${RULES[@]}"; do
            echo "RULE $rule"
        done
        if [[ -n "$AUTO_UPDATE_TIME" ]]; then
            echo "AUTO_UPDATE $AUTO_UPDATE_TIME"
        fi
    } > "$RULES_FILE"
}

ensure_ipset() {
    if ! ipset list "$CN_IPSET_NAME" >/dev/null 2>&1; then
        ipset create "$CN_IPSET_NAME" hash:net family inet maxelem 131072
    fi
}

update_cn_ipset() {
    ensure_ipset

    local tmp_file
    tmp_file=$(mktemp)
    >"$tmp_file"

    log INFO "正在下载国内 IP 数据..."
    local success=false
    for url in "${CN_IP_SOURCES[@]}"; do
        if curl -fsSL "$url" | sed 's/#.*//' | sed '/^\s*$/d' >>"$tmp_file"; then
            success=true
        else
            log WARN "下载失败: $url"
        fi
    done

    if [[ "$success" == false ]]; then
        log ERROR "所有国内 IP 数据源下载失败"
        rm -f "$tmp_file"
        return 1
    fi

    sort -u "$tmp_file" -o "$tmp_file"
    cp "$tmp_file" "$CACHE_DIR/cn_ipv4.list"

    {
        echo "create $CN_IPSET_NAME hash:net family inet maxelem 131072 -exist"
        echo "flush $CN_IPSET_NAME"
        while IFS= read -r cidr; do
            [[ -z "$cidr" ]] && continue
            echo "add $CN_IPSET_NAME $cidr"
        done < "$tmp_file"
    } | ipset restore

    rm -f "$tmp_file"
    local count
    count=$(wc -l < "$CACHE_DIR/cn_ipv4.list" | tr -d '[:space:]')
    log SUCCESS "国内 IP 库已更新，共收录 ${count} 条记录"
}

ensure_iptables_chain() {
    if ! iptables -nL "$IPTABLES_CHAIN" >/dev/null 2>&1; then
        iptables -N "$IPTABLES_CHAIN"
    fi
    if ! iptables -C INPUT -j "$IPTABLES_CHAIN" >/dev/null 2>&1; then
        iptables -I INPUT 1 -j "$IPTABLES_CHAIN"
    fi
}

apply_rule() {
    local action="$1" port="$2" protocol="$3"

    local protocols=()
    case "$protocol" in
        tcp|TCP) protocols=(tcp) ;;
        udp|UDP) protocols=(udp) ;;
        both|BOTH) protocols=(tcp udp) ;;
        *) log WARN "未知协议: $protocol"; return ;;
    esac

    for proto in "${protocols[@]}"; do
        case "$action" in
            block_cn)
                iptables -A "$IPTABLES_CHAIN" -p "$proto" --dport "$port" -m set --match-set "$CN_IPSET_NAME" src -j DROP
                ;;
            allow_cn_only)
                iptables -A "$IPTABLES_CHAIN" -p "$proto" --dport "$port" -m set ! --match-set "$CN_IPSET_NAME" src -j DROP
                ;;
        esac
    done
}

apply_all_rules() {
    ensure_ipset
    ensure_iptables_chain
    iptables -F "$IPTABLES_CHAIN"

    for rule in "${RULES[@]}"; do
        IFS='|' read -r action port protocol <<<"$rule"
        apply_rule "$action" "$port" "$protocol"
    done

    log SUCCESS "防火墙规则已应用"
}

list_rules() {
    if [[ ${#RULES[@]} -eq 0 ]]; then
        echo -e "${YELLOW}暂无规则${NC}"
        return
    fi

    printf "${CYAN}%-4s %-14s %-8s %-8s${NC}\n" "编号" "策略" "端口" "协议"
    local idx=1
    for rule in "${RULES[@]}"; do
        IFS='|' read -r action port protocol <<<"$rule"
        local action_text display_protocol
        case "$action" in
            block_cn) action_text="阻止国内" ;;
            allow_cn_only) action_text="仅国内" ;;
            *) action_text="$action" ;;
        esac
        display_protocol=$(echo "$protocol" | tr '[:lower:]' '[:upper:]')
        printf "%s%-4d%s %-14s %-8s %-8s\n" "$GREEN" "$idx" "$NC" "$action_text" "$port" "$display_protocol"
        ((idx++))
    done
}

prompt_port() {
    local port
    while true; do
        read -rp "请输入端口 (1-65535): " port
        if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
            echo "$port"
            return
        fi
        log WARN "端口号无效"
    done
}

prompt_protocol() {
    local choice
    echo "请选择协议:"
    echo "  1) TCP"
    echo "  2) UDP"
    echo "  3) TCP + UDP"
    while true; do
        read -rp "请输入序号: " choice
        case "$choice" in
            1) echo "tcp"; return ;;
            2) echo "udp"; return ;;
            3) echo "both"; return ;;
        esac
        log WARN "无效选择"
    done
}

add_rule() {
    local action
    echo "请选择策略类型:"
    echo "  1) 阻止中国大陆访问"
    echo "  2) 仅允许中国大陆访问"
    local choice
    while true; do
        read -rp "请输入序号: " choice
        case "$choice" in
            1) action="block_cn"; break ;;
            2) action="allow_cn_only"; break ;;
        esac
        log WARN "无效选择"
    done

    local port protocol
    port=$(prompt_port)
    protocol=$(prompt_protocol)

    local new_rule="$action|$port|$protocol"

    for existing in "${RULES[@]}"; do
        if [[ "$existing" == "$new_rule" ]]; then
            log WARN "该规则已存在"
            return
        fi
    done

    RULES+=("$new_rule")
    save_config
    apply_all_rules
    log SUCCESS "规则已添加"
}

remove_rule() {
    if [[ ${#RULES[@]} -eq 0 ]]; then
        log WARN "暂无规则可删除"
        return
    fi
    list_rules
    local idx
    while true; do
        read -rp "请输入要删除的编号: " idx
        if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#RULES[@]} )); then
            break
        fi
        log WARN "无效编号"
    done
    local array_index=$((idx - 1))
    unset 'RULES[array_index]'
    if [[ ${#RULES[@]} -gt 0 ]]; then
        RULES=("${RULES[@]}")
    else
        RULES=()
    fi
    save_config
    apply_all_rules
    log SUCCESS "规则已删除"
}

set_auto_update() {
    read -rp "请输入自动更新时间 (HH:MM，留空关闭): " input
    if [[ -z "$input" ]]; then
        AUTO_UPDATE_TIME=""
        rm -f "$AUTO_UPDATE_CRON"
        save_config
        log SUCCESS "已关闭自动更新"
        return
    fi

    if [[ ! "$input" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
        log WARN "时间格式错误"
        return
    fi

    AUTO_UPDATE_TIME="$input"
    save_config

    local minute="${input##*:}"
    local hour="${input%%:*}"

    cat <<CRON > "$AUTO_UPDATE_CRON"
$minute $hour * * * root $SCRIPT_PATH --cron-update >> $AUTO_UPDATE_LOG 2>&1
CRON

    log SUCCESS "自动更新时间已设置为 $hour:$minute"
}

show_banner() {
    clear
    cat <<BANNER
${CYAN}╔══════════════════════════════════════════════╗
║        Port Filter Script v${VERSION}        ║
║   国内访问控制 · SSH 终端友好 · 彩色界面    ║
╚══════════════════════════════════════════════╝${NC}
BANNER
}

cn_entry_count() {
    if [[ -f "$CACHE_DIR/cn_ipv4.list" ]]; then
        wc -l < "$CACHE_DIR/cn_ipv4.list" | tr -d '[:space:]'
    else
        echo 0
    fi
}

main_menu() {
    while true; do
        show_banner
        echo "当前国内 IP 数据条目: $(cn_entry_count)"
        echo "自动更新时间: ${AUTO_UPDATE_TIME:-未设置}"
        echo ""
        echo "${GREEN}1${NC}. 更新国内 IP 库"
        echo "${GREEN}2${NC}. 查看现有规则"
        echo "${GREEN}3${NC}. 新增规则"
        echo "${GREEN}4${NC}. 删除规则"
        echo "${GREEN}5${NC}. 设置自动更新"
        echo "${GREEN}0${NC}. 退出"
        echo ""
        read -rp "请选择操作: " choice
        case "$choice" in
            1) update_cn_ipset; read -rp "按回车继续..." _ ;;
            2) list_rules; read -rp "按回车继续..." _ ;;
            3) add_rule; read -rp "按回车继续..." _ ;;
            4) remove_rule; read -rp "按回车继续..." _ ;;
            5) set_auto_update; read -rp "按回车继续..." _ ;;
            0) exit 0 ;;
            *) log WARN "无效选择"; sleep 1 ;;
        esac
    done
}

cron_update() {
    update_cn_ipset
    load_config
    apply_all_rules
    log SUCCESS "定时任务已完成"
}

usage() {
    cat <<HELP
使用方法:
  $SCRIPT_NAME             # 打开交互菜单
  $SCRIPT_NAME --cron-update   # 定时任务：更新国内 IP 库并应用规则
HELP
}

main() {
    check_root
    install_dependencies
    init_environment
    load_config

    case "${1:-}" in
        --cron-update)
            cron_update
            ;;
        --help|-h)
            usage
            ;;
        "")
            apply_all_rules
            main_menu
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
