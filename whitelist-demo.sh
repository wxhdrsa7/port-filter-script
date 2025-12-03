#!/bin/bash
#
# whitelist-demo.sh - IP白名单功能演示脚本
# 演示如何使用IP白名单功能避免误拦截
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
SCRIPT="./port-filter-with-whitelist.sh"
DEMO_PORT=8080

# 打印函数
print_info() { printf "%b%s%b\n" "$CYAN" "$1" "$NC"; }
print_success() { printf "%b%s%b\n" "$GREEN" "$1" "$NC"; }
print_warning() { printf "%b%s%b\n" "$YELLOW" "$1" "$NC"; }
print_error() { printf "%b%s%b\n" "$RED" "$1" "$NC"; }
print_title() {
    printf "${BOLD}${MAGENTA}╔════════════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAGENTA}║      IP白名单功能演示 v1.0.0%-28s║${NC}\n" ""
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

# 场景1：内网服务器访问外网API
demo_scenario1() {
    clear
    print_title
    print_info "场景1：内网服务器访问外网API"
    echo ""
    print_info "问题描述："
    echo "- 公司内网有多台服务器需要访问外网API"
    echo "- 为了安全，设置了地域过滤（只允许国外IP访问）"
    echo "- 但内网服务器IP在中国，被误拦截"
    echo "- 需要将内网服务器IP加入白名单"
    echo ""
    
    wait_for_user
    
    # 步骤1：设置地域过滤规则
    print_info "步骤1：设置API端口的地域过滤规则（黑名单模式）"
    echo "端口: $DEMO_PORT"
    echo "协议: TCP"
    echo "模式: 黑名单（阻止中国IP访问）"
    echo ""
    
    # 模拟设置规则
    print_success "✓ 已设置黑名单规则：阻止中国IP访问端口 $DEMO_PORT"
    print_warning "⚠ 问题：内网服务器192.168.1.100也被拦截了！"
    echo ""
    
    wait_for_user
    
    # 步骤2：添加内网服务器到白名单
    print_info "步骤2：将内网服务器IP加入白名单"
    echo ""
    print_info "添加单个服务器IP："
    echo "IP: 192.168.1.100"
    echo "备注: 内网主服务器"
    print_success "✓ 已添加白名单IP: 192.168.1.100"
    echo ""
    
    print_info "添加整个内网网段："
    echo "IP段: 192.168.1.0/24"
    echo "备注: 内网服务器网段"
    print_success "✓ 已添加白名单网段: 192.168.1.0/24"
    echo ""
    
    print_success "✅ 解决方案：内网服务器现在可以正常访问API了！"
    print_info "说明：白名单优先级高于黑名单，所以内网服务器不会受到影响"
    echo ""
    
    wait_for_user
}

# 场景2：合作伙伴特殊访问权限
demo_scenario2() {
    clear
    print_title
    print_info "场景2：合作伙伴特殊访问权限"
    echo ""
    print_info "问题描述："
    echo "- 数据库端口3306默认是屏蔽的（安全考虑）"
    echo "- 合作伙伴需要访问数据库进行数据同步"
    echo "- 需要将合作伙伴的IP加入白名单"
    echo ""
    
    wait_for_user
    
    # 步骤1：设置端口屏蔽
    print_info "步骤1：设置数据库端口屏蔽（默认不允许访问）"
    echo "端口: 3306"
    echo "协议: TCP"
    echo "操作: 完全屏蔽"
    echo ""
    
    print_success "✓ 已屏蔽端口 3306"
    print_warning "⚠ 问题：合作伙伴203.0.113.50无法访问数据库！"
    echo ""
    
    wait_for_user
    
    # 步骤2：添加合作伙伴到白名单
    print_info "步骤2：将合作伙伴IP加入白名单"
    echo ""
    print_info "添加合作伙伴IP："
    echo "IP: 203.0.113.50"
    echo "备注: 合作伙伴数据库访问"
    print_success "✓ 已添加白名单IP: 203.0.113.50"
    echo ""
    
    print_success "✅ 解决方案：合作伙伴现在可以访问数据库了！"
    print_info "说明：白名单IP可以访问被屏蔽的端口"
    echo ""
    
    wait_for_user
}

# 场景3：管理员不受限制访问
demo_scenario3() {
    clear
    print_title
    print_info "场景3：管理员不受限制访问"
    echo ""
    print_info "问题描述："
    echo "- 服务器设置了严格的地域过滤规则"
    echo "- 管理员需要随时随地访问服务器"
    echo "- 管理员IP需要不受任何地域限制"
    echo ""
    
    wait_for_user
    
    # 步骤1：设置严格的地域过滤
    print_info "步骤1：设置SSH端口严格的地域过滤"
    echo "端口: 22"
    echo "协议: TCP"
    echo "模式: 白名单（仅允许中国IP）"
    echo ""
    
    print_success "✓ 已设置白名单规则：仅允许中国IP访问SSH"
    print_warning "⚠ 问题：管理员在国外出差，无法访问SSH！"
    echo ""
    
    wait_for_user
    
    # 步骤2：添加管理员到白名单
    print_info "步骤2：将管理员IP加入白名单"
    echo ""
    print_info "添加管理员IP："
    echo "IP: 198.51.100.10"
    echo "备注: 管理员IP（不受地域限制）"
    print_success "✓ 已添加白名单IP: 198.51.100.10"
    echo ""
    
    print_success "✅ 解决方案：管理员现在可以不受地域限制访问SSH了！"
    print_info "说明：白名单IP可以绕过所有地域过滤规则"
    echo ""
    
    wait_for_user
}

# 场景4：批量管理白名单
demo_scenario4() {
    clear
    print_title
    print_info "场景4：批量管理白名单"
    echo ""
    print_info "问题描述："
    echo "- 公司有多个办公地点，需要添加多个IP段"
    echo "- 手动一个个添加效率太低"
    echo "- 需要使用批量导入功能"
    echo ""
    
    wait_for_user
    
    # 步骤1：创建白名单文件
    print_info "步骤1：创建包含多个IP的白名单文件"
    echo ""
    
    cat > /tmp/company-whitelist.txt << 'EOF'
192.168.1.0/24    总部办公网络
192.168.2.0/24    分部办公网络
10.0.0.0/16       VPN用户网段
203.0.113.0/24    公网办公IP段
2001:db8::/64     IPv6办公网络
EOF
    
    print_info "创建文件: /tmp/company-whitelist.txt"
    echo "内容:"
    cat /tmp/company-whitelist.txt
    echo ""
    
    wait_for_user
    
    # 步骤2：批量导入
    print_info "步骤2：批量导入白名单IP"
    echo ""
    print_info "正在从文件导入IP白名单..."
    
    # 模拟批量导入过程
    local count=0
    while IFS=' ' read -r ip comment; do
        if [ -n "$ip" ] && [ -n "$comment" ]; then
            echo "✓ 已添加: $ip ($comment)"
            count=$((count + 1))
        fi
    done < /tmp/company-whitelist.txt
    
    print_success "✓ 批量导入完成！共导入 $count 个IP/段"
    echo ""
    
    # 清理临时文件
    rm -f /tmp/company-whitelist.txt
    
    print_success "✅ 解决方案：所有办公地点的IP都已加入白名单！"
    print_info "说明：批量导入功能大大提高了管理效率"
    echo ""
    
    wait_for_user
}

# 场景5：白名单优先级演示
demo_scenario5() {
    clear
    print_title
    print_info "场景5：白名单优先级演示"
    echo ""
    print_info "演示白名单优先级如何工作："
    echo ""
    
    # 显示规则优先级
    print_info "规则优先级（从高到低）："
    echo ""
    printf "  ${GREEN}1.${NC}  IP白名单（ACCEPT）- 最高优先级\n"
    printf "  ${YELLOW}2.${NC}  地域黑名单（DROP）\n"
    printf "  ${YELLOW}3.${NC}  地域白名单（ACCEPT）\n"
    printf "  ${YELLOW}4.${NC}  端口屏蔽（DROP）\n"
    printf "  ${YELLOW}5.${NC}  端口放行（ACCEPT）- 最低优先级\n"
    echo ""
    
    print_info "实际应用场景："
    echo ""
    print_info "假设有以下规则："
    echo "- 端口8080：黑名单模式（阻止中国IP）"
    echo "- 白名单：192.168.1.100"
    echo ""
    print_info "访问结果："
    printf "  ${GREEN}✓${NC}  192.168.1.100 → 可以访问（白名单优先级高）\n"
    printf "  ${RED}✗${NC}  其他中国IP → 不能访问（黑名单生效）\n"
    printf "  ${GREEN}✓${NC}  国外IP → 可以访问（不在黑名单）\n"
    echo ""
    
    print_success "✅ 结论：白名单提供了灵活的例外机制！"
    echo ""
    
    wait_for_user
}

# 实际演示操作
demo_operations() {
    clear
    print_title
    print_info "实际演示操作"
    echo ""
    print_info "现在让我们实际操作一下白名单功能："
    echo ""
    
    # 演示添加白名单
    print_info "1. 添加单个IP到白名单："
    echo "   $SCRIPT --add-whitelist 192.168.1.100 '测试服务器'"
    wait_for_user
    
    # 演示添加IP段
    print_info "2. 添加IP段到白名单："
    echo "   $SCRIPT --add-whitelist 10.0.0.0/24 '内网网段'"
    wait_for_user
    
    # 演示查看白名单
    print_info "3. 查看当前白名单："
    echo "   $SCRIPT --show-whitelist"
    wait_for_user
    
    # 演示移除白名单
    print_info "4. 移除白名单IP："
    echo "   $SCRIPT --remove-whitelist 192.168.1.100"
    wait_for_user
    
    print_success "✅ 演示完成！现在您可以开始使用IP白名单功能了。"
    echo ""
}

# 总结信息
show_summary() {
    clear
    print_title
    
    echo -e "${GREEN}演示总结${NC}"
    echo ""
    echo -e "${CYAN}IP白名单功能优势：${NC}"
    echo "  • 避免误拦截重要IP"
    echo "  • 提供灵活的例外机制"
    echo "  • 支持IPv4和IPv6"
    echo "  • 支持单个IP和IP段"
    echo "  • 优先级高于地域过滤"
    echo "  • 配置持久化存储"
    echo ""
    echo -e "${CYAN}使用建议：${NC}"
    echo "  1. 谨慎添加白名单IP"
    echo "  2. 为白名单IP添加清晰备注"
    echo "  3. 定期审查白名单列表"
    echo "  4. 重要IP建议双重确认"
    echo "  5. 批量导入前先测试"
    echo ""
    echo -e "${CYAN}下一步操作：${NC}"
    echo "  • 运行主脚本：sudo $SCRIPT"
    echo "  • 选择菜单10进入白名单管理"
    echo "  • 根据实际需求配置白名单"
    echo "  • 测试白名单功能是否正常"
    echo ""
    
    print_success "感谢观看IP白名单功能演示！"
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
        echo "这个脚本演示IP白名单功能的使用方法和场景，包括："
        echo "  - 内网服务器访问外网API"
        echo "  - 合作伙伴特殊访问权限"
        echo "  - 管理员不受限制访问"
        echo "  - 批量管理白名单"
        echo "  - 白名单优先级演示"
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