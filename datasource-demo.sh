#!/bin/bash
#
# datasource-demo.sh - IP数据源库管理功能演示脚本
# 演示如何使用数据源管理功能避免误拦截
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 演示脚本
SCRIPT="./port-filter-with-datasource.sh"

# 打印函数
print_info() { printf "%b%s%b\n" "$CYAN" "$1" "$NC"; }
print_success() { printf "%b%s%b\n" "$GREEN" "$1" "$NC"; }
print_warning() { printf "%b%s%b\n" "$YELLOW" "$1" "$NC"; }
print_error() { printf "%b%s%b\n" "$RED" "$1" "$NC"; }
print_title() {
    printf "${BOLD}${MAGENTA}╔════════════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAGENTA}║      IP数据源库管理演示 v1.0.0%-28s║${NC}\n" ""
    printf "${BOLD}${MAGENTA}╚════════════════════════════════════════════════╝${NC}\n"
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "错误：请使用 root 权限运行演示脚本"
        exit 1
    fi
}

# 检查脚本是否存在
check_script() {
    if [ ! -f "$SCRIPT" ]; then
        print_error "错误：主脚本 $SCRIPT 不存在"
        exit 1
    fi
}

# 等待用户确认
wait_for_user() {
    echo ""
    read -rp "按回车键继续演示..."
    echo ""
}

# 场景1：数据源过多导致误拦截问题
demo_scenario1() {
    clear
    print_title
    print_info "场景1：数据源过多导致误拦截问题"
    echo ""
    print_info "问题描述："
    echo "- 默认启用了4个IPv4数据源和1个IPv6数据源"
    echo "- 数据源之间存在重复和不一致的IP段"
    echo "- 某些数据源可能包含过时的IP信息"
    echo "- 导致正常的国外IP被误识别为中国IP"
    echo "- 需要精简数据源，只使用最可靠的1-2个"
    echo ""
    
    wait_for_user
    
    # 显示当前数据源配置
    print_info "当前数据源配置："
    echo ""
    printf "  ${GREEN}✓${NC}  metowolf/IPList     - IPv4 - 启用\n"
    printf "  ${GREEN}✓${NC}  17mon/ChinaIPList   - IPv4 - 启用\n"
    printf "  ${GREEN}✓${NC}  gaoyifan/OperatorIP  - IPv4 - 启用\n"
    printf "  ${GREEN}✓${NC}  misakaio/ChinaIP    - IPv4 - 启用\n"
    printf "  ${GREEN}✓${NC}  gaoyifan/ChinaIPv6  - IPv6 - 启用\n"
    echo ""
    print_warning "⚠ 问题：启用了5个数据源，可能导致重复和冲突！"
    echo ""
    
    wait_for_user
    
    # 解决方案：精简数据源
    print_info "解决方案：精简数据源配置"
    echo ""
    print_info "分析各数据源特点："
    echo "• metowolf/IPList    - 更新频繁，准确性高"
    echo "• 17mon/ChinaIPList  - 准确性高，覆盖全面"
    echo "• gaoyifan/OperatorIP - 运营商数据，覆盖全面"
    echo "• misakaio/ChinaIP   - 路由表数据，较为准确"
    echo "• gaoyifan/ChinaIPv6 - IPv6数据，可选使用"
    echo ""
    print_info "建议配置："
    echo "• 启用：metowolf/IPList (主要数据源)"
    echo "• 启用：17mon/ChinaIPList (验证数据源)"
    echo "• 禁用：其他数据源 (避免重复和冲突)"
    echo ""
    
    print_success "✅ 精简后的配置将大大减少误拦截概率！"
    echo ""
    
    wait_for_user
}

# 场景2：根据需求动态调整数据源
demo_scenario2() {
    clear
    print_title
    print_info "场景2：根据需求动态调整数据源"
    echo ""
    print_info "问题描述："
    echo "- 不同场景需要不同的数据源配置"
    echo "- 生产环境需要最可靠的数据源"
    echo "- 测试环境可以使用多个数据源进行对比"
    echo "- 需要根据实际需求动态调整"
    echo ""
    
    wait_for_user
    
    # 演示不同场景的配置
    print_info "场景A：生产环境配置（高可靠性）"
    echo ""
    printf "  ${GREEN}✓${NC}  metowolf/IPList     - 启用（主要数据源）\n"
    printf "  ${GREEN}✓${NC}  17mon/ChinaIPList   - 启用（验证数据源）\n"
    printf "  ${RED}✗${NC}  gaoyifan/OperatorIP  - 禁用（避免重复）\n"
    printf "  ${RED}✗${NC}  misakaio/ChinaIP    - 禁用（减少冲突）\n"
    printf "  ${GREEN}✓${NC}  gaoyifan/ChinaIPv6  - 启用（IPv6支持）\n"
    echo ""
    print_info "特点：数据源少而精，可靠性最高"
    echo ""
    
    wait_for_user
    
    print_info "场景B：测试环境配置（全面覆盖）"
    echo ""
    printf "  ${GREEN}✓${NC}  metowolf/IPList     - 启用\n"
    printf "  ${GREEN}✓${NC}  17mon/ChinaIPList   - 启用\n"
    printf "  ${GREEN}✓${NC}  gaoyifan/OperatorIP  - 启用\n"
    printf "  ${GREEN}✓${NC}  misakaio/ChinaIP    - 启用\n"
    printf "  ${GREEN}✓${NC}  gaoyifan/ChinaIPv6  - 启用\n"
    echo ""
    print_info "特点：数据源全面，便于对比和测试"
    echo ""
    
    wait_for_user
    
    print_info "场景C：仅IPv4环境配置"
    echo ""
    printf "  ${GREEN}✓${NC}  metowolf/IPList     - 启用\n"
    printf "  ${GREEN}✓${NC}  17mon/ChinaIPList   - 启用\n"
    printf "  ${RED}✗${NC}  gaoyifan/OperatorIP  - 禁用\n"
    printf "  ${RED}✗${NC}  misakaio/ChinaIP    - 禁用\n"
    printf "  ${RED}✗${NC}  gaoyifan/ChinaIPv6  - 禁用（不需要IPv6）\n"
    echo ""
    print_info "特点：只启用IPv4数据源，节省资源"
    echo ""
    
    print_success "✅ 通过动态调整数据源，可以适应不同场景需求！"
    echo ""
    
    wait_for_user
}

# 场景3：添加自定义企业数据源
demo_scenario3() {
    clear
    print_title
    print_info "场景3：添加自定义企业数据源"
    echo ""
    print_info "问题描述："
    echo "- 企业有自己的IP地址库"
    echo "- 需要更精确的IP地域信息"
    echo "- 希望将企业数据源集成到系统中"
    echo "- 需要支持自定义数据源添加"
    echo ""
    
    wait_for_user
    
    # 演示添加自定义数据源
    print_info "步骤：添加企业自定义数据源"
    echo ""
    print_info "企业数据源信息："
    echo "名称: EnterpriseChinaIP"
    echo "URL: https://enterprise.company.com/ip/china-ip-list.txt"
    echo "类型: IPv4"
    echo "描述: 企业内部维护的精确中国IP地址列表"
    echo ""
    
    # 模拟添加过程
    print_info "正在添加自定义数据源..."
    sleep 1
    print_success "✓ 已添加自定义数据源: EnterpriseChinaIP"
    echo ""
    
    print_info "验证添加结果："
    echo "• 数据源出现在配置列表中"
    echo "• 状态设置为启用"
    echo "• 可以像其他数据源一样管理"
    echo ""
    
    # 显示更新后的配置
    print_info "更新后的数据源配置："
    echo ""
    printf "  ${GREEN}✓${NC}  metowolf/IPList      - IPv4 - 启用\n"
    printf "  ${GREEN}✓${NC}  17mon/ChinaIPList    - IPv4 - 启用\n"
    printf "  ${GREEN}✓${NC}  EnterpriseChinaIP    - IPv4 - 启用（新增）\n"
    printf "  ${RED}✗${NC}  gaoyifan/OperatorIP   - IPv4 - 禁用\n"
    printf "  ${RED}✗${NC}  misakaio/ChinaIP     - IPv4 - 禁用\n"
    printf "  ${GREEN}✓${NC}  gaoyifan/ChinaIPv6   - IPv6 - 启用\n"
    echo ""
    
    print_success "✅ 企业自定义数据源已成功集成！"
    print_info "优势："
    echo "• 使用企业内部的精确IP数据"
    echo "• 提高地域识别的准确性"
    echo "• 保持与其他数据源的兼容性"
    echo "• 支持统一的管理界面"
    echo ""
    
    wait_for_user
}

# 场景4：数据源故障检测和处理
demo_scenario4() {
    clear
    print_title
    print_info "场景4：数据源故障检测和处理"
    echo ""
    print_info "问题描述："
    echo "- 某些数据源可能因为网络问题无法访问"
    echo "- 需要及时发现和诊断数据源问题"
    echo "- 需要有备用方案确保系统正常运行"
    echo "- 需要定期检测数据源可用性"
    echo ""
    
    wait_for_user
    
    # 模拟数据源状态
    print_info "当前数据源状态检测："
    echo ""
    printf "  ${GREEN}✓${NC}  metowolf/IPList     - 正常（200ms响应）\n"
    printf "  ${GREEN}✓${NC}  17mon/ChinaIPList   - 正常（180ms响应）\n"
    printf "  ${RED}✗${NC}  gaoyifan/OperatorIP  - 异常（连接超时）\n"
    printf "  ${YELLOW}⚠${NC}  misakaio/ChinaIP    - 警告（响应缓慢）\n"
    printf "  ${GREEN}✓${NC}  gaoyifan/ChinaIPv6  - 正常（220ms响应）\n"
    echo ""
    
    print_warning "⚠ 检测到数据源问题！"
    echo ""
    
    wait_for_user
    
    # 故障处理方案
    print_info "故障处理方案："
    echo ""
    print_info "1. 自动检测和报警："
    echo "   • 定期检查数据源可用性"
    echo "   • 发现故障时发送告警"
    echo "   • 记录故障时间和原因"
    echo ""
    
    print_info "2. 手动故障处理："
    echo "   • 禁用故障数据源"
    echo "   • 启用备用数据源"
    echo "   • 调整数据源优先级"
    echo ""
    
    # 演示故障处理
    print_info "执行故障处理："
    echo ""
    print_info "操作步骤："
    echo "1. 禁用故障数据源 'gaoyifan/OperatorIP'"
    echo "2. 暂时禁用警告数据源 'misakaio/ChinaIP'"
    echo "3. 确保至少2个数据源正常工作"
    echo ""
    
    sleep 2
    print_success "✓ 已禁用故障数据源"
    sleep 1
    print_success "✓ 已调整数据源配置"
    echo ""
    
    print_info "更新后的配置："
    echo ""
    printf "  ${GREEN}✓${NC}  metowolf/IPList     - 启用\n"
    printf "  ${GREEN}✓${NC}  17mon/ChinaIPList   - 启用\n"
    printf "  ${RED}✗${NC}  gaoyifan/OperatorIP  - 禁用（故障）\n"
    printf "  ${RED}✗${NC}  misakaio/ChinaIP    - 禁用（警告）\n"
    printf "  ${GREEN}✓${NC}  gaoyifan/ChinaIPv6  - 启用\n"
    echo ""
    
    print_success "✅ 故障处理完成，系统运行稳定！"
    echo ""
    
    wait_for_user
}

# 场景5：数据源管理最佳实践
demo_scenario5() {
    clear
    print_title
    print_info "场景5：数据源管理最佳实践"
    echo ""
    print_info "推荐的数据源管理策略："
    echo ""
    
    print_info "1. 精选数据源："
    echo "   • 选择2-3个最可靠的数据源"
    echo "   • 优先选择更新频繁的数据源"
    echo "   • 考虑数据源的权威性和准确性"
    echo ""
    
    print_info "2. 定期维护："
    echo "   • 每周检测数据源可用性"
    echo "   • 定期更新和审查数据源列表"
    echo "   • 监控数据源的性能和准确性"
    echo ""
    
    print_info "3. 备份策略："
    echo "   • 保持至少2个数据源启用"
    echo "   • 准备备用数据源配置"
    echo "   • 记录数据源的历史表现"
    echo ""
    
    print_info "4. 自定义集成："
    echo "   • 添加企业内部的精确IP数据"
    echo "   • 集成多个数据源进行交叉验证"
    echo "   • 建立数据源的评估和评分机制"
    echo ""
    
    print_success "✅ 通过合理的数据源管理，可以大大提高系统的准确性和可靠性！"
    echo ""
    
    wait_for_user
}

# 实际演示操作
demo_operations() {
    clear
    print_title
    print_info "实际演示操作"
    echo ""
    print_info "现在让我们实际操作一下数据源管理功能："
    echo ""
    
    # 演示查看数据源
    print_info "1. 查看当前数据源配置："
    echo "   $SCRIPT --进入菜单后选择11->1"
    wait_for_user
    
    # 演示启用/禁用数据源
    print_info "2. 启用/禁用数据源："
    echo "   $SCRIPT --进入菜单后选择11->2"
    echo "   输入数据源ID: 3"
    echo "   操作: disable"
    wait_for_user
    
    # 演示添加自定义数据源
    print_info "3. 添加自定义数据源："
    echo "   $SCRIPT --进入菜单后选择11->3"
    echo "   名称: MyCustomSource"
    echo "   URL: https://myserver.com/china-ip.txt"
    echo "   类型: IPv4"
    echo "   描述: 我的自定义IP列表"
    wait_for_user
    
    # 演示测试数据源
    print_info "4. 测试数据源可用性："
    echo "   $SCRIPT --进入菜单后选择11->5"
    wait_for_user
    
    print_success "✅ 演示完成！现在您可以开始使用数据源管理功能了。"
    echo ""
}

# 总结信息
show_summary() {
    clear
    print_title
    
    echo -e "${GREEN}演示总结${NC}"
    echo ""
    echo -e "${CYAN}IP数据源库管理功能优势：${NC}"
    echo "  • 避免数据源过多导致的误拦截"
    echo "  • 灵活选择和管理数据源"
    echo "  • 支持自定义企业数据源"
    echo "  • 实时监控数据源可用性"
    echo "  • 提高系统准确性和可靠性"
    echo ""
    echo -e "${CYAN}使用建议：${NC}"
    echo "  1. 只启用2-3个最可靠的数据源"
    echo "  2. 定期测试数据源可用性"
    echo "  3. 根据需求动态调整配置"
    echo "  4. 添加企业自定义数据源"
    echo "  5. 建立数据源监控机制"
    echo ""
    echo -e "${CYAN}下一步操作：${NC}"
    echo "  • 运行主脚本：sudo $SCRIPT"
    echo "  • 选择菜单11进入数据源管理"
    echo "  • 根据实际需求配置数据源"
    echo "  • 测试数据源可用性"
    echo "  • 定期维护和更新配置"
    echo ""
    
    print_success "感谢观看IP数据源库管理演示！"
}

# 主演示函数
main() {
    # 检查环境
    check_root
    check_script
    
    # 开始演示
    demo_scenario1
    demo_scenario2
    demo_scenario3
    demo_scenario4
    demo_scenario5
    demo_operations
    show_summary
}

# 处理命令行参数
case "$1" in
    "--help"|"-h")
        echo "用法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  --help, -h    显示帮助信息"
        echo ""
        echo "这个脚本演示IP数据源库管理功能的使用方法和场景，包括："
        echo "  - 数据源过多导致误拦截问题"
        echo "  - 根据需求动态调整数据源"
        echo "  - 添加自定义企业数据源"
        echo "  - 数据源故障检测和处理"
        echo "  - 数据源管理最佳实践"
        echo "  - 实际操作演示"
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