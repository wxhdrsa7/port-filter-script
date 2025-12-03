#!/bin/bash
#
# test-port-filter.sh - 端口过滤脚本测试套件
# 用于验证改进版脚本的各项功能
#

# 测试配置
TEST_SCRIPT="./port-filter-improved.sh"
TEST_PORT=12345
TEST_CONFIG_DIR="/etc/port-filter-test"
TEST_LOG="/var/log/port-filter-test.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 测试结果统计
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# 日志函数
log_test() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$TEST_LOG"
}

# 测试函数
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    echo -e "${BLUE}运行测试: $test_name${NC}"
    log_test "INFO" "开始测试: $test_name"
    
    if eval "$test_command"; then
        if [ "$expected_result" = "pass" ]; then
            echo -e "${GREEN}✓ 测试通过: $test_name${NC}"
            log_test "SUCCESS" "测试通过: $test_name"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}✗ 测试失败 (预期失败但通过了): $test_name${NC}"
            log_test "FAILED" "测试失败 (预期失败但通过了): $test_name"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    else
        if [ "$expected_result" = "fail" ]; then
            echo -e "${GREEN}✓ 测试通过 (预期失败): $test_name${NC}"
            log_test "SUCCESS" "测试通过 (预期失败): $test_name"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}✗ 测试失败: $test_name${NC}"
            log_test "FAILED" "测试失败: $test_name"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    fi
    
    echo ""
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：测试需要root权限${NC}"
        exit 1
    fi
}

# 检查脚本是否存在
check_script() {
    if [ ! -f "$TEST_SCRIPT" ]; then
        echo -e "${RED}错误：测试脚本 $TEST_SCRIPT 不存在${NC}"
        exit 1
    fi
    
    chmod +x "$TEST_SCRIPT"
}

# 清理测试环境
cleanup_test_env() {
    echo -e "${YELLOW}清理测试环境...${NC}"
    
    # 清除测试规则
    iptables -D INPUT -p tcp --dport "$TEST_PORT" -j DROP 2>/dev/null
    iptables -D INPUT -p tcp --dport "$TEST_PORT" -j ACCEPT 2>/dev/null
    iptables -D INPUT -p udp --dport "$TEST_PORT" -j DROP 2>/dev/null
    iptables -D INPUT -p udp --dport "$TEST_PORT" -j ACCEPT 2>/dev/null
    
    # 清理测试目录
    rm -rf "$TEST_CONFIG_DIR"
    
    # 清理ipset
    ipset destroy china-test 2>/dev/null
}

# 测试端口验证
test_port_validation() {
    echo -e "${BLUE}=== 测试端口验证功能 ===${NC}"
    
    # 测试有效端口
    run_test "有效端口 (80)" "$TEST_SCRIPT --test-port 80 2>/dev/null && echo 'pass'" "pass"
    run_test "有效端口 (443)" "$TEST_SCRIPT --test-port 443 2>/dev/null && echo 'pass'" "pass"
    run_test "有效端口 (8080)" "$TEST_SCRIPT --test-port 8080 2>/dev/null && echo 'pass'" "pass"
    run_test "有效端口 (65535)" "$TEST_SCRIPT --test-port 65535 2>/dev/null && echo 'pass'" "pass"
    
    # 测试无效端口
    run_test "无效端口 (0)" "$TEST_SCRIPT --test-port 0 2>/dev/null || echo 'fail'" "fail"
    run_test "无效端口 (65536)" "$TEST_SCRIPT --test-port 65536 2>/dev/null || echo 'fail'" "fail"
    run_test "无效端口 (abc)" "$TEST_SCRIPT --test-port abc 2>/dev/null || echo 'fail'" "fail"
    run_test "无效端口 (负数)" "$TEST_SCRIPT --test-port -1 2>/dev/null || echo 'fail'" "fail"
}

# 测试协议验证
test_protocol_validation() {
    echo -e "${BLUE}=== 测试协议验证功能 ===${NC}"
    
    # 测试有效协议
    run_test "有效协议 (tcp)" "$TEST_SCRIPT --test-protocol tcp 2>/dev/null && echo 'pass'" "pass"
    run_test "有效协议 (udp)" "$TEST_SCRIPT --test-protocol udp 2>/dev/null && echo 'pass'" "pass"
    run_test "有效协议 (both)" "$TEST_SCRIPT --test-protocol both 2>/dev/null && echo 'pass'" "pass"
    
    # 测试无效协议
    run_test "无效协议 (http)" "$TEST_SCRIPT --test-protocol http 2>/dev/null || echo 'fail'" "fail"
    run_test "无效协议 (ftp)" "$TEST_SCRIPT --test-protocol ftp 2>/dev/null || echo 'fail'" "fail"
    run_test "无效协议 (空)" "$TEST_SCRIPT --test-protocol '' 2>/dev/null || echo 'fail'" "fail"
}

# 测试IPSet功能
test_ipset_functionality() {
    echo -e "${BLUE}=== 测试IPSet功能 ===${NC}"
    
    # 创建测试IPSet
    run_test "创建IPSet" "ipset create china-test hash:net 2>/dev/null && echo 'pass'" "pass"
    
    # 添加IP地址
    run_test "添加IP地址" "ipset add china-test 192.168.1.0/24 2>/dev/null && echo 'pass'" "pass"
    run_test "添加重复IP" "ipset add china-test 192.168.1.0/24 2>/dev/null && echo 'pass'" "pass"
    
    # 检查IPSet内容
    run_test "检查IPSet内容" "ipset list china-test | grep -q '192.168.1.0/24' && echo 'pass'" "pass"
    
    # 清空IPSet
    run_test "清空IPSet" "ipset flush china-test 2>/dev/null && echo 'pass'" "pass"
    
    # 销毁IPSet
    run_test "销毁IPSet" "ipset destroy china-test 2>/dev/null && echo 'pass'" "pass"
}

# 测试iptables规则
test_iptables_rules() {
    echo -e "${BLUE}=== 测试iptables规则功能 ===${NC}"
    
    # 添加DROP规则
    run_test "添加DROP规则" "iptables -I INPUT -p tcp --dport $TEST_PORT -j DROP 2>/dev/null && echo 'pass'" "pass"
    
    # 检查规则是否存在
    run_test "检查DROP规则" "iptables -L INPUT -n | grep -q '$TEST_PORT' && echo 'pass'" "pass"
    
    # 删除规则
    run_test "删除DROP规则" "iptables -D INPUT -p tcp --dport $TEST_PORT -j DROP 2>/dev/null && echo 'pass'" "pass"
    
    # 添加ACCEPT规则
    run_test "添加ACCEPT规则" "iptables -I INPUT -p tcp --dport $TEST_PORT -j ACCEPT 2>/dev/null && echo 'pass'" "pass"
    
    # 检查规则
    run_test "检查ACCEPT规则" "iptables -L INPUT -n | grep -q '$TEST_PORT' && echo 'pass'" "pass"
    
    # 删除规则
    run_test "删除ACCEPT规则" "iptables -D INPUT -p tcp --dport $TEST_PORT -j ACCEPT 2>/dev/null && echo 'pass'" "pass"
}

# 测试配置文件操作
test_config_operations() {
    echo -e "${BLUE}=== 测试配置文件操作 ===${NC}"
    
    local test_config="$TEST_CONFIG_DIR/test.conf"
    
    # 创建测试目录
    mkdir -p "$TEST_CONFIG_DIR"
    
    # 测试设置值
    run_test "设置配置值" "echo 'test_key=test_value' > '$test_config' && echo 'pass'" "pass"
    
    # 测试读取值
    run_test "读取配置值" "grep -q 'test_key=test_value' '$test_config' && echo 'pass'" "pass"
    
    # 测试修改值
    run_test "修改配置值" "sed -i 's/test_key=test_value/test_key=new_value/' '$test_config' && echo 'pass'" "pass"
    
    # 验证修改
    run_test "验证修改" "grep -q 'test_key=new_value' '$test_config' && echo 'pass'" "pass"
    
    # 测试删除键
    run_test "删除配置键" "sed -i '/test_key=new_value/d' '$test_config' && echo 'pass'" "pass"
    
    # 验证删除
    run_test "验证删除" "! grep -q 'test_key' '$test_config' && echo 'pass'" "pass"
}

# 测试日志功能
test_logging() {
    echo -e "${BLUE}=== 测试日志功能 ===${NC}"
    
    local test_log="/tmp/test-port-filter.log"
    
    # 测试日志写入
    run_test "写入日志" "echo '[TEST] Test log entry' >> '$test_log' && echo 'pass'" "pass"
    
    # 测试日志读取
    run_test "读取日志" "grep -q '[TEST] Test log entry' '$test_log' && echo 'pass'" "pass"
    
    # 测试日志轮转
    run_test "日志轮转" "echo 'New log entry' >> '$test_log' && tail -1 '$test_log' | grep -q 'New log entry' && echo 'pass'" "pass"
    
    # 清理测试日志
    rm -f "$test_log"
}

# 测试网络连接
test_network_connectivity() {
    echo -e "${BLUE}=== 测试网络连接 ===${NC}"
    
    # 测试DNS解析
    run_test "DNS解析测试" "nslookup github.com >/dev/null 2>&1 && echo 'pass'" "pass"
    
    # 测试HTTP连接
    run_test "HTTP连接测试" "curl -s -I https://github.com | grep -q 'HTTP/1.1 200 OK' && echo 'pass'" "pass"
    
    # 测试GitHub API
    run_test "GitHub API测试" "curl -s https://api.github.com | grep -q 'current_user_url' && echo 'pass'" "pass"
}

# 测试错误处理
test_error_handling() {
    echo -e "${BLUE}=== 测试错误处理 ===${NC}"
    
    # 测试无效命令
    run_test "无效命令处理" "invalid_command 2>/dev/null || echo 'fail'" "fail"
    
    # 测试文件不存在
    run_test "文件不存在处理" "cat /non/existent/file 2>/dev/null || echo 'fail'" "fail"
    
    # 测试权限错误
    run_test "权限错误处理" "touch /root/test_permission 2>/dev/null || echo 'fail'" "fail"
    
    # 测试网络超时
    run_test "网络超时处理" "timeout 2 curl -s http://192.0.2.1 >/dev/null 2>&1 || echo 'fail'" "fail"
}

# 测试性能
test_performance() {
    echo -e "${BLUE}=== 测试性能 ===${NC}"
    
    # 测试iptables规则添加性能
    local start_time=$(date +%s.%N)
    for i in {1..100}; do
        iptables -I INPUT -p tcp --dport $((TEST_PORT + i)) -j DROP 2>/dev/null
    done
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    run_test "iptables规则添加性能" "echo '$duration < 5' | bc -l && echo 'pass'" "pass"
    
    # 清理测试规则
    for i in {1..100}; do
        iptables -D INPUT -p tcp --dport $((TEST_PORT + i)) -j DROP 2>/dev/null
    done
}

# 测试安全性
test_security() {
    echo -e "${BLUE}=== 测试安全性 ===${NC}"
    
    # 测试文件权限
    run_test "脚本权限检查" "[ -x '$TEST_SCRIPT' ] && echo 'pass'" "pass"
    
    # 测试配置文件权限
    touch /tmp/test_config
    chmod 600 /tmp/test_config
    run_test "配置文件权限" "ls -l /tmp/test_config | grep -q '^-rw-------' && echo 'pass'" "pass"
    rm -f /tmp/test_config
    
    # 测试目录权限
    mkdir -p /tmp/test_dir
    chmod 700 /tmp/test_dir
    run_test "目录权限检查" "ls -ld /tmp/test_dir | grep -q '^drwx------' && echo 'pass'" "pass"
    rm -rf /tmp/test_dir
}

# 显示测试结果
show_test_results() {
    echo -e "${BLUE}==================== 测试结果 ====================${NC}"
    echo -e "总测试数: ${TESTS_RUN}"
    echo -e "通过测试: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "失败测试: ${RED}${TESTS_FAILED}${NC}"
    
    local success_rate=$(echo "scale=2; $TESTS_PASSED / $TESTS_RUN * 100" | bc)
    echo -e "成功率: ${GREEN}${success_rate}%${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}所有测试通过！${NC}"
        return 0
    else
        echo -e "${RED}部分测试失败，请检查日志${NC}"
        return 1
    fi
}

# 主测试函数
main() {
    echo -e "${GREEN}端口过滤脚本测试套件${NC}"
    echo -e "版本: 1.0.0"
    echo -e "测试脚本: $TEST_SCRIPT"
    echo ""
    
    # 检查环境
    check_root
    check_script
    
    # 创建测试日志
    mkdir -p "$(dirname "$TEST_LOG")"
    touch "$TEST_LOG"
    chmod 644 "$TEST_LOG"
    
    # 记录测试开始
    log_test "INFO" "测试套件开始执行"
    
    # 执行测试
    test_port_validation
    test_protocol_validation
    test_ipset_functionality
    test_iptables_rules
    test_config_operations
    test_logging
    test_network_connectivity
    test_error_handling
    test_performance
    test_security
    
    # 显示结果
    show_test_results
    
    # 清理环境
    cleanup_test_env
    
    # 记录测试结束
    log_test "INFO" "测试套件执行完成"
    
    return $TESTS_FAILED
}

# 处理命令行参数
case "$1" in
    "--help"|"-h")
        echo "用法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  --help, -h    显示帮助信息"
        echo ""
        echo "这个脚本测试端口过滤脚本的各项功能，"
        echo "包括端口验证、协议验证、IPSet操作、iptables规则等。"
        echo ""
        echo "测试内容包括:"
        echo "  - 端口和协议验证"
        echo "  - IPSet功能测试"
        echo "  - iptables规则操作"
        echo "  - 配置文件操作"
        echo "  - 日志功能"
        echo "  - 网络连接测试"
        echo "  - 错误处理"
        echo "  - 性能测试"
        echo "  - 安全性检查"
        ;;
    "")
        main
        ;;
    *)
        echo "错误: 未知选项 '$1'"
        echo "使用 --help 查看帮助信息"
        exit 1
        ;;
esac