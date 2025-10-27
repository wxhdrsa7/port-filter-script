#!/bin/bash
# install.sh - 端口访问控制脚本一键安装器
# 使用方法：bash <(curl -sL http://your-domain.com/install.sh)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ===== 配置区域 - 修改这里 =====
SCRIPT_URL="https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main/port_filter.sh"
SCRIPT_NAME="port_filter.sh"
INSTALL_DIR="/usr/local/bin"
VERSION="1.1.0"
# ================================

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    端口访问控制脚本 - 一键安装器 v${VERSION}     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

# 检查root权限
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}错误：请使用 root 权限运行${NC}"
    echo ""
    echo "正确使用方法："
    echo -e "${YELLOW}  sudo bash <(curl -sL ${SCRIPT_URL%/*}/install.sh)${NC}"
    echo -e "${YELLOW}  或${NC}"
    echo -e "${YELLOW}  sudo bash <(wget -qO- ${SCRIPT_URL%/*}/install.sh)${NC}"
    exit 1
fi

# 检测系统
echo -e "${YELLOW}[1/5] 检测系统...${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    echo -e "${GREEN}✓ 系统: $PRETTY_NAME${NC}"
else
    echo -e "${RED}✗ 无法检测系统类型${NC}"
    exit 1
fi

# 检查网络连接
echo -e "${YELLOW}[2/5] 检查网络连接...${NC}"
if curl -s --connect-timeout 5 --max-time 10 "${SCRIPT_URL%/*}" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 网络连接正常${NC}"
else
    echo -e "${RED}✗ 无法连接到服务器${NC}"
    echo "请检查："
    echo "  1. 服务器地址是否正确"
    echo "  2. 网络连接是否正常"
    echo "  3. 防火墙是否阻止访问"
    exit 1
fi

# 下载主脚本
echo -e "${YELLOW}[3/5] 下载主脚本...${NC}"
TEMP_SCRIPT=$(mktemp)

if curl -sL --max-time 30 "$SCRIPT_URL" -o "$TEMP_SCRIPT"; then
    # 验证文件
    if [ -s "$TEMP_SCRIPT" ] && head -1 "$TEMP_SCRIPT" | grep -q "^#!/bin/bash"; then
        echo -e "${GREEN}✓ 下载成功 ($(du -h "$TEMP_SCRIPT" | cut -f1))${NC}"
    else
        echo -e "${RED}✗ 文件损坏或格式错误${NC}"
        rm -f "$TEMP_SCRIPT"
        exit 1
    fi
else
    echo -e "${RED}✗ 下载失败${NC}"
    echo "URL: $SCRIPT_URL"
    rm -f "$TEMP_SCRIPT"
    exit 1
fi

# 安装脚本
echo -e "${YELLOW}[4/5] 安装脚本...${NC}"

# 备份旧版本
if [ -f "$INSTALL_DIR/$SCRIPT_NAME" ]; then
    cp "$INSTALL_DIR/$SCRIPT_NAME" "$INSTALL_DIR/${SCRIPT_NAME}.backup.$(date +%Y%m%d%H%M%S)"
    echo -e "${BLUE}  已备份旧版本${NC}"
fi

# 安装新版本
cp "$TEMP_SCRIPT" "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
rm -f "$TEMP_SCRIPT"

echo -e "${GREEN}✓ 安装完成${NC}"

# 创建快捷命令
echo -e "${YELLOW}[5/5] 创建快捷命令...${NC}"

# 创建软链接
ln -sf "$INSTALL_DIR/$SCRIPT_NAME" /usr/local/bin/pf 2>/dev/null || true
ln -sf "$INSTALL_DIR/$SCRIPT_NAME" /usr/local/bin/port-filter 2>/dev/null || true

echo -e "${GREEN}✓ 快捷命令已创建${NC}"

# 完成提示
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              🎉 安装成功！                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}使用方法（任选其一）：${NC}"
echo -e "  ${YELLOW}port_filter.sh${NC}    # 完整命令"
echo -e "  ${YELLOW}port-filter${NC}       # 短命令"
echo -e "  ${YELLOW}pf${NC}                # 最短命令"
echo ""
echo -e "${GREEN}常用功能：${NC}"
echo -e "  • IP地域过滤（黑/白名单）"
echo -e "  • 端口屏蔽/放行"
echo -e "  • 支持 TCP/UDP"
echo -e "  • 自动更新IP列表"
echo ""
echo -e "${BLUE}立即启动？${NC}"
read -p "按回车启动，或输入 n 退出: " start_now

if [ "$start_now" != "n" ] && [ "$start_now" != "N" ]; then
    exec "$INSTALL_DIR/$SCRIPT_NAME"
else
    echo ""
    echo -e "${BLUE}稍后可运行以下任一命令启动：${NC}"
    echo -e "  ${YELLOW}pf${NC}"
    echo ""
fi
