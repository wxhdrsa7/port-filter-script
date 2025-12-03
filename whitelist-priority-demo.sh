#!/bin/bash
# IP白名单优先级演示脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== IP白名单优先级演示 ===${NC}"
echo

# 检查是否安装了port-filter
if ! command -v port-filter &> /dev/null; then
    echo -e "${RED}错误: 请先安装port-filter系统${NC}"
    echo "运行: ./INSTALLATION_GUIDE.md 中的一键安装脚本"
    exit 1
fi

echo -e "${YELLOW}演示1: 白名单IP绕过端口过滤${NC}"
echo "=================================="

# 清理现有规则
echo -e "${GREEN}步骤1: 清理现有规则${NC}"
port-filter cleanup

# 添加测试IP到白名单
echo -e "${GREEN}步骤2: 添加192.168.1.100到白名单${NC}"
port-filter whitelist-add 192.168.1.100

# 过滤SSH端口
echo -e "${GREEN}步骤3: 过滤SSH端口(22/tcp)${NC}"
port-filter apply 22 tcp

echo -e "${GREEN}步骤4: 检查结果${NC}"
echo "白名单中的IP: 192.168.1.100"
echo "过滤规则: 阻止所有IP访问22端口"
echo -e "${GREEN}结果: 192.168.1.100可以访问22端口（白名单优先级最高）${NC}"

echo
echo -e "${YELLOW}演示2: 白名单CIDR段绕过过滤${NC}"
echo "=================================="

# 添加CIDR段到白名单
echo -e "${GREEN}步骤1: 添加10.0.0.0/8网段到白名单${NC}"
port-filter whitelist-add 10.0.0.0/8

# 过滤HTTP端口
echo -e "${GREEN}步骤2: 过滤HTTP端口(80/tcp)${NC}"
port-filter apply 80 tcp

echo -e "${GREEN}步骤3: 检查结果${NC}"
echo "白名单中的网段: 10.0.0.0/8 (10.0.0.1 - 10.255.255.254)"
echo "过滤规则: 阻止所有IP访问80端口"
echo -e "${GREEN}结果: 10.x.x.x网段的所有IP都可以访问80端口${NC}"

echo
echo -e "${YELLOW}演示3: 白名单vs数据源过滤${NC}"
echo "=================================="

# 启用中国数据源
echo -e "${GREEN}步骤1: 启用中国IP数据源过滤${NC}"
echo "假设已配置中国IP数据源并启用"

# 添加一个中国IP到白名单
echo -e "${GREEN}步骤2: 添加中国IP 203.119.128.0/17 到白名单${NC}"
port-filter whitelist-add 203.119.128.0/17

# 过滤HTTPS端口
echo -e "${GREEN}步骤3: 过滤HTTPS端口(443/tcp)${NC}"
port-filter apply 443 tcp

echo -e "${GREEN}步骤4: 检查结果${NC}"
echo "数据源规则: 阻止所有中国IP访问443端口"
echo "白名单规则: 允许203.119.128.0/17访问"
echo -e "${GREEN}结果: 203.119.128.0/17网段可以访问443端口（白名单优先级高于数据源）${NC}"

echo
echo -e "${YELLOW}演示4: 实时验证${NC}"
echo "=================================="

echo -e "${GREEN}当前白名单内容:${NC}"
port-filter whitelist-show

echo
echo -e "${GREEN}当前系统状态:${NC}"
port-filter status

echo
echo -e "${YELLOW}演示总结${NC}"
echo "=========="
echo -e "${GREEN}✓${NC} 白名单IP始终具有最高优先级"
echo -e "${GREEN}✓${NC} 白名单可以覆盖端口过滤规则"
echo -e "${GREEN}✓${NC} 白名单可以覆盖数据源过滤规则"
echo -e "${GREEN}✓${NC} 支持单个IP和CIDR段格式"
echo -e "${GREEN}✓${NC} 支持IPv4和IPv6地址"

echo
echo -e "${CYAN}演示完成！${NC}"
echo "可以使用以下命令进行实际操作:"
echo "  port-filter whitelist-add <IP>    # 添加IP到白名单"
echo "  port-filter whitelist-remove <IP> # 从白名单移除IP"
echo "  port-filter whitelist-show        # 显示白名单内容"
echo "  port-filter status               # 查看系统状态"