#!/bin/bash
# 端口过滤脚本启动器

echo "启动端口过滤脚本..."
echo "="*40

# 检查Python3是否安装
if ! command -v python3 &> /dev/null; then
    echo "错误: Python3 未安装"
    exit 1
fi

# 运行主程序
python3 port_filter.py

echo "程序已退出"