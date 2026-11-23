#!/bin/bash
# port-filter.sh - 端口访问控制一键脚本（IP 源规则库版）
# 支持：IP地域过滤、端口屏蔽/放行、TCP/UDP协议控制、白名单管理、IP源规则库选择、自动更新计划

VERSION="3.2.0"

CONFIG_DIR="/etc/port-filter"
RULES_FILE="$CONFIG_DIR/rules.conf"
WHITELIST_FILE="$CONFIG_DIR/whitelist.conf"
SETTINGS_FILE="$CONFIG_DIR/settings.conf"
SOURCE_LIB_FILE="$CONFIG_DIR/ip_sources.conf"

IPSET_NAME="china"
IPSET_WHITE="whitelist"
IPSET_MAXELEM=65536
# 下载中国IP列表时先装入这个临时集合，全部成功后再与 china 交换，
# 避免下载失败时把正在使用的集合清空
IPSET_TMP="${IPSET_NAME}_new"
# 本脚本添加的 iptables 规则都带这个注释标记，用于准确识别和清理，不误删其它规则
RULE_TAG="port-filter"

CRON_FILE="/etc/cron.d/port-filter"
LOG_FILE="/var/log/port-filter/update.log"

APT_UPDATED=0

# 有些环境（部分发行版的 cron、精简的容器等）的 PATH 不包含 /usr/sbin，而 iptables、ipset 就装在那里，这里统一补上
PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# 当前脚本路径（给定时任务用）
SCRIPT_PATH="$(readlink -f "$0")"

# 颜色定义（兼容 SSH 终端）
if command -v tput >/dev/null 2>&1 && [ -n "$TERM" ] && [ "$TERM" != "dumb" ]; then
    RED="$(tput setaf 1 2>/dev/null)"
    GREEN="$(tput setaf 2 2>/dev/null)"
    YELLOW="$(tput setaf 3 2>/dev/null)"
    BLUE="$(tput setaf 4 2>/dev/null)"
    MAGENTA="$(tput setaf 5 2>/dev/null)"
    CYAN="$(tput setaf 6 2>/dev/null)"
    BOLD="$(tput bold 2>/dev/null)"
    NC="$(tput sgr0 2>/dev/null)"
fi

if [ -z "${NC:-}" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
fi

# IP 源规则库（你说的“规则库”就是这里）
IP_SOURCES=(
    "metowolf/IPList|https://raw.githubusercontent.com/metowolf/iplist/master/data/country/CN.txt"
    "17mon/ChinaIPList|https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt"
    "gaoyifan/OperatorIP|https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt"
)

# 常用打印函数
print_info()    { printf "%b%s%b\n" "$CYAN"   "$1" "$NC"; }
print_success() { printf "%b%s%b\n" "$GREEN"  "$1" "$NC"; }
print_warning() { printf "%b%s%b\n" "$YELLOW" "$1" "$NC"; }
print_error()   { printf "%b%s%b\n" "$RED"    "$1" "$NC"; }

print_title() {
    printf "${BOLD}${MAGENTA}╔════════════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAGENTA}║ 端口访问控制脚本 v%s%-28s║${NC}\n" "$VERSION" ""
    printf "${BOLD}${MAGENTA}╚════════════════════════════════════════════════╝${NC}\n"
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "错误：请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 清屏（系统没有 clear 命令时用转义序列代替）
clear_screen() {
    clear 2>/dev/null || printf '\033[2J\033[3J\033[H'
}

# 校验 IPv4 地址或网段（如 192.168.1.100、10.0.0.0/8），合法返回 0
is_valid_ipv4_cidr() {
    local ip="$1" addr prefix octet a b c d ip_int

    # 每段 1-3 位数字、不带前导零；前缀长度 0-32
    if ! [[ "$ip" =~ ^([0-9]|[1-9][0-9]{1,2})(\.([0-9]|[1-9][0-9]{1,2})){3}(/[0-9]|/[12][0-9]|/3[0-2])?$ ]]; then
        return 1
    fi

    addr="${ip%%/*}"
    for octet in ${addr//./ }; do
        (( octet > 255 )) && return 1
    done

    # 带 / 前缀时必须是网络地址（主机位全为 0），否则 ipset 会拒绝
    if [[ "$ip" == */* ]]; then
        prefix="${ip#*/}"
        IFS='.' read -r a b c d <<< "$addr"
        ip_int=$(( a << 24 | b << 16 | c << 8 | d ))
        (( (ip_int & ~((1 << (32 - prefix)) - 1)) == ip_int )) || return 1
    fi

    return 0
}

# 校验端口号或端口范围（如 22、8000:9000），合法返回 0
is_valid_port() {
    local port="$1" first="${1%%:*}" last="${1#*:}"

    if ! [[ "$port" =~ ^[1-9][0-9]{0,4}(:[1-9][0-9]{0,4})?$ ]]; then
        return 1
    fi
    (( first >= 1 && first <= 65535 && last >= first && last <= 65535 ))
}

# 去掉行内注释（# 之后）和空白字符，用于读取配置文件和下载列表里的一行
strip_line() {
    local s="${1%%#*}"
    printf '%s' "${s//[[:space:]]/}"
}

# 依赖安装
install_dependencies() {
    print_info "[1/3] 检查并安装依赖..."

    apt_update_once() {
        if [ $APT_UPDATED -eq 0 ]; then
            apt-get update -qq
            APT_UPDATED=1
        fi
    }

    # 缺少某个命令时用 apt 安装对应的包；安装失败会给出提示，不再静默忽略
    apt_install() {
        local cmd="$1" pkg="$2"
        command -v "$cmd" >/dev/null 2>&1 && return 0
        if ! command -v apt-get >/dev/null 2>&1; then
            print_warning "缺少 $cmd，且本系统没有 apt-get，请手动安装: $pkg"
            return 1
        fi
        apt_update_once
        if ! apt-get install -y "$pkg" >/dev/null 2>&1 || ! command -v "$cmd" >/dev/null 2>&1; then
            print_warning "安装 $pkg 失败，请手动执行: apt-get install $pkg"
            return 1
        fi
        return 0
    }

    apt_install ipset ipset
    apt_install iptables iptables
    apt_install netfilter-persistent iptables-persistent
    apt_install curl curl

    # iptables-persistent 只保存 iptables 规则；ipset-persistent 让 netfilter-persistent
    # 同时保存和恢复 ipset 集合，否则重启后规则引用的集合不存在，规则会恢复失败
    if command -v apt-get >/dev/null 2>&1 && [ -d /usr/share/netfilter-persistent/plugins.d ] \
        && ! compgen -G "/usr/share/netfilter-persistent/plugins.d/*ipset*" >/dev/null; then
        apt_update_once
        apt-get install -y ipset-persistent >/dev/null 2>&1 \
            || print_warning "安装 ipset-persistent 失败：ipset 集合不会被持久化，重启后规则可能恢复失败"
    fi

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"

    # 没有这两个命令脚本无法工作，直接报错退出
    if ! command -v ipset >/dev/null 2>&1 || ! command -v iptables >/dev/null 2>&1; then
        print_error "错误：缺少必需的依赖 (ipset / iptables)，无法继续"
        exit 1
    fi
}

# 初始化白名单配置
init_whitelist() {
    if [ ! -f "$WHITELIST_FILE" ]; then
        cat > "$WHITELIST_FILE" << 'EOF'
# IP白名单配置
# 支持单个IP: 192.168.1.100
# 支持IP段: 10.0.0.0/8
# 白名单IP不会被任何规则拦截
EOF
    fi
}

# 创建白名单 ipset
create_whitelist_set() {
    if ! ipset list "$IPSET_WHITE" >/dev/null 2>&1; then
        ipset create "$IPSET_WHITE" hash:net maxelem "$IPSET_MAXELEM"
    fi
}

# 把临时集合 $1 切换为正式集合 $2
# 正式集合已存在时用 swap 原子交换（正在引用它的 iptables 规则不受影响），不存在时直接改名
swap_in_set() {
    local tmp="$1" target="$2"

    if ! ipset list "$target" >/dev/null 2>&1; then
        ipset rename "$tmp" "$target"
        return $?
    fi

    if ipset swap "$tmp" "$target" 2>/dev/null; then
        ipset destroy "$tmp"
        return 0
    fi

    # swap 失败（比如旧集合的类型不一样）：旧集合没有被任何规则引用时，才用改名的方式替换
    if [ "$(ipset list -t "$target" 2>/dev/null | awk '/^References:/{print $2}')" != "0" ]; then
        return 1
    fi
    ipset rename "$target" "${target}_old" || return 1
    if ipset rename "$tmp" "$target"; then
        ipset destroy "${target}_old" 2>/dev/null
    else
        ipset rename "${target}_old" "$target"
        return 1
    fi
    return 0
}

# 加载白名单：先装入临时集合再交换，正在生效的白名单不会出现空档
load_whitelist() {
    local tmp="${IPSET_WHITE}_new" line ip invalid=0

    ipset destroy "$tmp" 2>/dev/null
    ipset create "$tmp" hash:net maxelem "$IPSET_MAXELEM" || return 1

    if [ -f "$WHITELIST_FILE" ]; then
        # 最后一行没有换行符时也要处理
        while IFS= read -r line || [ -n "$line" ]; do
            ip="$(strip_line "$line")"
            [ -z "$ip" ] && continue

            if ! is_valid_ipv4_cidr "$ip"; then
                print_warning "白名单中忽略了无效条目: $ip"
                invalid=$((invalid+1))
                continue
            fi
            ipset add "$tmp" "$ip" -exist 2>/dev/null || invalid=$((invalid+1))
        done < "$WHITELIST_FILE"
    fi

    swap_in_set "$tmp" "$IPSET_WHITE" || { ipset destroy "$tmp" 2>/dev/null; return 1; }
    [ "$invalid" -eq 0 ]
}

# 判断白名单文件里是否有某个 IP/IP 段（忽略注释和空白）
whitelist_file_has() {
    [ -f "$WHITELIST_FILE" ] || return 1
    awk -v ip="$1" '
        { s = $0; sub(/#.*/, "", s); gsub(/[ \t\r]/, "", s); if (s == ip) found = 1 }
        END { exit found ? 0 : 1 }
    ' "$WHITELIST_FILE"
}

# 初始化 IP 源规则库（默认启用全部内置源）
init_ip_sources() {
    mkdir -p "$CONFIG_DIR"
    if [ ! -f "$SOURCE_LIB_FILE" ]; then
        : > "$SOURCE_LIB_FILE"
        for entry in "${IP_SOURCES[@]}"; do
            IFS='|' read -r name url <<< "$entry"
            echo "$name" >> "$SOURCE_LIB_FILE"
        done
    fi
}

# 添加 IP 到白名单
add_whitelist_ip() {
    local ip="$1"

    if ! is_valid_ipv4_cidr "$ip"; then
        print_error "无效的IP地址格式: $ip（单个IP写成 192.168.1.100，IP段写成 10.0.0.0/8）"
        return 1
    fi

    mkdir -p "$CONFIG_DIR"
    if whitelist_file_has "$ip"; then
        print_warning "IP $ip 已存在于白名单中"
    else
        echo "$ip" >> "$WHITELIST_FILE" || { print_error "✗ 无法写入 $WHITELIST_FILE"; return 1; }
        print_success "已添加 $ip 到白名单"
    fi

    # 重新加载，让配置文件和 ipset 集合保持一致
    load_whitelist || print_warning "白名单重新加载失败，请检查上方信息"
    return 0
}

# 从白名单移除 IP
remove_whitelist_ip() {
    local ip="$1" tmp

    if ! is_valid_ipv4_cidr "$ip"; then
        print_error "无效的IP地址格式: $ip"
        return 1
    fi

    if ! whitelist_file_has "$ip"; then
        print_warning "IP $ip 不在白名单中"
        return 1
    fi

    # 整行精确匹配后再删除（IP 段里的“/”不能直接放进 sed 的表达式）
    mkdir -p "$CONFIG_DIR"
    tmp="$(mktemp "$CONFIG_DIR/.whitelist.XXXXXX")" || return 1
    awk -v ip="$ip" '{ s = $0; sub(/#.*/, "", s); gsub(/[ \t\r]/, "", s); if (s != ip) print }' "$WHITELIST_FILE" > "$tmp" || true
    cat "$tmp" > "$WHITELIST_FILE"
    rm -f "$tmp"
    print_success "已从白名单移除 $ip"

    # 重新加载，让配置文件和 ipset 集合保持一致
    load_whitelist || print_warning "白名单重新加载失败，请检查上方信息"
    return 0
}

# 显示白名单
show_whitelist() {
    print_info "当前白名单IP:"
    if [ -f "$WHITELIST_FILE" ]; then
        local count=0 line
        while IFS= read -r line || [ -n "$line" ]; do
            line="$(strip_line "$line")"
            [ -z "$line" ] && continue
            echo "  $line"
            ((count++))
        done < "$WHITELIST_FILE"

        if [ $count -eq 0 ]; then
            print_warning "白名单为空"
        fi
    else
        print_warning "白名单文件不存在"
    fi
}

# 下载中国 IP 列表（使用“已启用”的 IP 源规则库）
# 整个函数在子 shell 中运行：先装入临时集合，全部成功后再与 china 交换，
# 任何一步失败都保留正在使用的集合不变
download_china_ip() (
    print_info "正在下载中国IP列表..."

    local tmp_dir="" entry name url a line ip list_file
    local success=0 total=0 failed_sources=""
    local active_sources=()

    tmp_dir="$(mktemp -d /tmp/port-filter.XXXXXX)" || exit 1
    # 正常结束、失败或被中断，都清理临时文件和临时集合
    trap 'rm -rf "$tmp_dir"; ipset destroy "$IPSET_TMP" 2>/dev/null' EXIT

    ipset destroy "$IPSET_TMP" 2>/dev/null
    ipset create "$IPSET_TMP" hash:net maxelem "$IPSET_MAXELEM" || { print_error "✗ 无法创建临时集合 $IPSET_TMP"; exit 1; }

    # 读取当前启用的 IP 源规则库
    if [ -f "$SOURCE_LIB_FILE" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="$(strip_line "$line")"
            [ -z "$line" ] && continue
            active_sources+=("$line")
        done < "$SOURCE_LIB_FILE"
    fi

    for entry in "${IP_SOURCES[@]}"; do
        IFS='|' read -r name url <<< "$entry"

        # 判断该源是否启用
        local use_this=0
        if [ ${#active_sources[@]} -eq 0 ]; then
            # 没配置时默认全部启用
            use_this=1
        else
            for a in "${active_sources[@]}"; do
                if [ "$a" = "$name" ]; then
                    use_this=1
                    break
                fi
            done
        fi

        [ "$use_this" -eq 0 ] && continue

        print_info "正在从 $name 下载（$url）..."
        # -f：HTTP 错误码直接判为失败；--retry：网络抖动时自动重试
        if curl -fsSL --connect-timeout 10 --max-time 120 --retry 2 "$url" -o "$tmp_dir/$success.list"; then
            print_success "✓ 从 $name 下载成功"
            success=$((success+1))
        else
            rm -f "$tmp_dir/$success.list"
            print_error "✗ 从 $name 下载失败"
            failed_sources="$failed_sources $name"
        fi
    done

    if [ "$success" -eq 0 ]; then
        print_error "✗ 所有已启用的 IP 源下载失败，请检查网络或规则库配置"
        print_warning "  正在使用的 IP 集合未改动，现有规则不受影响"
        exit 1
    fi

    # 校验每一行，只保留合法的 IPv4 网段
    for list_file in "$tmp_dir"/*.list; do
        while IFS= read -r ip || [ -n "$ip" ]; do
            ip="$(strip_line "$ip")"
            [ -z "$ip" ] && continue
            is_valid_ipv4_cidr "$ip" || continue
            echo "add $IPSET_TMP $ip"
        done < "$list_file"
    done | sort -u > "$tmp_dir/restore"
    total="$(wc -l < "$tmp_dir/restore")"

    if [ "$total" -eq 0 ]; then
        print_error "✗ 下载到的内容里没有有效的 IP 段"
        print_warning "  正在使用的 IP 集合未改动，现有规则不受影响"
        exit 1
    fi

    # 一次性导入（-exist：多个源之间重复的网段自动忽略）
    if ! ipset restore -exist < "$tmp_dir/restore" 2> "$tmp_dir/err"; then
        print_error "✗ 导入 IP 段失败$(tail -n 1 "$tmp_dir/err" | sed 's/^.*: /: /')"
        print_warning "  正在使用的 IP 集合未改动，现有规则不受影响"
        exit 1
    fi

    # 切换到新集合
    swap_in_set "$IPSET_TMP" "$IPSET_NAME" || { print_error "✗ 无法切换到新的 IP 集合，正在使用的集合未改动"; exit 1; }

    print_success "✓ 成功导入 $total 条 IP 规则（来自 $success 个源）"
    if [ -n "$failed_sources" ]; then
        print_warning "  以下源下载失败，本次未纳入：$failed_sources"
    fi
    exit 0
)

# 把协议选择展开成具体协议：both → tcp udp
protocol_list() {
    if [ "$1" = "both" ]; then
        echo "tcp udp"
    else
        echo "$1"
    fi
}

# 输出已保存的端口策略，一行一条：端口|协议|模式|类型
# 旧版本保存的 both 会展开成 tcp、udp 两条，重复的记录只保留一条
read_rules() {
    [ -f "$RULES_FILE" ] || return 0
    local port proto mode action

    while IFS='|' read -r port proto mode action || [ -n "$port" ]; do
        [ -n "$port" ] && [ -n "$action" ] || continue
        for proto in $(protocol_list "$proto"); do
            echo "$port|$proto|$mode|$action"
        done
    done < "$RULES_FILE" | awk '!seen[$0]++'
}

# 输出已保存的端口策略，但去掉指定端口的记录（$2 为协议选择，both 表示 tcp 和 udp）
read_rules_except() {
    read_rules | grep -v -E "^$1\|($(protocol_list "$2" | tr ' ' '|'))\|" || true
}

# 保存端口策略到配置文件
# 同一端口+协议只保留一条记录；同一端口的另一种协议如果已有记录，保持不变
save_rule_config() {
    local port="$1" protocol="$2" mode="$3" action="$4" proto tmp

    mkdir -p "$CONFIG_DIR"
    tmp="$(mktemp "$CONFIG_DIR/.rules.XXXXXX")" || return 1
    # 先写入其它端口/协议的策略（顺带去掉旧记录和重复记录），再追加本次的策略
    read_rules_except "$port" "$protocol" > "$tmp"
    for proto in $(protocol_list "$protocol"); do
        echo "${port}|${proto}|${mode}|${action}" >> "$tmp"
    done
    cat "$tmp" > "$RULES_FILE"
    rm -f "$tmp"
}

# 从端口策略文件中删除某端口的记录
remove_rule_config() {
    local port="$1" protocol="$2" tmp

    [ -f "$RULES_FILE" ] || return 0
    mkdir -p "$CONFIG_DIR"
    tmp="$(mktemp "$CONFIG_DIR/.rules.XXXXXX")" || return 1
    read_rules_except "$port" "$protocol" > "$tmp"
    cat "$tmp" > "$RULES_FILE"
    rm -f "$tmp"
}

# 组装一条 INPUT 规则的参数（不含动作和链名），结果放在数组 RULE_ARGS 里
# 用法：build_rule <tcp|udp> <端口> <white|cn_drop|cn_accept|drop|accept> [legacy]
# 默认带 port-filter 注释标记；legacy 用来生成 3.1.0 及更早版本的旧规则（没有标记）
build_rule() {
    local proto="$1" port="$2" kind="$3" set_name="" target

    RULE_ARGS=(-p "$proto" --dport "$port")
    case "$kind" in
        white)     set_name="$IPSET_WHITE"; target=ACCEPT ;;
        cn_drop)   set_name="$IPSET_NAME";  target=DROP ;;
        cn_accept) set_name="$IPSET_NAME";  target=ACCEPT ;;
        drop)      target=DROP ;;
        accept)    target=ACCEPT ;;
        *) return 1 ;;
    esac
    [ -n "$set_name" ] && RULE_ARGS+=(-m set --match-set "$set_name" src)
    [ "${4:-}" != "legacy" ] && RULE_ARGS+=(-m comment --comment "$RULE_TAG")
    RULE_ARGS+=(-j "$target")
    return 0
}

# 在 INPUT 链最前面插入一条带标记的规则
insert_rule() {
    build_rule "$1" "$2" "$3" || return 1
    iptables -I INPUT "${RULE_ARGS[@]}"
}

# 删除某端口某协议上本脚本的某类规则
# 带标记的规则全部删除；旧版本（3.1.0 及更早）的无标记规则只在该端口
# 记录在端口策略文件里时才删除，避免误删不是本脚本添加的规则
delete_rule_kind() {
    local proto="$1" port="$2" kind="$3"

    build_rule "$proto" "$port" "$kind" || return 1
    while iptables -D INPUT "${RULE_ARGS[@]}" 2>/dev/null; do :; done

    if [ -f "$RULES_FILE" ] && grep -q "^${port}|" "$RULES_FILE"; then
        build_rule "$proto" "$port" "$kind" legacy
        while iptables -D INPUT "${RULE_ARGS[@]}" 2>/dev/null; do :; done
    fi
    return 0
}

# 端口上还留有不带标记的屏蔽/放行规则时提醒用户：它们不是本脚本（或有配置记录的旧版本规则）
warn_foreign_rules() {
    local proto="$1" port="$2" kind

    for kind in drop accept; do
        build_rule "$proto" "$port" "$kind" legacy
        if iptables -C INPUT "${RULE_ARGS[@]}" 2>/dev/null; then
            print_warning "端口 $port/$proto 上有不带标记的 $kind 规则（不是本脚本添加的，或是没有配置记录的旧规则），已保留，请用 iptables -L INPUT 确认"
        fi
    done
}

# 清除某个端口上本脚本添加的规则（both 同时处理 tcp 和 udp）
clear_port_rules() {
    local port="$1" protocol="$2" proto kind

    for proto in $(protocol_list "$protocol"); do
        for kind in white cn_drop cn_accept drop accept; do
            delete_rule_kind "$proto" "$port" "$kind"
        done
        warn_foreign_rules "$proto" "$port"
    done
}

# 应用规则中途失败时调用：撤掉本端口本次涉及的规则
fail_port() {
    local port="$1" protocol="$2" proto="$3"
    print_error "✗ ${proto^^}端口 $port: 规则应用失败，已撤回本次修改"
    clear_port_rules "$port" "$protocol"
    return 1
}

# 确保 IP 地域 ipset 存在且不为空
ensure_ipset_exists() {
    local count

    if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        download_china_ip
        return $?
    fi

    # 集合存在但是空的（例如旧版本下载失败后被清空）：重新下载
    count="$(ipset list -t "$IPSET_NAME" 2>/dev/null | awk '/^Number of entries:/{print $4}')"
    if [ -n "$count" ] && [ "$count" -eq 0 ]; then
        download_china_ip
        return $?
    fi

    return 0
}

# 判断某端口某协议上的地域规则是否都还在（定时更新时只补回丢失的规则）
geo_rules_present() {
    local port="$1" proto="$2" mode="$3"

    build_rule "$proto" "$port" white
    iptables -C INPUT "${RULE_ARGS[@]}" 2>/dev/null || return 1
    if [ "$mode" = "whitelist" ]; then
        build_rule "$proto" "$port" drop
        iptables -C INPUT "${RULE_ARGS[@]}" 2>/dev/null || return 1
        build_rule "$proto" "$port" cn_accept
        iptables -C INPUT "${RULE_ARGS[@]}" 2>/dev/null || return 1
    else
        build_rule "$proto" "$port" cn_drop
        iptables -C INPUT "${RULE_ARGS[@]}" 2>/dev/null || return 1
    fi
    return 0
}

# 应用地域规则（顺序：白名单 → 地域规则；-I 插在链顶，所以按相反顺序插入）
apply_rule() {
    local port="$1" protocol="$2" mode="$3" proto

    case "$mode" in
        blacklist|whitelist) ;;
        *) print_error "未知的地域过滤模式: $mode"; return 1 ;;
    esac

    # 先确保中国IP集合可用，拿不到时不改动现有规则
    ensure_ipset_exists || { print_error "✗ 无法获取中国IP列表，端口 $port 的规则未修改"; return 1; }
    create_whitelist_set || { print_error "✗ 无法创建白名单集合 $IPSET_WHITE"; return 1; }

    clear_port_rules "$port" "$protocol"

    for proto in $(protocol_list "$protocol"); do
        if [ "$mode" = "blacklist" ]; then
            insert_rule "$proto" "$port" cn_drop || { fail_port "$port" "$protocol" "$proto"; return 1; }
        else
            # 白名单模式：先插“全部拦截”，再插“放行中国IP”，保证放行规则排在前面
            insert_rule "$proto" "$port" drop || { fail_port "$port" "$protocol" "$proto"; return 1; }
            insert_rule "$proto" "$port" cn_accept || { fail_port "$port" "$protocol" "$proto"; return 1; }
        fi
        # 最后插入白名单放行规则（后插入的排在最前，优先级最高）
        insert_rule "$proto" "$port" white || { fail_port "$port" "$protocol" "$proto"; return 1; }

        if [ "$mode" = "blacklist" ]; then
            print_success "✓ ${proto^^}端口 $port: 已设置黑名单（阻止中国IP）"
        else
            print_success "✓ ${proto^^}端口 $port: 已设置白名单（仅允许中国IP）"
        fi
    done

    return 0
}

# 屏蔽端口
block_port() {
    local port="$1" protocol="$2" proto

    create_whitelist_set || { print_error "✗ 无法创建白名单集合 $IPSET_WHITE"; return 1; }
    clear_port_rules "$port" "$protocol"

    for proto in $(protocol_list "$protocol"); do
        # 先插屏蔽规则，最后插白名单放行规则（后插入的排在最前，白名单优先放行）
        insert_rule "$proto" "$port" drop || { fail_port "$port" "$protocol" "$proto"; return 1; }
        insert_rule "$proto" "$port" white || { fail_port "$port" "$protocol" "$proto"; return 1; }
        print_success "✓ 已屏蔽 ${proto^^} 端口 $port"
    done

    return 0
}

# 放行端口（顺序与屏蔽端口一致）
allow_port() {
    local port="$1" protocol="$2" proto

    create_whitelist_set || { print_error "✗ 无法创建白名单集合 $IPSET_WHITE"; return 1; }
    clear_port_rules "$port" "$protocol"

    for proto in $(protocol_list "$protocol"); do
        # 先插放行规则，最后插白名单放行规则（统一保证白名单最高优先级）
        insert_rule "$proto" "$port" accept || { fail_port "$port" "$protocol" "$proto"; return 1; }
        insert_rule "$proto" "$port" white || { fail_port "$port" "$protocol" "$proto"; return 1; }
        print_success "✓ 已放行 ${proto^^} 端口 $port"
    done

    return 0
}

# 查看当前规则
show_rules() {
    print_info "==================== 当前防火墙规则 ====================="
    print_warning "TCP 规则："
    iptables -L INPUT -n -v --line-numbers | grep -E "tcp dpts?:" | head -20 || true
    echo ""
    print_warning "UDP 规则："
    iptables -L INPUT -n -v --line-numbers | grep -E "udp dpts?:" | head -20 || true
    print_info "========================================================="
}

# 查看保存的端口策略
show_saved_configs() {
    if [ ! -f "$RULES_FILE" ]; then
        print_warning "暂无保存的端口策略"
        return
    fi

    print_info "==================== 已保存的端口策略 ===================="
    printf "%s%-8s%-12s%-16s%-16s%s\n" "$BOLD" "端口" "协议" "模式" "类型" "$NC"

    read_rules | while IFS='|' read -r port protocol mode action; do
        printf "%-8s%-12s%-16s%-16s\n" "$port" "$protocol" "$mode" "$action"
    done

    print_info "========================================================="
}

# 保存防火墙规则
save_rules() {
    print_info "[3/3] 保存防火墙规则..."
    if netfilter-persistent save >/dev/null 2>&1; then
        print_success "✓ 规则已保存"
        return 0
    fi
    print_warning "规则已生效，但保存失败（重启后会丢失）：请确认已安装 iptables-persistent / netfilter-persistent"
    return 1
}

# 查找 INPUT 链中第一条匹配 $1（grep -E 表达式）、且不匹配 $2（可选）的规则序号，找不到则输出为空
# 注意：
#  - iptables -S 的第一行是链的默认策略，所以只统计 -A 开头的规则行；
#  - 必须先在完整的规则列表上编号，再按内容排除 $2。如果先排除再编号，序号会和链里的实际位置对不上
find_rule_number() {
    local numbered
    numbered="$(iptables -S INPUT 2>/dev/null | grep '^-A ' | grep -n -E -- "$1")"
    if [ -n "${2:-}" ]; then
        numbered="$(printf '%s\n' "$numbered" | grep -v -E -- "$2")"
    fi
    printf '%s\n' "$numbered" | head -n 1 | cut -d: -f1
}

# 反复删除 INPUT 链中第一条匹配 $1（且不匹配 $2）的规则，直到没有匹配为止
delete_matching_rules() {
    local n
    while :; do
        n="$(find_rule_number "$@")"
        [ -z "$n" ] && return 0
        iptables -D INPUT "$n" 2>/dev/null || return 1
    done
}

# 清除所有规则（只删除本脚本添加的规则，不动其它程序或手动添加的规则）
clear_all_rules() {
    local port proto mode action

    print_warning "即将删除本脚本添加的全部 iptables 规则、定时任务和端口策略。"
    read -rp "确认清除吗？[y/N] " answer || { echo; print_info "已取消"; return 0; }
    case "$answer" in
        [yY]|[yY][eE][sS]) ;;
        *) print_info "已取消"; return 0 ;;
    esac

    print_warning "正在清除所有规则..."

    # 1. 旧版本（无标记）的屏蔽/放行规则没有注释可识别，按端口策略文件里的记录逐个清除
    while IFS='|' read -r port proto mode action; do
        [ -n "$port" ] && [ -n "$action" ] || continue
        clear_port_rules "$port" "$proto"
    done < <(read_rules)

    # 2. 删除所有带标记的规则
    delete_matching_rules "--comment \"?${RULE_TAG}\"?( |$)"

    # 3. 旧版本的地域/白名单规则一定引用 china / whitelist 集合且没有注释，按这两点识别
    #    （带注释的规则属于其它程序，即使引用了同名集合也不动）
    delete_matching_rules "--match-set (${IPSET_NAME}|${IPSET_WHITE}) " "-m comment"

    # 4. 规则删除后集合才允许销毁
    ipset destroy "$IPSET_NAME" 2>/dev/null || print_warning "集合 $IPSET_NAME 未能删除（仍被其它规则引用）"
    ipset destroy "$IPSET_WHITE" 2>/dev/null || print_warning "集合 $IPSET_WHITE 未能删除（仍被其它规则引用）"

    rm -f "$RULES_FILE"
    rm -f "$SETTINGS_FILE"
    rm -f "$CRON_FILE"
    rm -f "$SOURCE_LIB_FILE"

    save_rules
    print_success "✓ 所有规则已清除（白名单配置 $WHITELIST_FILE 已保留）"
}

# 重载/重启定时任务
reload_cron_service() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl reload cron 2>/dev/null || systemctl restart cron 2>/dev/null \
            || systemctl reload crond 2>/dev/null || systemctl restart crond 2>/dev/null
    else
        service cron reload 2>/dev/null || service cron restart 2>/dev/null \
            || service crond reload 2>/dev/null || service crond restart 2>/dev/null
    fi
}

# 读取 settings.conf 里的某个设置项（只读取，不执行文件内容）
get_setting() {
    [ -f "$SETTINGS_FILE" ] || return 0
    grep -E "^$1=" "$SETTINGS_FILE" 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -d '"'
}

# 配置自动更新计划
setup_auto_update() {
    print_info "==================== 配置自动更新计划 ===================="

    if [ ! -f "$SCRIPT_PATH" ]; then
        print_error "无法确定脚本文件的位置（$0），请先把脚本保存为文件再配置定时任务"
        return 1
    fi

    read -rp "请输入每天自动更新的时间（24小时制，如 03:30）: " update_time || return 1
    if [[ ! "$update_time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        print_error "时间格式错误，请输入有效的24小时制时间（如 03:30）"
        return 1
    fi

    local minute hour
    minute="${update_time#*:}"
    hour="${update_time%:*}"

    # 用 /bin/bash 调用，脚本没有可执行权限时定时任务也能运行
    if ! cat > "$CRON_FILE" << EOF
# port-filter 自动更新中国IP列表
$minute $hour * * * root /bin/bash "$SCRIPT_PATH" --update-ip >> $LOG_FILE 2>&1
EOF
    then
        print_error "✗ 无法写入 $CRON_FILE（系统可能没有安装 cron）"
        return 1
    fi

    reload_cron_service

    cat > "$SETTINGS_FILE" << EOF
UPDATE_TIME="$update_time"
AUTO_UPDATE_ENABLED="yes"
EOF

    print_success "✓ 自动更新计划已配置为每天 $update_time"

    # cron 服务没有运行时定时任务不会执行
    if [ -d /run/systemd/system ] && ! systemctl is-active --quiet cron 2>/dev/null \
        && ! systemctl is-active --quiet crond 2>/dev/null; then
        print_warning "定时任务服务（cron/crond）没有运行，自动更新不会生效，请启动它"
    fi
}

# 更新中国 IP 列表
update_china_ip() {
    local port proto mode action restored=0

    print_info "正在更新中国IP列表..."
    if download_china_ip; then
        # 新集合通过交换切换，已有规则自动使用新数据；这里只把丢失的地域规则补回来
        # （例如重启后规则没有恢复的情况）
        if [ -f "$RULES_FILE" ]; then
            print_info "检查已保存的地域规则..."
            while IFS='|' read -r port proto mode action; do
                if [ "$action" = "geo_filter" ] && ! geo_rules_present "$port" "$proto" "$mode"; then
                    print_info "补回端口 $port/$proto 的地域规则..."
                    apply_rule "$port" "$proto" "$mode" && restored=$((restored + 1))
                fi
            done < <(read_rules)
        fi
        save_rules
        if [ "$restored" -gt 0 ]; then
            print_success "✓ IP列表更新完成，并补回了 $restored 条丢失的地域规则"
        else
            print_success "✓ IP列表更新完成，已保存的地域规则都在正常生效"
        fi
        return 0
    else
        print_error "✗ IP列表更新失败"
        return 1
    fi
}

########################################
# IP 源规则库管理
########################################

show_ip_source_libraries() {
    print_info "当前已启用的 IP 源规则库："
    if [ -f "$SOURCE_LIB_FILE" ]; then
        local count=0 name line
        while IFS= read -r line || [ -n "$line" ]; do
            name="$(strip_line "$line")"
            [ -z "$name" ] && continue
            echo "  - $name"
            ((count++))
        done < "$SOURCE_LIB_FILE"
        [ $count -eq 0 ] && print_warning "暂无启用的 IP 源（将回退到内置默认全部）"
    else
        print_warning "还没有规则库配置文件（将回退到内置默认全部）"
    fi
}

enable_ip_source() {
    local name="$1"

    # 检查是否为内置源之一
    local found=0 n url
    for entry in "${IP_SOURCES[@]}"; do
        IFS='|' read -r n url <<< "$entry"
        if [ "$n" = "$name" ]; then
            found=1
            break
        fi
    done

    if [ "$found" -eq 0 ]; then
        print_error "未知 IP 源规则库: $name"
        return 1
    fi

    mkdir -p "$CONFIG_DIR"
    touch "$SOURCE_LIB_FILE"

    if grep -qxF -- "$name" "$SOURCE_LIB_FILE"; then
        print_warning "规则库 $name 已经启用"
        return 0
    fi

    echo "$name" >> "$SOURCE_LIB_FILE"
    print_success "已启用 IP 源规则库: $name"
}

disable_ip_source() {
    local name="$1" tmp

    if [ ! -f "$SOURCE_LIB_FILE" ]; then
        print_warning "规则库配置文件不存在"
        return 0
    fi

    if ! grep -qxF -- "$name" "$SOURCE_LIB_FILE"; then
        print_warning "规则库 $name 当前未启用"
        return 0
    fi

    # 整行精确匹配后再删除（名称里的“/”不能直接放进 sed 的表达式）
    tmp="$(mktemp "$CONFIG_DIR/.ip_sources.XXXXXX")" || return 1
    grep -vxF -- "$name" "$SOURCE_LIB_FILE" > "$tmp" || true
    cat "$tmp" > "$SOURCE_LIB_FILE"
    rm -f "$tmp"
    print_success "已禁用 IP 源规则库: $name"
}

reset_ip_sources_to_default() {
    local entry name url
    mkdir -p "$CONFIG_DIR"
    : > "$SOURCE_LIB_FILE"
    for entry in "${IP_SOURCES[@]}"; do
        IFS='|' read -r name url <<< "$entry"
        echo "$name" >> "$SOURCE_LIB_FILE"
    done
    print_success "已恢复默认：启用所有内置 IP 源规则库"
}

ip_source_library_menu() {
    local idx entry name url choice
    while true; do
        clear_screen
        print_title
        echo ""
        print_info "IP 源规则库选择（控制使用哪些中国IP数据源）"
        echo ""
        show_ip_source_libraries
        echo ""
        echo "内置可用规则库（IP 源）："
        idx=1
        for entry in "${IP_SOURCES[@]}"; do
            IFS='|' read -r name url <<< "$entry"
            echo "  $idx) $name"
            echo "     $url"
            ((idx++))
        done
        echo ""
        echo "a) 启用某个规则库（按名称，例如：metowolf/IPList）"
        echo "b) 禁用某个规则库"
        echo "c) 恢复默认（启用全部内置源）"
        echo "d) 返回主菜单"
        echo ""
        read -rp "请选择操作 [a/b/c/d]: " choice || return
        case "$choice" in
            a)
                read -rp "请输入要启用的规则库名称: " name || return
                if [ -n "$name" ]; then
                    enable_ip_source "$name"
                    print_info "变更在下次更新中国IP列表时生效（菜单 8 或定时更新）"
                fi
                read -rp "按回车键继续..." _ || return ;;
            b)
                read -rp "请输入要禁用的规则库名称: " name || return
                if [ -n "$name" ]; then
                    disable_ip_source "$name"
                    print_info "变更在下次更新中国IP列表时生效（菜单 8 或定时更新）"
                fi
                read -rp "按回车键继续..." _ || return ;;
            c)
                reset_ip_sources_to_default
                print_info "变更在下次更新中国IP列表时生效（菜单 8 或定时更新）"
                read -rp "按回车键继续..." _ || return ;;
            d)
                return ;;
            *)
                print_error "无效选择"
                read -rp "按回车键继续..." _ || return ;;
        esac
    done
}

########################################
# 安全提醒
########################################

# 防止管理员把自己锁在外面：
# 通过 SSH 管理本机时，如果要拦截 SSH 端口上非白名单的来源，先询问是否把当前来源IP加入白名单
# 用法：confirm_not_locking_out <端口> <协议>
confirm_not_locking_out() {
    local port="$1" protocol="$2" client_ip ssh_port first last answer=""

    case "$protocol" in
        tcp|both) ;;
        *) return 0 ;;
    esac

    # SSH_CONNECTION 的格式是：客户端IP 客户端端口 服务端IP 服务端端口（第 4 个字段才是 SSH 用的端口）
    [ -n "${SSH_CONNECTION:-}" ] || return 0
    read -r client_ip _ _ ssh_port <<< "$SSH_CONNECTION"
    first="${port%%:*}"
    last="${port#*:}"
    (( ssh_port >= first && ssh_port <= last )) || return 0

    if is_valid_ipv4_cidr "$client_ip" && ipset test "$IPSET_WHITE" "$client_ip" >/dev/null 2>&1; then
        return 0
    fi

    print_warning "注意：你正通过 SSH（端口 $ssh_port）管理本机，当前来源 IP 是 $client_ip"
    print_warning "该规则会拦截白名单以外的所有来源，可能把你自己锁在外面！"
    read -rp "是否先把当前来源 IP 加入白名单？[Y/n] " answer
    case "$answer" in
        [nN]|[nN][oO])
            print_warning "已跳过。请确认白名单里已有你的管理IP，或有其它方式（如控制台）可以连接本机" ;;
        *)
            if is_valid_ipv4_cidr "$client_ip"; then
                add_whitelist_ip "$client_ip"
            else
                print_warning "当前是通过 IPv6 连接的，本脚本的白名单只支持 IPv4，无法自动加白"
            fi ;;
    esac
    return 0
}

# 本脚本只管理 IPv4；服务器有公网 IPv6 地址时提醒用户
# 只看公网单播地址（2000::/3），内网的 fd00::/8 之类不算
warn_ipv6() {
    if command -v ip >/dev/null 2>&1 \
        && ip -6 addr show scope global 2>/dev/null | grep -Eq 'inet6 [23][0-9a-fA-F]{3}:'; then
        print_warning "检测到公网 IPv6 地址：本脚本只管理 IPv4 规则，IPv6 的访问不受影响，请另行处理"
    fi
}

########################################
# 交互菜单
########################################

show_menu() {
    clear_screen
    print_title
    echo ""

    if [ -f "$SETTINGS_FILE" ]; then
        if [ "$(get_setting AUTO_UPDATE_ENABLED)" = "yes" ]; then
            printf "自动更新：每天 %s${GREEN} ✓%s\n" "$(get_setting UPDATE_TIME)" "$NC"
        else
            printf "自动更新：%s未设置%s\n" "$YELLOW" "$NC"
        fi
    else
        printf "自动更新：%s未设置%s\n" "$YELLOW" "$NC"
    fi

    echo ""
    printf "${GREEN}1.${NC} IP地域过滤（黑名单/白名单）\n"
    printf "${GREEN}2.${NC} 屏蔽端口（完全阻止访问）\n"
    printf "${GREEN}3.${NC} 放行端口（完全允许访问）\n"
    printf "${GREEN}4.${NC} 查看当前 iptables 规则\n"
    printf "${GREEN}5.${NC} IP白名单管理\n"
    printf "${GREEN}6.${NC} IP 源规则库选择（选择使用哪些中国IP数据源）\n"
    printf "${GREEN}7.${NC} 清除所有规则\n"
    printf "${GREEN}8.${NC} 立即更新中国 IP\n"
    printf "${GREEN}9.${NC} 配置自动更新计划\n"
    printf "${GREEN}10.${NC} 查看已保存的端口策略\n"
    printf "${GREEN}0.${NC} 退出\n"
    echo ""
    printf "${YELLOW}请选择操作 [0-10]: ${NC}"
}

# IP 地域过滤设置
setup_geo_filter() {
    local port protocol mode proto_choice mode_choice

    print_info "==================== IP 地域过滤设置 ====================="

    if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        download_china_ip || return 1
    fi

    read -rp "请输入端口号: " port || return 1
    if ! is_valid_port "$port"; then
        print_error "无效的端口号: $port（范围 1-65535，端口范围写成 8000:9000）"
        return 1
    fi
    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -rp "请选择 [1-3]: " proto_choice || return 1

    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) print_error "无效选择"; return 1 ;;
    esac

    echo "选择模式："
    echo "1. 黑名单（阻止中国IP访问）"
    echo "2. 白名单（仅允许中国IP访问）"
    read -rp "请选择 [1-2]: " mode_choice || return 1

    case $mode_choice in
        1) mode="blacklist" ;;
        2) mode="whitelist" ;;
        *) print_error "无效选择"; return 1 ;;
    esac

    # 仅允许中国IP会拦截白名单以外的所有来源，先防止管理员把自己锁在外面
    [ "$mode" = "whitelist" ] && confirm_not_locking_out "$port" "$protocol"
    warn_ipv6

    if ! apply_rule "$port" "$protocol" "$mode"; then
        remove_rule_config "$port" "$protocol"
        return 1
    fi
    save_rule_config "$port" "$protocol" "$mode" "geo_filter"
    save_rules
}

# 屏蔽端口设置
setup_block_port() {
    local port protocol proto_choice

    print_info "==================== 屏蔽端口 =========================="

    read -rp "请输入要屏蔽的端口号: " port || return 1
    if ! is_valid_port "$port"; then
        print_error "无效的端口号: $port（范围 1-65535，端口范围写成 8000:9000）"
        return 1
    fi

    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -rp "请选择 [1-3]: " proto_choice || return 1

    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) print_error "无效选择"; return 1 ;;
    esac

    # 屏蔽会拦截白名单以外的所有来源，先防止管理员把自己锁在外面
    confirm_not_locking_out "$port" "$protocol"
    warn_ipv6

    if ! block_port "$port" "$protocol"; then
        remove_rule_config "$port" "$protocol"
        return 1
    fi
    save_rule_config "$port" "$protocol" "block" "block"
    save_rules
}

# 放行端口设置
setup_allow_port() {
    local port protocol proto_choice

    print_info "==================== 放行端口 =========================="

    read -rp "请输入要放行的端口号: " port || return 1
    if ! is_valid_port "$port"; then
        print_error "无效的端口号: $port（范围 1-65535，端口范围写成 8000:9000）"
        return 1
    fi

    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP + UDP"
    read -rp "请选择 [1-3]: " proto_choice || return 1

    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="both" ;;
        *) print_error "无效选择"; return 1 ;;
    esac

    if ! allow_port "$port" "$protocol"; then
        remove_rule_config "$port" "$protocol"
        return 1
    fi
    save_rule_config "$port" "$protocol" "allow" "allow"
    save_rules
}

# IP 白名单管理菜单
whitelist_menu() {
    local ip choice
    while true; do
        clear_screen
        print_title
        echo ""
        print_info "IP白名单管理"
        echo ""
        show_whitelist
        echo ""
        echo "1) 添加IP到白名单"
        echo "2) 从白名单移除IP"
        echo "3) 返回主菜单"
        echo ""
        read -rp "请选择操作 [1-3]: " choice || return
        case "$choice" in
            1)
                read -rp "请输入IP地址或IP段: " ip || return
                if [ -n "$ip" ]; then
                    add_whitelist_ip "$ip"
                    save_rules
                fi
                read -rp "按回车键继续..." _ || return ;;
            2)
                read -rp "请输入要移除的IP地址: " ip || return
                if [ -n "$ip" ]; then
                    remove_whitelist_ip "$ip"
                    save_rules
                fi
                read -rp "按回车键继续..." _ || return ;;
            3)
                return ;;
            *)
                print_error "无效选择"
                read -rp "按回车键继续..." _ || return ;;
        esac
    done
}

# 主程序
main() {
    check_root
    install_dependencies
    init_whitelist
    load_whitelist || print_warning "白名单加载不完整，请检查 $WHITELIST_FILE"
    init_ip_sources

    while true; do
        show_menu
        # 输入流已关闭（Ctrl+D 或非交互环境）时直接退出，避免死循环
        read -r choice || { echo; print_info "输入已结束，退出程序"; exit 0; }
        case "$choice" in
            1) setup_geo_filter;       read -rp "按回车继续..." _ || exit 0 ;;
            2) setup_block_port;       read -rp "按回车继续..." _ || exit 0 ;;
            3) setup_allow_port;       read -rp "按回车继续..." _ || exit 0 ;;
            4) show_rules;             read -rp "按回车继续..." _ || exit 0 ;;
            5) whitelist_menu ;;
            6) ip_source_library_menu ;;
            7) clear_all_rules;        read -rp "按回车继续..." _ || exit 0 ;;
            8) update_china_ip;        read -rp "按回车继续..." _ || exit 0 ;;
            9) setup_auto_update;      read -rp "按回车继续..." _ || exit 0 ;;
            10) show_saved_configs;    read -rp "按回车继续..." _ || exit 0 ;;
            0) print_success "退出程序"; exit 0 ;;
            *) print_error "无效选择";  read -rp "按回车继续..." _ || exit 0 ;;
        esac
    done
}

########################################
# 命令行模式（保持安装命令不变）
########################################

show_help() {
    cat << EOF
端口访问控制脚本 v$VERSION

用法：
  port-filter                 启动交互菜单
  port-filter --whitelist <IP或IP段>   把 IP 加入白名单（如 192.168.1.100 或 10.0.0.0/8）
  port-filter --update-ip     立即更新中国IP列表（供定时任务使用）
  port-filter --help          显示本帮助
  port-filter --version       显示版本号

需要 root 权限运行。
EOF
}

# 被 source 引入时只加载函数，不执行主程序
if [ "${BASH_SOURCE[0]:-$0}" != "$0" ]; then
    return 0 2>/dev/null
fi

if [ "${1:-}" = "--whitelist" ]; then
    if [ -z "${2:-}" ]; then
        print_error "用法: $(basename "$0") --whitelist <IP或IP段>"
        exit 1
    fi
    check_root
    install_dependencies
    init_whitelist
    add_whitelist_ip "$2" || exit 1
    save_rules
    exit 0
fi

if [ "${1:-}" = "--update-ip" ]; then
    check_root
    install_dependencies
    init_whitelist
    load_whitelist
    update_china_ip || exit 1
    exit 0
fi

if [ "${1:-}" = "--version" ]; then
    echo "port-filter $VERSION"
    exit 0
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    show_help
    exit 0
fi

# 运行主程序
main
