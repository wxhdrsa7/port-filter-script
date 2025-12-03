# 快速安装指南

## 一键安装脚本

```bash
#!/bin/bash
# Linux端口过滤系统 - 一键安装脚本

set -e

echo "=== Linux端口过滤系统安装开始 ==="

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo "错误: 必须以root权限运行"
    exit 1
fi

# 安装依赖
echo "安装依赖包..."
if command -v apt-get &> /dev/null; then
    # Ubuntu/Debian
    apt-get update
    apt-get install -y iptables ipset curl wget jq awk grep sed
elif command -v yum &> /dev/null; then
    # CentOS/RHEL
    yum install -y iptables ipset curl wget jq awk grep sed
else
    echo "错误: 不支持的操作系统"
    exit 1
fi

# 下载主脚本
echo "下载主脚本..."
curl -s -o /usr/local/bin/port-filter https://raw.githubusercontent.com/your-repo/port-filter/master/port-filter-master.sh
chmod +x /usr/local/bin/port-filter

# 创建符号链接
ln -sf /usr/local/bin/port-filter /usr/local/bin/pf

echo "=== 安装完成 ==="
echo "使用方法:"
echo "  port-filter          # 启动交互式菜单"
echo "  port-filter wizard   # 快速配置向导"
echo "  port-filter status   # 查看系统状态"
echo ""
echo "首次使用建议运行快速向导:"
echo "  port-filter wizard"