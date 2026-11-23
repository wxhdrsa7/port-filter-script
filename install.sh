#!/bin/bash
# install.sh - 一键安装端口防火墙脚本（增强版）
# 作者：你 + GPT
# 仓库：https://github.com/wxhdrsa7/port-filter-script

set -e

SCRIPT_URL="https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main/port-filter.sh"
INSTALL_URL="https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main/install.sh"
INSTALL_PATH="/usr/local/bin/port-filter"

# 安装位置只有 root 能写入，先检查权限再下载
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m错误：请使用 root 权限运行，例如：\033[0m"
    echo -e "\033[0;31m  sudo bash <(curl -fsSL $INSTALL_URL)\033[0m"
    exit 1
fi

echo -e "\033[1;34m[1/3] 下载增强版脚本...\033[0m"
# 先下载到临时文件并确认内容完整，再替换已经安装的旧版本，
# 避免网络出错时把原来的脚本覆盖成空文件
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT
# -f：HTTP 错误码直接判为失败，不会把 404 页面当成脚本保存下来
if ! curl -fsSL --connect-timeout 10 --max-time 120 "$SCRIPT_URL" -o "$TMP_FILE"; then
    echo -e "\033[0;31m错误：下载失败，请检查网络后重试：$SCRIPT_URL\033[0m"
    exit 1
fi
if [ ! -s "$TMP_FILE" ] || ! head -n 1 "$TMP_FILE" | grep -q '^#!/bin/bash'; then
    echo -e "\033[0;31m错误：下载到的内容不是脚本，已取消安装\033[0m"
    exit 1
fi
install -m 755 "$TMP_FILE" "$INSTALL_PATH"

echo -e "\033[1;32m✓ 下载完成，脚本已安装到：$INSTALL_PATH\033[0m"

echo -e "\033[1;34m[2/3] 检查依赖...\033[0m"
if ! command -v ipset &>/dev/null || ! command -v iptables &>/dev/null; then
    if command -v apt-get &>/dev/null; then
        # 这里装不上的依赖，port-filter.sh 启动时还会再试一次并给出提示，所以不在这里中断
        apt-get update -qq || true
        apt-get install -y ipset iptables-persistent curl > /dev/null 2>&1 \
            || echo "    部分依赖没能自动安装，脚本启动时会再次尝试"
    else
        echo "    本系统没有 apt-get，请手动安装 ipset 和 iptables"
    fi
    echo -e "\033[1;32m✓ 依赖检查完成\033[0m"
else
    echo -e "\033[1;32m✓ 依赖已存在\033[0m"
fi

echo -e "\033[1;34m[3/3] 启动防火墙菜单...\033[0m"
# 前面已经确认是 root，直接运行（精简系统里可能没有 sudo）
bash "$INSTALL_PATH"

echo ""
echo "安装完成！"
echo "功能："
echo "  • IP地域过滤（仅允许中国IP / 阻止中国IP）"
echo "  • 端口屏蔽 / 放行（TCP / UDP）"
echo "  • IP白名单管理（支持单个IP和IP段）"
echo "  • 中国IP数据源选择、定时自动更新"
echo "  • 命令行快速添加白名单：sudo port-filter --whitelist 192.168.1.100"
echo ""
echo "使用方法："
echo "  sudo port-filter                    # 启动交互式菜单"
echo "  sudo port-filter --whitelist IP     # 添加IP到白名单"
echo "  sudo port-filter --update-ip        # 立即更新中国IP列表"
