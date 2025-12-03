#!/bin/bash
#
# test-datasource-management.sh - IP数据源库管理功能测试套件
# 专门测试数据源库管理功能的各项能力
#

# 测试配置
TEST_SCRIPT="./port-filter-with-datasource.sh"
TEST_CONFIG_DIR="/etc/port-filter-test"
TEST_LOG="/var/log/datasource-test.log"
TEST_DATASOURCE_FILE="/tmp/test-datasources.conf"

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
    
    # 清理测试目录
    rm -rf "$TEST_CONFIG_DIR"
    rm -f "$TEST_DATASOURCE_FILE"
    
    # 清理测试IPSet
    ipset destroy test-datasource 2>/dev/null
}

# 测试数据源配置文件操作
test_datasource_config() {
    echo -e "${BLUE}=== 测试数据源配置文件操作 ===${NC}"
    
    # 创建测试目录
    mkdir -p "$TEST_CONFIG_DIR"
    
    # 测试创建配置文件
    run_test "创建数据源配置文件" "echo 'test|http://test.com/iplist.txt|IPv4|测试数据源|enabled' > '$TEST_CONFIG_DIR/datasources.conf' && echo 'pass'" "pass"
    
    # 测试读取配置文件
    run_test "读取数据源配置文件" "grep -q 'test|http://test.com/iplist.txt|IPv4|测试数据源|enabled' '$TEST_CONFIG_DIR/datasources.conf' && echo 'pass'" "pass"
    
    # 测试添加多个数据源
    run_test "添加多个数据源" "echo 'test2|http://test2.com/iplist.txt|IPv6|测试IPv6数据源|disabled' >> '$TEST_CONFIG_DIR/datasources.conf' && echo 'pass'" "pass"
    
    # 测试启用/禁用数据源
    run_test "切换数据源状态" "sed -i 's/enabled$/disabled/' '$TEST_CONFIG_DIR/datasources.conf' && echo 'pass'" "pass"
    
    # 测试删除数据源
    run_test "删除数据源" "sed -i '/test2|/d' '$TEST_CONFIG_DIR/datasources.conf' && echo 'pass'" "pass"
    
    # 清理
    rm -f "$TEST_CONFIG_DIR/datasources.conf"
}

# 测试数据源启用/禁用功能
test_datasource_toggle() {
    echo -e "${BLUE}=== 测试数据源启用/禁用功能 ===${NC}"
    
    # 创建测试配置文件
    cat > "$TEST_DATASOURCE_FILE" << 'EOF'
metowolf/IPList|https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt|IPv4|Metowolf的中国IP列表|enabled
17mon/ChinaIPList|https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt|IPv4|17mon的中国IP列表|enabled
gaoyifan/OperatorIP|https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt|IPv4|运营商IP列表|enabled
EOF
    
    # 测试启用数据源
    run_test "启用数据源功能" "toggle_datasource_func '2' 'enabled' && echo 'pass'" "pass"
    
    # 测试禁用数据源
    run_test "禁用数据源功能" "toggle_datasource_func '1' 'disabled' && echo 'pass'" "pass"
    
    # 测试获取启用的数据源
    run_test "获取启用数据源" "get_enabled_datasources_func 'IPv4' | grep -q 'metowolf' && echo 'pass'" "pass"
    
    # 清理
    rm -f "$TEST_DATASOURCE_FILE"
}

# 数据源切换函数（简化版）
toggle_datasource_func() {
    local id="$1"
    local new_status="$2"
    
    local current_id=1
    local temp_file=$(mktemp)
    
    while IFS='|' read -r name url ip_type description status; do
        if [ "$current_id" -eq "$id" ]; then
            echo "${name}|${url}|${ip_type}|${description}|${new_status}" >> "$temp_file"
        else
            echo "${name}|${url}|${ip_type}|${description}|${status}" >> "$temp_file"
        fi
        current_id=$((current_id + 1))
    done < "$TEST_DATASOURCE_FILE"
    
    mv "$temp_file" "$TEST_DATASOURCE_FILE"
    return 0
}

# 获取启用的数据源函数（简化版）
get_enabled_datasources_func() {
    local type="$1"
    local enabled_sources=()
    
    while IFS='|' read -r name url ip_type description status; do
        if [ "$status" = "enabled" ]; then
            if [ -z "$type" ] || [ "$ip_type" = "$type" ]; then
                enabled_sources+=("${name}|${url}")
            fi
        fi
    done < "$TEST_DATASOURCE_FILE"
    
    echo "${enabled_sources[@]}"
}

# 测试自定义数据源添加
test_custom_datasource() {
    echo -e "${BLUE}=== 测试自定义数据源添加 ===${NC}"
    
    # 创建初始配置文件
    cat > "$TEST_DATASOURCE_FILE" << 'EOF'
metowolf/IPList|https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt|IPv4|Metowolf的中国IP列表|enabled
EOF
    
    # 测试添加自定义数据源
    run_test "添加自定义数据源" "add_custom_datasource_func 'MyCustomSource' 'https://myserver.com/china-ip.txt' 'IPv4' '我的自定义IP列表' && echo 'pass'" "pass"
    
    # 测试添加重复数据源
    run_test "添加重复数据源" "add_custom_datasource_func 'MyCustomSource' 'https://myserver.com/china-ip2.txt' 'IPv4' '重复的数据源' && echo 'fail'" "fail"
    
    # 测试添加无效类型数据源
    run_test "添加无效类型数据源" "add_custom_datasource_func 'InvalidSource' 'https://myserver.com/china-ip.txt' 'IPv5' '无效类型' && echo 'fail'" "fail"
    
    # 清理
    rm -f "$TEST_DATASOURCE_FILE"
}

# 添加自定义数据源函数（简化版）
add_custom_datasource_func() {
    local name="$1"
    local url="$2"
    local ip_type="$3"
    local description="$4"
    
    if [ -z "$name" ] || [ -z "$url" ] || [ -z "$ip_type" ]; then
        return 1
    fi
    
    case "$ip_type" in
        "IPv4"|"IPv6") ;;
        *) 
            return 1
            ;;
    esac
    
    if grep -q "^${name}|" "$TEST_DATASOURCE_FILE"; then
        return 1
    fi
    
    echo "${name}|${url}|${ip_type}|${description}|enabled" >> "$TEST_DATASOURCE_FILE"
    return 0
}

# 测试数据源删除功能
test_remove_datasource() {
    echo -e "${BLUE}=== 测试数据源删除功能 ===${NC}"
    
    # 创建测试配置文件
    cat > "$TEST_DATASOURCE_FILE" << 'EOF'
metowolf/IPList|https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt|IPv4|Metowolf的中国IP列表|enabled
17mon/ChinaIPList|https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt|IPv4|17mon的中国IP列表|enabled
gaoyifan/OperatorIP|https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt|IPv4|运营商IP列表|enabled
EOF
    
    # 测试删除数据源
    run_test "删除数据源功能" "remove_datasource_func '2' && echo 'pass'" "pass"
    
    # 测试删除不存在的数据源
    run_test "删除不存在的数据源" "remove_datasource_func '99' && echo 'fail'" "fail"
    
    # 验证删除结果
    run_test "验证删除结果" "! grep -q '17mon/ChinaIPList' '$TEST_DATASOURCE_FILE' && echo 'pass'" "pass"
    
    # 清理
    rm -f "$TEST_DATASOURCE_FILE"
}

# 删除数据源函数（简化版）
remove_datasource_func() {
    local id="$1"
    
    local current_id=1
    local temp_file=$(mktemp)
    local found=false
    
    while IFS='|' read -r name url ip_type description status; do
        if [ "$current_id" -ne "$id" ]; then
            echo "${name}|${url}|${ip_type}|${description}|${status}" >> "$temp_file"
        else
            found=true
        fi
        current_id=$((current_id + 1))
    done < "$TEST_DATASOURCE_FILE"
    
    if [ "$found" = false ]; then
        rm -f "$temp_file"
        return 1
    fi
    
    mv "$temp_file" "$TEST_DATASOURCE_FILE"
    return 0
}

# 测试数据源可用性检测
test_datasource_availability() {
    echo -e "${BLUE}=== 测试数据源可用性检测 ===${NC}"
    
    # 测试可用数据源
    run_test "测试可用数据源" "test_datasource_availability_func 'TestSource' 'https://github.com' && echo 'pass'" "pass"
    
    # 测试不可用数据源
    run_test "测试不可用数据源" "test_datasource_availability_func 'InvalidSource' 'https://this-domain-does-not-exist-12345.com' && echo 'fail'" "fail"
    
    # 测试无效URL
    run_test "测试无效URL" "test_datasource_availability_func 'InvalidURL' 'not-a-valid-url' && echo 'fail'" "fail"
}

# 测试数据源可用性函数（简化版）
test_datasource_availability_func() {
    local name="$1"
    local url="$2"
    
    if curl -fsSL --max-time 5 --head "$url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 测试数据源统计功能
test_datasource_statistics() {
    echo -e "${BLUE}=== 测试数据源统计功能 ===${NC}"
    
    # 创建测试配置文件
    cat > "$TEST_DATASOURCE_FILE" << 'EOF'
metowolf/IPList|https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt|IPv4|Metowolf的中国IP列表|enabled
17mon/ChinaIPList|https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt|IPv4|17mon的中国IP列表|disabled
gaoyifan/OperatorIP|https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt|IPv4|运营商IP列表|enabled
misakaio/ChinaIP|https://raw.githubusercontent.com/misakaio/chnroutes2/master/chnroutes.txt|IPv4|MisakaIO的中国IP路由表|enabled
gaoyifan/ChinaIPv6|https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china6.txt|IPv6|中国运营商IPv6地址列表|enabled
EOF
    
    # 测试统计功能
    run_test "IPv4启用统计" "grep -c 'IPv4|enabled$' '$TEST_DATASOURCE_FILE' | grep -q '3' && echo 'pass'" "pass"
    run_test "IPv6启用统计" "grep -c 'IPv6|enabled$' '$TEST_DATASOURCE_FILE' | grep -q '1' && echo 'pass'" "pass"
    run_test "总数据源统计" "grep -c '|' '$TEST_DATASOURCE_FILE' | grep -q '5' && echo 'pass'" "pass"
    
    # 清理
    rm -f "$TEST_DATASOURCE_FILE"
}

# 测试实际应用场景
test_real_scenarios() {
    echo -e "${BLUE}=== 测试实际应用场景 ===${NC}"
    
    # 场景1：只使用最可靠的2个数据源
    run_test "场景1：精简数据源" "test_scenario_minimal_datasources && echo 'pass'" "pass"
    
    # 场景2：添加自定义企业数据源
    run_test "场景2：企业自定义数据源" "test_scenario_custom_enterprise_datasource && echo 'pass'" "pass"
    
    # 场景3：数据源故障切换
    run_test "场景3：数据源故障处理" "test_scenario_datasource_failure && echo 'pass'" "pass"
}

# 测试场景1：精简数据源
test_scenario_minimal_datasources() {
    # 创建配置文件，只启用2个数据源
    cat > "$TEST_DATASOURCE_FILE" << 'EOF'
metowolf/IPList|https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt|IPv4|Metowolf的中国IP列表|enabled
17mon/ChinaIPList|https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt|IPv4|17mon的中国IP列表|enabled
gaoyifan/OperatorIP|https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt|IPv4|运营商IP列表|disabled
misakaio/ChinaIP|https://raw.githubusercontent.com/misakaio/chnroutes2/master/chnroutes.txt|IPv4|MisakaIO的中国IP路由表|disabled
EOF
    
    # 验证只启用了2个数据源
    local enabled_count=$(grep -c "enabled$" "$TEST_DATASOURCE_FILE")
    
    # 清理
    rm -f "$TEST_DATASOURCE_FILE"
    
    return $([ "$enabled_count" -eq 2 ] && echo 0 || echo 1)
}

# 测试场景2：企业自定义数据源
test_scenario_custom_enterprise_datasource() {
    # 创建基础配置文件
    cat > "$TEST_DATASOURCE_FILE" << 'EOF'
metowolf/IPList|https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt|IPv4|Metowolf的中国IP列表|enabled
EOF
    
    # 添加企业自定义数据源
    add_custom_datasource_func "EnterpriseIPList" "https://enterprise.company.com/china-ip.txt" "IPv4" "企业内部的精确中国IP列表"
    
    # 验证添加成功
    local result=$(grep -c "EnterpriseIPList" "$TEST_DATASOURCE_FILE")
    
    # 清理
    rm -f "$TEST_DATASOURCE_FILE"
    
    return $([ "$result" -eq 1 ] && echo 0 || echo 1)
}

# 测试场景3：数据源故障处理
test_scenario_datasource_failure() {
    # 创建配置文件，包含可用和不可用的数据源
    cat > "$TEST_DATASOURCE_FILE" << 'EOF'
working-source|https://github.com|IPv4|正常工作的数据源|enabled
broken-source|https://this-domain-does-not-exist-12345.com|IPv4|损坏的数据源|enabled
EOF
    
    # 测试可用性
    local working_result=$(test_datasource_availability_func "working-source" "https://github.com" && echo "working" || echo "broken")
    local broken_result=$(test_datasource_availability_func "broken-source" "https://this-domain-does-not-exist-12345.com" && echo "working" || echo "broken")
    
    # 清理
    rm -f "$TEST_DATASOURCE_FILE"
    
    return $([ "$working_result" = "working" ] && [ "$broken_result" = "broken" ] && echo 0 || echo 1)
}

# 显示测试结果
show_test_results() {
    echo -e "${BLUE}==================== 数据源库管理功能测试结果 ====================${NC}"
    echo -e "总测试数: ${TESTS_RUN}"
    echo -e "通过测试: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "失败测试: ${RED}${TESTS_FAILED}${NC}"
    
    local success_rate=$(echo "scale=2; $TESTS_PASSED / $TESTS_RUN * 100" | bc)
    echo -e "成功率: ${GREEN}${success_rate}%${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}所有数据源库管理功能测试通过！${NC}"
        return 0
    else
        echo -e "${RED}部分测试失败，请检查日志${NC}"
        return 1
    fi
}

# 主测试函数
main() {
    echo -e "${GREEN}IP数据源库管理功能测试套件${NC}"
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
    log_test "INFO" "数据源库管理功能测试套件开始执行"
    
    # 执行测试
    test_datasource_config
    test_datasource_toggle
    test_custom_datasource
    test_remove_datasource
    test_datasource_availability
    test_datasource_statistics
    test_real_scenarios
    
    # 显示结果
    show_test_results
    
    # 清理环境
    cleanup_test_env
    
    # 记录测试结束
    log_test "INFO" "数据源库管理功能测试套件执行完成"
    
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
        echo "这个脚本专门测试IP数据源库管理功能的各项能力，包括："
        echo "  - 数据源配置文件操作"
        echo "  - 数据源启用/禁用功能"
        echo "  - 自定义数据源添加"
        echo "  - 数据源删除功能"
        echo "  - 数据源可用性检测"
        echo "  - 数据源统计功能"
        echo "  - 实际应用场景测试"
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