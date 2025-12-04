#!/bin/bash
# port-filter.sh - 端口访问控制一键脚本（IP 源规则库版）
# 支持：IP地域过滤、端口屏蔽/放行、TCP/UDP协议控制、白名单管理、IP源规则库选择、自动更新计划

VERSION="3.1.0"

CONFIG_DIR="/etc/port-filter"
RULES_FILE="$CONFIG_DIR/rules.conf"
WHITELIST_FILE="$CONFIG_DIR/whitelist.conf"
SETTINGS_FILE="$CONFIG_DIR/settings.conf"
SOURCE_LIB_FILE="$CONFIG_DIR/ip_sources.conf"

IPSET_NAME="china"
IPSET_WHITE="whitelist"

CRON_FILE="/etc/cron.d/port-filter"
LOG_FILE="/var/log/port-filter/update.log"

APT_UPDATED=0

# 当前脚本路径（给定时任务用）
SCRIPT_PATH="$(readlink -f "$0")"

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

# IP 源规则库（你说的“规则库”就是这里）
IP_SOURCES=(
    "metowolf/IPList|https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt"
    "17mon/ChinaIPList|https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt"
    "gaoyifan/OperatorIP|https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt"
)

# 常用打印函数
print_info()    { printf "%b%s%b\n" "$CYAN"   "$1" "$NC"; }
print_success() { printf "%b%s%b\n" "$GREEN"  "$1" "$NC"; }
print_warning() { printf "%b%s%b\n" "$YELLOW" "$1" "$NC"; }
print_error()   { printf "%b%s%b\n" "$RED"    "$1" "$NC"; }

print_title() {
    printf "${BOLD}${MAGENTA}╔════════════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAGENTA}║ 端口访问控制脚本 v%s%-28s║${NC}\n" "$VERSION" ""
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

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
}

# 初始化白名单配置
init_whitelist() {
    if [ ! -f "$WHITELIST_FILE" ]; then
        cat > "$WHITELIST_FILE" << 'EOF'
# IP白名单配置
# 支持单个IP: 192.168.1.100
# 支持IP段: 10.0.0.0/8
# 白名单IP不会被任何规则拦截
EOF
    fi
}

# 创建白名单 ipset
create_whitelist_set() {
    if ! ipset list "$IPSET_WHITE" >/dev/null 2>&1; then
        ipset create "$IPSET_WHITE" hash:net maxelem 65536
    fi
}

# 加载白名单
load_whitelist() {
    create_whitelist_set
    ipset flush "$IPSET_WHITE"

    if [ -f "$WHITELIST_FILE" ]; then
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue

            if [[ $line =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
                ipset add "$IPSET_WHITE" "$line" >/dev/null 2>&1
            fi
        done < "$WHITELIST_FILE"
    fi
}

# 初始化 IP 源规则库（默认启用全部内置源）
init_ip_sources() {
    mkdir -p "$CONFIG_DIR"
    if [ ! -f "$SOURCE_LIB_FILE" ]; then
        : > "$SOURCE_LIB_FILE"
        for entry in "${IP_SOURCES[@]}"; do
            IFS='|' read -r name url <<< "$entry"
            echo "$name" >> "$SOURCE_LIB_FILE"
        done
    fi
}

# 添加 IP 到白名单
add_whitelist_ip() {
    local ip="$1"

    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
        if ! grep -q "^$ip$" "$WHITELIST_FILE" 2>/dev/null; then
            echo "$ip" >> "$WHITELIST_FILE"
            create_whitelist_set
            ipset add "$IPSET_WHITE" "$ip" >/dev/null 2>&1
            print_success "已添加 $ip 到白名单"
            return 0
        else
            print_warning "IP $ip 已存在于白名单中"
            return 1
        fi
    else
        print_error "无效的IP地址格式: $ip"
        return 1
    fi
}

# 从白名单移除 IP
remove_whitelist_ip() {
    local ip="$1"

    if grep -q "^$ip$" "$WHITELIST_FILE" 2>/dev/null; then
        sed -i "/^$ip$/d" "$WHITELIST_FILE"
        ipset del "$IPSET_WHITE" "$ip" >/dev/null 2>&1
        print_success "已从白名单移除 $ip"
        return 0
    else
        print_warning "IP $ip 不在白名单中"
        return 1
    fi
}

# 显示白名单
show_whitelist() {
    print_info "当前白名单IP:"
    if [ -f "$WHITELIST_FILE" ]; then
        local count=0
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue
            echo "  $line"
            ((count++))
        done < "$WHITELIST_FILE"

        if [ $count -eq 0 ]; then
            print_warning "白名单为空"
        fi
    else
        print_warning "白名单文件不存在"
    fi
}

# 下载中国 IP 列表（使用“已启用”的 IP 源规则库）
download_china_ip() {
    print_info "正在下载中国IP列表..."

    if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        ipset create "$IPSET_NAME" hash:net maxelem 65536
    else
        ipset flush "$IPSET_NAME"
    fi

    # 读取当前启用的 IP 源规则库
    local active_sources=()
    if [ -f "$SOURCE_LIB_FILE" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            [[ "$line" =~ ^# ]] && continue
            active_sources+=("$line")
        done < "$SOURCE_LIB_FILE"
    fi

    local total=0
    local success=0

    for entry in "${IP_SOURCES[@]}"; do
        IFS='|' read -r name url <<< "$entry"

        # 判断该源是否启用
        local use_this=0
        if [ ${#active_sources[@]} -eq 0 ]; then
            # 没配置时默认全部启用
            use_this=1
        else
            for a in "${active_sources[@]}"; do
                if [ "$a" = "$name" ]; then
                    use_this=1
                    break
                fi
            done
        fi

        [ "$use_this" -eq 0 ] && continue

        print_info "正在从 $name 下载（$url）..."

        if curl -sL --connect-timeout 10 "$url" \
            | while read -r ip; do
                [[ "$ip" =~ ^#.*$ ]] && continue
                [[ -z "$ip" ]] && continue
                [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]] && echo "$ip"
              done \
            | while read -r ip; do
                ipset add "$IPSET_NAME" "$ip" 2>/dev/null && ((total++))
              done; then
            print_success "✓ 从 $name 成功导入IP段"
            ((success++))
        else
            print_error "✗ 从 $name 下载失败"
        fi
    done

    if [ "$success" -eq 0 ]; then
        print_error "✗ 所有已启用的 IP 源下载失败，请检查网络或规则库配置"
        return 1
    fi

    print_success "✓ 成功导入 ${total} 条 IP 规则（来自 $success 个源）"
    return 0
}

# 保存规则到配置文件
save_rule_config() {
    local port=$1
    local protocol=$2
    local mode=$3
    local action=$4

    mkdir -p "$CONFIG_DIR"
    echo "${port}|${protocol}|${mode}|${action}" >> "$RULES_FILE"
}

# 清除某个端口的所有规则
clear_port_rules() {
    local port=$1

    iptables -D INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null
    iptables -D INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_NAME" src -j ACCEPT 2>/dev/null
    iptables -D INPUT -p tcp --dport "$port" -j DROP 2>/dev/null
    iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
    iptables -D INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_WHITE" src -j ACCEPT 2>/dev/null

    iptables -D INPUT -p udp --dport "$port" -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null
    iptables -D INPUT -p udp --dport "$port" -m set --match-set "$IPSET_NAME" src -j ACCEPT 2>/dev/null
    iptables -D INPUT -p udp --dport "$port" -j DROP 2>/dev/null
    iptables -D INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
    iptables -D INPUT -p udp --dport "$port" -m set --match-set "$IPSET_WHITE" src -j ACCEPT 2>/dev/null
}

# 确保 IP 地域 ipset 存在
ensure_ipset_exists() {
    if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        download_china_ip
    fi
}

# 应用地域规则（先规则，再白名单；白名单优先）
apply_rule() {
    local port=$1
    local protocol=$2
    local mode=$3

    clear_port_rules "$port"
    ensure_ipset_exists

    # 1. 先插入 IP 地域过滤规则
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

    # 2. 再插入白名单（后插入 → 规则链最上面 → 优先放行）
    if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_WHITE" src -j ACCEPT
    fi

    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p udp --dport "$port" -m set --match-set "$IPSET_WHITE" src -j ACCEPT
    fi
}

# 屏蔽端口（修正白名单顺序）
block_port() {
    local port=$1
    local protocol=$2

    clear_port_rules "$port"

    # 1. 先插入屏蔽规则
    if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p tcp --dport "$port" -j DROP
        print_success "✓ 已屏蔽 TCP 端口 $port"
    fi

    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p udp --dport "$port" -j DROP
        print_success "✓ 已屏蔽 UDP 端口 $port"
    fi

    # 2. 再插入白名单规则（后插入，优先放行）
    if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_WHITE" src -j ACCEPT
    fi

    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p udp --dport "$port" -m set --match-set "$IPSET_WHITE" src -j ACCEPT
    fi
}

# 放行端口（顺序同样保持一致）
allow_port() {
    local port=$1
    local protocol=$2

    clear_port_rules "$port"

    # 1. 先插入放行规则
    if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
        print_success "✓ 已放行 TCP 端口 $port"
    fi

    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p udp --dport "$port" -j ACCEPT
        print_success "✓ 已放行 UDP 端口 $port"
    fi

    # 2. 再插入白名单规则（统一保证白名单最高优先级）
    if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_WHITE" src -j ACCEPT
    fi

    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p udp --dport "$port" -m set --match-set "$IPSET_WHITE" src -j ACCEPT
    fi
}

# 查看当前规则
show_rules() {
    print_info "==================== 当前防火墙规则 ====================="
    print_warning "TCP 规则："
    iptables -L INPUT -n -v --line-numbers | grep "tcp dpt:" | head -20 || true
    echo ""
    print_warning "UDP 规则："
    iptables -L INPUT -n -v --line-numbers | grep "udp dpt:" | head -20 || true
    print_info "========================================================="
}

# 查看保存的端口策略
show_saved_configs() {
    if [ ! -f "$RULES_FILE" ]; then
        print_warning "暂无保存的端口策略"
        return
    fi

    print_info "==================== 已保存的端口策略 ===================="
    printf "%s%-8s%-12s%-16s%-16s%s\n" "$BOLD" "端口" "协议" "模式" "类型" "$NC"

    while IFS='|' read -r port protocol mode action; do
        printf "%-8s%-12s%-16s%-16s\n" "$port" "$protocol" "$mode" "$action"
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
        iptables -D INPUT $rule 2>/dev/null || true
    done

    iptables -S INPUT | grep "dpt:" | cut -d" " -f2- | while read -r rule; do
        iptables -D INPUT $rule 2>/dev/null || true
    done

    ipset destroy "$IPSET_NAME" 2>/dev/null
    ipset destroy "$IPSET_WHITE" 2>/dev/null

    rm -f "$RULES_FILE"
    rm -f "$SETTINGS_FILE"
    rm -f "$CRON_FILE"
    rm -f "$SOURCE_LIB_FILE"

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

# 配置自动更新计划
setup_auto_update() {
    print_info "==================== 配置自动更新计划 ===================="

    read -rp "请输入每天自动更新的时间（24小时制，如 03:30）: " update_time
    if [[ ! "$update_time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        print_error "时间格式错误，请输入有效的24小时制时间（如 03:30）"
        return 1
    fi

    local minute hour
    minute="${update_time#*:}"
    hour="${update_time%:*}"

    cat > "$CRON_FILE" << EOF
# port-filter 自动更新中国IP列表
$minute $hour * * * root $SCRIPT_PATH --update-ip >> $LOG_FILE 2>&1
EOF

    reload_cron_service
    print_success "✓ 自动更新计划已配置为每天 $update_time"

    cat > "$SETTINGS_FILE" << EOF
UPDATE_TIME="$update_time"
AUTO_UPDATE_ENABLED="yes"
EOF
}

# 更新中国 IP 列表
update_china_ip() {
    print_info "正在更新中国IP列表..."
    if download_china_ip; then
        # 重新应用所有已保存的地域规则
        if [ -f "$RULES_FILE" ]; then
            print_info "重新应用已保存的地域规则..."
            while IFS='|' read -r port protocol mode action; do
                if [ "$action" = "geo_filter" ]; then
                    apply_rule "$port" "$protocol" "$mode"
                fi
            done < "$RULES_FILE"
        fi
        save_rules
        print_success "✓ IP列表更新完成，规则已重新应用"
    else
        print_error "✗ IP列表更新失败"
    fi
}

########################################
# IP 源规则库管理
########################################

show_ip_source_libraries() {
    print_info "当前已启用的 IP 源规则库："
    if [ -f "$SOURCE_LIB_FILE" ]; then
        local count=0
        while IFS= read -r name; do
            [ -z "$name" ] && continue
            echo "  - $name"
            ((count++))
        done < "$SOURCE_LIB_FILE"
        [ $count -eq 0 ] && print_warning "暂无启用的 IP 源（将回退到内置默认全部）"
    else
        print_warning "还没有规则库配置文件（将回退到内置默认全部）"
    fi
}

enable_ip_source() {
    local name="$1"

    # 检查是否为内置源之一
    local found=0
    for entry in "${IP_SOURCES[@]}"; do
        IFS='|' read -r n url <<< "$entry"
        if [ "$n" = "$name" ]; then
            found=1
            break
        fi
    done

    if [ "$found" -eq 0 ]; then
        print_error "未知 IP 源规则库: $name"
        return 1
    fi

    mkdir -p "$CONFIG_DIR"
    touch "$SOURCE_LIB_FILE"

    if grep -q "^$name$" "$SOURCE_LIB_FILE" 2>/dev/null; then
        print_warning "规则库 $name 已经启用"
        return 0
    fi

    echo "$name" >> "$SOURCE_LIB_FILE"
    print_success "已启用 IP 源规则库: $name"
}

disable_ip_source() {
    local name="$1"

    if [ ! -f "$SOURCE_LIB_FILE" ]; then
        print_warning "规则库配置文件不存在"
        return 0
    fi

    if ! grep -q "^$name$" "$SOURCE_LIB_FILE" 2>/dev/null; then
        print_warning "规则库 $name 当前未启用"
        return 0
    fi

    sed -i "/^$name$/d" "$SOURCE_LIB_FILE" 2>/dev/null
    print_success "已禁用 IP 源规则库: $name"
}

reset_ip_sources_to_default() {
    mkdir -p "$CONFIG_DIR"
    : > "$SOURCE_LIB_FILE"
    for entry in "${IP_SOURCES[@]}"; do
        IFS='|' read -r name url <<< "$entry"
        echo "$name" >> "$SOURCE_LIB_FILE"
    done
    print_success "已恢复默认：启用所有内置 IP 源规则库"
}

ip_source_library_menu() {
    while true; do
        clear
        print_title
        echo ""
        print_info "IP 源规则库选择（控制使用哪些中国IP数据源）"
        echo ""
        show_ip_source_libraries
        echo ""
        echo "内置可用规则库（IP 源）："
        local idx=1
        for entry in "${IP_SOURCES[@]}"; do
            IFS='|' read -r name url <<< "$entry"
            echo "  $idx) $name"
            echo "     $url"
            ((idx++))
        done
        echo ""
        echo "a) 启用某个规则库（按名称，例如：metowolf/IPList）"
        echo "b) 禁用某个规则库"
        echo "c) 恢复默认（启用全部内置源）"
        echo "d) 返回主菜单"
        echo ""
        read -rp "请选择操作 [a/b/c/d]: " choice
        case "$choice" in
            a)
                read -rp "请输入要启用的规则库名称: " name
                [ -n "$name" ] && enable_ip_source "$name"
                read -rp "按回车键继续..." ;;
            b)
                read -rp "请输入要禁用的规则库名称: " name
                [ -n "$name" ] && disable_ip_source "$name"
                read -rp "按回车键继续..." ;;
            c)
                reset_ip_sources_to_default
                read -rp "按回车键继续..." ;;
            d)
                return ;;
            *)
                print_error "无效选择"
                read -rp "按回车键继续..." ;;
        esac
    done
}

########################################
# 交互菜单
########################################

show_menu() {
    clear
    print_title
    echo ""

    if [ -f "$SETTINGS_FILE" ]; then
        # shellcheck disable=SC1090
        source "$SETTINGS_FILE" 2>/dev/null
        if [ "${AUTO_UPDATE_ENABLED:-no}" = "yes" ]; then
            printf "自动更新：每天 %s${GREEN} ✓%s\n" "$UPDATE_TIME" "$NC"
        else
            printf "自动更新：%s未设置%s\n" "$YELLOW" "$NC"
        fi
    else
        printf "自动更新：%s未设置%s\n" "$YELLOW" "$NC"
    fi

    echo ""
    printf "${GREEN}1.${NC} IP地域过滤（黑名单/白名单）\n"
    printf "${GREEN}2.${NC} 屏蔽端口（完全阻止访问）\n"
    printf "${GREEN}3.${NC} 放行端口（完全允许访问）\n"
    printf "${GREEN}4.${NC} 查看当前 iptables 规则\n"
    printf "${GREEN}5.${NC} IP白名单管理\n"
    printf "${GREEN}6.${NC} IP 源规则库选择（选择使用哪些中国IP数据源）\n"
    printf "${GREEN}7.${NC} 清除所有规则\n"
    printf "${GREEN}8.${NC} 立即更新中国 IP\n"
    printf "${GREEN}9.${NC} 配置自动更新计划\n"
    printf "${GREEN}10.${NC} 查看已保存的端口策略\n"
    printf "${GREEN}0.${NC} 退出\n"
    echo ""
    printf "${YELLOW}请选择操作 [0-10]: ${NC}"
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
    echo "1. 黑名单（阻止中国IP访问）"
    echo "2. 白名单（仅允许中国IP访问）"
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

# IP 白名单管理菜单
whitelist_menu() {
    while true; do
        clear
        print_title
        echo ""
        print_info "IP白名单管理"
        echo ""
        show_whitelist
        echo ""
        echo "1) 添加IP到白名单"
        echo "2) 从白名单移除IP"
        echo "3) 返回主菜单"
        echo ""
        read -rp "请选择操作 [1-3]: " choice
        case $choice in
            1)
                read -rp "请输入IP地址或IP段: " ip
                if [ -n "$ip" ]; then
                    add_whitelist_ip "$ip"
                    save_rules
                fi
                read -rp "按回车键继续..." ;;
            2)
                read -rp "请输入要移除的IP地址: " ip
                if [ -n "$ip" ]; then
                    remove_whitelist_ip "$ip"
                    save_rules
                fi
                read -rp "按回车键继续..." ;;
            3)
                return ;;
            *)
                print_error "无效选择"
                read -rp "按回车键继续..." ;;
        esac
    done
}

# 主程序
main() {
    check_root
    install_dependencies
    init_whitelist
    create_whitelist_set
    load_whitelist
    init_ip_sources

    while true; do
        show_menu
        read -r choice
        case $choice in
            1) setup_geo_filter;       read -rp "按回车继续..." _ ;;
            2) setup_block_port;       read -rp "按回车继续..." _ ;;
            3) setup_allow_port;       read -rp "按回车继续..." _ ;;
            4) show_rules;             read -rp "按回车继续..." _ ;;
            5) whitelist_menu ;;
            6) ip_source_library_menu ;;
            7) clear_all_rules;        read -rp "按回车继续..." _ ;;
            8) update_china_ip;        read -rp "按回车继续..." _ ;;
            9) setup_auto_update;      read -rp "按回车继续..." _ ;;
            10) show_saved_configs;    read -rp "按回车继续..." _ ;;
            0) print_success "退出程序"; exit 0 ;;
            *) print_error "无效选择";  read -rp "按回车继续..." _ ;;
        esac
    done
}

########################################
# 命令行模式（保持安装命令不变）
########################################

if [ "$1" = "--whitelist" ] && [ -n "$2" ]; then
    check_root
    install_dependencies
    init_whitelist
    create_whitelist_set
    add_whitelist_ip "$2"
    save_rules
    exit 0
fi

if [ "$1" = "--update-ip" ]; then
    check_root
    install_dependencies
    update_china_ip
    exit 0
fi

# 运行主程序
main
