#!/bin/bash
# port_filter.sh - 端口访问控制一键脚本（优化版）
# 支持：IP地域过滤、端口屏蔽/放行、TCP/UDP协议控制、自动更新

VERSION="1.1.0"
CONFIG_DIR="/etc/port-filter"
CONFIG_FILE="$CONFIG_DIR/config.conf"
IPSET_NAME="china"
IP_CACHE_FILE="$CONFIG_DIR/china_ip.txt"
CRON_SCRIPT="/usr/local/bin/update-china-ip.sh"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}错误：请使用 root 权限运行此脚本${NC}"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${BLUE}检查并安装依赖...${NC}"
    
    if ! command -v ipset &> /dev/null; then
        echo "正在安装 ipset 和 iptables-persistent..."
        apt-get update -qq
        apt-get install -y ipset iptables-persistent curl cron > /dev/null 2>&1
    fi
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    echo -e "${GREEN}✓ 依赖安装完成${NC}"
}

# 下载中国IP列表（带重试和多源）
download_china_ip() {
    echo -e "${BLUE}下载中国IP列表...${NC}"
    
    # IP列表源（按优先级）
    local sources=(
        "https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt"
        "https://cdn.jsdelivr.net/gh/metowolf/iplist/data/country/CN.txt"
        "https://raw.gitmirror.com/metowolf/iplist/master/data/country/CN.txt"
    )
    
    local TEMP_FILE=$(mktemp)
    local downloaded=0
    
    # 尝试从多个源下载
    for source in "${sources[@]}"; do
        echo -e "${YELLOW}尝试从源下载: $(echo $source | cut -d'/' -f3)${NC}"
        
        if timeout 30 curl -sL --retry 2 --retry-delay 2 "$source" -o "$TEMP_FILE" 2>/dev/null; then
            # 验证文件是否有效
            if [ -s "$TEMP_FILE" ] && head -1 "$TEMP_FILE" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
                downloaded=1
                echo -e "${GREEN}✓ 下载成功${NC}"
                break
            fi
        fi
        
        echo -e "${YELLOW}× 该源失败，尝试下一个...${NC}"
    done
    
    if [ $downloaded -eq 0 ]; then
        # 如果都失败，尝试使用缓存
        if [ -f "$IP_CACHE_FILE" ]; then
            echo -e "${YELLOW}⚠ 所有源下载失败，使用缓存文件${NC}"
            cp "$IP_CACHE_FILE" "$TEMP_FILE"
        else
            echo -e "${RED}✗ 下载失败且无缓存，无法继续${NC}"
            rm -f "$TEMP_FILE"
            return 1
        fi
    else
        # 保存到缓存
        cp "$TEMP_FILE" "$IP_CACHE_FILE"
    fi
    
    # 导入到ipset
    ipset destroy "$IPSET_NAME" 2>/dev/null
    ipset create "$IPSET_NAME" hash:net maxelem 100000
    
    local COUNT=0
    echo -e "${YELLOW}导入IP规则...${NC}"
    
    while read -r ip; do
        if [ -n "$ip" ] && [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
            ipset add "$IPSET_NAME" "$ip" 2>/dev/null && ((COUNT++))
        fi
    done < "$TEMP_FILE"
    
    rm -f "$TEMP_FILE"
    
    if [ $COUNT -gt 0 ]; then
        echo -e "${GREEN}✓ 成功导入 $COUNT 条IP规则${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S'): 成功导入 $COUNT 条规则" >> "$CONFIG_DIR/update.log"
        return 0
    else
        echo -e "${RED}✗ 导入失败${NC}"
        return 1
    fi
}

# 创建自动更新脚本
create_auto_update_script() {
    cat > "$CRON_SCRIPT" <<'SCRIPT_EOF'
#!/bin/bash
# 自动更新中国IP列表

CONFIG_DIR="/etc/port-filter"
IPSET_NAME="china"
IP_CACHE_FILE="$CONFIG_DIR/china_ip.txt"
LOG_FILE="$CONFIG_DIR/update.log"

echo "$(date '+%Y-%m-%d %H:%M:%S'): 开始自动更新" >> "$LOG_FILE"

# IP列表源
sources=(
    "https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt"
    "https://cdn.jsdelivr.net/gh/metowolf/iplist/data/country/CN.txt"
    "https://raw.gitmirror.com/metowolf/iplist/master/data/country/CN.txt"
)

TEMP_FILE=$(mktemp)
downloaded=0

for source in "${sources[@]}"; do
    if timeout 30 curl -sL --retry 2 "$source" -o "$TEMP_FILE" 2>/dev/null; then
        if [ -s "$TEMP_FILE" ] && head -1 "$TEMP_FILE" | grep -qE '^[0-9]+\.[0-9]+'; then
            downloaded=1
            break
        fi
    fi
done

if [ $downloaded -eq 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): 下载失败，使用缓存" >> "$LOG_FILE"
    rm -f "$TEMP_FILE"
    exit 1
fi

# 保存缓存
cp "$TEMP_FILE" "$IP_CACHE_FILE"

# 更新ipset
ipset destroy "$IPSET_NAME" 2>/dev/null
ipset create "$IPSET_NAME" hash:net maxelem 100000

COUNT=0
while read -r ip; do
    if [ -n "$ip" ] && [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        ipset add "$IPSET_NAME" "$ip" 2>/dev/null && ((COUNT++))
    fi
done < "$TEMP_FILE"

rm -f "$TEMP_FILE"

# 重新应用规则
if [ -f "$CONFIG_DIR/config.conf" ]; then
    while IFS='|' read -r port protocol mode action; do
        if [ "$action" = "geo_filter" ]; then
            # 重新应用地域过滤规则
            /usr/local/bin/port_filter.sh reapply "$port" "$protocol" "$mode" 2>/dev/null
        fi
    done < "$CONFIG_DIR/config.conf"
fi

echo "$(date '+%Y-%m-%d %H:%M:%S'): 更新完成，导入 $COUNT 条规则" >> "$LOG_FILE"
SCRIPT_EOF

    chmod +x "$CRON_SCRIPT"
    echo -e "${GREEN}✓ 自动更新脚本已创建${NC}"
}

# 设置定时任务
setup_cron() {
    create_auto_update_script
    
    # 检查是否已有定时任务
    if crontab -l 2>/dev/null | grep -q "$CRON_SCRIPT"; then
        echo -e "${YELLOW}定时任务已存在${NC}"
        return
    fi
    
    # 添加定时任务（每周日凌晨3点更新）
    (crontab -l 2>/dev/null; echo "0 3 * * 0 $CRON_SCRIPT") | crontab -
    
    echo -e "${GREEN}✓ 已设置自动更新（每周日凌晨3点）${NC}"
}

# 移除定时任务
remove_cron() {
    crontab -l 2>/dev/null | grep -v "$CRON_SCRIPT" | crontab -
    rm -f "$CRON_SCRIPT"
    echo -e "${GREEN}✓ 已移除自动更新任务${NC}"
}

# 保存配置
save_config() {
    local port=$1
    local protocol=$2
    local mode=$3
    local action=$4
    
    # 先删除该端口的旧配置
    if [ -f "$CONFIG_FILE" ]; then
        sed -i "/^${port}|/d" "$CONFIG_FILE"
    fi
    
    # 添加新配置
    echo "${port}|${protocol}|${mode}|${action}" >> "$CONFIG_FILE"
}

# 清除端口的所有规则
clear_port_rules() {
    local port=$1
    
    # 清除所有相关规则
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
    
    # 先清除该端口的旧规则
    clear_port_rules "$port"
    
    if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
        if [ "$mode" = "blacklist" ]; then
            iptables -I INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_NAME" src -j DROP
            echo -e "${GREEN}✓ TCP端口 $port: 黑名单（阻止中国IP）${NC}"
        elif [ "$mode" = "whitelist" ]; then
            iptables -I INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_NAME" src -j ACCEPT
            iptables -I INPUT -p tcp --dport "$port" -j DROP
            echo -e "${GREEN}✓ TCP端口 $port: 白名单（仅允许中国IP）${NC}"
        fi
    fi
    
    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        if [ "$mode" = "blacklist" ]; then
            iptables -I INPUT -p udp --dport "$port" -m set --match-set "$IPSET_NAME" src -j DROP
            echo -e "${GREEN}✓ UDP端口 $port: 黑名单（阻止中国IP）${NC}"
        elif [ "$mode" = "whitelist" ]; then
            iptables -I INPUT -p udp --dport "$port" -m set --match-set "$IPSET_NAME" src -j ACCEPT
            iptables -I INPUT -p udp --dport "$port" -j DROP
            echo -e "${GREEN}✓ UDP端口 $port: 白名单（仅允许中国IP）${NC}"
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
        echo -e "${GREEN}✓ 已屏蔽 TCP 端口 $port${NC}"
    fi
    
    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p udp --dport "$port" -j DROP
        echo -e "${GREEN}✓ 已屏蔽 UDP 端口 $port${NC}"
    fi
}

# 放行端口
allow_port() {
    local port=$1
    local protocol=$2
    
    clear_port_rules "$port"
    
    if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
        echo -e "${GREEN}✓ 已放行 TCP 端口 $port${NC}"
    fi
    
    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p udp --dport "$port" -j ACCEPT
        echo -e "${GREEN}✓ 已放行 UDP 端口 $port${NC}"
    fi
}

# 查看当前规则
show_rules() {
    echo -e "${BLUE}==================== 当前防火墙规则 ====================${NC}"
    echo -e "${YELLOW}TCP 规则：${NC}"
    iptables -L INPUT -n -v --line-numbers | grep "tcp dpt:" || echo "  无TCP规则"
    echo ""
    echo -e "${YELLOW}UDP 规则：${NC}"
    iptables -L INPUT -n -v --line-numbers | grep "udp dpt:" || echo "  无UDP规则"
    echo ""
    echo -e "${YELLOW}IPSet 状态：${NC}"
    if ipset list "$IPSET_NAME" &>/dev/null; then
        local count=$(ipset list "$IPSET_NAME" | grep -c '^[0-9]')
        echo "  中国IP数量: $count"
    else
        echo "  未加载IP列表"
    fi
    echo ""
    echo -e "${YELLOW}自动更新状态：${NC}"
    if crontab -l 2>/dev/null | grep -q "$CRON_SCRIPT"; then
        echo "  已启用（每周日凌晨3点更新）"
        if [ -f "$CONFIG_DIR/update.log" ]; then
            echo "  最后更新: $(tail -1 "$CONFIG_DIR/update.log" 2>/dev/null || echo '无记录')"
        fi
    else
        echo "  未启用"
    fi
    echo -e "${BLUE}=======================================================${NC}"
}

# 保存规则
save_rules() {
    netfilter-persistent save > /dev/null 2>&1
}

# 清除所有规则
clear_all_rules() {
    echo -e "${YELLOW}正在清除所有规则...${NC}"
    
    iptables -S INPUT | grep "$IPSET_NAME" | cut -d " " -f 2- | while read -r rule; do
        iptables -D INPUT $rule 2>/dev/null
    done
    
    ipset destroy "$IPSET_NAME" 2>/dev/null
    
    rm -f "$CONFIG_FILE" "$IP_CACHE_FILE"
    
    remove_cron
    save_rules
    
    echo -e "${GREEN}✓ 所有规则已清除${NC}"
}

# 主菜单
show_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      端口访问控制脚本 v${VERSION}              ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} IP地域过滤（黑名单/白名单）"
    echo -e "${GREEN}2.${NC} 屏蔽端口（完全阻止访问）"
    echo -e "${GREEN}3.${NC} 放行端口（完全允许访问）"
    echo -e "${GREEN}4.${NC} 查看当前规则"
    echo -e "${GREEN}5.${NC} 清除所有规则"
    echo -e "${GREEN}6.${NC} 手动更新中国IP列表"
    echo -e "${GREEN}7.${NC} 设置自动更新"
    echo -e "${GREEN}8.${NC} 移除自动更新"
    echo -e "${GREEN}0.${NC} 退出"
    echo ""
    echo -ne "${YELLOW}请选择操作 [0-8]: ${NC}"
}

# IP地域过滤设置
setup_geo_filter() {
    echo -e "${BLUE}==================== IP地域过滤设置 ====================${NC}"
    
    # 检查是否已下载IP列表
    if ! ipset list "$IPSET_NAME" &>/dev/null; then
        echo -e "${YELLOW}首次使用需要下载IP列表，请稍候...${NC}"
        if ! download_china_ip; then
            echo -e "${RED}IP列表加载失败，无法继续${NC}"
            return 1
        fi
    fi
    
    read -p "请输入端口号: " port
    
    # 验证端口号
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}无效的端口号${NC}"
        return 1
    fi
    
    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -p "请选择 [1-3]: " proto_choice
    
    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) echo -e "${RED}无效选择${NC}"; return 1 ;;
    esac
    
    echo "选择模式："
    echo "1. 黑名单（阻止中国IP，允许其他地区）"
    echo "2. 白名单（仅允许中国IP，阻止其他地区）"
    read -p "请选择 [1-2]: " mode_choice
    
    case $mode_choice in
        1) mode="blacklist" ;;
        2) mode="whitelist" ;;
        *) echo -e "${RED}无效选择${NC}"; return 1 ;;
    esac
    
    apply_rule "$port" "$protocol" "$mode"
    save_config "$port" "$protocol" "$mode" "geo_filter"
    save_rules
    
    echo ""
    echo -e "${GREEN}✓ 规则已生效并保存${NC}"
}

# 屏蔽端口设置
setup_block_port() {
    echo -e "${BLUE}==================== 屏蔽端口 ====================${NC}"
    
    read -p "请输入要屏蔽的端口号: " port
    
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}无效的端口号${NC}"
        return 1
    fi
    
    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -p "请选择 [1-3]: " proto_choice
    
    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) echo -e "${RED}无效选择${NC}"; return 1 ;;
    esac
    
    block_port "$port" "$protocol"
    save_config "$port" "$protocol" "block" "block"
    save_rules
    
    echo ""
    echo -e "${GREEN}✓ 端口已屏蔽${NC}"
}

# 放行端口设置
setup_allow_port() {
    echo -e "${BLUE}==================== 放行端口 ====================${NC}"
    
    read -p "请输入要放行的端口号: " port
    
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}无效的端口号${NC}"
        return 1
    fi
    
    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -p "请选择 [1-3]: " proto_choice
    
    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) echo -e "${RED}无效选择${NC}"; return 1 ;;
    esac
    
    allow_port "$port" "$protocol"
    save_config "$port" "$protocol" "allow" "allow"
    save_rules
    
    echo ""
    echo -e "${GREEN}✓ 端口已放行${NC}"
}

# 主程序
main() {
    check_root
    install_dependencies
    
    # 处理命令行参数（用于自动更新脚本调用）
    if [ "$1" = "reapply" ]; then
        apply_rule "$2" "$3" "$4"
        exit 0
    fi
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1)
                setup_geo_filter
                read -p "按回车继续..."
                ;;
            2)
                setup_block_port
                read -p "按回车继续..."
                ;;
            3)
                setup_allow_port
                read -p "按回车继续..."
                ;;
            4)
                show_rules
                read -p "按回车继续..."
                ;;
            5)
                read -p "确认清除所有规则？(y/N): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    clear_all_rules
                fi
                read -p "按回车继续..."
                ;;
            6)
                download_china_ip
                save_rules
                read -p "按回车继续..."
                ;;
            7)
                setup_cron
                read -p "按回车继续..."
                ;;
            8)
                remove_cron
                read -p "按回车继续..."
                ;;
            0)
                echo -e "${GREEN}再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重试${NC}"
                sleep 2
                ;;
        esac
    done
}

# 运行主程序
main "$@"
