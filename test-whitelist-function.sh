#!/bin/bash
#
# test-whitelist-function.sh - IP白名单功能测试套件
# 专门测试IP白名单功能的各项能力
#

# 测试配置
TEST_SCRIPT="./port-filter-with-whitelist.sh"
TEST_PORT=12345
TEST_CONFIG_DIR="/etc/port-filter-test"
TEST_LOG="/var/log/whitelist-test.log"
WHITELIST_TEST_FILE="/tmp/test-whitelist-ips.txt"

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
    
    # 清理白名单
    ipset del whitelist 192.168.1.100 2>/dev/null
    ipset del whitelist 10.0.0.0/24 2>/dev/null
    ipset del whitelist 2001:db8::1 2>/dev/null
    
    # 清理测试文件
    rm -rf "$TEST_CONFIG_DIR"
    rm -f "$WHITELIST_TEST_FILE"
}

# 测试IP地址验证
test_ip_validation() {
    echo -e "${BLUE}=== 测试IP地址验证功能 ===${NC}"
    
    # 测试有效IPv4地址
    run_test "有效IPv4地址 (192.168.1.1)" "validate_ip_func '192.168.1.1' && echo 'pass'" "pass"
    run_test "有效IPv4段 (192.168.1.0/24)" "validate_ip_func '192.168.1.0/24' && echo 'pass'" "pass"
    run_test "有效IPv4地址 (10.0.0.100)" "validate_ip_func '10.0.0.100' && echo 'pass'" "pass"
    run_test "有效IPv4段 (172.16.0.0/16)" "validate_ip_func '172.16.0.0/16' && echo 'pass'" "pass"
    
    # 测试有效IPv6地址
    run_test "有效IPv6地址 (2001:db8::1)" "validate_ip_func '2001:db8::1' && echo 'pass'" "pass"
    run_test "有效IPv6段 (2001:db8::/64)" "validate_ip_func '2001:db8::/64' && echo 'pass'" "pass"
    
    # 测试无效IP地址
    run_test "无效IP地址 (256.256.256.256)" "validate_ip_func '256.256.256.256' || echo 'fail'" "fail"
    run_test "无效IP格式 (192.168.1)" "validate_ip_func '192.168.1' || echo 'fail'" "fail"
    run_test "无效IP格式 (abc.def.ghi.jkl)" "validate_ip_func 'abc.def.ghi.jkl' || echo 'fail'" "fail"
    run_test "空IP地址" "validate_ip_func '' || echo 'fail'" "fail"
}

# IP验证函数（从主脚本提取）
validate_ip_func() {
    local ip="$1"
    
    # IPv4地址验证
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
        return 0
    fi
    
    # IPv6地址验证
    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}(/[0-9]+)?$ ]] || 
       [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,6}:[0-9a-fA-F]{0,4}(/[0-9]+)?$ ]]; then
        return 0
    fi
    
    return 1
}

# 测试白名单IPSet操作
test_whitelist_ipset() {
    echo -e "${BLUE}=== 测试白名单IPSet操作 ===${NC}"
    
    # 创建白名单IPSet
    run_test "创建白名单IPSet" "ipset create whitelist hash:net 2>/dev/null && echo 'pass'" "pass"
    
    # 添加单个IP
    run_test "添加单个IPv4地址" "ipset add whitelist 192.168.1.100 2>/dev/null && echo 'pass'" "pass"
    run_test "添加单个IPv6地址" "ipset add whitelist 2001:db8::1 2>/dev/null && echo 'pass'" "pass"
    
    # 添加IP段
    run_test "添加IPv4段" "ipset add whitelist 10.0.0.0/24 2>/dev/null && echo 'pass'" "pass"
    run_test "添加IPv6段" "ipset add whitelist 2001:db8::/64 2>/dev/null && echo 'pass'" "pass"
    
    # 检查内容
    run_test "检查白名单内容" "ipset list whitelist | grep -q '192.168.1.100' && echo 'pass'" "pass"
    
    # 测试重复添加
    run_test "重复添加IP" "ipset add whitelist 192.168.1.100 2>/dev/null && echo 'pass'" "pass"
    
    # 删除IP
    run_test "删除白名单IP" "ipset del whitelist 192.168.1.100 2>/dev/null && echo 'pass'" "pass"
    
    # 检查删除结果
    run_test "检查删除结果" "! ipset list whitelist | grep -q '192.168.1.100' && echo 'pass'" "pass"
    
    # 清理
    run_test "清空白名单IPSet" "ipset flush whitelist 2>/dev/null && echo 'pass'" "pass"
    run_test "销毁白名单IPSet" "ipset destroy whitelist 2>/dev/null && echo 'pass'" "pass"
}

# 测试白名单规则优先级
test_whitelist_priority() {
    echo -e "${BLUE}=== 测试白名单规则优先级 ===${NC}"
    
    # 创建测试环境
    ipset create whitelist hash:net 2>/dev/null
    ipset create china hash:net 2>/dev/null
    ipset add china 192.168.1.0/24 2>/dev/null
    ipset add whitelist 192.168.1.100 2>/dev/null
    
    # 添加地域过滤规则（黑名单模式）
    iptables -I INPUT -p tcp --dport $TEST_PORT -m set --match-set china src -j DROP
    
    # 添加白名单规则（应该优先）
    iptables -I INPUT -p tcp --dport $TEST_PORT -m set --match-set whitelist src -j ACCEPT
    
    # 检查规则顺序（白名单规则应该在前面）
    run_test "白名单规则优先级" "iptables -L INPUT -n --line-numbers | grep -m1 'whitelist' | grep -q 'ACCEPT' && echo 'pass'" "pass"
    
    # 测试IP匹配
    run_test "白名单IP匹配测试" "iptables -L INPUT -n | grep -A1 'whitelist' | grep -q 'ACCEPT' && echo 'pass'" "pass"
    
    # 清理测试规则
    iptables -D INPUT -p tcp --dport $TEST_PORT -m set --match-set whitelist src -j ACCEPT 2>/dev/null
    iptables -D INPUT -p tcp --dport $TEST_PORT -m set --match-set china src -j DROP 2>/dev/null
    
    # 清理IPSet
    ipset flush whitelist 2>/dev/null
    ipset flush china 2>/dev/null
    ipset destroy whitelist 2>/dev/null
    ipset destroy china 2>/dev/null
}

# 测试白名单配置文件操作
test_whitelist_config() {
    echo -e "${BLUE}=== 测试白名单配置文件操作 ===${NC}"
    
    local test_whitelist_file="$TEST_CONFIG_DIR/whitelist.conf"
    
    # 创建测试目录
    mkdir -p "$TEST_CONFIG_DIR"
    
    # 测试添加白名单到文件
    run_test "添加白名单到配置文件" "echo '192.168.1.100|测试服务器' >> '$test_whitelist_file' && echo 'pass'" "pass"
    
    # 测试读取白名单文件
    run_test "读取白名单配置文件" "grep -q '192.168.1.100|测试服务器' '$test_whitelist_file' && echo 'pass'" "pass"
    
    # 测试添加多个IP
    run_test "添加多个白名单IP" "echo '10.0.0.50|内网服务器' >> '$test_whitelist_file' && echo 'pass'" "pass"
    run_test "添加IP段白名单" "echo '172.16.0.0/16|内网网段' >> '$test_whitelist_file' && echo 'pass'" "pass"
    
    # 测试从文件加载
    run_test "从配置文件加载白名单" "while IFS='|' read -r ip comment; do echo \"IP:$ip Comment:$comment\" | grep -q '192.168.1.100'; done < '$test_whitelist_file' && echo 'pass'" "pass"
    
    # 测试删除白名单
    run_test "从配置文件删除白名单" "sed -i '/192.168.1.100|测试服务器/d' '$test_whitelist_file' && echo 'pass'" "pass"
    
    # 验证删除
    run_test "验证白名单删除" "! grep -q '192.168.1.100|测试服务器' '$test_whitelist_file' && echo 'pass'" "pass"
    
    # 清理
    rm -f "$test_whitelist_file"
}

# 测试白名单持久化
test_whitelist_persistence() {
    echo -e "${BLUE}=== 测试白名单持久化 ===${NC}"
    
    # 创建持久化白名单文件
    local whitelist_file="/etc/port-filter/whitelist.conf"
    mkdir -p /etc/port-filter
    
    # 添加测试数据
    echo "192.168.1.100|测试服务器1" > "$whitelist_file"
    echo "10.0.0.0/24|内网网段" >> "$whitelist_file"
    echo "2001:db8::1|IPv6测试服务器" >> "$whitelist_file"
    
    # 测试加载白名单
    run_test "加载持久化白名单" "load_whitelist_from_file_func && echo 'pass'" "pass"
    
    # 验证IPSet内容
    run_test "验证加载的白名单IP" "ipset list whitelist | grep -q '192.168.1.100' && echo 'pass'" "pass"
    run_test "验证加载的白名单网段" "ipset list whitelist | grep -q '10.0.0.0/24' && echo 'pass'" "pass"
    
    # 清理
    rm -f "$whitelist_file"
}

# 白名单加载函数（简化版）
load_whitelist_from_file_func() {
    local whitelist_file="/etc/port-filter/whitelist.conf"
    
    if [ ! -f "$whitelist_file" ]; then
        return 0
    fi
    
    # 确保IPSet存在
    ipset create whitelist hash:net 2>/dev/null
    
    local count=0
    while IFS='|' read -r ip comment; do
        [ -z "$ip" ] && continue
        
        if validate_ip_func "$ip"; then
            if ipset add whitelist "$ip" 2>/dev/null; then
                count=$((count + 1))
            fi
        fi
    done < "$whitelist_file"
    
    return 0
}

# 测试白名单管理菜单
test_whitelist_menu() {
    echo -e "${BLUE}=== 测试白名单管理功能 ===${NC}"
    
    # 测试添加白名单（模拟用户输入）
    run_test "添加白名单IP功能" "echo -e '1\n192.168.1.200\n测试服务器2\n' | timeout 5 bash -c 'read choice; read ip; read comment; validate_ip_func \"$ip\" && echo \"pass\"'" "pass"
    
    # 测试移除白名单
    run_test "移除白名单IP功能" "ipset add whitelist 192.168.1.200 2>/dev/null && ipset del whitelist 192.168.1.200 2>/dev/null && echo 'pass'" "pass"
    
    # 测试查看白名单
    run_test "查看白名单功能" "ipset create whitelist hash:net 2>/dev/null && ipset add whitelist 192.168.1.100 2>/dev/null && ipset list whitelist | grep -q '192.168.1.100' && echo 'pass'" "pass"
}

# 测试批量导入
test_batch_import() {
    echo -e "${BLUE}=== 测试批量导入功能 ===${NC}"
    
    # 创建测试文件
    cat > "$WHITELIST_TEST_FILE" << 'EOF'
192.168.1.10 服务器1
192.168.1.20 服务器2  
10.0.0.0/24 内网网段
2001:db8::10 IPv6服务器
EOF
    
    # 测试批量导入
    run_test "批量导入白名单" "batch_import_func '$WHITELIST_TEST_FILE' && echo 'pass'" "pass"
    
    # 验证导入结果
    run_test "验证批量导入结果" "ipset list whitelist | grep -q '192.168.1.10' && echo 'pass'" "pass"
    run_test "验证批量导入网段" "ipset list whitelist | grep -q '10.0.0.0/24' && echo 'pass'" "pass"
    run_test "验证批量导入IPv6" "ipset list whitelist | grep -q '2001:db8::10' && echo 'pass'" "pass"
    
    # 清理
    rm -f "$WHITELIST_TEST_FILE"
}

# 批量导入函数（简化版）
batch_import_func() {
    local file_path="$1"
    
    if [ ! -f "$file_path" ]; then
        return 1
    fi
    
    ipset create whitelist hash:net 2>/dev/null
    
    while IFS= read -r line; do
        ip=$(echo "$line" | awk '{print $1}')
        comment=$(echo "$line" | cut -d' ' -f2-)
        if validate_ip_func "$ip"; then
            ipset add whitelist "$ip" 2>/dev/null
        fi
    done < "$file_path"
    
    return 0
}

# 测试白名单优先级场景
test_whitelist_scenarios() {
    echo -e "${BLUE}=== 测试白名单实际场景 ===${NC}"
    
    # 场景1：内网服务器访问外网服务
    run_test "内网服务器绕过地域限制" "test_scenario1 && echo 'pass'" "pass"
    
    # 场景2：合作伙伴IP访问
    run_test "合作伙伴IP优先访问" "test_scenario2 && echo 'pass'" "pass"
    
    # 场景3：管理员IP访问
    run_test "管理员IP不受限制" "test_scenario3 && echo 'pass'" "pass"
}

# 测试场景1：内网服务器
test_scenario1() {
    # 模拟内网服务器IP在黑名单网段但被单独放行
    ipset create china hash:net 2>/dev/null
    ipset create whitelist hash:net 2>/dev/null
    
    ipset add china 192.168.0.0/16 2>/dev/null  # 整个内网网段在黑名单
    ipset add whitelist 192.168.1.100 2>/dev/null  # 但特定服务器在白名单
    
    # 添加规则：先白名单ACCEPT，后黑名单DROP
    iptables -I INPUT -p tcp --dport 80 -m set --match-set whitelist src -j ACCEPT
    iptables -I INPUT -p tcp --dport 80 -m set --match-set china src -j DROP
    
    # 检查规则顺序
    local result=$(iptables -L INPUT -n --line-numbers | grep -E "(whitelist|china)" | head -1 | grep -c "ACCEPT")
    
    # 清理
    iptables -D INPUT -p tcp --dport 80 -m set --match-set whitelist src -j ACCEPT 2>/dev/null
    iptables -D INPUT -p tcp --dport 80 -m set --match-set china src -j DROP 2>/dev/null
    ipset flush whitelist 2>/dev/null
    ipset flush china 2>/dev/null
    ipset destroy whitelist 2>/dev/null
    ipset destroy china 2>/dev/null
    
    return $result
}

# 测试场景2：合作伙伴IP
test_scenario2() {
    # 模拟合作伙伴IP需要访问特定服务
    ipset create whitelist hash:net 2>/dev/null
    ipset add whitelist 203.0.113.50 2>/dev/null
    
    # 添加白名单规则
    iptables -I INPUT -p tcp --dport 8080 -m set --match-set whitelist src -j ACCEPT
    
    # 验证规则存在
    local result=$(iptables -L INPUT -n | grep -c "203.0.113.50")
    
    # 清理
    iptables -D INPUT -p tcp --dport 8080 -m set --match-set whitelist src -j ACCEPT 2>/dev/null
    ipset flush whitelist 2>/dev/null
    ipset destroy whitelist 2>/dev/null
    
    return $result
}

# 测试场景3：管理员IP
test_scenario3() {
    # 模拟管理员需要不受限制访问
    ipset create whitelist hash:net 2>/dev/null
    ipset add whitelist 198.51.100.10 2>/dev/null
    
    # 添加全端口白名单规则
    iptables -I INPUT -p tcp -m set --match-set whitelist src -j ACCEPT
    
    # 验证规则
    local result=$(iptables -L INPUT -n | grep -c "198.51.100.10")
    
    # 清理
    iptables -D INPUT -p tcp -m set --match-set whitelist src -j ACCEPT 2>/dev/null
    ipset flush whitelist 2>/dev/null
    ipset destroy whitelist 2>/dev/null
    
    return $result
}

# 显示测试结果
show_test_results() {
    echo -e "${BLUE}==================== 白名单功能测试结果 ====================${NC}"
    echo -e "总测试数: ${TESTS_RUN}"
    echo -e "通过测试: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "失败测试: ${RED}${TESTS_FAILED}${NC}"
    
    local success_rate=$(echo "scale=2; $TESTS_PASSED / $TESTS_RUN * 100" | bc)
    echo -e "成功率: ${GREEN}${success_rate}%${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}所有白名单功能测试通过！${NC}"
        return 0
    else
        echo -e "${RED}部分测试失败，请检查日志${NC}"
        return 1
    fi
}

# 主测试函数
main() {
    echo -e "${GREEN}IP白名单功能测试套件${NC}"
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
    log_test "INFO" "白名单功能测试套件开始执行"
    
    # 执行测试
    test_ip_validation
    test_whitelist_ipset
    test_whitelist_priority
    test_whitelist_config
    test_whitelist_persistence
    test_whitelist_menu
    test_batch_import
    test_whitelist_scenarios
    
    # 显示结果
    show_test_results
    
    # 清理环境
    cleanup_test_env
    
    # 记录测试结束
    log_test "INFO" "白名单功能测试套件执行完成"
    
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
        echo "这个脚本专门测试IP白名单功能的各项能力，包括："
        echo "  - IP地址格式验证"
        echo "  - IPSet操作"
        echo "  - 规则优先级"
        echo "  - 配置文件操作"
        echo "  - 持久化存储"
        echo "  - 管理菜单功能"
        echo "  - 批量导入"
        echo "  - 实际应用场景"
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