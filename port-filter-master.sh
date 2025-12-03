#!/bin/bash
# =============================================================================
# Linux Port Filter Master Script
# =============================================================================
# 功能：端口过滤 + IP白名单（最高优先级） + 数据源管理 + 系统监控
# 作者：系统管理员
# 版本：3.0
# 更新：2025-12-03
# =============================================================================

set -euo pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[0;37m'
readonly NC='\033[0m' # No Color

# 脚本信息
readonly SCRIPT_NAME="port-filter-master.sh"
readonly SCRIPT_VERSION="3.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOCK_FILE="/var/run/port-filter.lock"

# 配置目录和文件
readonly CONFIG_DIR="/etc/port-filter"
readonly LOG_DIR="/var/log/port-filter"
readonly BACKUP_DIR="/var/backups/port-filter"
readonly DATA_DIR="/var/lib/port-filter"
readonly CONFIG_FILE="${CONFIG_DIR}/config.conf"
readonly WHITELIST_FILE="${CONFIG_DIR}/whitelist.conf"
readonly DATASOURCE_FILE="${CONFIG_DIR}/datasources.conf"

# IPSet名称（确保唯一性）
readonly IPSET_WHITELIST="whitelist_ips"
readonly IPSET_BLOCKED="blocked_ips"
readonly IPSET_BLOCKED6="blocked_ips6"

# 默认配置
readonly DEFAULT_CONFIG="# Port Filter Configuration
# 启用IPv6支持
IPV6_ENABLED=true

# 自动更新间隔（小时）
AUTO_UPDATE_INTERVAL=24

# 日志级别：DEBUG, INFO, WARN, ERROR
LOG_LEVEL=INFO

# 备份保留天数
BACKUP_RETENTION_DAYS=30

# 最大规则数限制
MAX_RULES=50000

# 数据源超时时间（秒）
DATASOURCE_TIMEOUT=30
"

# 默认数据源配置
readonly DEFAULT_DATASOURCES="# IP Data Sources Configuration
# 格式：name|url|enabled|description
china|https://iplist.cc/code/cn|true|中国IP段
usa|https://iplist.cc/code/us|false|美国IP段
russia|https://iplist.cc/code/ru|false|俄罗斯IP段
iran|https://iplist.cc/code/ir|false|伊朗IP段
northkorea|https://iplist.cc/code/kp|false|朝鲜IP段
"

# =============================================================================
# 日志系统
# =============================================================================
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 确保日志目录存在
    mkdir -p "$LOG_DIR"
    
    # 写入日志文件
    echo "[$timestamp] [$level] $message" >> "${LOG_DIR}/port-filter.log"
    
    # 根据级别输出到控制台
    case "$level" in
        "ERROR")
            echo -e "${RED}[$timestamp] [错误] $message${NC}" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] [警告] $message${NC}"
            ;;
        "INFO")
            echo -e "${GREEN}[$timestamp] [信息] $message${NC}"
            ;;
        "DEBUG")
            echo -e "${CYAN}[$timestamp] [调试] $message${NC}"
            ;;
        *)
            echo "[$timestamp] [$level] $message"
            ;;
    esac
}

# =============================================================================
# 工具函数
# =============================================================================

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "此脚本必须以root权限运行"
        exit 1
    fi
}

# 检查依赖
check_dependencies() {
    local deps=("iptables" "ipset" "curl" "wget" "jq" "awk" "grep" "sed")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "ERROR" "缺少依赖包: ${missing[*]}"
        log "INFO" "请安装: apt-get install iptables ipset curl wget jq awk grep sed"
        exit 1
    fi
}

# 文件锁定
acquire_lock() {
    if ! mkdir "$LOCK_FILE" 2>/dev/null; then
        log "ERROR" "另一个实例正在运行 (PID: $(cat "$LOCK_FILE/pid" 2>/dev/null || echo "unknown"))"
        exit 1
    fi
    echo $$ > "$LOCK_FILE/pid"
}

# 释放锁
release_lock() {
    rm -rf "$LOCK_FILE"
}

# 清理函数
cleanup() {
    release_lock
}

# =============================================================================
# 初始化系统
# =============================================================================
init_system() {
    log "INFO" "初始化端口过滤系统..."
    
    # 创建必要的目录
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$BACKUP_DIR" "$DATA_DIR"
    
    # 创建默认配置文件
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "$DEFAULT_CONFIG" > "$CONFIG_FILE"
        log "INFO" "创建默认配置文件: $CONFIG_FILE"
    fi
    
    # 创建默认数据源配置
    if [[ ! -f "$DATASOURCE_FILE" ]]; then
        echo "$DEFAULT_DATASOURCES" > "$DATASOURCE_FILE"
        log "INFO" "创建默认数据源配置: $DATASOURCE_FILE"
    fi
    
    # 创建白名单文件
    if [[ ! -f "$WHITELIST_FILE" ]]; then
        touch "$WHITELIST_FILE"
        log "INFO" "创建白名单文件: $WHITELIST_FILE"
    fi
    
    # 加载配置
    source "$CONFIG_FILE"
    
    log "INFO" "系统初始化完成"
}

# =============================================================================
# IP白名单管理（最高优先级）
# =============================================================================

# 验证IP地址格式
validate_ip() {
    local ip="$1"
    
    # IPv4地址验证
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if ((octet > 255)); then
                return 1
            fi
        done
        return 0
    fi
    
    # IPv6地址验证
    if [[ $ip =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]]; then
        return 0
    fi
    
    # CIDR格式验证
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        local prefix=${ip#*/}
        if ((prefix >= 0 && prefix <= 32)); then
            return 0
        fi
    fi
    
    return 1
}

# 初始化白名单IPSet
init_whitelist_ipset() {
    log "INFO" "初始化白名单IPSet..."
    
    # 创建IPv4白名单集合
    if ! ipset list "$IPSET_WHITELIST" &>/dev/null; then
        ipset create "$IPSET_WHITELIST" hash:net maxelem 65535
        log "INFO" "创建IPv4白名单集合: $IPSET_WHITELIST"
    fi
    
    # 创建IPv6白名单集合
    if [[ "$IPV6_ENABLED" == "true" ]]; then
        if ! ipset list "${IPSET_WHITELIST}6" &>/dev/null; then
            ipset create "${IPSET_WHITELIST}6" hash:net family inet6 maxelem 65535
            log "INFO" "创建IPv6白名单集合: ${IPSET_WHITELIST}6"
        fi
    fi
}

# 添加IP到白名单
add_to_whitelist() {
    local ip="$1"
    
    if ! validate_ip "$ip"; then
        log "ERROR" "无效的IP地址格式: $ip"
        return 1
    fi
    
    # 检查是否已存在
    if grep -q "^$ip$" "$WHITELIST_FILE" 2>/dev/null; then
        log "WARN" "IP已存在于白名单: $ip"
        return 0
    fi
    
    # 添加到文件
    echo "$ip" >> "$WHITELIST_FILE"
    
    # 添加到IPSet
    if [[ $ip =~ : ]]; then
        # IPv6
        if [[ "$IPV6_ENABLED" == "true" ]]; then
            ipset add "${IPSET_WHITELIST}6" "$ip" 2>/dev/null || true
        fi
    else
        # IPv4
        ipset add "$IPSET_WHITELIST" "$ip" 2>/dev/null || true
    fi
    
    log "INFO" "已添加到白名单: $ip"
    return 0
}

# 从白名单移除IP
remove_from_whitelist() {
    local ip="$1"
    
    # 从文件中移除
    sed -i "/^$ip$/d" "$WHITELIST_FILE" 2>/dev/null || true
    
    # 从IPSet中移除
    if [[ $ip =~ : ]]; then
        # IPv6
        ipset del "${IPSET_WHITELIST}6" "$ip" 2>/dev/null || true
    else
        # IPv4
        ipset del "$IPSET_WHITELIST" "$ip" 2>/dev/null || true
    fi
    
    log "INFO" "已从白名单移除: $ip"
}

# 加载白名单到IPSet
load_whitelist() {
    log "INFO" "加载白名单规则..."
    
    init_whitelist_ipset
    
    # 清空现有规则
    ipset flush "$IPSET_WHITELIST" 2>/dev/null || true
    ipset flush "${IPSET_WHITELIST}6" 2>/dev/null || true
    
    # 加载白名单文件
    if [[ -f "$WHITELIST_FILE" ]]; then
        local count=0
        while IFS= read -r ip; do
            [[ -z "$ip" || ${ip:0:1} == "#" ]] && continue
            
            if validate_ip "$ip"; then
                if [[ $ip =~ : ]]; then
                    # IPv6
                    if [[ "$IPV6_ENABLED" == "true" ]]; then
                        ipset add "${IPSET_WHITELIST}6" "$ip" 2>/dev/null || true
                        ((count++))
                    fi
                else
                    # IPv4
                    ipset add "$IPSET_WHITELIST" "$ip" 2>/dev/null || true
                    ((count++))
                fi
            fi
        done < "$WHITELIST_FILE"
        
        log "INFO" "已加载 $count 个白名单IP"
    fi
}

# 显示白名单
show_whitelist() {
    echo -e "${CYAN}=== IP白名单列表 ===${NC}"
    echo -e "${YELLOW}IPv4地址:${NC}"
    ipset list "$IPSET_WHITELIST" | grep -E "^[0-9]" || echo "无IPv4地址"
    
    if [[ "$IPV6_ENABLED" == "true" ]]; then
        echo -e "${YELLOW}IPv6地址:${NC}"
        ipset list "${IPSET_WHITELIST}6" | grep -E "^[0-9a-fA-F:]" || echo "无IPv6地址"
    fi
}

# =============================================================================
# 防火墙规则管理
# =============================================================================

# 创建白名单iptables规则（最高优先级）
create_whitelist_rules() {
    log "INFO" "创建白名单防火墙规则（最高优先级）..."
    
    # IPv4白名单规则 - 最高优先级
    iptables -I INPUT 1 -m set --match-set "$IPSET_WHITELIST" src -j ACCEPT -m comment --comment "Whitelist IPs - Highest Priority"
    iptables -I OUTPUT 1 -m set --match-set "$IPSET_WHITELIST" dst -j ACCEPT -m comment --comment "Whitelist IPs - Highest Priority"
    iptables -I FORWARD 1 -m set --match-set "$IPSET_WHITELIST" src -j ACCEPT -m comment --comment "Whitelist IPs - Highest Priority"
    iptables -I FORWARD 1 -m set --match-set "$IPSET_WHITELIST" dst -j ACCEPT -m comment --comment "Whitelist IPs - Highest Priority"
    
    # IPv6白名单规则
    if [[ "$IPV6_ENABLED" == "true" ]]; then
        ip6tables -I INPUT 1 -m set --match-set "${IPSET_WHITELIST}6" src -j ACCEPT -m comment --comment "Whitelist IPv6 - Highest Priority"
        ip6tables -I OUTPUT 1 -m set --match-set "${IPSET_WHITELIST}6" dst -j ACCEPT -m comment --comment "Whitelist IPv6 - Highest Priority"
        ip6tables -I FORWARD 1 -m set --match-set "${IPSET_WHITELIST}6" src -j ACCEPT -m comment --comment "Whitelist IPv6 - Highest Priority"
        ip6tables -I FORWARD 1 -m set --match-set "${IPSET_WHITELIST}6" dst -j ACCEPT -m comment --comment "Whitelist IPv6 - Highest Priority"
    fi
    
    log "INFO" "白名单防火墙规则创建完成"
}

# 创建端口过滤规则
create_port_filter_rules() {
    local port="$1"
    local protocol="$2"
    
    log "INFO" "创建端口过滤规则: $protocol/$port"
    
    # 创建IPSet集合
    if ! ipset list "$IPSET_BLOCKED" &>/dev/null; then
        ipset create "$IPSET_BLOCKED" hash:net maxelem "$MAX_RULES"
    fi
    
    # IPv4过滤规则（在白名单规则之后）
    iptables -A INPUT -p "$protocol" --dport "$port" -m set --match-set "$IPSET_BLOCKED" src -j DROP -m comment --comment "Port $port filter"
    iptables -A OUTPUT -p "$protocol" --sport "$port" -m set --match-set "$IPSET_BLOCKED" dst -j DROP -m comment --comment "Port $port filter"
    
    # IPv6过滤规则
    if [[ "$IPV6_ENABLED" == "true" ]]; then
        if ! ipset list "$IPSET_BLOCKED6" &>/dev/null; then
            ipset create "$IPSET_BLOCKED6" hash:net family inet6 maxelem "$MAX_RULES"
        fi
        
        ip6tables -A INPUT -p "$protocol" --dport "$port" -m set --match-set "$IPSET_BLOCKED6" src -j DROP -m comment --comment "Port $port IPv6 filter"
        ip6tables -A OUTPUT -p "$protocol" --sport "$port" -m set --match-set "$IPSET_BLOCKED6" dst -j DROP -m comment --comment "Port $port IPv6 filter"
    fi
}

# =============================================================================
# 数据源管理
# =============================================================================

# 初始化数据源
init_datasources() {
    log "INFO" "初始化数据源系统..."
    
    # 创建数据源目录
    mkdir -p "${DATA_DIR}/sources"
    
    # 加载数据源配置
    if [[ -f "$DATASOURCE_FILE" ]]; then
        log "INFO" "数据源配置文件已存在"
    else
        log "WARN" "数据源配置文件不存在，使用默认配置"
        echo "$DEFAULT_DATASOURCES" > "$DATASOURCE_FILE"
    fi
}

# 更新IP数据
update_ip_data() {
    local source_name="$1"
    local source_url="$2"
    
    log "INFO" "更新IP数据: $source_name from $source_url"
    
    local temp_file="${DATA_DIR}/sources/${source_name}.tmp"
    local data_file="${DATA_DIR}/sources/${source_name}.txt"
    
    # 下载IP数据
    if curl --connect-timeout "$DATASOURCE_TIMEOUT" -s "$source_url" > "$temp_file"; then
        # 验证数据格式
        if grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" "$temp_file" >/dev/null; then
            mv "$temp_file" "$data_file"
            log "INFO" "成功更新 $source_name 数据"
            return 0
        else
            log "WARN" "$source_name 数据格式无效"
            rm -f "$temp_file"
            return 1
        fi
    else
        log "ERROR" "无法下载 $source_name 数据"
        rm -f "$temp_file"
        return 1
    fi
}

# 加载IP数据到IPSet
load_ip_data() {
    local source_name="$1"
    local data_file="${DATA_DIR}/sources/${source_name}.txt"
    
    if [[ ! -f "$data_file" ]]; then
        log "WARN" "数据文件不存在: $data_file"
        return 1
    fi
    
    log "INFO" "加载 $source_name IP数据到过滤集合..."
    
    local count=0
    while IFS= read -r ip; do
        [[ -z "$ip" || ${ip:0:1} == "#" ]] && continue
        
        if validate_ip "$ip"; then
            # 确保IP不在白名单中
            if ! ipset test "$IPSET_WHITELIST" "$ip" &>/dev/null; then
                if [[ $ip =~ : ]]; then
                    # IPv6
                    if [[ "$IPV6_ENABLED" == "true" ]]; then
                        ipset add "$IPSET_BLOCKED6" "$ip" 2>/dev/null || true
                        ((count++))
                    fi
                else
                    # IPv4
                    ipset add "$IPSET_BLOCKED" "$ip" 2>/dev/null || true
                    ((count++))
                fi
            fi
        fi
    done < "$data_file"
    
    log "INFO" "已加载 $count 个 $source_name IP地址"
}

# =============================================================================
# 主功能函数
# =============================================================================

# 应用端口过滤
apply_port_filter() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    # 验证输入
    if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
        log "ERROR" "无效的端口号: $port"
        return 1
    fi
    
    if ! [[ "$protocol" =~ ^(tcp|udp)$ ]]; then
        log "ERROR" "无效的协议: $protocol (必须是tcp或udp)"
        return 1
    fi
    
    log "INFO" "应用端口过滤: $protocol/$port"
    
    # 创建白名单规则（最高优先级）
    create_whitelist_rules
    
    # 创建端口过滤规则
    create_port_filter_rules "$port" "$protocol"
    
    # 加载数据源IP
    while IFS='|' read -r name url enabled desc; do
        [[ -z "$name" || ${name:0:1} == "#" ]] && continue
        if [[ "$enabled" == "true" ]]; then
            update_ip_data "$name" "$url"
            load_ip_data "$name"
        fi
    done < "$DATASOURCE_FILE"
    
    log "INFO" "端口过滤规则应用完成"
}

# 移除端口过滤
remove_port_filter() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    log "INFO" "移除端口过滤规则: $protocol/$port"
    
    # 删除iptables规则
    iptables -D INPUT -p "$protocol" --dport "$port" -m set --match-set "$IPSET_BLOCKED" src -j DROP -m comment --comment "Port $port filter" 2>/dev/null || true
    iptables -D OUTPUT -p "$protocol" --sport "$port" -m set --match-set "$IPSET_BLOCKED" dst -j DROP -m comment --comment "Port $port filter" 2>/dev/null || true
    
    if [[ "$IPV6_ENABLED" == "true" ]]; then
        ip6tables -D INPUT -p "$protocol" --dport "$port" -m set --match-set "$IPSET_BLOCKED6" src -j DROP -m comment --comment "Port $port IPv6 filter" 2>/dev/null || true
        ip6tables -D OUTPUT -p "$protocol" --sport "$port" -m set --match-set "$IPSET_BLOCKED6" dst -j DROP -m comment --comment "Port $port IPv6 filter" 2>/dev/null || true
    fi
    
    log "INFO" "端口过滤规则已移除"
}

# 清理所有规则
cleanup_rules() {
    log "INFO" "清理所有防火墙规则..."
    
    # 删除白名单规则
    while iptables -D INPUT -m set --match-set "$IPSET_WHITELIST" src -j ACCEPT -m comment --comment "Whitelist IPs - Highest Priority" 2>/dev/null; do :; done
    while iptables -D OUTPUT -m set --match-set "$IPSET_WHITELIST" dst -j ACCEPT -m comment --comment "Whitelist IPs - Highest Priority" 2>/dev/null; do :; done
    while iptables -D FORWARD -m set --match-set "$IPSET_WHITELIST" src -j ACCEPT -m comment --comment "Whitelist IPs - Highest Priority" 2>/dev/null; do :; done
    while iptables -D FORWARD -m set --match-set "$IPSET_WHITELIST" dst -j ACCEPT -m comment --comment "Whitelist IPs - Highest Priority" 2>/dev/null; do :; done
    
    # 删除IPv6白名单规则
    if [[ "$IPV6_ENABLED" == "true" ]]; then
        while ip6tables -D INPUT -m set --match-set "${IPSET_WHITELIST}6" src -j ACCEPT -m comment --comment "Whitelist IPv6 - Highest Priority" 2>/dev/null; do :; done
        while ip6tables -D OUTPUT -m set --match-set "${IPSET_WHITELIST}6" dst -j ACCEPT -m comment --comment "Whitelist IPv6 - Highest Priority" 2>/dev/null; do :; done
        while ip6tables -D FORWARD -m set --match-set "${IPSET_WHITELIST}6" src -j ACCEPT -m comment --comment "Whitelist IPv6 - Highest Priority" 2>/dev/null; do :; done
        while ip6tables -D FORWARD -m set --match-set "${IPSET_WHITELIST}6" dst -j ACCEPT -m comment --comment "Whitelist IPv6 - Highest Priority" 2>/dev/null; do :; done
    fi
    
    # 销毁IPSet
    ipset destroy "$IPSET_WHITELIST" 2>/dev/null || true
    ipset destroy "${IPSET_WHITELIST}6" 2>/dev/null || true
    ipset destroy "$IPSET_BLOCKED" 2>/dev/null || true
    ipset destroy "$IPSET_BLOCKED6" 2>/dev/null || true
    
    log "INFO" "所有规则已清理"
}

# =============================================================================
# 备份和恢复
# =============================================================================

create_backup() {
    local backup_file="${BACKUP_DIR}/backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    log "INFO" "创建备份: $backup_file"
    
    tar -czf "$backup_file" -C / \
        "${CONFIG_DIR#/}" \
        "${DATA_DIR#/}/sources" \
        2>/dev/null
    
    log "INFO" "备份创建完成: $backup_file"
}

restore_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log "ERROR" "备份文件不存在: $backup_file"
        return 1
    fi
    
    log "INFO" "恢复备份: $backup_file"
    
    # 停止当前规则
    cleanup_rules
    
    # 恢复文件
    tar -xzf "$backup_file" -C /
    
    # 重新加载配置
    init_system
    
    log "INFO" "备份恢复完成"
}

# =============================================================================
# 系统状态
# =============================================================================
show_status() {
    echo -e "${CYAN}=== 端口过滤系统状态 ===${NC}"
    echo -e "${YELLOW}脚本版本:${NC} $SCRIPT_VERSION"
    echo -e "${YELLOW}配置目录:${NC} $CONFIG_DIR"
    echo -e "${YELLOW}日志目录:${NC} $LOG_DIR"
    echo -e "${YELLOW}数据目录:${NC} $DATA_DIR"
    
    echo -e "${GREEN}IPSet状态:${NC}"
    ipset list -t "$IPSET_WHITELIST" 2>/dev/null && echo -e "  ${GREEN}✓${NC} IPv4白名单集合"
    [[ "$IPV6_ENABLED" == "true" ]] && ipset list -t "${IPSET_WHITELIST}6" 2>/dev/null && echo -e "  ${GREEN}✓${NC} IPv6白名单集合"
    ipset list -t "$IPSET_BLOCKED" 2>/dev/null && echo -e "  ${GREEN}✓${NC} IPv4过滤集合"
    [[ "$IPV6_ENABLED" == "true" ]] && ipset list -t "$IPSET_BLOCKED6" 2>/dev/null && echo -e "  ${GREEN}✓${NC} IPv6过滤集合"
    
    echo -e "${GREEN}防火墙规则:${NC}"
    iptables -L INPUT -n --line-numbers | grep -q "$IPSET_WHITELIST" && echo -e "  ${GREEN}✓${NC} IPv4白名单规则"
    [[ "$IPV6_ENABLED" == "true" ]] && ip6tables -L INPUT -n --line-numbers | grep -q "${IPSET_WHITELIST}6" && echo -e "  ${GREEN}✓${NC} IPv6白名单规则"
    
    echo -e "${GREEN}活动数据源:${NC}"
    while IFS='|' read -r name url enabled desc; do
        [[ -z "$name" || ${name:0:1} == "#" ]] && continue
        if [[ "$enabled" == "true" ]]; then
            echo -e "  ${GREEN}✓${NC} $name - $desc"
        fi
    done < "$DATASOURCE_FILE"
}

# =============================================================================
# 交互式菜单
# =============================================================================

show_menu() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}    Linux端口过滤系统 - 主菜单        ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "${GREEN}1.${NC} 应用端口过滤"
    echo -e "${GREEN}2.${NC} 移除端口过滤"
    echo -e "${GREEN}3.${NC} IP白名单管理"
    echo -e "${GREEN}4.${NC} 数据源管理"
    echo -e "${GREEN}5.${NC} 系统状态"
    echo -e "${GREEN}6.${NC} 备份管理"
    echo -e "${GREEN}7.${NC} 清理所有规则"
    echo -e "${GREEN}8.${NC} 快速向导"
    echo -e "${GREEN}0.${NC} 退出"
    echo -e "${CYAN}========================================${NC}"
}

whitelist_menu() {
    while true; do
        clear
        echo -e "${CYAN}=== IP白名单管理 ===${NC}"
        echo -e "${GREEN}1.${NC} 添加IP到白名单"
        echo -e "${GREEN}2.${NC} 从白名单移除IP"
        echo -e "${GREEN}3.${NC} 显示当前白名单"
        echo -e "${GREEN}4.${NC} 重新加载白名单"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        
        read -p "请选择操作: " choice
        
        case $choice in
            1)
                read -p "请输入IP地址或CIDR段: " ip
                add_to_whitelist "$ip"
                read -p "按回车键继续..."
                ;;
            2)
                read -p "请输入要移除的IP地址: " ip
                remove_from_whitelist "$ip"
                read -p "按回车键继续..."
                ;;
            3)
                show_whitelist
                read -p "按回车键继续..."
                ;;
            4)
                load_whitelist
                read -p "按回车键继续..."
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

datasource_menu() {
    while true; do
        clear
        echo -e "${CYAN}=== 数据源管理 ===${NC}"
        echo -e "${GREEN}1.${NC} 启用/禁用数据源"
        echo -e "${GREEN}2.${NC} 添加自定义数据源"
        echo -e "${GREEN}3.${NC} 更新所有数据源"
        echo -e "${GREEN}4.${NC} 显示数据源状态"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        
        read -p "请选择操作: " choice
        
        case $choice in
            1)
                echo "数据源列表:"
                nl -w2 -s'. ' "$DATASOURCE_FILE" | grep -v "^$"
                read -p "请输入要切换的数据源编号: " num
                # 这里应该实现启用/禁用逻辑
                log "INFO" "功能待实现"
                read -p "按回车键继续..."
                ;;
            2)
                read -p "数据源名称: " name
                read -p "数据源URL: " url
                read -p "描述: " desc
                echo "$name|$url|true|$desc" >> "$DATASOURCE_FILE"
                log "INFO" "已添加数据源: $name"
                read -p "按回车键继续..."
                ;;
            3)
                while IFS='|' read -r name url enabled desc; do
                    [[ -z "$name" || ${name:0:1} == "#" ]] && continue
                    if [[ "$enabled" == "true" ]]; then
                        update_ip_data "$name" "$url"
                    fi
                done < "$DATASOURCE_FILE"
                read -p "按回车键继续..."
                ;;
            4)
                echo -e "${GREEN}当前数据源:${NC}"
                while IFS='|' read -r name url enabled desc; do
                    [[ -z "$name" || ${name:0:1} == "#" ]] && continue
                    if [[ "$enabled" == "true" ]]; then
                        echo -e "  ${GREEN}✓${NC} $name - $desc"
                    else
                        echo -e "  ${RED}✗${NC} $name - $desc"
                    fi
                done < "$DATASOURCE_FILE"
                read -p "按回车键继续..."
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

backup_menu() {
    while true; do
        clear
        echo -e "${CYAN}=== 备份管理 ===${NC}"
        echo -e "${GREEN}1.${NC} 创建备份"
        echo -e "${GREEN}2.${NC} 恢复备份"
        echo -e "${GREEN}3.${NC} 列出备份"
        echo -e "${GREEN}4.${NC} 清理旧备份"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        
        read -p "请选择操作: " choice
        
        case $choice in
            1)
                create_backup
                read -p "按回车键继续..."
                ;;
            2)
                ls -la "$BACKUP_DIR"/*.tar.gz 2>/dev/null
                read -p "请输入备份文件路径: " backup_file
                restore_backup "$backup_file"
                read -p "按回车键继续..."
                ;;
            3)
                ls -la "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "无备份文件"
                read -p "按回车键继续..."
                ;;
            4)
                find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -delete
                log "INFO" "已清理超过 $BACKUP_RETENTION_DAYS 天的备份"
                read -p "按回车键继续..."
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

quick_wizard() {
    clear
    echo -e "${CYAN}=== 快速向导 ===${NC}"
    echo -e "${GREEN}这个向导将帮助您快速配置端口过滤系统${NC}"
    
    # 步骤1：添加白名单IP
    echo -e "\n${YELLOW}步骤1: 配置IP白名单（可选）${NC}"
    echo "请输入需要加入白名单的IP地址，直接回车跳过:"
    while true; do
        read -p "IP地址(输入done完成): " ip
        [[ "$ip" == "done" ]] && break
        [[ -z "$ip" ]] && break
        add_to_whitelist "$ip"
    done
    
    # 步骤2：选择数据源
    echo -e "\n${YELLOW}步骤2: 选择IP数据源${NC}"
    echo "可用的数据源:"
    while IFS='|' read -r name url enabled desc; do
        [[ -z "$name" || ${name:0:1} == "#" ]] && continue
        echo "  $name - $desc"
    done < "$DATASOURCE_FILE"
    
    read -p "要启用的数据源（空格分隔，默认china）: " sources
    sources=${sources:-china}
    
    # 步骤3：配置端口
    echo -e "\n${YELLOW}步骤3: 配置端口过滤${NC}"
    read -p "要过滤的端口号: " port
    read -p "协议（tcp/udp，默认tcp）: " protocol
    protocol=${protocol:-tcp}
    
    # 应用配置
    echo -e "\n${GREEN}正在应用配置...${NC}"
    apply_port_filter "$port" "$protocol"
    
    echo -e "\n${GREEN}配置完成！${NC}"
    show_status
    read -p "按回车键继续..."
}

# =============================================================================
# 主程序
# =============================================================================

main() {
    # 设置信号处理
    trap cleanup EXIT
    trap cleanup INT TERM
    
    # 检查权限
    check_root
    
    # 检查依赖
    check_dependencies
    
    # 获取文件锁
    acquire_lock
    
    # 初始化系统
    init_system
    
    # 加载白名单（确保最高优先级）
    load_whitelist
    
    # 命令行模式
    if [[ $# -gt 0 ]]; then
        case "$1" in
            "apply")
                apply_port_filter "$2" "${3:-tcp}"
                ;;
            "remove")
                remove_port_filter "$2" "${3:-tcp}"
                ;;
            "whitelist-add")
                add_to_whitelist "$2"
                ;;
            "whitelist-remove")
                remove_from_whitelist "$2"
                ;;
            "whitelist-show")
                show_whitelist
                ;;
            "status")
                show_status
                ;;
            "backup")
                create_backup
                ;;
            "cleanup")
                cleanup_rules
                ;;
            "wizard")
                quick_wizard
                ;;
            *)
                echo "用法: $0 {apply|remove|whitelist-add|whitelist-remove|whitelist-show|status|backup|cleanup|wizard}"
                echo "  apply <port> [protocol]     - 应用端口过滤"
                echo "  remove <port> [protocol]    - 移除端口过滤"
                echo "  whitelist-add <ip>          - 添加IP到白名单"
                echo "  whitelist-remove <ip>       - 从白名单移除IP"
                echo "  whitelist-show              - 显示白名单"
                echo "  status                      - 显示系统状态"
                echo "  backup                      - 创建备份"
                echo "  cleanup                     - 清理所有规则"
                echo "  wizard                      - 快速向导"
                exit 1
                ;;
        esac
        exit 0
    fi
    
    # 交互式菜单模式
    while true; do
        show_menu
        read -p "请选择操作: " choice
        
        case $choice in
            1)
                read -p "端口号: " port
                read -p "协议(tcp/udp): " protocol
                protocol=${protocol:-tcp}
                apply_port_filter "$port" "$protocol"
                ;;
            2)
                read -p "端口号: " port
                read -p "协议(tcp/udp): " protocol
                protocol=${protocol:-tcp}
                remove_port_filter "$port" "$protocol"
                ;;
            3)
                whitelist_menu
                ;;
            4)
                datasource_menu
                ;;
            5)
                show_status
                read -p "按回车键继续..."
                ;;
            6)
                backup_menu
                ;;
            7)
                read -p "确定要清理所有规则吗？(y/N): " confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    cleanup_rules
                fi
                ;;
            8)
                quick_wizard
                ;;
            0)
                log "INFO" "退出系统"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 启动主程序
main "$@"