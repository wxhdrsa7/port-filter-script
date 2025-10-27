#!/bin/bash
# port_filter.sh - 端口访问控制一键脚本 (增强版 v2.1.0)
# 作者：你 + GPT + Grok
# 版本：2.1.0
# 新特性：IPv6支持、规则备份/恢复、多源IP下载+缓存、增强错误处理与回滚、流量统计、nftables兼容预备
# 优化：专用链管理规则、动态maxelem、端口multiport、配置验证

VERSION="2.1.0"
CONFIG_DIR="/etc/port-filter"
CONFIG_FILE="$CONFIG_DIR/config.conf"
LOG_FILE="$CONFIG_DIR/port-filter.log"
BACKUP_DIR="$CONFIG_DIR/backups"
SCRIPT_PATH="$(realpath "$0")"
IPSET_NAME="geo_filter"
CHAIN_NAME="PORT_FILTER"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
DEFAULT_COUNTRY="CN"
DEFAULT_UPDATE_CRON="true"
DEFAULT_LOG_LEVEL="INFO"
DEFAULT_IPV6="false"
DEFAULT_NFT_MODE="false"

# 日志函数
log() {
    local level=$1
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    case $level in
        "ERROR") echo -e "${RED}✗ $msg${NC}" >&2 ;;
        "WARN") echo -e "${YELLOW}⚠️ $msg${NC}" ;;
        *) echo "$msg" ;;
    esac
}

# 加载配置
load_config() {
    touch "$CONFIG_FILE"
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
# 国家代码 (默认 CN)
COUNTRY=$DEFAULT_COUNTRY

# 是否启用定时更新 (true/false)
UPDATE_CRON=$DEFAULT_UPDATE_CRON

# 日志级别 (INFO/DEBUG)
LOG_LEVEL=$DEFAULT_LOG_LEVEL

# IPv6支持 (true/false)
ENABLE_IPV6=$DEFAULT_IPV6

# nftables模式 (true/false, 实验性)
NFT_MODE=$DEFAULT_NFT_MODE

# 批量规则格式: port_range protocol mode (例如: 80 tcp blacklist)
# 协议: tcp/udp/both
# 模式: blacklist(阻止指定国家IP)/whitelist(仅允许指定国家IP)/block(完全阻止)/allow(完全允许)
# 示例:
# 22-25 both whitelist
# 80 tcp block
# 443 udp allow
EOF
        log "INFO" "创建默认配置文件: $CONFIG_FILE"
    fi
    source "$CONFIG_FILE" 2>/dev/null || log "WARN" "配置文件加载失败，使用默认值"
    COUNTRY=${COUNTRY:-$DEFAULT_COUNTRY}
    UPDATE_CRON=${UPDATE_CRON:-$DEFAULT_UPDATE_CRON}
    LOG_LEVEL=${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}
    ENABLE_IPV6=${ENABLE_IPV6:-$DEFAULT_IPV6}
    NFT_MODE=${NFT_MODE:-$DEFAULT_NFT_MODE}
    log "INFO" "加载配置: 国家=$COUNTRY, IPv6=$ENABLE_IPV6, nft=$NFT_MODE"
}

#==================== 基础检测 ====================#

check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log "ERROR" "请使用 root 权限运行此脚本"
        exit 1
    fi
}

check_stdin() {
    if [ ! -t 0 ]; then
        log "WARN" "检测到通过管道运行，请使用建议方式"
        echo -e "${YELLOW}⚠️ 检测到你通过管道运行（例如 curl | bash）${NC}"
        echo -e "${BLUE}请改用以下方式运行：${NC}"
        echo ""
        echo "  curl -sL https://raw.githubusercontent.com/你的仓库路径/port-filter.sh -o port-filter.sh"
        echo "  sudo bash port-filter.sh"
        echo ""
        echo -e "${YELLOW}或者：${NC}"
        echo "  curl -sL https://raw.githubusercontent.com/你的仓库路径/port-filter.sh | sudo bash -s < /dev/tty"
        echo ""
        exit 1
    fi
}

#==================== 功能实现 ====================#

install_dependencies() {
    log "INFO" "检查并安装依赖..."
    apt-get update -qq || log "WARN" "apt-get update 失败"
    apt-get install -y ipset iptables-persistent nftables curl cron > /dev/null 2>&1 || log "ERROR" "依赖安装失败"
    mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    log "INFO" "依赖安装完成"
}

setup_cron() {
    if [ "$UPDATE_CRON" != "true" ]; then
        log "INFO" "定时更新已禁用"
        return
    fi
    local cron_job="0 2 * * * $SCRIPT_PATH update_ip >> $LOG_FILE 2>&1"
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" || true; echo "$cron_job") | crontab -
    log "INFO" "已安装定时任务: 每日2点更新IP列表"
}

# 备份规则
backup_rules() {
    local backup_file="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).rules"
    if [ "$NFT_MODE" = "true" ]; then
        nft list ruleset > "$backup_file"
    else
        iptables-save > "$backup_file"
        if [ "$ENABLE_IPV6" = "true" ]; then
            ip6tables-save >> "$backup_file"
        fi
    fi
    log "INFO" "规则备份到: $backup_file"
    echo "$backup_file"
}

# 恢复规则
restore_rules() {
    local backup_file="$1"
    if [ ! -f "$backup_file" ]; then
        log "ERROR" "备份文件不存在: $backup_file"
        return 1
    fi
    if [ "$NFT_MODE" = "true" ]; then
        nft -f "$backup_file"
    else
        iptables-restore < "$backup_file"
        if [ "$ENABLE_IPV6" = "true" ]; then
            ip6tables-restore < "$backup_file"  # 假设备份包含ip6部分
        fi
    fi
    log "INFO" "规则从 $backup_file 恢复"
}

show_stats() {
    echo -e "${BLUE}==================== 流量统计 ====================${NC}"
    if ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        ipset xstats "$IPSET_NAME" 2>/dev/null | head -5 || echo "ipset统计不可用"
    fi
    iptables -L INPUT -n -v | grep -E "pkts|bytes" | head -5 || echo "(暂无统计)"
    echo -e "${BLUE}=======================================================${NC}"
}

download_geo_ip() {
    local country_code=$1
    local ipset_name=$2
    log "INFO" "下载 $country_code IP列表..."

    local cache_file="$CONFIG_DIR/ip_$country_code.cache"
    local cache_age=$( [ -f "$cache_file" ] && echo $(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) )) || echo 999999 )
    if [ "$cache_age" -lt 86400 ] && [ -s "$cache_file" ]; then
        log "INFO" "使用缓存 (年龄: $(($cache_age / 3600))h)"
        cat "$cache_file"
    else
        ipset destroy "$ipset_name" 2>/dev/null
        local maxelem=$(curl -s "https://raw.githubusercontent.com/metowolf/iplist/master/data/country/${country_code}.txt" | wc -l || echo 70000)
        ipset create "$ipset_name" hash:net maxelem $((maxelem * 2)) 2>/dev/null || log "ERROR" "创建 ipset $ipset_name 失败"

        local sources=(
            "https://raw.githubusercontent.com/metowolf/iplist/master/data/country/${country_code}.txt"
            "https://www.ipdeny.com/ipblocks/data/countries/${country_code}.zone"
            "https://raw.githubusercontent.com/herrbischoff/country-ip-blocks/master/ipv4/${country_code}.cidr"
        )
        if [ "$country_code" = "CN" ]; then
            sources+=("https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt")
        fi

        local temp_file=$(mktemp)
        local success=false
        local count=0

        for source in "${sources[@]}"; do
            if curl -sL --connect-timeout 10 --max-time 30 --retry 3 "$source" -o "$temp_file"; then
                if [ -s "$temp_file" ]; then
                    while read -r ip; do
                        [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/([0-9]|[1-2][0-9]|3[0-2]))?$ ]] && {
                            ipset add "$ipset_name" "$ip" 2>/dev/null && ((count++))
                        }
                    done < "$temp_file"
                    cp "$temp_file" "$cache_file"
                    success=true
                    log "INFO" "从源 $source 成功导入 $count 条 IP"
                    break
                fi
            fi
        done

        rm -f "$temp_file"
        if [ "$success" = false ]; then
            log "ERROR" "所有下载源失败，请检查网络"
            return 1
        fi
        log "INFO" "IP列表更新完成: $count 条规则 (缓存更新)"
    fi
}

update_ip() {
    download_geo_ip "$COUNTRY" "$IPSET_NAME" || return 1
    if [ "$ENABLE_IPV6" = "true" ]; then
        # IPv6 ipset (简化，实际需IPv6源)
        local ip6set_name="${IPSET_NAME}_v6"
        ipset destroy "$ip6set_name" 2>/dev/null
        ipset create "$ip6set_name" hash:net family inet6 maxelem 20000 2>/dev/null
        # TODO: 添加IPv6下载源，如 ipdeny IPv6
        log "INFO" "IPv6 IPset 创建 (需手动添加源)"
    fi
}

init_chain() {
    iptables -N "$CHAIN_NAME" 2>/dev/null || true
    iptables -F "$CHAIN_NAME"
    iptables -I INPUT 1 -j "$CHAIN_NAME"
    if [ "$ENABLE_IPV6" = "true" ]; then
        ip6tables -N "$CHAIN_NAME" 2>/dev/null || true
        ip6tables -F "$CHAIN_NAME"
        ip6tables -I INPUT 1 -j "$CHAIN_NAME"
    fi
}

clear_port_rules() {
    local port_range=$1
    # 用专用链，避免全局flush
    for p in tcp udp; do
        iptables -D "$CHAIN_NAME" -p $p --dport "$port_range" -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null
        iptables -D "$CHAIN_NAME" -p $p --dport "$port_range" -m set --match-set "$IPSET_NAME" src -j ACCEPT 2>/dev/null
        iptables -D "$CHAIN_NAME" -p $p --dport "$port_range" -j DROP 2>/dev/null
        iptables -D "$CHAIN_NAME" -p $p --dport "$port_range" -j ACCEPT 2>/dev/null
        if [ "$ENABLE_IPV6" = "true" ]; then
            ip6tables -D "$CHAIN_NAME" -p $p --dport "$port_range" -m set --match-set "${IPSET_NAME}_v6" src -j DROP 2>/dev/null
            # 类似IPv6规则
        fi
    done
}

apply_rule() {
    local port_range=$1 protocol=$2 mode=$3
    local backup_file=$(backup_rules)  # 回滚准备
    clear_port_rules "$port_range"
    local success=true

    for p in tcp udp; do
        if [ "$protocol" = "$p" ] || [ "$protocol" = "both" ]; then
            case $mode in
                "blacklist")
                    if ! iptables -I "$CHAIN_NAME" -p $p --dport "$port_range" -m set --match-set "$IPSET_NAME" src -j DROP; then
                        success=false
                    fi
                    log "INFO" "$p 端口 $port_range: 阻止 $COUNTRY IP"
                    ;;
                "whitelist")
                    if ! iptables -I "$CHAIN_NAME" -p $p --dport "$port_range" -m set --match-set "$IPSET_NAME" src -j ACCEPT ||
                       ! iptables -I "$CHAIN_NAME" -p $p --dport "$port_range" -j DROP; then
                        success=false
                    fi
                    log "INFO" "$p 端口 $port_range: 仅允许 $COUNTRY IP"
                    ;;
            esac
            if [ "$ENABLE_IPV6" = "true" ]; then
                # 类似IPv6规则，使用ip6tables和_v6 ipset
                ip6tables -I "$CHAIN_NAME" -p $p --dport "$port_range" -m set --match-set "${IPSET_NAME}_v6" src -j DROP  # 示例
            fi
        fi
    done

    if [ "$success" = false ]; then
        log "ERROR" "规则应用失败，回滚..."
        restore_rules "$backup_file"
        return 1
    fi
    save_rules
}

block_port() {
    local port_range=$1 protocol=$2
    clear_port_rules "$port_range"
    for p in tcp udp; do
        if [ "$protocol" = "$p" ] || [ "$protocol" = "both" ]; then
            iptables -I "$CHAIN_NAME" -p $p --dport "$port_range" -j DROP || log "ERROR" "屏蔽规则失败: $p $port_range"
            log "INFO" "已屏蔽 $p 端口 $port_range"
        fi
    done
    save_rules
}

allow_port() {
    local port_range=$1 protocol=$2
    clear_port_rules "$port_range"
    for p in tcp udp; do
        if [ "$protocol" = "$p" ] || [ "$protocol" = "both" ]; then
            iptables -I "$CHAIN_NAME" -p $p --dport "$port_range" -j ACCEPT || log "ERROR" "放行规则失败: $p $port_range"
            log "INFO" "已放行 $p 端口 $port_range"
        fi
    done
    save_rules
}

# 配置验证
validate_config_line() {
    local line=$1
    local port_range=$(echo "$line" | awk '{print $1}')
    local protocol=$(echo "$line" | awk '{print $2}')
    local mode=$(echo "$line" | awk '{print $3}')
    if ! [[ "$port_range" =~ ^[1-9][0-9]{0,4}(-[1-9][0-9]{0,4})?$ ]] || [ $port_range -gt 65535 ]; then
        return 1
    fi
    if [[ "$protocol" != "tcp" && "$protocol" != "udp" && "$protocol" != "both" ]]; then
        return 1
    fi
    if [[ "$mode" != "blacklist" && "$mode" != "whitelist" && "$mode" != "block" && "$mode" != "allow" ]]; then
        return 1
    fi
    return 0
}

apply_batch_rules() {
    log "INFO" "应用批量规则..."
    update_ip || return 1
    init_chain
    local line_num=0
    local invalid_count=0
    while IFS= read -r line || [ -n "$line" ]; do
        ((line_num++))
        line=$(echo "$line" | xargs)
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if ! validate_config_line "$line"; then
            log "WARN" "无效配置行 $line_num: $line"
            ((invalid_count++))
            continue
        fi
        local port_range=$(echo "$line" | awk '{print $1}')
        local protocol=$(echo "$line" | awk '{print $2}')
        local mode=$(echo "$line" | awk '{print $3}')
        case $mode in
            "blacklist"|"whitelist")
                apply_rule "$port_range" "$protocol" "$mode" || ((invalid_count++))
                ;;
            "block")
                block_port "$port_range" "$protocol"
                ;;
            "allow")
                allow_port "$port_range" "$protocol"
                ;;
        esac
    done < <(grep -v '^#' "$CONFIG_FILE" | grep -E '^[0-9]+(-[0-9]+)? [a-z]+ (blacklist|whitelist|block|allow)')
    log "INFO" "批量应用完成: $((line_num - invalid_count)) 有效 / $invalid_count 无效"
}

save_rules() {
    log "INFO" "保存规则..."
    if [ "$NFT_MODE" = "true" ]; then
        netfilter-persistent save > /dev/null 2>&1 || log "WARN" "nft保存失败"
    else
        netfilter-persistent save > /dev/null 2>&1 || log "WARN" "iptables保存失败"
    fi
}

show_rules() {
    echo -e "${BLUE}==================== 当前防火墙规则 ====================${NC}"
    if [ "$NFT_MODE" = "true" ]; then
        nft list chain ip filter PORT_FILTER || echo "(nft规则空)"
    else
        iptables -L "$CHAIN_NAME" -n -v --line-numbers || echo "(iptables规则空)"
    fi
    echo -e "${BLUE}=======================================================${NC}"
    tail -5 "$LOG_FILE" | sed 's/^/日志: /'
}

clear_all_rules() {
    log "WARN" "正在清除所有规则..."
    backup_rules  # 自动备份前清除
    iptables -F "$CHAIN_NAME" 2>/dev/null || true
    iptables -D INPUT -j "$CHAIN_NAME" 2>/dev/null || true
    ipset destroy "$IPSET_NAME" 2>/dev/null || true
    if [ "$ENABLE_IPV6" = "true" ]; then
        ip6tables -F "$CHAIN_NAME" 2>/dev/null || true
        ip6tables -D INPUT -j "$CHAIN_NAME" 2>/dev/null || true
        ipset destroy "${IPSET_NAME}_v6" 2>/dev/null || true
    fi
    save_rules
    log "INFO" "已清除所有规则"
}

#==================== 菜单区 ====================#

show_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   端口访问控制脚本 v${VERSION}   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} IP 地域过滤（黑/白名单）"
    echo -e "${GREEN}2.${NC} 屏蔽端口（完全阻止）"
    echo -e "${GREEN}3.${NC} 放行端口（完全允许）"
    echo -e "${GREEN}4.${NC} 查看当前规则"
    echo -e "${GREEN}5.${NC} 清除所有规则"
    echo -e "${GREEN}6.${NC} 更新IP列表"
    echo -e "${GREEN}7.${NC} 批量应用配置文件规则"
    echo -e "${GREEN}8.${NC} 配置国家/定时任务/IPv6"
    echo -e "${GREEN}9.${NC} 备份/恢复规则"
    echo -e "${GREEN}10.${NC} 查看流量统计"
    echo -e "${GREEN}0.${NC} 退出"
    echo ""
    echo -ne "${YELLOW}请选择操作 [0-10]: ${NC}"
}

#==================== 主逻辑 ====================#

main() {
    check_root
    check_stdin
    load_config
    install_dependencies
    setup_cron
    init_chain  # 初始化专用链

    # 处理命令行参数
    if [ "$1" = "update_ip" ]; then
        update_ip
        exit $?
    elif [ "$1" = "backup" ]; then
        echo $(backup_rules)
        exit 0
    elif [ "$1" = "restore" ] && [ -n "$2" ]; then
        restore_rules "$2"
        exit $?
    fi

    while true; do
        show_menu
        read choice < /dev/tty
        case $choice in
            1)
                echo "请输入端口范围 (例如: 80 或 22-25):"
                read port_range < /dev/tty
                if ! [[ "$port_range" =~ ^[1-9][0-9]{0,4}(-[1-9][0-9]{0,4})?$ ]] || [ "${port_range%%-*}" -gt 65535 ]; then
                    log "ERROR" "无效端口范围: $port_range (1-65535)"
                    read -p "按回车继续..." < /dev/tty
                    continue
                fi
                echo "选择协议：1.TCP 2.UDP 3.同时"
                read proto_choice < /dev/tty
                case $proto_choice in
                    1) protocol="tcp" ;;
                    2) protocol="udp" ;;
                    3) protocol="both" ;;
                    *) log "ERROR" "无效协议选择"; read -p "按回车继续..." < /dev/tty; continue ;;
                esac
                echo "选择模式：1.黑名单(阻止 $COUNTRY IP) 2.白名单(仅允许 $COUNTRY IP)"
                read mode_choice < /dev/tty
                case $mode_choice in
                    1) mode="blacklist" ;;
                    2) mode="whitelist" ;;
                    *) log "ERROR" "无效模式选择"; read -p "按回车继续..." < /dev/tty; continue ;;
                esac
                update_ip || { log "ERROR" "IP更新失败"; read -p "按回车继续..." < /dev/tty; continue; }
                apply_rule "$port_range" "$protocol" "$mode"
                read -p "按回车继续..." < /dev/tty
                ;;
            2)
                echo "请输入要屏蔽的端口范围 (例如: 80 或 22-25):"
                read port_range < /dev/tty
                if ! [[ "$port_range" =~ ^[1-9][0-9]{0,4}(-[1-9][0-9]{0,4})?$ ]] || [ "${port_range%%-*}" -gt 65535 ]; then
                    log "ERROR" "无效端口范围: $port_range"
                    read -p "按回车继续..." < /dev/tty
                    continue
                fi
                echo "协议：1.TCP 2.UDP 3.同时"
                read proto_choice < /dev/tty
                case $proto_choice in
                    1) protocol="tcp" ;;
                    2) protocol="udp" ;;
                    3) protocol="both" ;;
                    *) log "ERROR" "无效协议选择"; read -p "按回车继续..." < /dev/tty; continue ;;
                esac
                block_port "$port_range" "$protocol"
                read -p "按回车继续..." < /dev/tty
                ;;
            3)
                echo "请输入要放行的端口范围 (例如: 80 或 22-25):"
                read port_range < /dev/tty
                if ! [[ "$port_range" =~ ^[1-9][0-9]{0,4}(-[1-9][0-9]{0,4})?$ ]] || [ "${port_range%%-*}" -gt 65535 ]; then
                    log "ERROR" "无效端口范围: $port_range"
                    read -p "按回车继续..." < /dev/tty
                    continue
                fi
                echo "协议：1.TCP 2.UDP 3.同时"
                read proto_choice < /dev/tty
                case $proto_choice in
                    1) protocol="tcp" ;;
                    2) protocol="udp" ;;
                    3) protocol="both" ;;
                    *) log "ERROR" "无效协议选择"; read -p "按回车继续..." < /dev/tty; continue ;;
                esac
                allow_port "$port_range" "$protocol"
                read -p "按回车继续..." < /dev/tty
                ;;
            4)
                show_rules
                read -p "按回车继续..." < /dev/tty
                ;;
            5)
                read -p "确认清除所有规则？(y/N): " confirm < /dev/tty
                [[ $confirm =~ ^[Yy]$ ]] && clear_all_rules
                read -p "按回车继续..." < /dev/tty
                ;;
            6)
                update_ip
                save_rules
                read -p "按回车继续..." < /dev/tty
                ;;
            7)
                apply_batch_rules
                read -p "按回车继续..." < /dev/tty
                ;;
            8)
                echo "当前配置:"
                echo "  国家: $COUNTRY"
                echo "  定时更新: $UPDATE_CRON"
                echo "  IPv6: $ENABLE_IPV6"
                echo ""
                echo "输入新国家代码 (例如: US, JP, 留空保持 $COUNTRY):"
                read new_country < /dev/tty
                [[ -n "$new_country" ]] && sed -i "s/^COUNTRY=.*/COUNTRY=$new_country/" "$CONFIG_FILE"
                echo "启用IPv6? (y/n, 留空保持 $ENABLE_IPV6):"
                read ipv6_choice < /dev/tty
                [[ "$ipv6_choice" =~ ^[Yy]$ ]] && sed -i 's/^ENABLE_IPV6=.*/ENABLE_IPV6=true/' "$CONFIG_FILE"
                [[ "$ipv6_choice" =~ ^[Nn]$ ]] && sed -i 's/^ENABLE_IPV6=.*/ENABLE_IPV6=false/' "$CONFIG_FILE"
                echo "启用定时更新? (y/n, 留空保持 $UPDATE_CRON):"
                read cron_choice < /dev/tty
                [[ "$cron_choice" =~ ^[Yy]$ ]] && sed -i 's/^UPDATE_CRON=.*/UPDATE_CRON=true/' "$CONFIG_FILE"
                [[ "$cron_choice" =~ ^[Nn]$ ]] && sed -i 's/^UPDATE_CRON=.*/UPDATE_CRON=false/' "$CONFIG_FILE"
                load_config  # 重新加载
                setup_cron
                if [ "$ENABLE_IPV6" = "true" ]; then
                    update_ip  # 更新IPv6
                fi
                read -p "按回车继续..." < /dev/tty
                ;;
            9)
                echo "1. 备份规则  2. 恢复规则"
                read action < /dev/tty
                case $action in
                    1)
                        backup_rules
                        read -p "按回车继续..." < /dev/tty
                        ;;
                    2)
                        echo "可用备份: $(ls -t $BACKUP_DIR/*.rules 2>/dev/null | head -3)"
                        read -p "输入备份文件名: " backup_file < /dev/tty
                        restore_rules "$BACKUP_DIR/$backup_file"
                        read -p "按回车继续..." < /dev/tty
                        ;;
                esac
                ;;
            10)
                show_stats
                read -p "按回车继续..." < /dev/tty
                ;;
            0)
                log "INFO" "脚本退出"
                exit 0
                ;;
            *)
                log "WARN" "无效选择，请重试"
                sleep 2
                ;;
        esac
    done
}

main "$@"
