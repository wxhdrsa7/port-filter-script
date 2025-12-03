#!/bin/bash
#
# port-filter-with-whitelist.sh - 支持IP白名单的端口过滤脚本
# 在原有过滤功能基础上，增加IP白名单功能，避免误拦截
#
# 新增功能：
# - 支持单个IP地址白名单
# - 支持IP段白名单（CIDR格式）
# - 白名单优先级高于黑名单
# - 动态白名单管理
# - 白名单持久化存储
#

VERSION="2.2.0"
CONFIG_DIR="/etc/port-filter"
RULES_FILE="$CONFIG_DIR/rules.conf"
SETTINGS_FILE="$CONFIG_DIR/settings.conf"
WHITELIST_FILE="$CONFIG_DIR/whitelist.conf"
BACKUP_DIR="$CONFIG_DIR/backups"
LOG_DIR="/var/log/port-filter"
LOG_FILE="$LOG_DIR/update.log"
ERROR_LOG="$LOG_DIR/error.log"
IPSET_NAME="china"
IPSET_NAME6="china6"
WHITELIST_IPSET="whitelist"
WHITELIST_IPSET6="whitelist6"
CRON_FILE="/etc/cron.d/port-filter"
LOCK_FILE="/var/run/port-filter.lock"

# 配置常量
MAX_PORT=65535
MIN_PORT=1
MAX_IPSET_SIZE=524288
DEFAULT_TIMEOUT=90
BACKUP_COUNT=5

# APT更新状态
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

# 脚本路径
SCRIPT_PATH="$(readlink -f "$0")"

# IP数据源
IP_SOURCES=(
    "metowolf/IPList|https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt"
    "17mon/ChinaIPList|https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt"
    "gaoyifan/OperatorIP|https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt"
    "misakaio/ChinaIP|https://raw.githubusercontent.com/misakaio/chnroutes2/master/chnroutes.txt"
)

# IPv6数据源
IP6_SOURCES=(
    "gaoyifan/ChinaIPv6|https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china6.txt"
)

# 常用打印函数
print_info() { 
    local msg="$1"
    printf "%b%s%b\n" "$CYAN" "$msg" "$NC" 
    log_message "INFO" "$msg"
}

print_success() { 
    local msg="$1"
    printf "%b%s%b\n" "$GREEN" "$msg" "$NC" 
    log_message "SUCCESS" "$msg"
}

print_warning() { 
    local msg="$1"
    printf "%b%s%b\n" "$YELLOW" "$msg" "$NC" 
    log_message "WARNING" "$msg"
}

print_error() { 
    local msg="$1"
    printf "%b%s%b\n" "$RED" "$msg" "$NC" 
    log_message "ERROR" "$msg"
}

print_title() {
    printf "${BOLD}${MAGENTA}╔════════════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAGENTA}║      端口访问控制脚本 v%s%-28s║${NC}\n" "$VERSION" ""
    printf "${BOLD}${MAGENTA}╚════════════════════════════════════════════════╝${NC}\n"
}

# 日志记录函数
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    mkdir -p "$LOG_DIR"
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    if [ "$level" = "ERROR" ]; then
        echo "[$timestamp] [$level] $message" >> "$ERROR_LOG"
    fi
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "错误：请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 检查系统兼容性
check_system() {
    local supported_distros=("ubuntu" "debian" "centos" "redhat" "fedora")
    local distro=""
    
    if [ -f /etc/os-release ]; then
        distro=$(. /etc/os-release && echo "$ID" | tr '[:upper:]' '[:lower:]')
    elif [ -f /etc/redhat-release ]; then
        distro="redhat"
    elif [ -f /etc/centos-release ]; then
        distro="centos"
    fi
    
    local supported=false
    for d in "${supported_distros[@]}"; do
        if [[ "$distro" == *"$d"* ]]; then
            supported=true
            break
        fi
    done
    
    if [ "$supported" = false ]; then
        print_warning "警告：未检测到支持的Linux发行版，可能无法正常工作"
        print_warning "支持的发行版：Ubuntu, Debian, CentOS, RedHat, Fedora"
        read -rp "是否继续？(y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# 文件锁定（防止并发执行）
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if ps -p "$lock_pid" >/dev/null 2>&1; then
            print_error "另一个实例正在运行 (PID: $lock_pid)"
            exit 1
        else
            print_warning "发现过期的锁文件，正在清理..."
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
}

# 释放锁
release_lock() {
    rm -f "$LOCK_FILE"
}

# 清理函数（退出时执行）
cleanup() {
    release_lock
}

# 设置陷阱以确保清理
trap cleanup EXIT

# 依赖安装
install_dependencies() {
    print_info "[1/3] 检查并安装依赖..."
    
    # 检查网络连接
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        print_error "网络连接失败，无法安装依赖"
        return 1
    fi
    
    # 更新包列表（仅一次）
    apt_update_once() {
        if [ $APT_UPDATED -eq 0 ]; then
            if apt-get update -qq; then
                APT_UPDATED=1
            else
                print_error "包列表更新失败"
                return 1
            fi
        fi
    }
    
    # 检查并安装必要的包
    local packages=("ipset" "iptables" "iptables-persistent" "curl" "cron")
    local failed_packages=()
    
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            print_info "正在安装 $pkg..."
            if ! apt_update_once; then
                failed_packages+=("$pkg")
                continue
            fi
            if ! apt-get install -y "$pkg" >/dev/null 2>&1; then
                failed_packages+=("$pkg")
            fi
        fi
    done
    
    # 检查关键组件
    if ! command -v ipset >/dev/null 2>&1; then
        failed_packages+=("ipset")
    fi
    
    if ! command -v iptables >/dev/null 2>&1; then
        failed_packages+=("iptables")
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        failed_packages+=("curl")
    fi
    
    if [ ${#failed_packages[@]} -gt 0 ]; then
        print_error "以下包安装失败: ${failed_packages[*]}"
        return 1
    fi
    
    # 创建必要的目录
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$LOG_DIR"
    
    # 设置权限
    chmod 700 "$CONFIG_DIR"
    chmod 700 "$LOG_DIR"
    
    print_success "✓ 依赖检查完成"
}

# IP地址验证函数
validate_ip() {
    local ip="$1"
    
    # IPv4地址验证
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
        return 0
    fi
    
    # IPv6地址验证
    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}(/[0-9]+)?$ ]] || 
       [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,6}:[0-9a-fA-F]{0,4}(/[0-9]+)?$ ]]; then
        return 0
    fi
    
    return 1
}

# 端口验证函数
validate_port() {
    local port="$1"
    
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        print_error "端口号必须是数字"
        return 1
    fi
    
    if [ "$port" -lt "$MIN_PORT" ] || [ "$port" -gt "$MAX_PORT" ]; then
        print_error "端口号必须在 $MIN_PORT-$MAX_PORT 之间"
        return 1
    fi
    
    # 检查保留端口
    if [ "$port" -lt 1024 ] && [ "$port" -ne 22 ] && [ "$port" -ne 80 ] && [ "$port" -ne 443 ]; then
        print_warning "警告：$port 是系统保留端口，修改规则可能影响系统服务"
    fi
    
    return 0
}

# 协议验证函数
validate_protocol() {
    local protocol="$1"
    
    case "$protocol" in
        "tcp"|"udp"|"both") return 0 ;;
        *) 
            print_error "无效的协议: $protocol"
            return 1
            ;;
    esac
}

# 模式验证函数
validate_mode() {
    local mode="$1"
    
    case "$mode" in
        "blacklist"|"whitelist"|"block"|"allow") return 0 ;;
        *) 
            print_error "无效的模式: $mode"
            return 1
            ;;
    esac
}

# 配置文件工具
get_setting() {
    local key="$1"
    [ -f "$SETTINGS_FILE" ] || return 1
    grep -E "^${key}=" "$SETTINGS_FILE" | tail -n1 | cut -d'=' -f2-
}

set_setting() {
    local key="$1"
    local value="$2"
    
    if [ -z "$key" ]; then
        print_error "设置键不能为空"
        return 1
    fi
    
    mkdir -p "$CONFIG_DIR"
    touch "$SETTINGS_FILE"
    chmod 600 "$SETTINGS_FILE"
    
    if grep -qE "^${key}=" "$SETTINGS_FILE"; then
        sed -i "s/^${key}=.*/${key}=${value}/" "$SETTINGS_FILE"
    else
        echo "${key}=${value}" >> "$SETTINGS_FILE"
    fi
}

delete_setting() {
    local key="$1"
    [ -f "$SETTINGS_FILE" ] || return
    sed -i "/^${key}=.*/d" "$SETTINGS_FILE"
}

# IPSet工具
ensure_ipset_exists() {
    local set_name="$1"
    
    if ! ipset list "$set_name" >/dev/null 2>&1; then
        if [ "$set_name" = "$IPSET_NAME6" ] || [ "$set_name" = "$WHITELIST_IPSET6" ]; then
            ipset create "$set_name" hash:net family inet6 hashsize 4096 maxelem $MAX_IPSET_SIZE
        else
            ipset create "$set_name" hash:net family inet hashsize 4096 maxelem $MAX_IPSET_SIZE
        fi
    fi
}

refresh_ipset() {
    local set_name="$1"
    ensure_ipset_exists "$set_name"
    ipset flush "$set_name"
}

# 白名单管理
add_whitelist_ip() {
    local ip="$1"
    local comment="$2"
    
    if ! validate_ip "$ip"; then
        print_error "无效的IP地址格式: $ip"
        return 1
    fi
    
    # 添加到IPv4白名单
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        ensure_ipset_exists "$WHITELIST_IPSET"
        if ipset add "$WHITELIST_IPSET" "$ip" 2>/dev/null; then
            print_success "✓ 已添加IPv4白名单: $ip"
        else
            print_warning "⚠ IPv4白名单已存在: $ip"
        fi
    fi
    
    # 添加到IPv6白名单
    if [[ "$ip" =~ ^[0-9a-fA-F:]+ ]]; then
        ensure_ipset_exists "$WHITELIST_IPSET6"
        if ipset add "$WHITELIST_IPSET6" "$ip" 2>/dev/null; then
            print_success "✓ 已添加IPv6白名单: $ip"
        else
            print_warning "⚠ IPv6白名单已存在: $ip"
        fi
    fi
    
    # 保存到配置文件
    if ! grep -q "^${ip}|" "$WHITELIST_FILE" 2>/dev/null; then
        echo "${ip}|${comment:-手动添加}" >> "$WHITELIST_FILE"
        chmod 600 "$WHITELIST_FILE"
    fi
    
    return 0
}

remove_whitelist_ip() {
    local ip="$1"
    
    # 从IPv4白名单移除
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        if ipset del "$WHITELIST_IPSET" "$ip" 2>/dev/null; then
            print_success "✓ 已移除IPv4白名单: $ip"
        else
            print_warning "⚠ IPv4白名单不存在: $ip"
        fi
    fi
    
    # 从IPv6白名单移除
    if [[ "$ip" =~ ^[0-9a-fA-F:]+ ]]; then
        if ipset del "$WHITELIST_IPSET6" "$ip" 2>/dev/null; then
            print_success "✓ 已移除IPv6白名单: $ip"
        else
            print_warning "⚠ IPv6白名单不存在: $ip"
        fi
    fi
    
    # 从配置文件移除
    sed -i "/^${ip}|/d" "$WHITELIST_FILE" 2>/dev/null
    
    return 0
}

show_whitelist() {
    print_info "==================== IP白名单列表 ===================="
    
    if [ ! -f "$WHITELIST_FILE" ] || [ ! -s "$WHITELIST_FILE" ]; then
        print_warning "暂无IP白名单"
        return
    fi
    
    printf "%-40s%-20s%s\n" "$BOLD" "IP地址/段" "类型" "备注" "$NC"
    
    while IFS='|' read -r ip comment; do
        local ip_type=""
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
            ip_type="IPv4"
        elif [[ "$ip" =~ ^[0-9a-fA-F:]+ ]]; then
            ip_type="IPv6"
        fi
        
        if [[ "$ip" =~ / ]]; then
            ip_type="${ip_type}-段"
        fi
        
        printf "%-40s%-20s%s\n" "$ip" "$ip_type" "$comment"
    done < "$WHITELIST_FILE"
    
    print_info "========================================================="
}

load_whitelist_from_file() {
    if [ ! -f "$WHITELIST_FILE" ]; then
        return 0
    fi
    
    print_info "正在加载IP白名单..."
    
    local count=0
    while IFS='|' read -r ip comment; do
        [ -z "$ip" ] && continue
        
        if validate_ip "$ip"; then
            if add_whitelist_ip "$ip" "$comment" >/dev/null 2>&1; then
                count=$((count + 1))
            fi
        else
            print_warning "无效的IP地址格式: $ip"
        fi
    done < "$WHITELIST_FILE"
    
    print_success "✓ 已加载 $count 个IP白名单"
}

# 备份函数
create_backup() {
    local backup_file="$BACKUP_DIR/rules_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    mkdir -p "$BACKUP_DIR"
    
    # 备份配置文件
    tar -czf "$backup_file" -C "$CONFIG_DIR" . 2>/dev/null
    
    # 备份iptables规则
    iptables-save > "$BACKUP_DIR/iptables_backup_$(date +%Y%m%d_%H%M%S).rules"
    
    # 清理旧备份
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete
    find "$BACKUP_DIR" -name "*.rules" -mtime +7 -delete
    
    print_success "✓ 备份已创建: $backup_file"
}

# 下载IP列表（增强版）
download_ip_list() {
    local sources_var="$1"
    local set_name="$2"
    local list_type="$3"
    
    print_info "[2/3] 下载并更新${list_type} IP列表..."
    
    refresh_ipset "$set_name"
    
    local total=0
    local success=0
    local failed_sources=()
    
    eval "local sources=(\${$sources_var[@]})"
    
    for source in "${sources[@]}"; do
        local name=${source%%|*}
        local url=${source#*|}
        local temp_file=$(mktemp)
        
        printf "  %s%-40s%s" "$BLUE" "→ 获取 ${name}" "$NC"
        
        if curl -fsSL --max-time "$DEFAULT_TIMEOUT" --retry 3 --retry-delay 5 "$url" -o "$temp_file"; then
            local count=0
            local valid_ips=0
            
            while IFS= read -r ip; do
                ip=${ip%%#*}
                ip=${ip// /}
                [ -z "$ip" ] && continue
                
                # 验证IP地址格式
                if [ "$set_name" = "$IPSET_NAME6" ] || [ "$set_name" = "$WHITELIST_IPSET6" ]; then
                    # IPv6验证
                    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}(/[0-9]+)?$ ]] || 
                       [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,6}:[0-9a-fA-F]{0,4}(/[0-9]+)?$ ]]; then
                        if ipset add "$set_name" "$ip" 2>/dev/null; then
                            count=$((count + 1))
                        fi
                    fi
                else
                    # IPv4验证
                    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
                        if ipset add "$set_name" "$ip" 2>/dev/null; then
                            count=$((count + 1))
                        fi
                    fi
                fi
                valid_ips=$((valid_ips + 1))
            done < "$temp_file"
            
            rm -f "$temp_file"
            success=$((success + 1))
            total=$((total + count))
            
            printf "\r  %s%-40s%s\n" "$GREEN" "✓ 已导入 ${count}/${valid_ips} 条" "$NC"
        else
            rm -f "$temp_file"
            failed_sources+=("$name")
            printf "\r  %s%-40s%s\n" "$YELLOW" "⚠ 源不可用" "$NC"
        fi
    done
    
    if [ "$success" -eq 0 ]; then
        print_error "✗ 所有${list_type} IP源均下载失败，请检查网络"
        return 1
    fi
    
    print_success "✓ 成功导入${total}条${list_type} IP规则"
    
    if [ ${#failed_sources[@]} -gt 0 ]; then
        print_warning "以下源下载失败: ${failed_sources[*]}"
    fi
    
    return 0
}

# 下载中国IP列表
download_china_ip() {
    local result=0
    
    # 下载IPv4列表
    if ! download_ip_list "IP_SOURCES" "$IPSET_NAME" "中国IPv4"; then
        result=1
    fi
    
    # 下载IPv6列表（如果系统支持）
    if [ -f /proc/net/if_inet6 ]; then
        print_info "检测到IPv6支持，正在下载IPv6列表..."
        if ! download_ip_list "IP6_SOURCES" "$IPSET_NAME6" "中国IPv6"; then
            print_warning "IPv6列表下载失败，将继续使用IPv4规则"
        fi
    fi
    
    return $result
}

# 保存规则配置
save_rule_config() {
    local port="$1"
    local protocol="$2"
    local mode="$3"
    local action="$4"
    
    if ! validate_port "$port" || ! validate_protocol "$protocol" || ! validate_mode "$mode"; then
        return 1
    fi
    
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"
    
    # 检查是否已存在相同规则
    if grep -q "^${port}|${protocol}|${mode}|${action}$" "$RULES_FILE" 2>/dev/null; then
        print_info "规则已存在，跳过保存"
        return 0
    fi
    
    echo "${port}|${protocol}|${mode}|${action}" >> "$RULES_FILE"
    chmod 600 "$RULES_FILE"
    
    return 0
}

# 清除端口规则（增强版）
clear_port_rules() {
    local port="$1"
    
    if ! validate_port "$port"; then
        return 1
    fi
    
    # 定义所有可能的规则组合
    local protocols=("tcp" "udp")
    local sets=("$IPSET_NAME" "$IPSET_NAME6" "$WHITELIST_IPSET" "$WHITELIST_IPSET6")
    local actions=("DROP" "ACCEPT")
    
    for proto in "${protocols[@]}"; do
        for set in "${sets[@]}"; do
            for action in "${actions[@]}"; do
                # 清除带ipset的规则
                iptables -D INPUT -p "$proto" --dport "$port" -m set --match-set "$set" src -j "$action" 2>/dev/null
                # 清除IPv6规则
                ip6tables -D INPUT -p "$proto" --dport "$port" -m set --match-set "$set" src -j "$action" 2>/dev/null
            done
            # 清除基本规则
            iptables -D INPUT -p "$proto" --dport "$port" -j DROP 2>/dev/null
            iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null
            ip6tables -D INPUT -p "$proto" --dport "$port" -j DROP 2>/dev/null
            ip6tables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null
        done
    done
}

# 应用规则（增强版 - 包含白名单处理）
apply_rule() {
    local port="$1"
    local protocol="$2"
    local mode="$3"
    
    if ! validate_port "$port" || ! validate_protocol "$protocol" || ! validate_mode "$mode"; then
        return 1
    fi
    
    clear_port_rules "$port"
    ensure_ipset_exists "$IPSET_NAME"
    ensure_ipset_exists "$WHITELIST_IPSET"
    
    # IPv6支持
    if [ -f /proc/net/if_inet6 ]; then
        ensure_ipset_exists "$IPSET_NAME6"
        ensure_ipset_exists "$WHITELIST_IPSET6"
    fi
    
    # 首先应用白名单规则（优先级最高）
    if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p tcp --dport "$port" -m set --match-set "$WHITELIST_IPSET" src -j ACCEPT
        if [ -f /proc/net/if_inet6 ]; then
            ip6tables -I INPUT -p tcp --dport "$port" -m set --match-set "$WHITELIST_IPSET6" src -j ACCEPT
        fi
    fi
    
    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p udp --dport "$port" -m set --match-set "$WHITELIST_IPSET" src -j ACCEPT
        if [ -f /proc/net/if_inet6 ]; then
            ip6tables -I INPUT -p udp --dport "$port" -m set --match-set "$WHITELIST_IPSET6" src -j ACCEPT
        fi
    fi
    
    # 然后应用地域过滤规则
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
    
    # 应用IPv6规则
    if [ -f /proc/net/if_inet6 ]; then
        if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
            if [ "$mode" = "blacklist" ]; then
                ip6tables -I INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_NAME6" src -j DROP
                print_success "✓ TCP端口 $port: 已设置IPv6黑名单（阻止中国IPv6）"
            elif [ "$mode" = "whitelist" ]; then
                ip6tables -I INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_NAME6" src -j ACCEPT
                ip6tables -I INPUT -p tcp --dport "$port" -j DROP
                print_success "✓ TCP端口 $port: 已设置IPv6白名单（仅允许中国IPv6）"
            fi
        fi
        
        if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
            if [ "$mode" = "blacklist" ]; then
                ip6tables -I INPUT -p udp --dport "$port" -m set --match-set "$IPSET_NAME6" src -j DROP
                print_success "✓ UDP端口 $port: 已设置IPv6黑名单（阻止中国IPv6）"
            elif [ "$mode" = "whitelist" ]; then
                ip6tables -I INPUT -p udp --dport "$port" -m set --match-set "$IPSET_NAME6" src -j ACCEPT
                ip6tables -I INPUT -p udp --dport "$port" -j DROP
                print_success "✓ UDP端口 $port: 已设置IPv6白名单（仅允许中国IPv6）"
            fi
        fi
    fi
}

# 屏蔽端口
block_port() {
    local port="$1"
    local protocol="$2"
    
    if ! validate_port "$port" || ! validate_protocol "$protocol"; then
        return 1
    fi
    
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
    local port="$1"
    local protocol="$2"
    
    if ! validate_port "$port" || ! validate_protocol "$protocol"; then
        return 1
    fi
    
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

# 查看当前规则（增强版）
show_rules() {
    print_info "==================== 当前防火墙规则 ====================="
    
    # 显示白名单统计
    print_info "IP白名单统计："
    if ipset list "$WHITELIST_IPSET" >/dev/null 2>&1; then
        local whitelist4_count=$(ipset list "$WHITELIST_IPSET" | grep -c "^[0-9]")
        print_success "  IPv4白名单: $whitelist4_count 个"
    fi
    
    if ipset list "$WHITELIST_IPSET6" >/dev/null 2>&1; then
        local whitelist6_count=$(ipset list "$WHITELIST_IPSET6" | grep -c "^[0-9a-fA-F:]")
        print_success "  IPv6白名单: $whitelist6_count 个"
    fi
    
    echo ""
    
    # IPv4规则
    print_warning "IPv4 TCP 规则："
    iptables -L INPUT -n -v --line-numbers | grep -E "(tcp dpt:|whitelist|china)" | head -20
    echo ""
    
    print_warning "IPv4 UDP 规则："
    iptables -L INPUT -n -v --line-numbers | grep -E "(udp dpt:|whitelist|china)" | head -20
    echo ""
    
    # IPv6规则
    if [ -f /proc/net/if_inet6 ]; then
        print_warning "IPv6 TCP 规则："
        ip6tables -L INPUT -n -v --line-numbers | grep -E "(tcp dpt:|whitelist|china)" | head -20
        echo ""
        
        print_warning "IPv6 UDP 规则："
        ip6tables -L INPUT -n -v --line-numbers | grep -E "(udp dpt:|whitelist|china)" | head -20
        echo ""
    fi
    
    # IPSet统计
    print_info "IPSet统计："
    if ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        local ipv4_count=$(ipset list "$IPSET_NAME" | grep -c "^[0-9]")
        print_success "  IPv4中国IP: $ipv4_count 条"
    fi
    
    if ipset list "$IPSET_NAME6" >/dev/null 2>&1; then
        local ipv6_count=$(ipset list "$IPSET_NAME6" | grep -c "^[0-9a-fA-F:]")
        print_success "  IPv6中国IP: $ipv6_count 条"
    fi
    
    print_info "========================================================="
}

# 查看保存的端口策略
show_saved_configs() {
    if [ ! -f "$RULES_FILE" ]; then
        print_warning "暂无保存的端口策略"
        return
    fi
    
    print_info "==================== 已保存的端口策略 ===================="
    printf "%-8s%-12s%-12s%-12s%s\n" "$BOLD" "端口" "协议" "模式" "类型" "$NC"
    
    local rule_count=0
    while IFS='|' read -r port protocol mode action; do
        if validate_port "$port" && validate_protocol "$protocol" && validate_mode "$mode"; then
            printf "%-8s%-12s%-12s%-12s\n" "$port" "$protocol" "$mode" "$action"
            rule_count=$((rule_count + 1))
        else
            print_warning "无效规则: $port|$protocol|$mode|$action"
        fi
    done < "$RULES_FILE"
    
    print_info "========================================================="
    print_info "总计: $rule_count 条规则"
}

# 保存防火墙规则（增强版）
save_rules() {
    print_info "[3/3] 保存防火墙规则..."
    
    # 创建备份
    create_backup
    
    # 保存IPv4规则
    if command -v netfilter-persistent >/dev/null 2>&1; then
        if ! netfilter-persistent save >/dev/null 2>&1; then
            print_error "规则保存失败"
            return 1
        fi
    elif command -v iptables-save >/dev/null 2>&1; then
        iptables-save > /etc/iptables/rules.v4
        if [ -f /proc/net/if_inet6 ]; then
            ip6tables-save > /etc/iptables/rules.v6
        fi
    else
        print_error "未找到可用的规则保存工具"
        return 1
    fi
    
    print_success "✓ 规则已保存"
    return 0
}

# 清除所有规则（增强版）
clear_all_rules() {
    print_warning "正在清除所有规则..."
    
    # 备份当前规则
    create_backup
    
    # 清除IPv4规则
    iptables -S INPUT | grep -E "$IPSET_NAME|$IPSET_NAME6|$WHITELIST_IPSET|$WHITELIST_IPSET6" | cut -d" " -f2- | while read -r rule; do
        iptables -D INPUT $rule 2>/dev/null
    done
    
    iptables -S INPUT | grep "dpt:" | cut -d" " -f2- | while read -r rule; do
        iptables -D INPUT $rule 2>/dev/null
    done
    
    # 清除IPv6规则
    if [ -f /proc/net/if_inet6 ]; then
        ip6tables -S INPUT | grep -E "$IPSET_NAME|$IPSET_NAME6|$WHITELIST_IPSET|$WHITELIST_IPSET6" | cut -d" " -f2- | while read -r rule; do
            ip6tables -D INPUT $rule 2>/dev/null
        done
        
        ip6tables -S INPUT | grep "dpt:" | cut -d" " -f2- | while read -r rule; do
            ip6tables -D INPUT $rule 2>/dev/null
        done
    fi
    
    # 销毁IPSet
    ipset destroy "$IPSET_NAME" 2>/dev/null
    ipset destroy "$IPSET_NAME6" 2>/dev/null
    ipset destroy "$WHITELIST_IPSET" 2>/dev/null
    ipset destroy "$WHITELIST_IPSET6" 2>/dev/null
    
    # 删除配置文件
    rm -f "$RULES_FILE"
    rm -f "$SETTINGS_FILE"
    rm -f "$WHITELIST_FILE"
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

# 配置自动更新（增强版）
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
        delete_setting "AUTO_UPDATE_ENABLED"
        print_warning "已关闭自动更新"
        reload_cron_service
        return
    fi
    
    if [[ ! $schedule =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
        print_error "时间格式错误，请使用 24 小时制 HH:MM"
        return 1
    fi
    
    local hour=${schedule%:*}
    local minute=${schedule#*:}
    
    # 创建cron文件
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
    set_setting "AUTO_UPDATE_ENABLED" "true"
    
    reload_cron_service
    print_success "✓ 已设置每天 ${schedule} 自动更新中国IP列表"
}

# 显示系统状态
show_system_status() {
    print_info "==================== 系统状态 ===================="
    
    # 系统信息
    printf "%-20s: %s\n" "操作系统" "$(. /etc/os-release && echo "$PRETTY_NAME")"
    printf "%-20s: %s\n" "内核版本" "$(uname -r)"
    printf "%-20s: %s\n" "脚本版本" "$VERSION"
    printf "%-20s: %s\n" "运行时间" "$(uptime -p)"
    
    # 网络状态
    echo ""
    print_info "网络接口:"
    ip -4 addr show | grep -E "inet.*eth|inet.*ens|inet.*enp" | awk '{print "  " $2 " -> " $NF}' | head -5
    
    # 防火墙状态
    echo ""
    print_info "防火墙状态:"
    if systemctl is-active --quiet firewalld; then
        print_success "  firewalld: 运行中"
    elif systemctl is-active --quiet ufw; then
        print_success "  ufw: 运行中"
    else
        print_warning "  防火墙: 未运行"
    fi
    
    # 内存使用
    echo ""
    print_info "内存使用:"
    free -h | grep -E "^Mem|^Swap" | awk '{print "  " $1 ": " $3 "/" $2}'
    
    # 磁盘使用
    echo ""
    print_info "磁盘使用:"
    df -h / | tail -1 | awk '{print "  /: " $3 "/" $2 " (" $5 ")"}'
    
    print_info "========================================================="
}

# 白名单管理菜单
whitelist_menu() {
    while true; do
        clear
        print_title
        print_info "==================== IP白名单管理 ===================="
        
        printf "${GREEN}1.${NC}  添加IP白名单\n"
        printf "${GREEN}2.${NC}  移除IP白名单\n"
        printf "${GREEN}3.${NC}  查看IP白名单\n"
        printf "${GREEN}4.${NC}  清空IP白名单\n"
        printf "${GREEN}5.${NC}  从文件导入白名单\n"
        printf "${GREEN}0.${NC}  返回主菜单\n\n"
        printf "${YELLOW}请选择操作 [0-5]: ${NC}"
        
        read -r choice
        
        case "$choice" in
            1)
                read -rp "请输入IP地址或IP段 (支持192.168.1.1或192.168.1.0/24格式): " ip
                read -rp "请输入备注信息 (可选): " comment
                if validate_ip "$ip"; then
                    add_whitelist_ip "$ip" "$comment"
                    save_rules
                else
                    print_error "无效的IP地址格式"
                fi
                read -rp "按回车继续..." _
                ;;
            2)
                read -rp "请输入要移除的IP地址或IP段: " ip
                if validate_ip "$ip"; then
                    remove_whitelist_ip "$ip"
                    save_rules
                else
                    print_error "无效的IP地址格式"
                fi
                read -rp "按回车继续..." _
                ;;
            3)
                show_whitelist
                read -rp "按回车继续..." _
                ;;
            4)
                read -rp "确认清空所有IP白名单？(y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    ipset flush "$WHITELIST_IPSET" 2>/dev/null
                    ipset flush "$WHITELIST_IPSET6" 2>/dev/null
                    rm -f "$WHITELIST_FILE"
                    print_success "✓ IP白名单已清空"
                    save_rules
                fi
                read -rp "按回车继续..." _
                ;;
            5)
                read -rp "请输入包含IP列表的文件路径 (每行一个IP): " file_path
                if [ -f "$file_path" ]; then
                    print_info "正在从文件导入IP白名单..."
                    local count=0
                    while IFS= read -r line; do
                        ip=$(echo "$line" | awk '{print $1}')
                        comment=$(echo "$line" | cut -d' ' -f2-)
                        if validate_ip "$ip"; then
                            add_whitelist_ip "$ip" "$comment"
                            count=$((count + 1))
                        fi
                    done < "$file_path"
                    print_success "✓ 已从文件导入 $count 个IP白名单"
                    save_rules
                else
                    print_error "文件不存在: $file_path"
                fi
                read -rp "按回车继续..." _
                ;;
            0)
                return
                ;;
            *)
                print_error "无效选择，请重试"
                sleep 1
                ;;
        esac
    done
}

# 主菜单（增强版）
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
    printf "${GREEN}1.${NC}  IP地域过滤（黑名单/白名单）\n"
    printf "${GREEN}2.${NC}  屏蔽端口（完全阻止访问）\n"
    printf "${GREEN}3.${NC}  放行端口（完全允许访问）\n"
    printf "${GREEN}4.${NC}  查看当前iptables规则\n"
    printf "${GREEN}5.${NC}  清除所有规则\n"
    printf "${GREEN}6.${NC}  更新中国IP列表\n"
    printf "${GREEN}7.${NC}  配置自动更新计划\n"
    printf "${GREEN}8.${NC}  查看已保存的端口策略\n"
    printf "${GREEN}9.${NC}  系统状态检查\n"
    printf "${GREEN}10.${NC} IP白名单管理\n"
    printf "${GREEN}11.${NC} 备份和恢复\n"
    printf "${GREEN}0.${NC}  退出\n\n"
    printf "${YELLOW}请选择操作 [0-11]: ${NC}"
}

# IP 地域过滤设置（增强版）
setup_geo_filter() {
    print_info "==================== IP地域过滤设置 ===================="
    
    # 检查IPSet是否存在，如果不存在则下载
    if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        if ! download_china_ip; then
            print_error "IP列表下载失败，无法继续"
            return 1
        fi
    fi
    
    # 加载白名单
    load_whitelist_from_file
    
    # 获取端口号
    local port
    read -rp "请输入端口号: " port
    
    if ! validate_port "$port"; then
        return 1
    fi
    
    # 选择协议
    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -rp "请选择 [1-3]: " proto_choice
    
    local protocol
    case "$proto_choice" in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) 
            print_error "无效选择"
            return 1
            ;;
    esac
    
    # 选择模式
    echo "选择模式："
    echo "1. 黑名单（阻止中国IP，允许其他地区）"
    echo "2. 白名单（仅允许中国IP，阻止其他地区）"
    read -rp "请选择 [1-2]: " mode_choice
    
    local mode
    case "$mode_choice" in
        1) mode="blacklist" ;;
        2) mode="whitelist" ;;
        *) 
            print_error "无效选择"
            return 1
            ;;
    esac
    
    # 确认操作
    echo ""
    print_info "配置摘要:"
    printf "  端口: %s\n" "$port"
    printf "  协议: %s\n" "$protocol"
    printf "  模式: %s\n" "$mode"
    echo ""
    
    read -rp "确认应用此规则？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "操作已取消"
        return 0
    fi
    
    # 应用规则
    if apply_rule "$port" "$protocol" "$mode"; then
        save_rule_config "$port" "$protocol" "$mode" "geo_filter"
        save_rules
        print_success "规则应用成功"
    else
        print_error "规则应用失败"
        return 1
    fi
}

# 屏蔽端口设置
setup_block_port() {
    print_info "==================== 屏蔽端口 =========================="
    
    local port
    read -rp "请输入要屏蔽的端口号: " port
    
    if ! validate_port "$port"; then
        return 1
    fi
    
    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -rp "请选择 [1-3]: " proto_choice
    
    local protocol
    case "$proto_choice" in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) 
            print_error "无效选择"
            return 1
            ;;
    esac
    
    # 确认操作
    echo ""
    print_warning "即将完全屏蔽端口 $port ($protocol)"
    read -rp "确认继续？(y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if block_port "$port" "$protocol"; then
            save_rule_config "$port" "$protocol" "block" "block"
            save_rules
            print_success "端口屏蔽成功"
        else
            print_error "端口屏蔽失败"
            return 1
        fi
    else
        print_warning "操作已取消"
    fi
}

# 放行端口设置
setup_allow_port() {
    print_info "==================== 放行端口 =========================="
    
    local port
    read -rp "请输入要放行的端口号: " port
    
    if ! validate_port "$port"; then
        return 1
    fi
    
    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -rp "请选择 [1-3]: " proto_choice
    
    local protocol
    case "$proto_choice" in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) 
            print_error "无效选择"
            return 1
            ;;
    esac
    
    # 确认操作
    echo ""
    print_warning "即将完全放行端口 $port ($protocol)"
    read -rp "确认继续？(y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if allow_port "$port" "$protocol"; then
            save_rule_config "$port" "$protocol" "allow" "allow"
            save_rules
            print_success "端口放行成功"
        else
            print_error "端口放行失败"
            return 1
        fi
    else
        print_warning "操作已取消"
    fi
}

# 备份和恢复菜单
backup_restore_menu() {
    while true; do
        clear
        print_title
        print_info "==================== 备份和恢复 ===================="
        
        printf "${GREEN}1.${NC}  创建备份\n"
        printf "${GREEN}2.${NC}  查看备份列表\n"
        printf "${GREEN}3.${NC}  恢复备份\n"
        printf "${GREEN}4.${NC}  删除旧备份\n"
        printf "${GREEN}0.${NC}  返回主菜单\n\n"
        printf "${YELLOW}请选择操作 [0-4]: ${NC}"
        
        read -r choice
        
        case "$choice" in
            1)
                create_backup
                read -rp "按回车继续..." _
                ;;
            2)
                if [ -d "$BACKUP_DIR" ]; then
                    print_info "可用备份:"
                    ls -la "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -10
                else
                    print_warning "暂无备份"
                fi
                read -rp "按回车继续..." _
                ;;
            3)
                print_warning "恢复功能需要手动操作，请联系管理员"
                read -rp "按回车继续..." _
                ;;
            4)
                if [ -d "$BACKUP_DIR" ]; then
                    find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete
                    print_success "已删除30天前的备份"
                else
                    print_warning "备份目录不存在"
                fi
                read -rp "按回车继续..." _
                ;;
            0)
                return
                ;;
            *)
                print_error "无效选择，请重试"
                sleep 1
                ;;
        esac
    done
}

# 主程序
main() {
    # 检查root权限
    check_root
    
    # 获取文件锁
    acquire_lock
    
    # 检查系统兼容性
    check_system
    
    # 安装依赖
    if ! install_dependencies; then
        print_error "依赖安装失败，脚本退出"
        exit 1
    fi
    
    # 主循环
    while true; do
        show_menu
        read -r choice
        
        case "$choice" in
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
                if download_china_ip && save_rules; then
                    print_success "IP列表更新完成"
                else
                    print_error "IP列表更新失败"
                fi
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
            9)
                show_system_status
                read -rp "按回车继续..." _
                ;;
            10)
                whitelist_menu
                ;;
            11)
                backup_restore_menu
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

# 参数帮助
print_usage() {
    cat <<'USAGE'
用法：port-filter-with-whitelist [选项]

选项：
  --update-ip    仅更新中国IP列表并保存规则
  --status       显示系统状态
  --backup       创建配置备份
  --version,-v   查看脚本版本
  --help,-h      显示本帮助信息

IP白名单功能：
  支持单个IP地址和IP段白名单
  白名单优先级高于地域过滤规则
  支持IPv4和IPv6地址

示例：
  # 添加IP白名单
  在IP白名单管理菜单中选择"添加IP白名单"
  输入: 192.168.1.100
  备注: 内网服务器

  # 添加IP段白名单
  在IP白名单管理菜单中选择"添加IP白名单"  
  输入: 192.168.1.0/24
  备注: 内网网段

注意事项：
  - 白名单IP将绕过所有地域过滤规则
  - 支持同时添加IPv4和IPv6地址
  - 白名单配置会自动保存
  - 重启后白名单仍然有效
USAGE
}

# 处理命令行参数
case "$1" in
    "--update-ip")
        check_root
        acquire_lock
        install_dependencies
        if download_china_ip && save_rules; then
            print_success "IP列表更新完成"
            exit 0
        else
            print_error "IP列表更新失败"
            exit 1
        fi
        ;;
    "--status")
        check_root
        acquire_lock
        install_dependencies
        show_system_status
        show_rules
        exit 0
        ;;
    "--backup")
        check_root
        acquire_lock
        create_backup
        exit 0
        ;;
    "--version"|"-v")
        echo "$VERSION"
        exit 0
        ;;
    "--help"|"-h")
        print_usage
        exit 0
        ;;
    "")
        # 无参数，运行主程序
        main
        ;;
    *)
        print_error "未知选项: $1"
        print_usage
        exit 1
        ;;
esac