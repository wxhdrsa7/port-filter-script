#!/bin/bash
# port_filter.sh - 端口访问控制一键脚本
# 支持：IP地域过滤、端口屏蔽/放行、TCP/UDP协议控制

VERSION="1.0.0"
CONFIG_DIR="/etc/port-filter"
CONFIG_FILE="$CONFIG_DIR/config.conf"
IPSET_NAME="china"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}错误：请使用 root 权限运行此脚本${NC}"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${BLUE}[1/3] 检查并安装依赖...${NC}"
    
    if ! command -v ipset &> /dev/null; then
        apt-get update -qq
        apt-get install -y ipset iptables-persistent curl > /dev/null 2>&1
    fi
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    echo -e "${GREEN}✓ 依赖安装完成${NC}"
}

# 下载中国IP列表
download_china_ip() {
    echo -e "${BLUE}[2/3] 下载中国IP列表...${NC}"
    
    # 销毁旧的ipset
    ipset destroy "$IPSET_NAME" 2>/dev/null
    
    # 创建新的ipset
    ipset create "$IPSET_NAME" hash:net maxelem 70000
    
    # 下载IP列表
    TEMP_FILE=$(mktemp)
    if curl -sL --max-time 60 "https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt" -o "$TEMP_FILE"; then
        COUNT=0
        while read -r ip; do
            if [ -n "$ip" ]; then
                ipset add "$IPSET_NAME" "$ip" 2>/dev/null && ((COUNT++))
            fi
        done < "$TEMP_FILE"
        rm -f "$TEMP_FILE"
        echo -e "${GREEN}✓ 成功导入 $COUNT 条IP规则${NC}"
    else
        echo -e "${RED}✗ IP列表下载失败${NC}"
        rm -f "$TEMP_FILE"
        return 1
    fi
}

# 保存配置
save_config() {
    local port=$1
    local protocol=$2
    local mode=$3
    local action=$4
    
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
            # 黑名单：阻止中国IP
            iptables -I INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_NAME" src -j DROP
            echo -e "${GREEN}✓ TCP端口 $port: 已设置黑名单（阻止中国IP）${NC}"
        elif [ "$mode" = "whitelist" ]; then
            # 白名单：仅允许中国IP
            iptables -I INPUT -p tcp --dport "$port" -m set --match-set "$IPSET_NAME" src -j ACCEPT
            iptables -I INPUT -p tcp --dport "$port" -j DROP
            echo -e "${GREEN}✓ TCP端口 $port: 已设置白名单（仅允许中国IP）${NC}"
        fi
    fi
    
    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        if [ "$mode" = "blacklist" ]; then
            iptables -I INPUT -p udp --dport "$port" -m set --match-set "$IPSET_NAME" src -j DROP
            echo -e "${GREEN}✓ UDP端口 $port: 已设置黑名单（阻止中国IP）${NC}"
        elif [ "$mode" = "whitelist" ]; then
            iptables -I INPUT -p udp --dport "$port" -m set --match-set "$IPSET_NAME" src -j ACCEPT
            iptables -I INPUT -p udp --dport "$port" -j DROP
            echo -e "${GREEN}✓ UDP端口 $port: 已设置白名单（仅允许中国IP）${NC}"
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
    iptables -L INPUT -n -v --line-numbers | grep "tcp dpt:" | head -20
    echo ""
    echo -e "${YELLOW}UDP 规则：${NC}"
    iptables -L INPUT -n -v --line-numbers | grep "udp dpt:" | head -20
    echo -e "${BLUE}=======================================================${NC}"
}

# 保存规则
save_rules() {
    echo -e "${BLUE}[3/3] 保存防火墙规则...${NC}"
    netfilter-persistent save > /dev/null 2>&1
    echo -e "${GREEN}✓ 规则已保存${NC}"
}

# 清除所有规则
clear_all_rules() {
    echo -e "${YELLOW}正在清除所有规则...${NC}"
    
    # 清除所有与ipset相关的规则
    iptables -S INPUT | grep "$IPSET_NAME" | cut -d " " -f 2- | while read -r rule; do
        iptables -D INPUT $rule 2>/dev/null
    done
    
    # 删除ipset
    ipset destroy "$IPSET_NAME" 2>/dev/null
    
    # 清除配置文件
    rm -f "$CONFIG_FILE"
    
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
    echo -e "${GREEN}6.${NC} 更新中国IP列表"
    echo -e "${GREEN}0.${NC} 退出"
    echo ""
    echo -ne "${YELLOW}请选择操作 [0-6]: ${NC}"
}

# IP地域过滤设置
setup_geo_filter() {
    echo -e "${BLUE}==================== IP地域过滤设置 ====================${NC}"
    
    # 检查是否已下载IP列表
    if ! ipset list "$IPSET_NAME" &>/dev/null; then
        download_china_ip
    fi
    
    read -p "请输入端口号: " port
    
    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -p "请选择 [1-3]: " proto_choice
    
    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) echo -e "${RED}无效选择${NC}"; return ;;
    esac
    
    echo "选择模式："
    echo "1. 黑名单（阻止中国IP，允许其他地区）"
    echo "2. 白名单（仅允许中国IP，阻止其他地区）"
    read -p "请选择 [1-2]: " mode_choice
    
    case $mode_choice in
        1) mode="blacklist" ;;
        2) mode="whitelist" ;;
        *) echo -e "${RED}无效选择${NC}"; return ;;
    esac
    
    apply_rule "$port" "$protocol" "$mode"
    save_config "$port" "$protocol" "$mode" "geo_filter"
    save_rules
}

# 屏蔽端口设置
setup_block_port() {
    echo -e "${BLUE}==================== 屏蔽端口 ====================${NC}"
    
    read -p "请输入要屏蔽的端口号: " port
    
    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -p "请选择 [1-3]: " proto_choice
    
    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) echo -e "${RED}无效选择${NC}"; return ;;
    esac
    
    block_port "$port" "$protocol"
    save_config "$port" "$protocol" "block" "block"
    save_rules
}

# 放行端口设置
setup_allow_port() {
    echo -e "${BLUE}==================== 放行端口 ====================${NC}"
    
    read -p "请输入要放行的端口号: " port
    
    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -p "请选择 [1-3]: " proto_choice
    
    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) echo -e "${RED}无效选择${NC}"; return ;;
    esac
    
    allow_port "$port" "$protocol"
    save_config "$port" "$protocol" "allow" "allow"
    save_rules
}

# 主程序
main() {
    check_root
    install_dependencies
    
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
main
