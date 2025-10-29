#!/bin/bash
# port-filter.sh - 智能端口访问控制脚本
# 支持：多地区 IP 集合管理、端口屏蔽/放行、TCP/UDP/双协议控制

set -euo pipefail

VERSION="2.1.0"
CONFIG_DIR="/etc/port-filter"
CONFIG_FILE="$CONFIG_DIR/config.conf"
CACHE_DIR="$CONFIG_DIR/geoip-cache"
CACHE_TTL=$((7 * 24 * 60 * 60)) # 7 天缓存
IPSET_PREFIX="pf_geo_"
AUTO_UPDATE_CRON_FILE="/etc/cron.d/port-filter-auto-update"
AUTO_UPDATE_CONFIG="$CONFIG_DIR/auto-update.conf"
AUTO_UPDATE_LOG="$CONFIG_DIR/auto-update.log"
METOWOLF_BASE="https://raw.githubusercontent.com/metowolf/iplist/master"
COUNTRY_DATA_SOURCE="$METOWOLF_BASE/data/country"

# 常用国家/地区列表（ISO 3166-1 alpha-2）
COUNTRY_OPTIONS=(
    "CN|中国大陆（ISO）"
    "CN_MAINLAND|中国大陆（综合高频段）"
    "CN_CT|中国电信"
    "CN_CUCC|中国联通"
    "CN_CMCC|中国移动"
    "CN_CERNET|中国教育网"
    "CN_BACKBONE|中国骨干网"
    "HK|中国香港"
    "MO|中国澳门"
    "TW|中国台湾"
    "SG|新加坡"
    "JP|日本"
    "KR|韩国"
    "TH|泰国"
    "VN|越南"
    "MY|马来西亚"
    "PH|菲律宾"
    "ID|印度尼西亚"
    "US|美国"
    "CA|加拿大"
    "GB|英国"
    "DE|德国"
    "FR|法国"
    "NL|荷兰"
    "RU|俄罗斯"
    "IN|印度"
    "AE|阿联酋"
    "AU|澳大利亚"
    "BR|巴西"
    "ZA|南非"
)

declare -A DATA_SOURCE_OVERRIDES=(
    [CN_MAINLAND]="$METOWOLF_BASE/data/cn/china.txt"
    [CN_CT]="$METOWOLF_BASE/data/cn/chinatelecom.txt"
    [CN_CUCC]="$METOWOLF_BASE/data/cn/chinaunicom.txt"
    [CN_CMCC]="$METOWOLF_BASE/data/cn/chinamobile.txt"
    [CN_CERNET]="$METOWOLF_BASE/data/cn/cernet.txt"
    [CN_BACKBONE]="$METOWOLF_BASE/data/cn/backbone.txt"
)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志工具
log_info() { echo -e "${BLUE}[信息]${NC} $*"; }
log_success() { echo -e "${GREEN}[成功]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
log_error() { echo -e "${RED}[错误]${NC} $*"; }

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

init_environment() {
    mkdir -p "$CONFIG_DIR" "$CACHE_DIR"
    touch "$CONFIG_FILE"
}

install_dependencies() {
    log_info "检查并安装依赖..."

    local packages=(ipset iptables-persistent curl)
    local missing=()

    for pkg in "${packages[@]}"; do
        if ! command_exists "$pkg"; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        if command_exists apt-get; then
            if apt-get update -qq > /dev/null 2>&1 && \
               DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" > /dev/null 2>&1; then
                log_success "已安装缺失依赖: ${missing[*]}"
            else
                log_warn "自动安装依赖失败，请检查网络或手动安装: ${missing[*]}"
            fi
        elif command_exists yum; then
            if yum install -y "${missing[@]}" > /dev/null 2>&1; then
                log_success "已安装缺失依赖: ${missing[*]}"
            else
                log_warn "自动安装依赖失败，请手动安装: ${missing[*]}"
            fi
        else
            log_warn "无法自动安装依赖，请手动安装: ${missing[*]}"
        fi
    else
        log_success "依赖已全部就绪"
    fi
}

print_banner() {
    clear
    cat <<BANNER
${CYAN}╔════════════════════════════════════════════════════════╗
║            Port Filter Script v${VERSION} - by GPT            ║
╚════════════════════════════════════════════════════════╝${NC}
BANNER
}

press_enter() {
    echo ""
    read -rp "按回车继续..." _
}

validate_port() {
    local port=$1
    if [[ ! $port =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "端口号必须在 1-65535 范围内"
        return 1
    fi
    return 0
}

select_protocol() {
    echo "选择协议："
    echo "  1) TCP"
    echo "  2) UDP"
    echo "  3) TCP + UDP"
    read -rp "请选择 [1-3]: " choice
    case $choice in
        1) echo "tcp" ;;
        2) echo "udp" ;;
        3) echo "both" ;;
        *) log_error "无效选择"; return 1 ;;
    esac
}

select_mode() {
    echo "选择模式："
    echo "  1) 黑名单（阻止选定地区 IP）"
    echo "  2) 白名单（仅允许选定地区 IP）"
    read -rp "请选择 [1-2]: " choice
    case $choice in
        1) echo "blacklist" ;;
        2) echo "whitelist" ;;
        *) log_error "无效选择"; return 1 ;;
    esac
}

# 构建国家名映射
declare -A COUNTRY_NAME_MAP
for item in "${COUNTRY_OPTIONS[@]}"; do
    IFS='|' read -r code name <<< "$item"
    COUNTRY_NAME_MAP[$code]="$name"
done

describe_countries() {
    local codes=$1
    if [ -z "$codes" ] || [ "$codes" = "-" ]; then
        echo "-"
        return
    fi
    local -a result=()
    IFS=',' read -ra list <<< "$codes"
    for code in "${list[@]}"; do
        code=${code^^}
        if [ -n "${COUNTRY_NAME_MAP[$code]:-}" ]; then
            result+=("${COUNTRY_NAME_MAP[$code]}($code)")
        else
            result+=("$code")
        fi
    done
    local joined="${result[*]}"
    echo "${joined// /, }"
}

prompt_countries() {
    echo "请选择需要控制的国家/地区（可多选，使用逗号分隔）："
    local index=1
    for option in "${COUNTRY_OPTIONS[@]}"; do
        IFS='|' read -r code name <<< "$option"
        printf "  %2d) %-3s %s\n" "$index" "$code" "$name"
        ((index++))
    done
    echo "     all) 全部内置国家/地区"
    read -rp "请输入序号或国家代码（如 1,3,US）: " input
    input=${input// /}
    input=${input//，/,}

    if [ -z "$input" ]; then
        log_error "未选择任何国家/地区"
        return 1
    fi

    local -a selected=()
    IFS=',' read -ra tokens <<< "$input"

    if [ "${tokens[0],,}" = "all" ]; then
        for option in "${COUNTRY_OPTIONS[@]}"; do
            IFS='|' read -r code _ <<< "$option"
            selected+=("${code^^}")
        done
    else
        for token in "${tokens[@]}"; do
            if [[ $token =~ ^[0-9]+$ ]]; then
                local idx=$((token-1))
                if [ $idx -ge 0 ] && [ $idx -lt ${#COUNTRY_OPTIONS[@]} ]; then
                    IFS='|' read -r code _ <<< "${COUNTRY_OPTIONS[$idx]}"
                    selected+=("${code^^}")
                else
                    log_error "序号 $token 超出范围"
                    return 1
                fi
            else
                token=${token^^}
                if [ -n "${COUNTRY_NAME_MAP[$token]:-}" ]; then
                    selected+=("$token")
                else
                    log_error "未知的国家代码: $token"
                    return 1
                fi
            fi
        done
    fi

    # 去重
    local unique=()
    local -A seen=()
    for code in "${selected[@]}"; do
        if [ -z "${seen[$code]:-}" ]; then
            unique+=("$code")
            seen[$code]=1
        fi
    done

    if [ ${#unique[@]} -eq 0 ]; then
        log_error "未选择任何有效的国家/地区"
        return 1
    fi

    local joined=$(IFS=','; echo "${unique[*]}")
    echo "$joined"
}

stat_mtime() {
    local file=$1
    if [ -f "$file" ]; then
        stat -c %Y "$file" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

resolve_data_url() {
    local code=${1^^}
    if [ -n "${DATA_SOURCE_OVERRIDES[$code]:-}" ]; then
        echo "${DATA_SOURCE_OVERRIDES[$code]}"
    else
        echo "$COUNTRY_DATA_SOURCE/${code}.txt"
    fi
}

fetch_country_data() {
    local code=${1^^}
    local force_refresh=${2:-0}
    local cache_file="$CACHE_DIR/${code}.cidr"
    local url=$(resolve_data_url "$code")

    if [ -z "$url" ]; then
        log_error "未找到 ${code} 对应的数据源"
        return 1
    fi

    local now=$(date +%s)
    local mtime=$(stat_mtime "$cache_file")

    if [ ! -f "$cache_file" ] || [ $force_refresh -eq 1 ] || [ $((now - mtime)) -ge $CACHE_TTL ]; then
        log_info "更新 ${code} IP 数据..."
        if ! curl -fsSL --max-time 120 "$url" -o "${cache_file}.tmp"; then
            log_error "下载 ${code} IP 数据失败"
            rm -f "${cache_file}.tmp"
            return 1
        fi
        mv "${cache_file}.tmp" "$cache_file"
    fi

    echo "$cache_file"
}

build_ipset() {
    local ipset_name=$1
    local countries=$2
    local force_refresh=${3:-0}

    local -a codes=()
    IFS=',' read -ra codes <<< "$countries"

    if [ ${#codes[@]} -eq 0 ]; then
        log_error "未提供任何国家/地区代码"
        return 1
    fi

    ipset create "$ipset_name" hash:net maxelem 200000 -exist
    ipset flush "$ipset_name" 2>/dev/null || true

    local total=0
    for code in "${codes[@]}"; do
        local data_file
        if ! data_file=$(fetch_country_data "$code" "$force_refresh"); then
            continue
        fi
        while IFS= read -r cidr; do
            [ -z "$cidr" ] && continue
            ipset add "$ipset_name" "$cidr" 2>/dev/null && ((total++))
        done < "$data_file"
    done

    if [ $total -eq 0 ]; then
        log_warn "未能向 IP 集合 $ipset_name 添加任何条目"
    else
        log_success "IP 集合 $ipset_name 已包含 $total 条记录"
    fi

    return 0
}

clear_port_rules() {
    local port=$1
    local rules
    rules=$(iptables -S INPUT | grep -- "--dport $port" || true)
    while IFS= read -r rule; do
        [ -z "$rule" ] && continue
        iptables -D INPUT ${rule#-A INPUT } 2>/dev/null || true
    done <<< "$rules"
}

block_port() {
    local port=$1
    local protocol=$2
    local quiet=${3:-0}

    clear_port_rules "$port"

    if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p tcp --dport "$port" -j DROP
    fi
    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p udp --dport "$port" -j DROP
    fi

    if [ "$quiet" -eq 0 ]; then
        log_success "端口 $port ($protocol) 已设置为完全屏蔽"
    fi
}

allow_port() {
    local port=$1
    local protocol=$2
    local quiet=${3:-0}

    clear_port_rules "$port"

    if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
    fi
    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        iptables -I INPUT -p udp --dport "$port" -j ACCEPT
    fi

    if [ "$quiet" -eq 0 ]; then
        log_success "端口 $port ($protocol) 已设置为完全放行"
    fi
}

generate_ipset_name() {
    local countries=$1
    local hash
    hash=$(echo -n "$countries" | md5sum | cut -c1-10)
    echo "${IPSET_PREFIX}${hash}"
}

apply_geo_rule() {
    local port=$1
    local protocol=$2
    local mode=$3 # blacklist / whitelist
    local ipset_name=$4
    local countries=$5
    local quiet=${6:-0}
    local force_refresh=${7:-0}

    if ! build_ipset "$ipset_name" "$countries" "$force_refresh"; then
        log_error "构建 IP 集合失败，规则未应用"
        return 1
    fi

    clear_port_rules "$port"

    if [ "$protocol" = "tcp" ] || [ "$protocol" = "both" ]; then
        if [ "$mode" = "blacklist" ]; then
            iptables -I INPUT -p tcp --dport "$port" -m set --match-set "$ipset_name" src -j DROP
        else
            iptables -I INPUT -p tcp --dport "$port" -j DROP
            iptables -I INPUT -p tcp --dport "$port" -m set --match-set "$ipset_name" src -j ACCEPT
        fi
    fi

    if [ "$protocol" = "udp" ] || [ "$protocol" = "both" ]; then
        if [ "$mode" = "blacklist" ]; then
            iptables -I INPUT -p udp --dport "$port" -m set --match-set "$ipset_name" src -j DROP
        else
            iptables -I INPUT -p udp --dport "$port" -j DROP
            iptables -I INPUT -p udp --dport "$port" -m set --match-set "$ipset_name" src -j ACCEPT
        fi
    fi

    if [ "$quiet" -eq 0 ]; then
        local mode_text="黑名单"
        [ "$mode" = "whitelist" ] && mode_text="白名单"
        log_success "端口 $port ($protocol) 已应用地域${mode_text}，目标地区：$(describe_countries "$countries")"
    fi
}

save_rules() {
    log_info "保存防火墙规则..."
    if command_exists netfilter-persistent; then
        netfilter-persistent save > /dev/null 2>&1 && log_success "规则已持久化"
    elif command_exists service; then
        service netfilter-persistent save > /dev/null 2>&1 && log_success "规则已持久化"
    else
        log_warn "未检测到 netfilter-persistent，规则不会在重启后自动恢复"
    fi
}

update_config_entry() {
    local port=$1
    local protocol=$2
    local type=$3
    local ipset_name=$4
    local countries=${5:--}

    local tmp=$(mktemp)
    awk -F'|' -v p="$port" -v proto="$protocol" '!( $1==p && $2==proto )' "$CONFIG_FILE" > "$tmp"
    echo "${port}|${protocol}|${type}|${ipset_name}|${countries}" >> "$tmp"
    mv "$tmp" "$CONFIG_FILE"
}

remove_config_entry() {
    local port=$1
    local protocol=$2
    local tmp=$(mktemp)
    awk -F'|' -v p="$port" -v proto="$protocol" '!( $1==p && $2==proto )' "$CONFIG_FILE" > "$tmp"
    mv "$tmp" "$CONFIG_FILE"
}

reload_rules_for_port() {
    local target_port=$1
    local force_refresh=${2:-0}
    local tmp=$(mktemp)
    awk -F'|' -v p="$target_port" '$1==p' "$CONFIG_FILE" > "$tmp"

    if [ ! -s "$tmp" ]; then
        clear_port_rules "$target_port"
        rm -f "$tmp"
        return
    fi

    clear_port_rules "$target_port"

    while IFS='|' read -r port protocol type ipset countries; do
        case $type in
            geo_blacklist)
                apply_geo_rule "$port" "$protocol" "blacklist" "$ipset" "$countries" 1 "$force_refresh"
                ;;
            geo_whitelist)
                apply_geo_rule "$port" "$protocol" "whitelist" "$ipset" "$countries" 1 "$force_refresh"
                ;;
            block)
                block_port "$port" "$protocol" 1
                ;;
            allow)
                allow_port "$port" "$protocol" 1
                ;;
        esac
    done < "$tmp"

    rm -f "$tmp"
}

load_config() {
    if [ ! -s "$CONFIG_FILE" ]; then
        return
    fi

    log_info "加载历史配置..."

    while IFS='|' read -r port protocol type ipset countries; do
        [ -z "$port" ] && continue
        case $type in
            geo_blacklist)
                apply_geo_rule "$port" "$protocol" "blacklist" "$ipset" "$countries" 1 || true
                ;;
            geo_whitelist)
                apply_geo_rule "$port" "$protocol" "whitelist" "$ipset" "$countries" 1 || true
                ;;
            block)
                block_port "$port" "$protocol" 1 || true
                ;;
            allow)
                allow_port "$port" "$protocol" 1 || true
                ;;
        esac
    done < "$CONFIG_FILE"

    log_success "历史规则已加载"
}

refresh_all_geo_rules() {
    local force_refresh=${1:-0}

    if [ ! -s "$CONFIG_FILE" ]; then
        log_warn "当前没有任何规则可以刷新"
        return 0
    fi

    local -A handled_ports=()
    local refreshed=0

    while IFS='|' read -r port _protocol type _ipset _countries; do
        [ -z "$port" ] && continue
        if [[ $type == geo_* ]]; then
            if [ -z "${handled_ports[$port]:-}" ]; then
                log_info "刷新端口 $port 的地域规则..."
                reload_rules_for_port "$port" "$force_refresh"
                handled_ports[$port]=1
            fi
            refreshed=1
        fi
    done < "$CONFIG_FILE"

    if [ $refreshed -eq 0 ]; then
        log_warn "当前没有配置任何地域规则"
    else
        log_success "地域规则刷新完成"
    fi
}

describe_auto_update_schedule() {
    if [ ! -f "$AUTO_UPDATE_CONFIG" ]; then
        echo "未开启"
        return
    fi

    local schedule
    schedule=$(awk -F'=' '$1=="SCHEDULE" {print $2}' "$AUTO_UPDATE_CONFIG" 2>/dev/null)

    case $schedule in
        hourly)
            echo "已启用（每 6 小时刷新）"
            ;;
        daily)
            echo "已启用（每日 03:00 刷新）"
            ;;
        weekly)
            echo "已启用（每周日 03:00 刷新）"
            ;;
        *)
            echo "已启用"
            ;;
    esac
}

write_auto_update_cron() {
    local schedule=$1
    local cron_expr=$2

    local script_path
    script_path=$(command -v port-filter 2>/dev/null || readlink -f "$0")

    mkdir -p "$(dirname "$AUTO_UPDATE_LOG")"
    touch "$AUTO_UPDATE_LOG"

    cat <<EOF > "$AUTO_UPDATE_CRON_FILE"
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$cron_expr root "$script_path" --refresh-rules >> "$AUTO_UPDATE_LOG" 2>&1
EOF

    chmod 644 "$AUTO_UPDATE_CRON_FILE"

    {
        echo "SCHEDULE=$schedule"
        echo "CRON_EXPRESSION=\"$cron_expr\""
        echo "UPDATED_AT=$(date '+%Y-%m-%d %H:%M:%S')"
    } > "$AUTO_UPDATE_CONFIG"

    log_success "自动更新任务已配置（$(describe_auto_update_schedule)）"
}

disable_auto_update() {
    rm -f "$AUTO_UPDATE_CRON_FILE" "$AUTO_UPDATE_CONFIG"
    log_success "已关闭自动更新"
}

setup_auto_update() {
    print_banner
    echo -e "${MAGENTA}==================== 自动更新规则 ====================${NC}"
    echo "当前状态：$(describe_auto_update_schedule)"
    echo ""
    echo "  1) 每 6 小时刷新一次（推荐）"
    echo "  2) 每日凌晨 03:00 刷新"
    echo "  3) 每周日凌晨 03:00 刷新"
    echo "  4) 关闭自动更新"
    echo "  0) 返回上级"
    read -rp "请选择 [0-4]: " choice

    case $choice in
        1)
            write_auto_update_cron "hourly" "0 */6 * * *"
            ;;
        2)
            write_auto_update_cron "daily" "0 3 * * *"
            ;;
        3)
            write_auto_update_cron "weekly" "0 3 * * 0"
            ;;
        4)
            disable_auto_update
            ;;
        0)
            log_info "已返回主菜单"
            ;;
        *)
            log_error "无效选择"
            ;;
    esac

    press_enter
}

show_configured_rules() {
    print_banner
    echo -e "${MAGENTA}==================== 已配置规则 ====================${NC}"
    if [ ! -s "$CONFIG_FILE" ]; then
        log_warn "尚未配置任何规则"
        press_enter
        return
    fi

    printf "%-8s %-8s %-14s %-30s %-16s\n" "端口" "协议" "控制类型" "国家/地区" "IP 集合"
    printf '%s\n' "----------------------------------------------------------------------------------------------------"

    while IFS='|' read -r port protocol type ipset countries; do
        local type_text=""
        case $type in
            geo_blacklist) type_text="地域黑名单" ;;
            geo_whitelist) type_text="地域白名单" ;;
            block) type_text="完全屏蔽" ;;
            allow) type_text="完全放行" ;;
            *) type_text="$type" ;;
        esac
        printf "%-8s %-8s %-14s %-30s %-16s\n" "$port" "$protocol" "$type_text" "$(describe_countries "$countries")" "${ipset:- -}"
    done < "$CONFIG_FILE"

    press_enter
}

show_firewall_rules() {
    print_banner
    echo -e "${MAGENTA}==================== 当前 iptables 规则 ====================${NC}"
    echo -e "${YELLOW}TCP 规则：${NC}"
    iptables -L INPUT -n -v --line-numbers | grep "tcp" | head -n 30
    echo ""
    echo -e "${YELLOW}UDP 规则：${NC}"
    iptables -L INPUT -n -v --line-numbers | grep "udp" | head -n 30
    press_enter
}

setup_geo_filter() {
    print_banner
    echo -e "${MAGENTA}==================== 地域访问控制 ====================${NC}"

    read -rp "请输入端口号: " port
    if ! validate_port "$port"; then
        press_enter
        return
    fi

    local protocol
    if ! protocol=$(select_protocol); then
        press_enter
        return
    fi

    local mode
    if ! mode=$(select_mode); then
        press_enter
        return
    fi

    local countries
    if ! countries=$(prompt_countries); then
        press_enter
        return
    fi

    local ipset_name=$(generate_ipset_name "$countries")
    apply_geo_rule "$port" "$protocol" "$mode" "$ipset_name" "$countries"

    if [ "$mode" = "blacklist" ]; then
        update_config_entry "$port" "$protocol" "geo_blacklist" "$ipset_name" "$countries"
    else
        update_config_entry "$port" "$protocol" "geo_whitelist" "$ipset_name" "$countries"
    fi

    save_rules
    press_enter
}

setup_block_port() {
    print_banner
    echo -e "${MAGENTA}==================== 屏蔽端口 ====================${NC}"

    read -rp "请输入要屏蔽的端口号: " port
    if ! validate_port "$port"; then
        press_enter
        return
    fi

    local protocol
    if ! protocol=$(select_protocol); then
        press_enter
        return
    fi

    block_port "$port" "$protocol"
    update_config_entry "$port" "$protocol" "block" "-" "-"
    save_rules
    press_enter
}

setup_allow_port() {
    print_banner
    echo -e "${MAGENTA}==================== 放行端口 ====================${NC}"

    read -rp "请输入要放行的端口号: " port
    if ! validate_port "$port"; then
        press_enter
        return
    fi

    local protocol
    if ! protocol=$(select_protocol); then
        press_enter
        return
    fi

    allow_port "$port" "$protocol"
    update_config_entry "$port" "$protocol" "allow" "-" "-"
    save_rules
    press_enter
}

update_country_cache() {
    print_banner
    echo -e "${MAGENTA}==================== 更新国家/地区 IP 数据 ====================${NC}"
    echo "  1) 更新全部内置国家/地区"
    echo "  2) 仅更新中国大陆数据"
    echo "  3) 更新国内运营商/骨干网络扩展"
    echo "  4) 指定国家/地区"
    read -rp "请选择 [1-4]: " choice

    local targets=""
    case $choice in
        1)
            local codes=()
            for option in "${COUNTRY_OPTIONS[@]}"; do
                IFS='|' read -r code _ <<< "$option"
                codes+=("$code")
            done
            targets=$(IFS=','; echo "${codes[*]}")
            ;;
        2)
            targets="CN"
            ;;
        3)
            targets="CN_MAINLAND,CN_CT,CN_CUCC,CN_CMCC,CN_CERNET,CN_BACKBONE"
            ;;
        4)
            if ! targets=$(prompt_countries); then
                press_enter
                return
            fi
            ;;
        *)
            log_error "无效选择"
            press_enter
            return
            ;;
    esac

    IFS=',' read -ra codes <<< "$targets"
    for code in "${codes[@]}"; do
        fetch_country_data "$code" 1 >/dev/null || true
    done

    log_success "IP 数据更新完成"
    press_enter
}

delete_rule() {
    print_banner
    echo -e "${MAGENTA}==================== 删除规则 ====================${NC}"

    if [ ! -s "$CONFIG_FILE" ]; then
        log_warn "当前没有任何规则"
        press_enter
        return
    fi

    local -a entries=()
    local index=1
    while IFS='|' read -r port protocol type ipset countries; do
        entries+=("$port|$protocol|$type|$ipset|$countries")
        local type_text=""
        case $type in
            geo_blacklist) type_text="地域黑名单" ;;
            geo_whitelist) type_text="地域白名单" ;;
            block) type_text="完全屏蔽" ;;
            allow) type_text="完全放行" ;;
            *) type_text="$type" ;;
        esac
        printf "  %2d) 端口 %-5s 协议 %-4s 类型 %-10s 地区 %s\n" "$index" "$port" "$protocol" "$type_text" "$(describe_countries "$countries")"
        ((index++))
    done < "$CONFIG_FILE"

    read -rp "请选择要删除的规则编号: " choice
    if [[ ! $choice =~ ^[0-9]+$ ]] || [ "$choice" -le 0 ] || [ "$choice" -gt ${#entries[@]} ]; then
        log_error "无效编号"
        press_enter
        return
    fi

    local entry="${entries[$((choice-1))]}"
    IFS='|' read -r port protocol type ipset countries <<< "$entry"

    remove_config_entry "$port" "$protocol"

    if [[ $type == geo_* ]]; then
        ipset destroy "$ipset" 2>/dev/null || true
    fi

    reload_rules_for_port "$port"
    save_rules

    log_success "已删除端口 $port ($protocol) 的规则"
    press_enter
}

clear_all_rules() {
    print_banner
    echo -e "${MAGENTA}==================== 清除所有规则 ====================${NC}"
    read -rp "确认清除所有规则并删除配置文件？(y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_info "已取消操作"
        press_enter
        return
    fi

    if [ -s "$CONFIG_FILE" ]; then
        while IFS='|' read -r port protocol type ipset _; do
            clear_port_rules "$port"
            if [[ $type == geo_* ]]; then
                ipset destroy "$ipset" 2>/dev/null || true
            fi
        done < "$CONFIG_FILE"
    fi

    if command_exists ipset; then
        ipset list -name 2>/dev/null | grep "^${IPSET_PREFIX}" | while read -r set; do
            ipset destroy "$set" 2>/dev/null || true
        done
    fi

    > "$CONFIG_FILE"
    save_rules
    log_success "已清除脚本创建的所有规则"
    press_enter
}

show_menu() {
    print_banner
    echo -e "${CYAN}自动更新状态：$(describe_auto_update_schedule)${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} 配置地域访问控制"
    echo -e "${GREEN}2.${NC} 屏蔽端口"
    echo -e "${GREEN}3.${NC} 放行端口"
    echo -e "${GREEN}4.${NC} 查看已配置规则"
    echo -e "${GREEN}5.${NC} 删除指定规则"
    echo -e "${GREEN}6.${NC} 更新国家/地区 IP 数据"
    echo -e "${GREEN}7.${NC} 查看当前 iptables 规则"
    echo -e "${GREEN}8.${NC} 清除所有规则"
    echo -e "${GREEN}9.${NC} 设置自动更新"
    echo -e "${GREEN}0.${NC} 退出"
    echo ""
    read -rp "请选择操作 [0-9]: " choice

    case $choice in
        1) setup_geo_filter ;;
        2) setup_block_port ;;
        3) setup_allow_port ;;
        4) show_configured_rules ;;
        5) delete_rule ;;
        6) update_country_cache ;;
        7) show_firewall_rules ;;
        8) clear_all_rules ;;
        9) setup_auto_update ;;
        0)
            log_success "感谢使用，再见！"
            exit 0
            ;;
        *)
            log_error "无效选择，请重试"
            sleep 1
            ;;
    esac
}

main() {
    check_root
    init_environment
    install_dependencies
    load_config

    while true; do
        show_menu
    done
}

handle_cli_args() {
    case ${1:-} in
        --refresh-rules)
            check_root
            init_environment
            if [ ! -s "$CONFIG_FILE" ]; then
                log_warn "没有可刷新的地域规则"
                exit 0
            fi
            refresh_all_geo_rules 1
            save_rules
            exit 0
            ;;
        --refresh-cache)
            check_root
            init_environment
            if [ ! -s "$CONFIG_FILE" ]; then
                log_warn "当前没有任何规则可用于更新缓存"
                exit 0
            fi

            local -A seen=()
            while IFS='|' read -r _port _protocol type _ipset countries; do
                [[ $type == geo_* ]] || continue
                IFS=',' read -ra codes <<< "$countries"
                for code in "${codes[@]}"; do
                    code=${code^^}
                    if [ -z "${seen[$code]:-}" ]; then
                        fetch_country_data "$code" 1 >/dev/null || true
                        seen[$code]=1
                    fi
                done
            done < "$CONFIG_FILE"

            log_success "地域规则缓存已更新"
            exit 0
            ;;
    esac
}

handle_cli_args "$@"

main
