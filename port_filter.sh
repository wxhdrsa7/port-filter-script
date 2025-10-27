#!/bin/bash
# port_filter.sh - 端口访问控制一键脚本 (增强版)
# 作者：你 + GPT
# 版本：1.1.0
# 特性：自动检测输入源、支持 bash <(curl ...) 一键运行、彩色交互菜单

VERSION="1.1.0"
CONFIG_DIR="/etc/port-filter"
CONFIG_FILE="$CONFIG_DIR/config.conf"
IPSET_NAME="china"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#==================== 基础检测 ====================#

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}✗ 错误：请使用 root 权限运行此脚本${NC}"
        exit 1
    fi
}

# 检测是否通过管道执行（stdin 非 TTY）
check_stdin() {
    if [ ! -t 0 ]; then
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
    echo -e "${BLUE}[1/3] 检查并安装依赖...${NC}"
    apt-get update -qq
    apt-get install -y ipset iptables-persistent curl > /dev/null 2>&1
    mkdir -p "$CONFIG_DIR"
    echo -e "${GREEN}✓ 依赖安装完成${NC}"
}

download_china_ip() {
    echo -e "${BLUE}[2/3] 下载中国IP列表...${NC}"
    ipset destroy "$IPSET_NAME" 2>/dev/null
    ipset create "$IPSET_NAME" hash:net maxelem 70000 2>/dev/null

    TEMP_FILE=$(mktemp)
    if curl -sL --max-time 60 "https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt" -o "$TEMP_FILE"; then
        COUNT=0
        while read -r ip; do
            [[ -n "$ip" ]] && ipset add "$IPSET_NAME" "$ip" 2>/dev/null && ((COUNT++))
        done < "$TEMP_FILE"
        rm -f "$TEMP_FILE"
        echo -e "${GREEN}✓ 成功导入 $COUNT 条 IP 规则${NC}"
    else
        echo -e "${RED}✗ 下载失败，请检查网络${NC}"
    fi
}

clear_port_rules() {
    local port=$1
    for p in tcp udp; do
        iptables -D INPUT -p $p --dport "$port" -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null
        iptables -D INPUT -p $p --dport "$port" -m set --match-set "$IPSET_NAME" src -j ACCEPT 2>/dev/null
        iptables -D INPUT -p $p --dport "$port" -j DROP 2>/dev/null
        iptables -D INPUT -p $p --dport "$port" -j ACCEPT 2>/dev/null
    done
}

apply_rule() {
    local port=$1 protocol=$2 mode=$3
    clear_port_rules "$port"

    for p in tcp udp; do
        if [ "$protocol" = "$p" ] || [ "$protocol" = "both" ]; then
            if [ "$mode" = "blacklist" ]; then
                iptables -I INPUT -p $p --dport "$port" -m set --match-set "$IPSET_NAME" src -j DROP
                echo -e "${GREEN}✓ $p 端口 $port: 阻止中国IP${NC}"
            else
                iptables -I INPUT -p $p --dport "$port" -m set --match-set "$IPSET_NAME" src -j ACCEPT
                iptables -I INPUT -p $p --dport "$port" -j DROP
                echo -e "${GREEN}✓ $p 端口 $port: 仅允许中国IP${NC}"
            fi
        fi
    done
}

block_port() {
    local port=$1 protocol=$2
    clear_port_rules "$port"
    for p in tcp udp; do
        if [ "$protocol" = "$p" ] || [ "$protocol" = "both" ]; then
            iptables -I INPUT -p $p --dport "$port" -j DROP
            echo -e "${GREEN}✓ 已屏蔽 $p 端口 $port${NC}"
        fi
    done
}

allow_port() {
    local port=$1 protocol=$2
    clear_port_rules "$port"
    for p in tcp udp; do
        if [ "$protocol" = "$p" ] || [ "$protocol" = "both" ]; then
            iptables -I INPUT -p $p --dport "$port" -j ACCEPT
            echo -e "${GREEN}✓ 已放行 $p 端口 $port${NC}"
        fi
    done
}

save_rules() {
    echo -e "${BLUE}[3/3] 保存规则...${NC}"
    netfilter-persistent save > /dev/null 2>&1
    echo -e "${GREEN}✓ 防火墙规则已保存${NC}"
}

show_rules() {
    echo -e "${BLUE}==================== 当前防火墙规则 ====================${NC}"
    iptables -L INPUT -n -v --line-numbers | grep -E "dpt:" || echo "(暂无端口规则)"
    echo -e "${BLUE}=======================================================${NC}"
}

clear_all_rules() {
    echo -e "${YELLOW}正在清除所有规则...${NC}"
    iptables -F INPUT
    ipset destroy "$IPSET_NAME" 2>/dev/null
    rm -f "$CONFIG_FILE"
    save_rules
    echo -e "${GREEN}✓ 已清除所有规则${NC}"
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
    echo -e "${GREEN}6.${NC} 更新中国IP列表"
    echo -e "${GREEN}0.${NC} 退出"
    echo ""
    echo -ne "${YELLOW}请选择操作 [0-6]: ${NC}"
}

#==================== 主逻辑 ====================#

main() {
    check_root
    check_stdin
    install_dependencies

    while true; do
        show_menu
        read choice < /dev/tty
        case $choice in
            1)
                echo "请输入端口号:"
                read port < /dev/tty
                echo "选择协议：1.TCP 2.UDP 3.同时"
                read proto_choice < /dev/tty
                case $proto_choice in
                    1) protocol="tcp" ;;
                    2) protocol="udp" ;;
                    3) protocol="both" ;;
                    *) echo "无效选择"; continue ;;
                esac
                echo "选择模式：1.黑名单(阻止中国IP) 2.白名单(仅允许中国IP)"
                read mode_choice < /dev/tty
                case $mode_choice in
                    1) mode="blacklist" ;;
                    2) mode="whitelist" ;;
                    *) echo "无效选择"; continue ;;
                esac
                download_china_ip
                apply_rule "$port" "$protocol" "$mode"
                save_rules
                read -p "按回车继续..." < /dev/tty
                ;;
            2)
                echo "请输入要屏蔽的端口号:"
                read port < /dev/tty
                echo "协议：1.TCP 2.UDP 3.同时"
                read proto_choice < /dev/tty
                case $proto_choice in
                    1) protocol="tcp" ;;
                    2) protocol="udp" ;;
                    3) protocol="both" ;;
                    *) echo "无效选择"; continue ;;
                esac
                block_port "$port" "$protocol"
                save_rules
                read -p "按回车继续..." < /dev/tty
                ;;
            3)
                echo "请输入要放行的端口号:"
                read port < /dev/tty
                echo "协议：1.TCP 2.UDP 3.同时"
                read proto_choice < /dev/tty
                case $proto_choice in
                    1) protocol="tcp" ;;
                    2) protocol="udp" ;;
                    3) protocol="both" ;;
                    *) echo "无效选择"; continue ;;
                esac
                allow_port "$port" "$protocol"
                save_rules
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
                download_china_ip
                save_rules
                read -p "按回车继续..." < /dev/tty
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

main
