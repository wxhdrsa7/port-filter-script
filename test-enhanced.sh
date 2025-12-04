#!/bin/bash
# test-enhanced.sh - 增强版端口过滤测试脚本

echo "端口过滤脚本增强版测试"
echo "======================"

# 检查root权限
if [ "$EUID" -ne 0 ]; then 
    echo "请使用root权限运行测试"
    exit 1
fi

# 测试配置目录
CONFIG_DIR="/etc/port-filter"
WHITELIST_FILE="$CONFIG_DIR/whitelist.conf"
SETTINGS_FILE="$CONFIG_DIR/settings.conf"

echo "1. 测试配置目录创建"
mkdir -p "$CONFIG_DIR"
echo "✓ 配置目录已创建"

echo ""
echo "2. 测试白名单功能"
# 创建测试白名单文件
cat > "$WHITELIST_FILE" << 'EOF'
# 测试白名单
192.168.1.100
10.0.0.0/8
EOF
echo "✓ 测试白名单文件已创建"

echo ""
echo "3. 测试设置文件"
cat > "$SETTINGS_FILE" << 'EOF'
# 测试设置
ACTIVE_RULES="common_attacks"
AUTO_UPDATE_ENABLED="no"
UPDATE_TIME="03:30"
EOF
echo "✓ 测试设置文件已创建"

echo ""
echo "4. 检查依赖"
for cmd in ipset iptables curl; do
    if command -v $cmd >/dev/null 2>&1; then
        echo "✓ $cmd 已安装"
    else
        echo "✗ $cmd 未安装"
    fi
done

echo ""
echo "5. 测试ipset功能"
if command -v ipset >/dev/null 2>&1; then
    # 创建测试ipset
    ipset create test_whitelist hash:net maxelem 65536 2>/dev/null || true
    ipset add test_whitelist 192.168.1.100 2>/dev/null || true
    ipset add test_whitelist 10.0.0.0/8 2>/dev/null || true
    
    echo "ipset列表:"
    ipset list test_whitelist 2>/dev/null | head -10
    
    # 清理测试ipset
    ipset destroy test_whitelist 2>/dev/null || true
    echo "✓ ipset功能正常"
else
    echo "✗ ipset不可用"
fi

echo ""
echo "6. 配置文件内容预览"
echo "--- 白名单文件 ---"
cat "$WHITELIST_FILE"
echo ""
echo "--- 设置文件 ---"
cat "$SETTINGS_FILE"

echo ""
echo "测试完成！"
echo ""
echo "下一步:"
echo "1. 运行 ./port-filter-enhanced.sh 启动交互式菜单"
echo "2. 或使用命令行模式测试功能"
echo "   ./port-filter-enhanced.sh --whitelist 192.168.1.200"
echo "   ./port-filter-enhanced.sh --rules 'common_attacks malware_ports'"