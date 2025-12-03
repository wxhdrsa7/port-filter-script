#!/bin/bash
#
# install-improved.sh - 端口过滤脚本改进版安装程序
# 自动下载、配置和安装改进版端口过滤脚本
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

# 版本信息
VERSION="2.1.0"
SCRIPT_NAME="port-filter-improved.sh"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/port-filter"
LOG_DIR="/var/log/port-filter"

# GitHub仓库信息（需要替换为实际地址）
GITHUB_REPO="https://github.com/wxhdrsa7/port-filter-script"
RAW_URL="https://raw.githubusercontent.com/wxhdrsa7/port-filter-script/main"

# 打印函数
print_info() { printf "%b%s%b\n" "$CYAN" "$1" "$NC"; }
print_success() { printf "%b%s%b\n" "$GREEN" "$1" "$NC"; }
print_warning() { printf "%b%s%b\n" "$YELLOW" "$1" "$NC"; }
print_error() { printf "%b%s%b\n" "$RED" "$1" "$NC"; }
print_title() {
    printf "${BOLD}${MAGENTA}╔════════════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAGENTA}║      端口过滤脚本安装程序 v%s%-28s║${NC}\n" "$VERSION" ""
    printf "${BOLD}${MAGENTA}╚════════════════════════════════════════════════╝${NC}\n"
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "错误：请使用 root 权限运行安装程序"
        exit 1
    fi
}

# 检查系统兼容性
check_system() {
    local supported_distros=("ubuntu" "debian" "centos" "redhat" "fedora")
    local distro=""
    
    if [ -f /etc/os-release ]; then
        distro=$(. /etc/os-release && echo "$ID" | tr '[:upper:]' '[:lower:]')
    elif [ -f /etc/redhat-release ]; then
        distro="redhat"
    elif [ -f /etc/centos-release ]; then
        distro="centos"
    fi
    
    local supported=false
    for d in "${supported_distros[@]}"; do
        if [[ "$distro" == *"$d"* ]]; then
            supported=true
            break
        fi
    done
    
    if [ "$supported" = false ]; then
        print_warning "警告：未检测到支持的Linux发行版"
        print_warning "支持的发行版：Ubuntu, Debian, CentOS, RedHat, Fedora"
        read -rp "是否继续安装？(y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    print_success "✓ 系统兼容性检查通过"
}

# 检查网络连接
check_network() {
    print_info "检查网络连接..."
    
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        print_error "网络连接失败，无法继续安装"
        exit 1
    fi
    
    # 检查GitHub连接
    if ! curl -s --head --max-time 10 "$GITHUB_REPO" >/dev/null; then
        print_warning "无法连接到GitHub，可能无法下载脚本"
        read -rp "是否继续？(y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    print_success "✓ 网络连接正常"
}

# 安装依赖
install_dependencies() {
    print_info "安装依赖软件..."
    
    # 更新包列表
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq
        local packages=("curl" "ipset" "iptables" "iptables-persistent" "cron")
        for pkg in "${packages[@]}"; do
            if ! dpkg -l | grep -q "^ii  $pkg "; then
                apt-get install -y "$pkg" >/dev/null 2>&1
            fi
        done
    elif command -v yum >/dev/null 2>&1; then
        yum makecache -q
        local packages=("curl" "ipset" "iptables" "iptables-services" "cronie")
        for pkg in "${packages[@]}"; do
            if ! rpm -q "$pkg" >/dev/null 2>&1; then
                yum install -y "$pkg" >/dev/null 2>&1
            fi
        done
    else
        print_warning "未识别的包管理器，请手动安装依赖"
    fi
    
    # 检查关键组件
    local missing_packages=()
    for cmd in curl ipset iptables; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_packages+=("$cmd")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        print_error "以下组件安装失败: ${missing_packages[*]}"
        print_error "请手动安装后重新运行"
        exit 1
    fi
    
    print_success "✓ 依赖安装完成"
}

# 下载脚本
download_script() {
    print_info "下载改进版脚本..."
    
    # 检查是否已存在
    if [ -f "$SCRIPT_NAME" ]; then
        print_warning "检测到本地脚本文件"
        read -rp "是否使用本地文件？(y/N): " use_local
        if [[ "$use_local" =~ ^[Yy]$ ]]; then
            print_info "使用本地脚本文件"
            return 0
        fi
    fi
    
    # 尝试从GitHub下载
    print_info "正在从GitHub下载脚本..."
    if curl -fsSL --max-time 60 "$RAW_URL/$SCRIPT_NAME" -o "$SCRIPT_NAME"; then
        print_success "✓ 脚本下载成功"
    else
        print_error "脚本下载失败"
        read -rp "是否手动上传脚本文件？(y/N): " manual_upload
        if [[ "$manual_upload" =~ ^[Yy]$ ]]; then
            print_info "请将脚本文件放置在: $(pwd)/$SCRIPT_NAME"
            read -rp "准备好后按回车继续..."
            if [ ! -f "$SCRIPT_NAME" ]; then
                print_error "未找到脚本文件"
                exit 1
            fi
        else
            exit 1
        fi
    fi
}

# 验证脚本
verify_script() {
    print_info "验证脚本完整性..."
    
    if [ ! -f "$SCRIPT_NAME" ]; then
        print_error "脚本文件不存在"
        exit 1
    fi
    
    # 检查脚本格式
    if ! head -1 "$SCRIPT_NAME" | grep -q "#!/bin/bash"; then
        print_error "脚本格式不正确"
        exit 1
    fi
    
    # 检查脚本内容
    if ! grep -q "VERSION=" "$SCRIPT_NAME"; then
        print_warning "脚本可能不完整"
    fi
    
    # 设置执行权限
    chmod +x "$SCRIPT_NAME"
    
    print_success "✓ 脚本验证通过"
}

# 安装脚本
install_script() {
    print_info "安装脚本到系统..."
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    
    # 复制脚本
    cp "$SCRIPT_NAME" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    
    # 创建符号链接
    ln -sf "$INSTALL_DIR/$SCRIPT_NAME" "/usr/local/bin/port-filter"
    
    # 设置目录权限
    chmod 700 "$CONFIG_DIR"
    chmod 755 "$LOG_DIR"
    
    print_success "✓ 脚本安装完成"
}

# 配置系统
configure_system() {
    print_info "配置系统环境..."
    
    # 启用IP转发（如果需要）
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "0" ]; then
        echo 1 > /proc/sys/net/ipv4/ip_forward
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    fi
    
    # 启用IPv6转发（如果支持）
    if [ -f /proc/sys/net/ipv6/conf/all/forwarding ]; then
        if [ "$(cat /proc/sys/net/ipv6/conf/all/forwarding)" = "0" ]; then
            echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
            echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
        fi
    fi
    
    # 确保iptables服务启动
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files | grep -q iptables; then
            systemctl enable iptables 2>/dev/null
            systemctl start iptables 2>/dev/null
        fi
    fi
    
    print_success "✓ 系统配置完成"
}

# 显示安装信息
show_install_info() {
    clear
    print_title
    
    echo -e "${GREEN}安装完成！${NC}"
    echo ""
    echo -e "${CYAN}使用方法:${NC}"
    echo "  sudo port-filter"
    echo "  sudo port-filter --update-ip"
    echo "  sudo port-filter --status"
    echo "  sudo port-filter --help"
    echo ""
    echo -e "${CYAN}配置文件:${NC}"
    echo "  主配置目录: $CONFIG_DIR"
    echo "  规则文件: $CONFIG_DIR/rules.conf"
    echo "  设置文件: $CONFIG_DIR/settings.conf"
    echo ""
    echo -e "${CYAN}日志文件:${NC}"
    echo "  主日志: $LOG_DIR/update.log"
    echo "  错误日志: $LOG_DIR/error.log"
    echo ""
    echo -e "${YELLOW}重要提醒:${NC}"
    echo "  1. 首次运行建议执行系统状态检查"
    echo "  2. 配置自动更新以保持IP列表最新"
    echo "  3. 定期创建配置备份"
    echo "  4. 监控错误日志以及时发现问题"
    echo ""
    echo -e "${GREEN}按回车键开始使用...${NC}"
    read -r
    
    # 运行脚本
    sudo port-filter
}

# 主安装函数
main() {
    clear
    print_title
    
    # 检查环境
    check_root
    check_system
    check_network
    
    # 安装依赖
    install_dependencies
    
    # 下载和安装脚本
    download_script
    verify_script
    install_script
    
    # 配置系统
    configure_system
    
    # 显示安装信息
    show_install_info
}

# 处理命令行参数
case "$1" in
    "--help"|"-h")
        echo "用法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  --help, -h    显示帮助信息"
        echo ""
        echo "这个安装程序会自动下载、验证和安装端口过滤脚本的改进版。"
        echo ""
        echo "安装过程包括:"
        echo "  1. 系统兼容性检查"
        echo "  2. 网络连接测试"
        echo "  3. 依赖软件安装"
        echo "  4. 脚本下载和验证"
        echo "  5. 系统环境配置"
        echo "  6. 首次运行引导"
        echo ""
        echo "安装完成后，可以使用 'sudo port-filter' 命令运行脚本。"
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