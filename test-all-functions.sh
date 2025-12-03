#!/bin/bash
# 端口过滤系统完整功能测试脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 测试结果计数
TESTS_PASSED=0
TESTS_FAILED=0

# 测试函数
test_case() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    echo -e "${BLUE}测试: $test_name${NC}"
    
    if eval "$test_command"; then
        echo -e "  ${GREEN}✓ 通过${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "  ${RED}✗ 失败${NC}"
        echo "  期望: $expected_result"
        ((TESTS_FAILED++))
        return 1
    fi
}

# 检查依赖
check_dependencies() {
    echo -e "${CYAN}=== 检查系统依赖 ===${NC}"
    
    test_case "检查iptables" "command -v iptables" "iptables已安装"
    test_case "检查ipset" "command -v ipset" "ipset已安装"
    test_case "检查curl" "command -v curl" "curl已安装"
    test_case "检查port-filter" "command -v port-filter" "port-filter已安装"
}

# 测试IP白名单功能
test_whitelist() {
    echo -e "${CYAN}=== 测试IP白名单功能 ===${NC}"
    
    # 清理环境
    port-filter cleanup 2>/dev/null || true
    
    # 测试1: 添加单个IPv4地址
    test_case "添加IPv4地址到白名单" \
        "port-filter whitelist-add 192.168.1.100 && grep -q '192.168.1.100' /etc/port-filter/whitelist.conf" \
        "IP地址已添加到白名单文件"
    
    # 测试2: 添加CIDR段
    test_case "添加CIDR段到白名单" \
        "port-filter whitelist-add 10.0.0.0/8 && grep -q '10.0.0.0/8' /etc/port-filter/whitelist.conf" \
        "CIDR段已添加到白名单文件"
    
    # 测试3: 添加IPv6地址
    test_case "添加IPv6地址到白名单" \
        "port-filter whitelist-add 2001:db8::1 && grep -q '2001:db8::1' /etc/port-filter/whitelist.conf" \
        "IPv6地址已添加到白名单文件"
    
    # 测试4: 无效IP格式
    test_case "拒绝无效IP格式" \
        "! port-filter whitelist-add 999.999.999.999" \
        "无效IP被拒绝"
    
    # 测试5: 显示白名单
    test_case "显示白名单内容" \
        "port-filter whitelist-show | grep -q '192.168.1.100'" \
        "白名单内容显示正常"
    
    # 测试6: 移除IP
    test_case "从白名单移除IP" \
        "port-filter whitelist-remove 192.168.1.100 && ! grep -q '192.168.1.100' /etc/port-filter/whitelist.conf" \
        "IP已从白名单移除"
}

# 测试端口过滤功能
test_port_filter() {
    echo -e "${CYAN}=== 测试端口过滤功能 ===${NC}"
    
    # 清理环境
    port-filter cleanup 2>/dev/null || true
    
    # 测试1: 应用端口过滤
    test_case "应用端口80过滤" \
        "port-filter apply 80 tcp" \
        "端口80过滤规则已应用"
    
    # 测试2: 验证iptables规则
    test_case "验证iptables规则存在" \
        "iptables -L INPUT -n | grep -q '80'" \
        "iptables规则已创建"
    
    # 测试3: 移除端口过滤
    test_case "移除端口80过滤" \
        "port-filter remove 80 tcp" \
        "端口80过滤规则已移除"
    
    # 测试4: 验证规则已删除
    test_case "验证iptables规则已删除" \
        "! iptables -L INPUT -n | grep -q 'dpt:80'" \
        "iptables规则已删除"
}

# 测试白名单优先级
test_whitelist_priority() {
    echo -e "${CYAN}=== 测试白名单优先级 ===${NC}"
    
    # 清理环境
    port-filter cleanup 2>/dev/null || true
    
    # 添加IP到白名单
    port-filter whitelist-add 192.168.1.100
    
    # 应用端口过滤
    port-filter apply 22 tcp
    
    # 测试1: 白名单规则优先级
    test_case "白名单规则在INPUT链首位" \
        "iptables -L INPUT --line-numbers | head -5 | grep -q 'ACCEPT' && iptables -L INPUT --line-numbers | head -5 | grep -q 'whitelist'" \
        "白名单规则具有最高优先级"
    
    # 测试2: 白名单IPSet存在
    test_case "白名单IPSet已创建" \
        "ipset list whitelist_ips >/dev/null 2>&1" \
        "白名单IPSet已创建"
    
    # 测试3: IP在白名单集合中
    test_case "IP在白名单集合中" \
        "ipset test whitelist_ips 192.168.1.100 >/dev/null 2>&1" \
        "IP已在白名单集合中"
}

# 测试数据源管理
test_datasources() {
    echo -e "${CYAN}=== 测试数据源管理 ===${NC}"
    
    # 测试1: 数据源配置文件存在
    test_case "数据源配置文件存在" \
        "[[ -f /etc/port-filter/datasources.conf ]]" \
        "数据源配置文件已创建"
    
    # 测试2: 数据源格式正确
    test_case "数据源格式正确" \
        "grep -q 'china|https://iplist.cc/code/cn' /etc/port-filter/datasources.conf" \
        "默认数据源配置正确"
}

# 测试系统管理
test_system_management() {
    echo -e "${CYAN}=== 测试系统管理功能 ===${NC}"
    
    # 测试1: 系统状态
    test_case "系统状态正常" \
        "port-filter status | grep -q 'port-filter'" \
        "系统状态显示正常"
    
    # 测试2: 创建备份
    test_case "创建系统备份" \
        "port-filter backup && ls -la /var/backups/port-filter/backup_*.tar.gz" \
        "备份文件已创建"
    
    # 测试3: 配置文件存在
    test_case "配置文件存在" \
        "[[ -f /etc/port-filter/config.conf ]] && [[ -f /etc/port-filter/whitelist.conf ]]" \
        "配置文件已创建"
    
    # 测试4: 日志文件
    test_case "日志文件存在" \
        "[[ -f /var/log/port-filter/port-filter.log ]]" \
        "日志文件已创建"
}

# 测试IPv6支持
test_ipv6() {
    echo -e "${CYAN}=== 测试IPv6支持 ===${NC}"
    
    # 检查IPv6是否启用
    if grep -q "IPV6_ENABLED=true" /etc/port-filter/config.conf; then
        # 测试1: IPv6白名单
        test_case "添加IPv6地址到白名单" \
            "port-filter whitelist-add 2001:db8::/32" \
            "IPv6地址已添加到白名单"
        
        # 测试2: IPv6 IPSet
        test_case "IPv6 IPSet已创建" \
            "ipset list whitelist_ips6 >/dev/null 2>&1" \
            "IPv6白名单IPSet已创建"
    else
        echo -e "  ${YELLOW}IPv6未启用，跳过IPv6测试${NC}"
    fi
}

# 测试错误处理
test_error_handling() {
    echo -e "${CYAN}=== 测试错误处理 ===${NC}"
    
    # 测试1: 无效端口号
    test_case "拒绝无效端口号" \
        "! port-filter apply 99999 tcp" \
        "无效端口号被拒绝"
    
    # 测试2: 无效协议
    test_case "拒绝无效协议" \
        "! port-filter apply 80 invalid" \
        "无效协议被拒绝"
    
    # 测试3: 重复添加相同IP
    test_case "重复添加相同IP有警告" \
        "port-filter whitelist-add 192.168.1.101 && port-filter whitelist-add 192.168.1.101 2>&1 | grep -q '已存在'" \
        "重复添加有适当警告"
}

# 运行所有测试
main() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}    端口过滤系统功能测试开始          ${NC}"
    echo -e "${CYAN}========================================${NC}"
    
    # 初始化测试环境
    echo -e "${YELLOW}初始化测试环境...${NC}"
    mkdir -p /etc/port-filter /var/log/port-filter /var/backups/port-filter
    
    # 运行测试
    check_dependencies
    test_whitelist
    test_port_filter
    test_whitelist_priority
    test_datasources
    test_system_management
    test_ipv6
    test_error_handling
    
    # 显示测试结果
    echo
echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}    测试结果汇总                      ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "${GREEN}通过: $TESTS_PASSED${NC}"
    echo -e "${RED}失败: $TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}所有测试通过！系统功能正常。${NC}"
        return 0
    else
        echo -e "${RED}有 $TESTS_FAILED 个测试失败，请检查系统配置。${NC}"
        return 1
    fi
}

# 执行测试
main "$@"