#!/bin/bash
# install.sh - 一键安装端口防火墙脚本
# 作者：你 + GPT
# 仓库：https://github.com/wxhdrsa7/port-filter-script

set -e

SCRIPT_URL="https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main/port-filter.sh"
INSTALL_PATH="/usr/local/bin/port-filter"

echo -e "\033[1;34m[1/3] 下载主脚本...\033[0m"
curl -sL "$SCRIPT_URL" -o "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

echo -e "\033[1;32m✓ 下载完成，脚本已安装到：$INSTALL_PATH\033[0m"

echo -e "\033[1;34m[2/3] 检查依赖...\033[0m"
if ! command -v ipset &>/dev/null || ! command -v iptables &>/dev/null; then
    apt-get update -qq
    apt-get install -y ipset iptables-persistent curl > /dev/null 2>&1
    echo -e "\033[1;32m✓ 依赖已安装\033[0m"
else
    echo -e "\033[1;32m✓ 依赖已存在\033[0m"
fi

echo -e "\033[1;34m[3/3] 启动防火墙菜单...\033[0m"
sudo bash "$INSTALL_PATH"
