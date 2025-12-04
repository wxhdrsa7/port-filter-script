#!/bin/bash
# port-filter-enhanced.sh - 改进版端口访问控制脚本
# 新增功能：IP白名单、规则库选择、动态规则管理

VERSION="3.0.0"
CONFIG_DIR="/etc/port-filter"
RULES_FILE="$CONFIG_DIR/rules.conf"
WHITELIST_FILE="$CONFIG_DIR/whitelist.conf"
SETTINGS_FILE="$CONFIG_DIR/settings.conf"
IPSET_NAME="china"
IPSET_WHITE="whitelist"
CRON_FILE="/etc/cron.d/port-filter"
LOG_FILE="/var/log/port-filter/update.log"
APT_UPDATED=0

# 颜色定义
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

# 打印函数
print_info() { printf "%b%s%b\n" "$CYAN" "$1" "$NC"; }
print_success() { printf "%b%s%b\n" "$GREEN" "$1" "$NC"; }
print_warning() { printf "%b%s%b\n" "$YELLOW" "$1" "$NC"; }
print_error() { printf "%b%s%b\n" "$RED" "$1" "$NC"; }
print_title() {
    printf "${BOLD}${MAGENTA}╔════════════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAGENTA}║      端口访问控制脚本 v%s%-28s║${NC}\n" "$VERSION" ""
    printf "${BOLD}${MAGENTA}╚════════════════════════════════════════════════╝${NC}\n"
}

# 检查root权限
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

# 初始化配置
init_config() {
    if [ ! -f "$SETTINGS_FILE" ]; then
        cat > "$SETTINGS_FILE" << 'EOF'
# 端口过滤器设置
ACTIVE_RULES="common_attacks malware_ports"
AUTO_UPDATE_ENABLED="no"
UPDATE_TIME="03:30"
EOF
    fi

    if [ ! -f "$WHITELIST_FILE" ]; then
        cat > "$WHITELIST_FILE" << 'EOF'
# IP白名单 (支持单个IP和IP段)
# 示例:
# 192.168.1.100
# 10.0.0.0/8
# 172.16.0.0/12
EOF
    fi
}

# 加载设置
load_settings() {
    if [ -f "$SETTINGS_FILE" ]; then
        source "$SETTINGS_FILE"
    fi
}

# 创建白名单ipset
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
            # 跳过注释和空行
            [[ "$line" =~ ^#.*$ ]] || [[ -z "$line" ]] && continue
            
            # 验证IP地址格式
            if [[ $line =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
                ipset add "$IPSET_WHITE" "$line" >/dev/null 2>&1
                print_success "已添加白名单IP: $line"
            fi
        done < "$WHITELIST_FILE"
    fi
}

# 添加IP到白名单
add_whitelist_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
        # 检查是否已经存在
        if grep -q "^$ip$" "$WHITELIST_FILE" 2>/dev/null; then
            print_warning "IP $ip 已存在于白名单中"
            return 1
        fi
        
        # 添加到文件
        echo "$ip" >> "$WHITELIST_FILE"
        
        # 添加到ipset
        create_whitelist_set
        ipset add "$IPSET_WHITE" "$ip" >/dev/null 2>&1
        
        print_success "已添加 $ip 到白名单"
        
        # 重新加载iptables规则
        setup_iptables
        return 0
    else
        print_error "无效的IP地址格式: $ip"
        return 1
    fi
}

# 从白名单移除IP
remove_whitelist_ip() {
    local ip="$1"
    
    # 从文件中删除
    if grep -q "^$ip$" "$WHITELIST_FILE" 2>/dev/null; then
        sed -i "/^$ip$/d" "$WHITELIST_FILE"
        
        # 从ipset中删除
        ipset del "$IPSET_WHITE" "$ip" >/dev/null 2>&1
        
        print_success "已从白名单移除 $ip"
        
        # 重新加载iptables规则
        setup_iptables
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
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ ]] || [[ -z "$line" ]] && continue
            echo "  $line"
        done < "$WHITELIST_FILE"
    else
        print_warning "白名单为空"
    fi
}

# 规则库管理
list_available_rules() {
    print_info "可用规则库:"
    echo "  1. common_attacks    - 常见攻击端口 (SSH, Telnet, RDP等)"
    echo "  2. malware_ports     - 已知恶意软件端口"
    echo "  3. scan_detection    - 扫描检测端口"
    echo "  4. web_services      - Web服务端口"
    echo "  5. database_ports    - 数据库端口"
}

get_active_rules() {
    load_settings
    echo "$ACTIVE_RULES"
}

set_active_rules() {
    local rules="$1"
    sed -i "s/^ACTIVE_RULES=.*/ACTIVE_RULES=\"$rules\"/" "$SETTINGS_FILE"
    print_success "已激活规则库: $rules"
}

# 获取端口列表
get_ports_for_rule() {
    local rule="$1"
    case "$rule" in
        common_attacks)
            echo "22 23 135 139 445 1433 3389"
            ;;
        malware_ports)
            echo "135 4444 5554 8866 9996 12345 27374"
            ;;
        scan_detection)
            echo "1 7 9 11 15 21 25 111 135 139 445"
            ;;
        web_services)
            echo "80 443 8080 8888"
            ;;
        database_ports)
            echo "3306 5432 1433 1521 27017"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 设置iptables规则
setup_iptables() {
    local active_rules=$(get_active_rules)
    
    # 创建白名单规则（最高优先级）
    if ipset list "$IPSET_WHITE" >/dev/null 2>&1; then
        iptables -I INPUT -m set --match-set "$IPSET_WHITE" src -j ACCEPT
    fi
    
    # 为每个激活的规则创建iptables规则
    for rule in $active_rules; do
        local ports=$(get_ports_for_rule "$rule")
        if [ -n "$ports" ]; then
            for port in $ports; do
                iptables -I INPUT -p tcp --dport "$port" -j DROP
                iptables -I INPUT -p udp --dport "$port" -j DROP
            done
        fi
    done
    
    # 保存规则
    netfilter-persistent save >/dev/null 2>&1
}

# 清除所有规则
clear_all_rules() {
    print_info "清除所有防火墙规则..."
    
    # 清除iptables规则
    iptables -F INPUT 2>/dev/null
    
    # 销毁ipset
    ipset destroy "$IPSET_NAME" 2>/dev/null
    ipset destroy "$IPSET_WHITE" 2>/dev/null
    
    # 清除配置文件
    rm -f "$SETTINGS_FILE"
    rm -f "$WHITELIST_FILE"
    rm -f "$RULES_FILE"
    rm -f "$CRON_FILE"
    
    print_success "所有规则已清除"
}

# 主菜单
show_menu() {
    clear
    print_title
    
    echo ""
    echo "1) IP白名单管理"
    echo "2) 规则库管理"
    echo "3) 查看当前规则"
    echo "4) 清除所有规则"
    echo "5) 保存并退出"
    echo ""
}

# IP白名单管理菜单
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
        
        read -p "请选择操作 [1-3]: " choice
        
        case $choice in
            1)
                read -p "请输入IP地址或IP段: " ip
                if [ -n "$ip" ]; then
                    add_whitelist_ip "$ip"
                fi
                read -p "按回车键继续..."
                ;;
            2)
                read -p "请输入要移除的IP地址: " ip
                if [ -n "$ip" ]; then
                    remove_whitelist_ip "$ip"
                fi
                read -p "按回车键继续..."
                ;;
            3)
                return
                ;;
            *)
                print_error "无效选择"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 规则库管理菜单
rules_menu() {
    while true; do
        clear
        print_title
        echo ""
        print_info "规则库管理"
        echo ""
        list_available_rules
        echo ""
        print_info "当前激活的规则库: $(get_active_rules)"
        echo ""
        echo "1) 选择激活的规则库"
        echo "2) 返回主菜单"
        echo ""
        
        read -p "请选择操作 [1-2]: " choice
        
        case $choice in
            1)
                echo "请输入要激活的规则库名称（空格分隔，建议不超过2个）:"
                echo "例如: common_attacks malware_ports"
                read -p "> " rules
                if [ -n "$rules" ]; then
                    set_active_rules "$rules"
                    setup_iptables
                fi
                read -p "按回车键继续..."
                ;;
            2)
                return
                ;;
            *)
                print_error "无效选择"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 查看当前规则
show_current_rules() {
    clear
    print_title
    echo ""
    print_info "当前iptables规则:"
    echo ""
    iptables -L INPUT -n --line-numbers | head -20
    echo ""
    print_info "当前激活的规则库: $(get_active_rules)"
    echo ""
    show_whitelist
    read -p "按回车键继续..."
}

# 主程序
main() {
    check_root
    install_dependencies
    init_config
    load_settings
    create_whitelist_set
    load_whitelist
    
    while true; do
        show_menu
        read -p "请选择操作 [1-5]: " choice
        
        case $choice in
            1)
                whitelist_menu
                ;;
            2)
                rules_menu
                ;;
            3)
                show_current_rules
                ;;
            4)
                read -p "确定要清除所有规则吗? (y/N): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    clear_all_rules
                fi
                read -p "按回车键继续..."
                ;;
            5)
                print_success "配置已保存，退出程序"
                netfilter-persistent save >/dev/null 2>&1
                exit 0
                ;;
            *)
                print_error "无效选择"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 命令行模式
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "端口过滤脚本 v$VERSION"
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --help, -h     显示帮助信息"
    echo "  --whitelist    添加IP到白名单"
    echo "  --rules        设置激活的规则库"
    echo ""
    echo "示例:"
    echo "  $0 --whitelist 192.168.1.100"
    echo "  $0 --rules 'common_attacks malware_ports'"
    exit 0
fi

if [ "$1" = "--whitelist" ] && [ -n "$2" ]; then
    check_root
    install_dependencies
    init_config
    load_settings
    create_whitelist_set
    add_whitelist_ip "$2"
    setup_iptables
    exit 0
fi

if [ "$1" = "--rules" ] && [ -n "$2" ]; then
    check_root
    install_dependencies
    init_config
    load_settings
    set_active_rules "$2"
    setup_iptables
    exit 0
fi

# 运行主程序
main