#!/bin/bash
# port_filter.sh - 端口访问控制一键脚本
# 支持：IP地域过滤、端口屏蔽/放行、TCP/UDP协议控制、自动更新计划

VERSION="2.0.0"
CONFIG_DIR="/etc/port-filter"
RULES_FILE="$CONFIG_DIR/rules.conf"
SETTINGS_FILE="$CONFIG_DIR/settings.conf"
IPSET_NAME="china"
CRON_FILE="/etc/cron.d/port-filter"
LOG_FILE="/var/log/port-filter/update.log"
APT_UPDATED=0

# 颜色定义（兼容 SSH 终端）
if command -v tput >/dev/null 2>&1 && [ -n "$TERM" ] && [ "$TERM" != "dumb" ]; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    MAGENTA="$(tput setaf 5)"
    CYAN="$(tput setaf 6)"
    BOLD="$(tput bold)"
    NC="$(tput sgr0)"
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
fi

SCRIPT_PATH="$(readlink -f "$0")"

IP_SOURCES=(
    "metowolf/IPList|https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt"
    "17mon/ChinaIPList|https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt"
    "gaoyifan/OperatorIP|https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt"
)

# 常用打印函数
print_info() { printf "%b%s%b\n" "$CYAN" "$1" "$NC"; }
print_success() { printf "%b%s%b\n" "$GREEN" "$1" "$NC"; }
print_warning() { printf "%b%s%b\n" "$YELLOW" "$1" "$NC"; }
print_error() { printf "%b%s%b\n" "$RED" "$1" "$NC"; }
print_title() {
    printf "${BOLD}${MAGENTA}╔════════════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAGENTA}║      端口访问控制脚本 v%s%-28s║${NC}\n" "$VERSION" ""
    printf "${BOLD}${MAGENTA}╚════════════════════════════════════════════════╝${NC}\n"
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "错误：请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 依赖安装
install_dependencies() {
    print_info "[1/3] 检查并安装依赖..."

    apt_update_once() {
        if [ $APT_UPDATED -eq 0 ]; then
            apt-get update -qq
            APT_UPDATED=1
        fi
    }

    if ! command -v ipset >/dev/null 2>&1; then
        apt_update_once
        apt-get install -y ipset >/dev/null 2>&1
    fi

    if ! command -v iptables >/dev/null 2>&1; then
        apt_update_once
        apt-get install -y iptables >/dev/null 2>&1
    fi

    if ! command -v netfilter-persistent >/dev/null 2>&1; then
        apt_update_once
        apt-get install -y iptables-persistent >/dev/null 2>&1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        apt_update_once
        apt-get install -y curl >/dev/null 2>&1
    fi

    if ! command -v cron >/dev/null 2>&1 && ! pgrep cron >/dev/null 2>&1; then
        apt_update_once
        apt-get install -y cron >/dev/null 2>&1
    fi

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"

    print_success "✓ 依赖检查完成"
}

# 配置文件工具
get_setting() {
    local key=$1
    [ -f "$SETTINGS_FILE" ] || return 1
    grep -E "^${key}=" "$SETTINGS_FILE" | tail -n1 | cut -d'=' -f2-
}

set_setting() {
    local key=$1
    local value=$2
    mkdir -p "$CONFIG_DIR"
    touch "$SETTINGS_FILE"
    if grep -qE "^${key}=" "$SETTINGS_FILE"; then
        sed -i "s/^${key}=.*/${key}=${value}/" "$SETTINGS_FILE"
    else
        echo "${key}=${value}" >> "$SETTINGS_FILE"
    fi
}

delete_setting() {
    local key=$1
    [ -f "$SETTINGS_FILE" ] || return
    sed -i "/^${key}=.*/d" "$SETTINGS_FILE"
}

# IPSet 工具
ensure_ipset_exists() {
    if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        ipset create "$IPSET_NAME" hash:net family inet hashsize 4096 maxelem 262144
    fi
}

refresh_ipset() {
    ensure_ipset_exists
    ipset flush "$IPSET_NAME"
}

# 下载中国 IP 列表
download_china_ip() {
    print_info "[2/3] 下载并更新中国 IP 列表..."

    refresh_ipset

    local total=0
    local success=0

    for source in "${IP_SOURCES[@]}"; do
        local name=${source%%|*}
        local url=${source#*|}
        local temp_file
        temp_file=$(mktemp)

        printf "  %s%-40s%s" "$BLUE" "→ 获取 ${name}" "$NC"
        if curl -fsSL --max-time 90 "$url" -o "$temp_file"; then
            local count=0
            while IFS= read -r ip; do
                ip=${ip%%#*}
                ip=${ip// /}
                [ -z "$ip" ] && continue
                [[ "$ip" == *:* ]] && continue
                ipset add "$IPSET_NAME" "$ip" 2>/dev/null && count=$((count+1))
            done < "$temp_file"
            rm -f "$temp_file"
            success=$((success+1))
            total=$((total+count))
            printf "\r  %s%-40s%s\n" "$GREEN" "✓ 已导入 ${count} 条" "$NC"
        else
            rm -f "$temp_file"
            printf "\r  %s%-40s%s\n" "$YELLOW" "⚠ 源不可用" "$NC"
        fi
    done

    if [ "$success" -eq 0 ]; then
        print_error "✗ 所有 IP 源均下载失败，请检查网络"
        return 1
    fi

    print_success "✓ 成功导入 ${total} 条 IP 规则"
}

# 保存规则
save_rule_config() {
    local port=$1
    local protocol=$2
    local mode=$3
    local action=$4

    mkdir -p "$CONFIG_DIR"
    echo "${port}|${protocol}|${mode}|${action}" >> "$RULES_FILE"
}

# 清除端口的所有规则
clear_port_rules() {
    local port=$1

    iptables -D INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null
    iptables -D INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_NAME" src -j ACCEPT 2>/dev/null
    iptables -D INPUT -p tcp --dport "$port" -j DROP 2>/dev/null
    iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null

    iptables -D INPUT -p udp --dport "$port" -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null
    iptables -D INPUT -p udp --dport "$port" -m set --match-set "$IPSET_NAME" src -j ACCEPT 2>/dev/null
    iptables -D INPUT -p udp --dport "$port" -j DROP 2>/dev/null
    iptables -D INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
}

# 应用规则
apply_rule() {
    local port=$1
    local protocol=$2
    local mode=$3

    clear_port_rules "$port"
    ensure_ipset_exists

    if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
        if [ "$mode" = "blacklist" ]; then
            iptables -I INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_NAME" src -j DROP
            print_success "✓ TCP端口 $port: 已设置黑名单（阻止中国IP）"
        elif [ "$mode" = "whitelist" ]; then
            iptables -I INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_NAME" src -j ACCEPT
            iptables -I INPUT -p tcp --dport "$port" -j DROP
            print_success "✓ TCP端口 $port: 已设置白名单（仅允许中国IP）"
        fi
    fi

    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        if [ "$mode" = "blacklist" ]; then
            iptables -I INPUT -p udp --dport "$port" -m set --match-set "$IPSET_NAME" src -j DROP
            print_success "✓ UDP端口 $port: 已设置黑名单（阻止中国IP）"
        elif [ "$mode" = "whitelist" ]; then
            iptables -I INPUT -p udp --dport "$port" -m set --match-set "$IPSET_NAME" src -j ACCEPT
            iptables -I INPUT -p udp --dport "$port" -j DROP
            print_success "✓ UDP端口 $port: 已设置白名单（仅允许中国IP）"
        fi
    fi
}

# 屏蔽端口
block_port() {
    local port=$1
    local protocol=$2

    clear_port_rules "$port"

    if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p tcp --dport "$port" -j DROP
        print_success "✓ 已屏蔽 TCP 端口 $port"
    fi

    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p udp --dport "$port" -j DROP
        print_success "✓ 已屏蔽 UDP 端口 $port"
    fi
}

# 放行端口
allow_port() {
    local port=$1
    local protocol=$2

    clear_port_rules "$port"

    if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
        print_success "✓ 已放行 TCP 端口 $port"
    fi

    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p udp --dport "$port" -j ACCEPT
        print_success "✓ 已放行 UDP 端口 $port"
    fi
}

# 查看当前规则
show_rules() {
    print_info "==================== 当前防火墙规则 ====================="
    print_warning "TCP 规则："
    iptables -L INPUT -n -v --line-numbers | grep "tcp dpt:" | head -20
    echo ""
    print_warning "UDP 规则："
    iptables -L INPUT -n -v --line-numbers | grep "udp dpt:" | head -20
    print_info "========================================================="
}

# 查看保存的端口策略
show_saved_configs() {
    if [ ! -f "$RULES_FILE" ]; then
        print_warning "暂无保存的端口策略"
        return
    fi

    print_info "==================== 已保存的端口策略 ===================="
    printf "%s%-8s%-12s%-12s%-12s%s\n" "$BOLD" "端口" "协议" "模式" "类型" "$NC"
    while IFS='|' read -r port protocol mode action; do
        printf "%-8s%-12s%-12s%-12s\n" "$port" "$protocol" "$mode" "$action"
    done < "$RULES_FILE"
    print_info "========================================================="
}

# 保存防火墙规则
save_rules() {
    print_info "[3/3] 保存防火墙规则..."
    netfilter-persistent save >/dev/null 2>&1
    print_success "✓ 规则已保存"
}

# 清除所有规则
clear_all_rules() {
    print_warning "正在清除所有规则..."

    iptables -S INPUT | grep "$IPSET_NAME" | cut -d" " -f2- | while read -r rule; do
        iptables -D INPUT $rule 2>/dev/null
    done

    iptables -S INPUT | grep "dpt:" | cut -d" " -f2- | while read -r rule; do
        iptables -D INPUT $rule 2>/dev/null
    done

    ipset destroy "$IPSET_NAME" 2>/dev/null

    rm -f "$RULES_FILE"
    rm -f "$SETTINGS_FILE"
    rm -f "$CRON_FILE"

    save_rules
    print_success "✓ 所有规则已清除"
}

# 重载/重启定时任务
reload_cron_service() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl reload cron 2>/dev/null || systemctl restart cron 2>/dev/null
    else
        service cron reload 2>/dev/null || service cron restart 2>/dev/null
    fi
}

# 配置自动更新
configure_auto_update() {
    local current
    current=$(get_setting "AUTO_UPDATE_TIME")
    if [ -n "$current" ]; then
        print_info "当前自动更新时间：$current"
    else
        print_info "当前未设置自动更新"
    fi

    read -rp "请输入每天自动更新时间 (HH:MM，留空禁用): " schedule

    if [ -z "$schedule" ]; then
        rm -f "$CRON_FILE"
        delete_setting "AUTO_UPDATE_TIME"
        print_warning "已关闭自动更新"
        return
    fi

    if [[ ! $schedule =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
        print_error "时间格式错误，请使用 24 小时制 HH:MM"
        return
    fi

    local hour=${schedule%:*}
    local minute=${schedule#*:}

    cat > "$CRON_FILE" <<'CRON_UPDATE'
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
__MINUTE__ __HOUR__ * * * root __SCRIPT_PATH__ --update-ip >> __LOG_FILE__ 2>&1
CRON_UPDATE

    sed -i "s/__MINUTE__/${minute}/" "$CRON_FILE"
    sed -i "s/__HOUR__/${hour}/" "$CRON_FILE"
    sed -i "s#__SCRIPT_PATH__#${SCRIPT_PATH}#" "$CRON_FILE"
    sed -i "s#__LOG_FILE__#${LOG_FILE}#" "$CRON_FILE"

    set_setting "AUTO_UPDATE_TIME" "$schedule"
    reload_cron_service
    print_success "✓ 已设置每天 ${schedule} 自动更新中国 IP 列表"
}

# 主菜单
show_menu() {
    clear
    print_title

    local schedule
    schedule=$(get_setting "AUTO_UPDATE_TIME")
    if [ -n "$schedule" ]; then
        printf "%s自动更新：每天 %s%s\n" "$GREEN" "$schedule" "$NC"
    else
        printf "%s自动更新：未设置%s\n" "$YELLOW" "$NC"
    fi
    echo ""

    printf "${GREEN}1.${NC} IP地域过滤（黑名单/白名单）\n"
    printf "${GREEN}2.${NC} 屏蔽端口（完全阻止访问）\n"
    printf "${GREEN}3.${NC} 放行端口（完全允许访问）\n"
    printf "${GREEN}4.${NC} 查看当前 iptables 规则\n"
    printf "${GREEN}5.${NC} 清除所有规则\n"
    printf "${GREEN}6.${NC} 更新中国 IP 列表\n"
    printf "${GREEN}7.${NC} 配置自动更新计划\n"
    printf "${GREEN}8.${NC} 查看已保存的端口策略\n"
    printf "${GREEN}0.${NC} 退出\n\n"
    printf "${YELLOW}请选择操作 [0-8]: ${NC}"
}

# IP 地域过滤设置
setup_geo_filter() {
    print_info "==================== IP 地域过滤设置 ====================="

    if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        download_china_ip || return
    fi

    read -rp "请输入端口号: " port

    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -rp "请选择 [1-3]: " proto_choice

    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) print_error "无效选择"; return ;;
    esac

    echo "选择模式："
    echo "1. 黑名单（阻止中国IP，允许其他地区）"
    echo "2. 白名单（仅允许中国IP，阻止其他地区）"
    read -rp "请选择 [1-2]: " mode_choice

    case $mode_choice in
        1) mode="blacklist" ;;
        2) mode="whitelist" ;;
        *) print_error "无效选择"; return ;;
    esac

    apply_rule "$port" "$protocol" "$mode"
    save_rule_config "$port" "$protocol" "$mode" "geo_filter"
    save_rules
}

# 屏蔽端口设置
setup_block_port() {
    print_info "==================== 屏蔽端口 =========================="

    read -rp "请输入要屏蔽的端口号: " port

    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -rp "请选择 [1-3]: " proto_choice

    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) print_error "无效选择"; return ;;
    esac

    block_port "$port" "$protocol"
    save_rule_config "$port" "$protocol" "block" "block"
    save_rules
}

# 放行端口设置
setup_allow_port() {
    print_info "==================== 放行端口 =========================="

    read -rp "请输入要放行的端口号: " port

    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -rp "请选择 [1-3]: " proto_choice

    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) print_error "无效选择"; return ;;
    esac

    allow_port "$port" "$protocol"
    save_rule_config "$port" "$protocol" "allow" "allow"
    save_rules
}

# 主程序
main() {
    check_root
    install_dependencies

    while true; do
        show_menu
        read -r choice

        case $choice in
            1)
                setup_geo_filter
                read -rp "按回车继续..." _
                ;;
            2)
                setup_block_port
                read -rp "按回车继续..." _
                ;;
            3)
                setup_allow_port
                read -rp "按回车继续..." _
                ;;
            4)
                show_rules
                read -rp "按回车继续..." _
                ;;
            5)
                read -rp "确认清除所有规则？(y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    clear_all_rules
                fi
                read -rp "按回车继续..." _
                ;;
            6)
                download_china_ip && save_rules
                read -rp "按回车继续..." _
                ;;
            7)
                configure_auto_update
                read -rp "按回车继续..." _
                ;;
            8)
                show_saved_configs
                read -rp "按回车继续..." _
                ;;
            0)
                print_success "再见！"
                exit 0
                ;;
            *)
                print_error "无效选择，请重试"
                sleep 1
                ;;
        esac
    done
}

# 处理命令行参数
if [ "$1" = "--update-ip" ]; then
    check_root
    install_dependencies
    if download_china_ip; then
        save_rules
        exit 0
    else
        exit 1
    fi
fi

# 运行主程序
main
