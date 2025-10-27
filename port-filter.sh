#!/bin/bash
# port_filter.sh - 端口访问控制一键脚本 (增强版 v2.4.0)
# 作者：你 + GPT + Grok
# 版本：2.4.0
# 新特性：一键安装/卸载功能（依赖安装、systemd服务、完整清理）、菜单集成
# 优化：卸载时恢复默认防火墙政策、移除Fail2Ban/UFW配置、2025 systemd最佳实践

VERSION="2.4.0"
CONFIG_DIR="/etc/port-filter"
CONFIG_FILE="$CONFIG_DIR/config.conf"
LOG_FILE="$CONFIG_DIR/port-filter.log"
BACKUP_DIR="$CONFIG_DIR/backups"
SCRIPT_PATH="$(realpath "$0")"
IPSET_NAME="geo_filter"
CHAIN_NAME="PORT_FILTER"
TABLE_NAME="filter"
SERVICE_NAME="port-filter"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 默认配置
DEFAULT_COUNTRY="CN"
DEFAULT_UPDATE_CRON="true"
DEFAULT_LOG_LEVEL="INFO"
DEFAULT_IPV6="false"
DEFAULT_NFT_MODE="true"
DEFAULT_DEFAULT_DENY="true"
DEFAULT_UFW_MODE="false"
DEFAULT_SOURCES="metowolf,17mon,mayaxcn"

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

# IP来源 (逗号分隔: metowolf,17mon,mayaxcn)
SOURCES=$DEFAULT_SOURCES

# 是否启用定时更新 (true/false)
UPDATE_CRON=$DEFAULT_UPDATE_CRON

# 日志级别 (INFO/DEBUG)
LOG_LEVEL=$DEFAULT_LOG_LEVEL

# IPv6支持 (true/false)
ENABLE_IPV6=$DEFAULT_IPV6

# nftables模式 (true/false)
NFT_MODE=$DEFAULT_NFT_MODE

# 默认拒绝政策 (true/false)
DEFAULT_DENY=$DEFAULT_DEFAULT_DENY

# UFW模式 (true/false)
UFW_MODE=$DEFAULT_UFW_MODE

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
    SOURCES=${SOURCES:-$DEFAULT_SOURCES}
    UPDATE_CRON=${UPDATE_CRON:-$DEFAULT_UPDATE_CRON}
    LOG_LEVEL=${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}
    ENABLE_IPV6=${ENABLE_IPV6:-$DEFAULT_IPV6}
    NFT_MODE=${NFT_MODE:-$DEFAULT_NFT_MODE}
    DEFAULT_DENY=${DEFAULT_DENY:-$DEFAULT_DEFAULT_DENY}
    UFW_MODE=${UFW_MODE:-$DEFAULT_UFW_MODE}
    log "INFO" "加载配置: 国家=$COUNTRY, 来源=$SOURCES, IPv6=$ENABLE_IPV6"
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
    apt-get install -y ipset iptables-persistent nftables curl cron fail2ban ufw nmap > /dev/null 2>&1 || log "ERROR" "依赖安装失败"
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

setup_fail2ban() {
    if [ "$NFT_MODE" = "true" ]; then
        sed -i 's/^banaction\s*=.*/banaction = nftables-multiport/' /etc/fail2ban/jail.local 2>/dev/null || echo "banaction = nftables-multiport" >> /etc/fail2ban/jail.local
    else
        sed -i 's/^banaction\s*=.*/banaction = iptables-multiport/' /etc/fail2ban/jail.local 2>/dev/null || echo "banaction = iptables-multiport" >> /etc/fail2ban/jail.local
    fi
    cat > /etc/fail2ban/jail.d/port-filter.local << EOF
[port-filter]
enabled = true
port = any
logpath = $LOG_FILE
maxretry = 5
bantime = 3600
findtime = 600
EOF
    systemctl restart fail2ban || log "WARN" "Fail2Ban重启失败"
    log "INFO" "Fail2Ban已配置监控 $LOG_FILE"
}

setup_ufw_geo() {
    if [ "$UFW_MODE" != "true" ]; then return; fi
    ufw --force enable
    ufw default deny incoming
    ufw insert 1 allow from $IPSET_NAME to any port 22 proto tcp
    log "INFO" "UFW geo-block启用"
}

# 新: 一键安装
install_script() {
    log "INFO" "[安装步骤1/5] 安装依赖..."
    install_dependencies
    log "INFO" "[安装步骤2/5] 加载配置..."
    load_config
    log "INFO" "[安装步骤3/5] 设置定时任务..."
    setup_cron
    log "INFO" "[安装步骤4/5] 配置Fail2Ban和UFW..."
    setup_fail2ban
    setup_ufw_geo
    log "INFO" "[安装步骤5/5] 初始化链..."
    init_chain
    # 创建systemd服务 (2025最佳实践)
    cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=Port Filter Service
After=network.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH init
RemainAfterExit=yes
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    log "INFO" "systemd服务已启用: systemctl start $SERVICE_NAME"
    echo -e "${GREEN}✓ 安装完成！脚本已就绪。${NC}"
}

# 新: 一键卸载
uninstall_script() {
    read -p "确认卸载脚本？(y/N): " confirm < /dev/tty
    [[ $confirm =~ ^[Yy]$ ]] || { log "INFO" "卸载取消"; return; }
    log "WARN" "[卸载步骤1/6] 停止服务..."
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    systemctl disable $SERVICE_NAME 2>/dev/null || true
    rm -f /etc/systemd/system/$SERVICE_NAME.service
    systemctl daemon-reload
    log "WARN" "[卸载步骤2/6] 清除所有规则..."
    clear_all_rules
    log "WARN" "[卸载步骤3/6] 移除定时任务..."
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" || true) | crontab -
    log "WARN" "[卸载步骤4/6] 移除Fail2Ban配置..."
    rm -f /etc/fail2ban/jail.d/port-filter.local
    systemctl restart fail2ban 2>/dev/null || true
    log "WARN" "[卸载步骤5/6] 禁用UFW geo..."
    ufw delete allow from $IPSET_NAME 2>/dev/null || true
    ufw reload 2>/dev/null || true
    log "WARN" "[卸载步骤6/6] 清理文件..."
    rm -rf "$CONFIG_DIR"
    log "INFO" "卸载完成！所有配置已清理。"
    echo -e "${GREEN}✓ 卸载成功。${NC}"
}

# IP源映射
get_sources() {
    local country=$1
    case $country in
        "CN")
            local src_array=()
            IFS=',' read -ra ADDR <<< "$SOURCES"
            for src in "${ADDR[@]}"; do
                case $src in
                    "metowolf") src_array+=("https://raw.githubusercontent.com/metowolf/iplist/master/data/country/${country}.txt") ;;
                    "17mon") src_array+=("https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt") ;;
                    "mayaxcn") src_array+=("https://raw.githubusercontent.com/mayaxcn/china-ip-list/main/china_ip_list.txt") ;;
                esac
            done
            echo "${src_array[@]}"
            ;;
        *) echo "https://raw.githubusercontent.com/metowolf/iplist/master/data/country/${country}.txt" ;;
    esac
}

download_geo_ip() {
    local country_code=$1
    local ipset_name=$2
    log "INFO" "下载 $country_code IP列表 (来源: $SOURCES)..."

    local cache_file="$CONFIG_DIR/ip_$country_code.cache"
    local cache_age=$([ -f "$cache_file" ] && echo $(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) )) || echo 999999)
    if [ "$cache_age" -lt 86400 ] && [ -s "$cache_file" ]; then
        log "INFO" "使用缓存 (年龄: $(($cache_age / 3600))h)"
        cat "$cache_file"
    else
        if [ "$NFT_MODE" = "true" ]; then
            nft delete set ip $TABLE_NAME $ipset_name 2>/dev/null
            nft add set ip $TABLE_NAME $ipset_name { type ipv4_addr\; flags interval\; }
        else
            ipset destroy "$ipset_name" 2>/dev/null
            local est_size=10000
            ipset create "$ipset_name" hash:net maxelem $((est_size * 2)) 2>/dev/null || log "ERROR" "创建 ipset 失败"
        fi

        local merged_file=$(mktemp)
        local count=0
        local sources=($(get_sources "$country_code"))
        for source in "${sources[@]}"; do
            local temp_file=$(mktemp)
            if curl -sL --connect-timeout 10 --max-time 30 --retry 3 "$source" -o "$temp_file"; then
                if [ -s "$temp_file" ]; then
                    grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]{1,2})?$' "$temp_file" >> "$merged_file"
                    log "INFO" "从 $source 添加 (估算 $(wc -l < "$temp_file") 条)"
                fi
            fi
            rm -f "$temp_file"
        done

        sort -u "$merged_file" -o "$merged_file"
        count=$(wc -l < "$merged_file")

        while read -r ip; do
            [[ -n "$ip" ]] && {
                if [ "$NFT_MODE" = "true" ]; then
                    nft add element ip $TABLE_NAME $ipset_name { "$ip" } 2>/dev/null
                else
                    ipset add "$ipset_name" "$ip" 2>/dev/null
                fi
            }
        done < "$merged_file"

        cp "$merged_file" "$cache_file"
        rm -f "$merged_file"
        log "INFO" "合并完成: $count 条唯一规则"
    fi

    if [ "$ENABLE_IPV6" = "true" ]; then
        local ip6set_name="${IPSET_NAME}_v6"
        local ipv6_sources=("https://www.ipdeny.com/ipblocks/data/countries/${country_code}-ipv6.zone")
        log "INFO" "IPv6加载 (来源: ipdeny, ~2000条)"
    fi
}

update_ip() {
    download_geo_ip "$COUNTRY" "$IPSET_NAME" || return 1
}

init_chain() {
    if [ "$NFT_MODE" = "true" ]; then
        nft add table ip $TABLE_NAME 2>/dev/null || true
        nft add chain ip $TABLE_NAME $CHAIN_NAME { type filter hook input priority 0 \; policy drop \; } 2>/dev/null || true
        if [ "$DEFAULT_DENY" = "true" ]; then
            nft add rule ip $TABLE_NAME $CHAIN_NAME ct state established,related accept
            nft add rule ip $TABLE_NAME $CHAIN_NAME iif lo accept
        fi
    else
        iptables -N "$CHAIN_NAME" 2>/dev/null || true
        iptables -F "$CHAIN_NAME"
        iptables -I INPUT 1 -j "$CHAIN_NAME"
        if [ "$DEFAULT_DENY" = "true" ]; then
            iptables -P INPUT DROP
            iptables -A INPUT -i lo -j ACCEPT
            iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        fi
        if [ "$ENABLE_IPV6" = "true" ]; then
            ip6tables -N "$CHAIN_NAME" 2>/dev/null || true
            ip6tables -F "$CHAIN_NAME"
            ip6tables -I INPUT 1 -j "$CHAIN_NAME"
            ip6tables -P INPUT DROP
            ip6tables -A INPUT -i lo -j ACCEPT
        fi
    fi
    setup_ufw_geo
}

clear_port_rules() {
    local port_range=$1
    if [ "$NFT_MODE" = "true" ]; then
        for p in tcp udp; do
            nft delete rule ip $TABLE_NAME $CHAIN_NAME handle $(nft -a list chain ip $TABLE_NAME $CHAIN_NAME | grep "$p dport $port_range.*$IPSET_NAME" | awk '{print $NF}' | head -1) 2>/dev/null
        done
    else
        for p in tcp udp; do
            iptables -D "$CHAIN_NAME" -p $p --dport "$port_range" -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null
            iptables -D "$CHAIN_NAME" -p $p --dport "$port_range" -m set --match-set "$IPSET_NAME" src -j ACCEPT 2>/dev/null
            iptables -D "$CHAIN_NAME" -p $p --dport "$port_range" -j DROP 2>/dev/null
            iptables -D "$CHAIN_NAME" -p $p --dport "$port_range" -j ACCEPT 2>/dev/null
            if [ "$ENABLE_IPV6" = "true" ]; then
                ip6tables -D "$CHAIN_NAME" -p $p --dport "$port_range" -m set --match-set "${IPSET_NAME}_v6" src -j DROP 2>/dev/null
            fi
        done
    fi
}

apply_rule() {
    local port_range=$1 protocol=$2 mode=$3
    local backup_file=$(backup_rules)
    clear_port_rules "$port_range"
    local success=true

    for p in tcp udp; do
        if [ "$protocol" = "$p" ] || [ "$protocol" = "both" ]; then
            case $mode in
                "blacklist")
                    if [ "$NFT_MODE" = "true" ]; then
                        nft add rule ip $TABLE_NAME $CHAIN_NAME ip protocol $p $p dport $port_range ip saddr @$IPSET_NAME drop || success=false
                    else
                        iptables -I "$CHAIN_NAME" -p $p --dport "$port_range" -m set --match-set "$IPSET_NAME" src -j DROP || success=false
                    fi
                    log "INFO" "$p 端口 $port_range: 阻止 $COUNTRY IP"
                    ;;
                "whitelist")
                    if [ "$NFT_MODE" = "true" ]; then
                        nft add rule ip $TABLE_NAME $CHAIN_NAME ip protocol $p $p dport $port_range ip saddr @$IPSET_NAME accept
                        nft add rule ip $TABLE_NAME $CHAIN_NAME ip protocol $p $p dport $port_range drop || success=false
                    else
                        iptables -I "$CHAIN_NAME" -p $p --dport "$port_range" -m set --match-set "$IPSET_NAME" src -j ACCEPT || success=false
                        iptables -I "$CHAIN_NAME" -p $p --dport "$port_range" -j DROP || success=false
                    fi
                    log "INFO" "$p 端口 $port_range: 仅允许 $COUNTRY IP"
                    ;;
            esac
            if [ "$NFT_MODE" = "true" ]; then
                nft add rule ip $TABLE_NAME $CHAIN_NAME log prefix "PORT_DROP: " || true
            else
                iptables -I "$CHAIN_NAME" 1 -j LOG --log-prefix "PORT_DROP: " || true
            fi
            if [ "$ENABLE_IPV6" = "true" ]; then
                :
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
            if [ "$NFT_MODE" = "true" ]; then
                nft add rule ip $TABLE_NAME $CHAIN_NAME ip protocol $p $p dport $port_range drop || log "ERROR" "屏蔽规则失败: $p $port_range"
            else
                iptables -I "$CHAIN_NAME" -p $p --dport "$port_range" -j DROP || log "ERROR" "屏蔽规则失败: $p $port_range"
            fi
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
            if [ "$NFT_MODE" = "true" ]; then
                nft add rule ip $TABLE_NAME $CHAIN_NAME ip protocol $p $p dport $port_range accept || log "ERROR" "放行规则失败: $p $port_range"
            else
                iptables -I "$CHAIN_NAME" -p $p --dport "$port_range" -j ACCEPT || log "ERROR" "放行规则失败: $p $port_range"
            fi
            log "INFO" "已放行 $p 端口 $port_range"
        fi
    done
    save_rules
}

validate_config_line() {
    local line=$1
    local port_range=$(echo "$line" | awk '{print $1}')
    local protocol=$(echo "$line" | awk '{print $2}')
    local mode=$(echo "$line" | awk '{print $3}')
    if ! [[ "$port_range" =~ ^[1-9][0-9]{0,4}(-[1-9][0-9]{0,4})?$ ]] || [ "${port_range%%-*}" -gt 65535 ]; then
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
    if [ "$UFW_MODE" = "true" ]; then
        ufw reload
    fi
}

show_rules() {
    echo -e "${BLUE}==================== 当前防火墙规则 ====================${NC}"
    if [ "$NFT_MODE" = "true" ]; then
        nft list chain ip $TABLE_NAME $CHAIN_NAME || echo "(nft规则空)"
    else
        iptables -L "$CHAIN_NAME" -n -v --line-numbers || echo "(iptables规则空)"
    fi
    echo -e "${BLUE}=======================================================${NC}"
    tail -5 "$LOG_FILE" | sed 's/^/日志: /'
}

clear_all_rules() {
    log "WARN" "正在清除所有规则..."
    backup_rules
    if [ "$NFT_MODE" = "true" ]; then
        nft flush chain ip $TABLE_NAME $CHAIN_NAME 2>/dev/null || true
        nft delete chain ip $TABLE_NAME $CHAIN_NAME 2>/dev/null || true
    else
        iptables -F "$CHAIN_NAME" 2>/dev/null || true
        iptables -D INPUT -j "$CHAIN_NAME" 2>/dev/null || true
        ipset destroy "$IPSET_NAME" 2>/dev/null || true
        if [ "$ENABLE_IPV6" = "true" ]; then
            ip6tables -F "$CHAIN_NAME" 2>/dev/null || true
            ip6tables -D INPUT -j "$CHAIN_NAME" 2>/dev/null || true
            ipset destroy "${IPSET_NAME}_v6" 2>/dev/null || true
        fi
    fi
    if [ "$DEFAULT_DENY" = "true" ]; then
        iptables -P INPUT ACCEPT
        ip6tables -P INPUT ACCEPT 2>/dev/null || true
    fi
    save_rules
    log "INFO" "已清除所有规则"
}

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
            ip6tables-restore < "$backup_file"
        fi
    fi
    log "INFO" "规则从 $backup_file 恢复"
}

show_stats() {
    echo -e "${BLUE}==================== 流量统计 ====================${NC}"
    if command -v ipset >/dev/null && ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        ipset xstats "$IPSET_NAME" 2>/dev/null | head -5 || echo "ipset统计不可用"
    fi
    if [ "$NFT_MODE" = "true" ]; then
        nft list ruleset | grep counter || echo "(nft无计数器)"
    else
        iptables -L INPUT -n -v | grep -E "pkts|bytes" | head -5 || echo "(iptables暂无统计)"
    fi
    echo -e "${BLUE}=======================================================${NC}"
}

scan_ports() {
    local port_range=$1
    echo -e "${BLUE}扫描端口 $port_range...${NC}"
    nmap -p "$port_range" --open localhost -sV || log "WARN" "nmap失败，确保安装"
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
    echo -e "${GREEN}8.${NC} 配置国家/定时/IPv6/nft/UFW/默认拒绝"
    echo -e "${GREEN}9.${NC} 备份/恢复规则"
    echo -e "${GREEN}10.${NC} 查看流量统计"
    echo -e "${GREEN}11.${NC} 配置Fail2Ban"
    echo -e "${GREEN}12.${NC} 端口诊断扫描"
    echo -e "${GREEN}13.${NC} 优化IP源 (多源合并)"
    echo -e "${GREEN}14.${NC} 一键安装脚本"
    echo -e "${GREEN}15.${NC} 一键卸载脚本"
    echo -e "${GREEN}0.${NC} 退出"
    echo ""
    echo -ne "${YELLOW}请选择操作 [0-15]: ${NC}"
}

#==================== 主逻辑 ====================#

main() {
    check_root
    check_stdin

    # 处理命令行参数 (新: 支持 install/uninstall)
    case "$1" in
        "install")
            install_script
            exit 0
            ;;
        "uninstall")
            uninstall_script
            exit 0
            ;;
        "update_ip")
            load_config
            update_ip
            exit $?
            ;;
        "backup")
            load_config
            echo $(backup_rules)
            exit 0
            ;;
        "restore") 
            if [ -n "$2" ]; then
                load_config
                restore_rules "$2"
                exit $?
            fi
            ;;
    esac

    load_config
    install_dependencies  # 首次运行安装依赖
    setup_cron
    init_chain

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
                echo "  nft: $NFT_MODE"
                echo "  默认拒绝: $DEFAULT_DENY"
                echo "  UFW: $UFW_MODE"
                echo ""
                echo "输入新国家代码 (留空保持 $COUNTRY):"
                read new_country < /dev/tty
                [[ -n "$new_country" ]] && sed -i "s/^COUNTRY=.*/COUNTRY=$new_country/" "$CONFIG_FILE"
                echo "输入IP来源 (逗号分隔, 留空保持 $SOURCES):"
                read new_sources < /dev/tty
                [[ -n "$new_sources" ]] && sed -i "s/^SOURCES=.*/SOURCES=$new_sources/" "$CONFIG_FILE"
                echo "启用IPv6? (y/n):"
                read ipv6_choice < /dev/tty
                [[ "$ipv6_choice" =~ ^[Yy]$ ]] && sed -i 's/^ENABLE_IPV6=.*/ENABLE_IPV6=true/' "$CONFIG_FILE"
                [[ "$ipv6_choice" =~ ^[Nn]$ ]] && sed -i 's/^ENABLE_IPV6=.*/ENABLE_IPV6=false/' "$CONFIG_FILE"
                echo "启用nft? (y/n):"
                read nft_choice < /dev/tty
                [[ "$nft_choice" =~ ^[Yy]$ ]] && sed -i 's/^NFT_MODE=.*/NFT_MODE=true/' "$CONFIG_FILE"
                [[ "$nft_choice" =~ ^[Nn]$ ]] && sed -i 's/^NFT_MODE=.*/NFT_MODE=false/' "$CONFIG_FILE"
                echo "启用默认拒绝? (y/n):"
                read deny_choice < /dev/tty
                [[ "$deny_choice" =~ ^[Yy]$ ]] && sed -i 's/^DEFAULT_DENY=.*/DEFAULT_DENY=true/' "$CONFIG_FILE"
                [[ "$deny_choice" =~ ^[Nn]$ ]] && sed -i 's/^DEFAULT_DENY=.*/DEFAULT_DENY=false/' "$CONFIG_FILE"
                echo "启用UFW? (y/n):"
                read ufw_choice < /dev/tty
                [[ "$ufw_choice" =~ ^[Yy]$ ]] && sed -i 's/^UFW_MODE=.*/UFW_MODE=true/' "$CONFIG_FILE"
                [[ "$ufw_choice" =~ ^[Nn]$ ]] && sed -i 's/^UFW_MODE=.*/UFW_MODE=false/' "$CONFIG_FILE"
                load_config
                setup_cron
                init_chain
                if [ "$ENABLE_IPV6" = "true" ]; then
                    update_ip
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
            11)
                setup_fail2ban
                read -p "按回车继续..." < /dev/tty
                ;;
            12)
                echo "请输入端口范围扫描 (例如: 80 或 22-25):"
                read port_range < /dev/tty
                scan_ports "$port_range"
                read -p "按回车继续..." < /dev/tty
                ;;
            13)
                echo "当前来源: $SOURCES"
                echo "可用CN源: metowolf,17mon,mayaxcn (逗号分隔)"
                read new_sources < /dev/tty
                [[ -n "$new_sources" ]] && sed -i "s/^SOURCES=.*/SOURCES=$new_sources/" "$CONFIG_FILE"
                load_config
                update_ip
                read -p "按回车继续..." < /dev/tty
                ;;
            14)
                install_script
                read -p "按回车继续..." < /dev/tty
                ;;
            15)
                uninstall_script
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
