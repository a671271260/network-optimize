#!/bin/bash
# ============================================================
#  NETOPT.SH  网络优化脚本工具箱（菜单交互版）
#
#  功能：一键给服务器开启 BBR 加速 + CAKE 限速整形
#  适用：100Mbps 的 TCP / Realm 中转线路（台湾、中东等跨境场景）
#
#  仓库：https://github.com/a671271260/network-optimize
#
#  运行：bash netopt.sh        （菜单版，输入数字选择）
#        bash netopt.sh taiwan（也可直接带参数按原方式执行）
# ============================================================

# ------------------------------------------------------------
# 颜色定义（界面美化用）
# ------------------------------------------------------------
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
WHITE='\033[37m'
RESET='\033[0m'

# 非终端环境（如输出重定向到日志文件）关闭颜色，避免日志里出现转义乱码
if [ ! -t 1 ]; then
    CYAN=''; GREEN=''; YELLOW=''; RED=''; WHITE=''; RESET=''
fi

# ------------------------------------------------------------
# 兼容「curl ... | bash」一键运行方式
#   管道运行时标准输入是「脚本内容本身」而非键盘，直接 read 会读到脚本
#   残留内容或 EOF，表现为菜单刷屏 / 选不动数字 / 装不了 yh。
#   这里统一封装「优先从终端读取」：有终端就读终端，没有终端（如纯脚本
#   非交互）再退回默认 stdin。只作用于读取输入，不影响 bash 继续读脚本。
# ------------------------------------------------------------
read_tty() {
    if { true < /dev/tty; } 2>/dev/null; then
        read -r "$@" < /dev/tty
    else
        read -r "$@"
    fi
}

VERSION="v1.0.2"

# ------------------------------------------------------------
# 线路预设参数（菜单、命令行、帮助共用同一份，改这里一处即可）
#   格式：前一个为带宽(Mbps)，后一个为 RTT(ms)
# ------------------------------------------------------------
PROFILE_TAIWAN_RATE=94
PROFILE_TAIWAN_RTT=50
PROFILE_MIDEAST_RATE=92
PROFILE_MIDEAST_RTT=160

# ------------------------------------------------------------
# 关键文件路径
# ------------------------------------------------------------
SYSCTL_FILE="/etc/sysctl.d/99-network-stability.conf"
MODULES_FILE="/etc/modules-load.d/network-optimize.conf"
TC_SCRIPT="/usr/local/sbin/network-cake.sh"
SERVICE_FILE="/etc/systemd/system/network-cake.service"

# ------------------------------------------------------------
# 仓库地址（供「安装快捷命令 yh」下载脚本本体用）
#   下载优先级：raw 直链 -> GitHub API 原始内容 -> git 浅克隆
# ------------------------------------------------------------
REPO_OWNER="a671271260"
REPO_NAME="network-optimize"
REPO_BRANCH="main"
REPO_RAW="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/ty.sh"
REPO_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/ty.sh?ref=${REPO_BRANCH}"
REPO_GIT="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"

IFACE=""

# ------------------------------------------------------------
# 检查 root 权限
# ------------------------------------------------------------
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请使用 root 权限运行本脚本${RESET}"
        echo -e "例如: ${CYAN}sudo bash $0${RESET}"
        exit 1
    fi
}

# ------------------------------------------------------------
# 自动获取默认出口网卡
# ------------------------------------------------------------
get_interface() {
    ip route show default 2>/dev/null \
        | awk '/default/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

# ------------------------------------------------------------
# 覆盖前备份：仅当 .bak 不存在时才保存，保留最原始的版本
# ------------------------------------------------------------
backup_file() {
    if [ -f "$1" ] && [ ! -f "$1.bak" ]; then
        cp -f "$1" "$1.bak" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------
# 卸载用：有备份则还原原始文件，无备份则直接删除
# ------------------------------------------------------------
restore_or_remove() {
    if [ -f "$1.bak" ]; then
        mv -f "$1.bak" "$1" 2>/dev/null || rm -f "$1"
    else
        rm -f "$1"
    fi
}

# ------------------------------------------------------------
# 顶部 ASCII 标题 + 版本信息
# ------------------------------------------------------------
show_banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}"
    cat <<'BANNER'
███╗   ██╗███████╗████████╗ ██████╗ ██████╗ ████████╗
████╗  ██║██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗╚══██╔══╝
██╔██╗ ██║█████╗     ██║   ██║   ██║██████╔╝   ██║
██║╚██╗██║██╔══╝     ██║   ██║   ██║██╔═══╝    ██║
██║ ╚████║███████╗   ██║   ╚██████╔╝██║        ██║
╚═╝  ╚═══╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝        ╚═╝
BANNER
    echo -e "${RESET}"
    echo -e "${CYAN}网络优化脚本工具箱${RESET}  ${GREEN}${VERSION}${RESET}"
    echo -e "${YELLOW}命令输入 yh 可快速启动脚本${RESET}"
}

# ------------------------------------------------------------
# 主菜单
# ------------------------------------------------------------
show_menu() {
    echo -e "${CYAN}----------------------------------------${RESET}"
    echo -e "${GREEN}1.${RESET}   ${WHITE}台湾线路优化${RESET}   ${YELLOW}[${PROFILE_TAIWAN_RATE}M / ${PROFILE_TAIWAN_RTT}ms]${RESET}"
    echo -e "${GREEN}2.${RESET}   ${WHITE}中东线路优化${RESET}   ${YELLOW}[${PROFILE_MIDEAST_RATE}M / ${PROFILE_MIDEAST_RTT}ms]${RESET}"
    echo -e "${GREEN}3.${RESET}   ${WHITE}自定义线路优化${RESET}"
    echo -e "${GREEN}4.${RESET}   ${WHITE}网络状态查询${RESET}"
    echo -e "${GREEN}5.${RESET}   ${WHITE}关闭 CAKE 限速${RESET}"
    echo -e "${GREEN}6.${RESET}   ${WHITE}卸载所有优化${RESET}"
    echo -e "${GREEN}7.${RESET}   ${WHITE}安装快捷启动命令 yh${RESET}"
    echo -e "${CYAN}----------------------------------------${RESET}"
    echo -e "${GREEN}00.${RESET}  ${WHITE}查看使用说明${RESET}"
    echo -e "${CYAN}----------------------------------------${RESET}"
    echo -e "${GREEN}0.${RESET}   ${WHITE}退出脚本${RESET}"
    echo -e "${CYAN}----------------------------------------${RESET}"
}

# ------------------------------------------------------------
# 加载 BBR / CAKE 内核模块
# ------------------------------------------------------------
load_modules() {
    echo -e "${CYAN}[1/5] 加载 BBR / CAKE 模块...${RESET}"
    modprobe tcp_bbr 2>/dev/null || true
    modprobe sch_cake 2>/dev/null || true
    backup_file "$MODULES_FILE"
    printf 'tcp_bbr\nsch_cake\n' > "$MODULES_FILE"
}

# ------------------------------------------------------------
# 写入 TCP 内核参数（sysctl）
# ------------------------------------------------------------
write_sysctl() {
    echo -e "${CYAN}[2/5] 写入 TCP 内核参数...${RESET}"
    backup_file "$SYSCTL_FILE"
    cat > "$SYSCTL_FILE" <<'EOF'
# ============================================================
# TCP stability optimization
# ============================================================

# BBR 拥塞控制
net.ipv4.tcp_congestion_control = bbr

# 默认队列（实际公网网卡稍后由 CAKE 覆盖）
net.core.default_qdisc = fq

# ============================================================
# PMTU：1 = 检测到 PMTU 黑洞后启用探测
# ============================================================
net.ipv4.tcp_mtu_probing = 1

# ============================================================
# TCP Buffer：100Mbps 场景 16MB 已足够，避免缓冲膨胀
# ============================================================
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# ============================================================
# TCP 基础功能
# ============================================================
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1

# ============================================================
# 提高监听队列（Realm / HAProxy / nginx stream 大量连接）
# ============================================================
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
EOF
    sysctl --system >/dev/null 2>&1 || true
}

# ------------------------------------------------------------
# 生成 CAKE 限速脚本 + 开机自启服务，并立即应用
# 参数：$1 = 带宽(Mbps)   $2 = RTT(ms)
# ------------------------------------------------------------
setup_cake() {
    local rate="$1"
    local rtt="$2"

    echo -e "${CYAN}[3/5] 生成 CAKE 限速脚本...${RESET}"
    backup_file "$TC_SCRIPT"
    cat > "$TC_SCRIPT" <<EOF
#!/bin/bash
set -e

IFACE="$IFACE"
RATE="${rate}Mbit"
RTT="${rtt}ms"

# 等待网卡存在
for i in {1..30}; do
    if ip link show "\$IFACE" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# 清除旧 root qdisc
tc qdisc del dev "\$IFACE" root 2>/dev/null || true

# CAKE 限速整形
tc qdisc replace dev "\$IFACE" root cake \\
    bandwidth "\$RATE" \\
    besteffort \\
    rtt "\$RTT" \\
    raw

exit 0
EOF
    chmod +x "$TC_SCRIPT"

    echo -e "${CYAN}[4/5] 创建开机自启服务...${RESET}"
    backup_file "$SERVICE_FILE"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=CAKE Network Shaper
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$TC_SCRIPT
RemainAfterExit=yes
ExecStop=/bin/sh -c '/sbin/tc qdisc del dev $IFACE root 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable network-cake.service >/dev/null 2>&1 || true

    echo -e "${CYAN}[5/5] 应用限速...${RESET}"
    # 由 systemd 拉起应用一次即可（服务的 ExecStart 就是 TC_SCRIPT）；
    # 若环境没有 systemd，再直接执行脚本兜底，避免重复应用两次。
    systemctl restart network-cake.service 2>/dev/null || "$TC_SCRIPT" || true
}

# ------------------------------------------------------------
# 应用指定线路配置（核心流程）
# 参数：$1 = 名称   $2 = 带宽(Mbps)   $3 = RTT(ms)
# ------------------------------------------------------------
apply_profile() {
    local name="$1"
    local rate="$2"
    local rtt="$3"

    echo
    echo -e "${CYAN}============================================${RESET}"
    echo -e "${WHITE} 开始优化：${name}线路${RESET}"
    echo -e "${CYAN}============================================${RESET}"
    echo -e "出口网卡 : ${GREEN}$IFACE${RESET}"
    echo -e "限速带宽 : ${GREEN}${rate} Mbps${RESET}"
    echo -e "CAKE RTT : ${GREEN}${rtt} ms${RESET}"
    echo

    load_modules
    write_sysctl

    if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
        echo -e "${YELLOW}警告：当前内核未发现 BBR，拥塞控制可能不生效。${RESET}"
    fi

    setup_cake "$rate" "$rtt"

    echo
    echo -e "${GREEN}============================================${RESET}"
    echo -e "${GREEN} 优化完成！${RESET}"
    echo -e "${GREEN}============================================${RESET}"
    echo -e "出口网卡 : ${GREEN}$IFACE${RESET}"
    echo -e "限速带宽 : ${GREEN}${rate} Mbps / RTT ${rtt} ms${RESET}"
    echo -e "TCP 算法 : ${GREEN}BBR${RESET}"
    echo -e "查看状态 : ${CYAN}菜单 4${RESET}  或  ${CYAN}tc -s qdisc show dev $IFACE${RESET}"
}

# ------------------------------------------------------------
# 自定义线路：手动输入带宽与 RTT
# ------------------------------------------------------------
menu_custom() {
    echo
    echo -en "${CYAN}请输入带宽 (Mbps，例如 93): ${RESET}"
    read_tty rate
    echo -en "${CYAN}请输入 RTT (ms，例如 120): ${RESET}"
    read_tty rtt

    if ! [[ "$rate" =~ ^[0-9]+$ ]] || ! [[ "$rtt" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}输入无效：带宽与 RTT 必须是数字。${RESET}"
        return 1
    fi

    apply_profile "自定义" "$rate" "$rtt"
}

# ------------------------------------------------------------
# 网络状态查询
# ------------------------------------------------------------
show_status() {
    echo
    echo -e "${CYAN}==============================${RESET}"
    echo -e "${WHITE} Network Optimization Status${RESET}"
    echo -e "${CYAN}==============================${RESET}"
    echo -e "出口网卡 : ${GREEN}$IFACE${RESET}"
    echo

    echo -e "${CYAN}---- Kernel ----${RESET}"
    uname -r
    echo

    echo -e "${CYAN}---- TCP Congestion ----${RESET}"
    sysctl net.ipv4.tcp_congestion_control 2>/dev/null || true
    sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null || true
    sysctl net.core.default_qdisc 2>/dev/null || true
    echo

    echo -e "${CYAN}---- TCP Buffer ----${RESET}"
    sysctl net.ipv4.tcp_rmem 2>/dev/null || true
    sysctl net.ipv4.tcp_wmem 2>/dev/null || true
    sysctl net.core.rmem_max 2>/dev/null || true
    sysctl net.core.wmem_max 2>/dev/null || true
    echo

    echo -e "${CYAN}---- PMTU ----${RESET}"
    sysctl net.ipv4.tcp_mtu_probing 2>/dev/null || true
    echo

    echo -e "${CYAN}---- QDISC ----${RESET}"
    tc -s qdisc show dev "$IFACE" || true
    echo

    echo -e "${CYAN}---- Interface ----${RESET}"
    ip -s link show dev "$IFACE" || true
    echo

    echo -e "${CYAN}---- TCP Retransmission ----${RESET}"
    nstat -az 2>/dev/null \
        | grep -E 'TcpRetransSegs|TcpExtTCPTimeouts|TcpExtTCPSpuriousRTOs' \
        || true
    echo
}

# ------------------------------------------------------------
# 关闭 CAKE 限速（恢复为普通 fq）
# ------------------------------------------------------------
disable_cake() {
    echo
    echo -e "${CYAN}正在关闭 CAKE...${RESET}"

    systemctl disable --now network-cake.service 2>/dev/null || true

    tc qdisc del dev "$IFACE" root 2>/dev/null || true
    tc qdisc replace dev "$IFACE" root fq 2>/dev/null || true

    echo -e "${GREEN}CAKE 已关闭，队列恢复为 fq。${RESET}"
    echo
    echo -e "${CYAN}当前 qdisc:${RESET}"
    tc qdisc show dev "$IFACE" || true
}

# ------------------------------------------------------------
# 卸载所有优化：移除脚本写入的全部配置，并把内核参数还原为默认
# ------------------------------------------------------------
uninstall_all() {
    echo -e "${YELLOW}此操作将移除本脚本写入的全部配置，是否继续？[y/N]${RESET}"
    echo -en "${CYAN}请输入: ${RESET}"
    read_tty ans

    case "$ans" in
        y|Y) : ;;
        *) echo -e "${YELLOW}已取消。${RESET}"; return 0 ;;
    esac

    echo -e "${CYAN}正在卸载...${RESET}"

    systemctl disable --now network-cake.service 2>/dev/null || true

    # 有备份则还原成原始文件，没有则直接删除
    restore_or_remove "$TC_SCRIPT"
    restore_or_remove "$SERVICE_FILE"
    restore_or_remove "$SYSCTL_FILE"
    restore_or_remove "$MODULES_FILE"
    rm -f /usr/local/bin/netopt.sh /usr/local/bin/k /usr/local/bin/yh
    systemctl daemon-reload 2>/dev/null || true

    # 还原运行时的内核默认：拥塞算法回 cubic、默认队列回 fq_codel
    sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
    sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1 || true
    sysctl --system >/dev/null 2>&1 || true

    # 删除 root qdisc，让网卡回到系统默认队列
    tc qdisc del dev "$IFACE" root 2>/dev/null || true

    echo -e "${GREEN}卸载完成，已恢复为系统默认状态。${RESET}"
    echo -e "${YELLOW}提示：TCP Buffer 等参数如需完全回到出厂值，重启一次即可。${RESET}"
}

# ------------------------------------------------------------
# 下载脚本本体到指定路径
#   方式一：raw 直链（https://raw.githubusercontent.com）
#   方式二：GitHub API 取原始内容（Accept: application/vnd.github.raw）
#   方式三：git 浅克隆后从仓库拷贝
# 参数：$1 = 输出文件路径
# ------------------------------------------------------------
fetch_script() {
    local out="$1"

    # 方式一：raw 直链
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL --retry 2 --connect-timeout 10 "$REPO_RAW" -o "$out" 2>/dev/null \
            && [ -s "$out" ]; then
            return 0
        fi
    fi

    # 方式二：GitHub API 原始内容
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL --retry 2 --connect-timeout 10 \
            -H "Accept: application/vnd.github.raw" "$REPO_API" -o "$out" 2>/dev/null \
            && [ -s "$out" ]; then
            return 0
        fi
    fi

    # 方式三：git 浅克隆
    if command -v git >/dev/null 2>&1; then
        local tmp
        tmp="$(mktemp -d 2>/dev/null || echo "/tmp/netopt.$$")"
        if git clone --depth 1 "$REPO_GIT" "$tmp" >/dev/null 2>&1 \
            && cp -f "$tmp/ty.sh" "$out" 2>/dev/null; then
            rm -rf "$tmp" 2>/dev/null || true
            [ -s "$out" ] && return 0
        fi
        rm -rf "$tmp" 2>/dev/null || true
    fi

    return 1
}

# ------------------------------------------------------------
# 安装快捷启动命令 yh
# ------------------------------------------------------------
install_shortcut() {
    local target="/usr/local/bin/netopt.sh"
    local marker="NETOPT.SH"

    echo
    echo -e "${CYAN}正在安装快捷启动命令 yh ...${RESET}"

    # 优先复制本地脚本本体：但必须满足「真实普通文件 + 非空 + 是本脚本」，
    # 否则在「bash <(curl ...)」方式下会把 /dev/fd 管道复制成一个空文件。
    if [ -f "$0" ] && [ -s "$0" ] && grep -q "$marker" "$0" 2>/dev/null; then
        cp -f "$0" "$target" 2>/dev/null || true
    fi

    # 本地复制不可用或结果无效：改从仓库下载一份完整脚本（raw -> API -> git）
    if ! grep -q "$marker" "$target" 2>/dev/null; then
        echo -e "${YELLOW}正在从仓库下载脚本本体...${RESET}"
        fetch_script "$target" || true
    fi

    # 最终校验：存在、非空、且确实是本脚本，才允许安装快捷命令
    if [ ! -s "$target" ] || ! grep -q "$marker" "$target" 2>/dev/null; then
        echo -e "${RED}安装失败：未能获取有效的脚本文件（缺少 curl/git 或网络不通）。${RESET}"
        echo -e "${YELLOW}可稍后重试，或手动把脚本放到 ${target} 后再选本项。${RESET}"
        rm -f "$target" 2>/dev/null || true
        return 1
    fi

    chmod +x "$target"
    cat > /usr/local/bin/yh <<'EOF'
#!/bin/bash
exec /usr/local/bin/netopt.sh "$@"
EOF
    chmod +x /usr/local/bin/yh

    echo -e "${GREEN}安装完成！在任意位置输入 yh 即可启动本脚本。${RESET}"
}

# ------------------------------------------------------------
# 使用说明
# ------------------------------------------------------------
show_help() {
    echo
    echo -e "${CYAN}================ 使用说明 ================${RESET}"
    echo -e "${WHITE}本脚本用于给服务器开启 BBR 加速 + CAKE 限速整形。${RESET}"
    echo
    echo -e "${CYAN}菜单方式：${RESET}"
    echo -e "  直接运行脚本，按数字选择即可。"
    echo
    echo -e "${CYAN}命令行方式（也可用）：${RESET}"
    echo -e "  bash $0 taiwan         台湾线路   (${PROFILE_TAIWAN_RATE}Mbps / ${PROFILE_TAIWAN_RTT}ms)"
    echo -e "  bash $0 middleeast     中东线路   (${PROFILE_MIDEAST_RATE}Mbps / ${PROFILE_MIDEAST_RTT}ms)"
    echo -e "  bash $0 custom 93 120  自定义：带宽(Mbps) RTT(ms)"
    echo -e "  bash $0 status         查看状态（普通用户也可运行）"
    echo -e "  bash $0 disable-cake   关闭 CAKE"
    echo
    echo -e "${CYAN}原理简述：${RESET}"
    echo -e "  1) 内核开启 BBR，跨境高延迟链路提速更稳；"
    echo -e "  2) CAKE 主动把带宽压到 100M 以内并按 RTT 校准，"
    echo -e "     避免跑满被上游限速、减少丢包。"
    echo
    echo -e "${YELLOW}注意：除 status 外需 root 运行；依赖 systemd 与 iproute2(ip/tc)；"
    echo -e "     覆盖同名配置文件前会自动备份为 .bak。"
    echo -e "     多网卡机器可用 IFACE=eth0 bash $0 指定出口网卡。${RESET}"
}

# ------------------------------------------------------------
# 带参数运行时（兼容原命令行用法）
# ------------------------------------------------------------
run_with_args() {
    case "$1" in
        taiwan)      apply_profile "台湾" "$PROFILE_TAIWAN_RATE" "$PROFILE_TAIWAN_RTT" ;;
        middleeast)  apply_profile "中东" "$PROFILE_MIDEAST_RATE" "$PROFILE_MIDEAST_RTT" ;;
        status)      show_status ;;
        disable-cake) disable_cake ;;
        custom)
            if [ -z "$2" ] || [ -z "$3" ]; then
                echo -e "${YELLOW}用法: bash $0 custom <Mbps> <RTT-ms>${RESET}"
                exit 1
            fi
            apply_profile "自定义" "$2" "$3"
            ;;
        *)
            echo -e "${YELLOW}未知参数：$1${RESET}"
            show_help
            exit 1
            ;;
    esac
}

# ------------------------------------------------------------
# 主循环
# ------------------------------------------------------------
main() {
    # status 为只读操作，允许普通用户执行，无需 root
    if [ "${1:-}" = "status" ]; then
        IFACE="${IFACE:-$(get_interface)}"
        show_status
        exit 0
    fi

    check_root

    # 多网卡机器可用环境变量 IFACE 手动指定出口网卡
    IFACE="${IFACE:-$(get_interface)}"
    if [ -z "$IFACE" ]; then
        echo -e "${RED}无法自动识别默认出口网卡，请检查网络配置（可用 IFACE=eth0 指定）。${RESET}"
        exit 1
    fi

    # 带参数：直接执行对应命令后退出
    if [ -n "${1:-}" ]; then
        run_with_args "$1" "${2:-}" "${3:-}"
        exit 0
    fi

    # 无参数：进入交互菜单
    # 首次进入菜单时若尚未安装快捷命令 yh，则静默自动安装一次（已装则跳过）
    if [ ! -x /usr/local/bin/yh ]; then
        install_shortcut >/dev/null 2>&1 || true
    fi

    while true; do
        show_banner
        show_menu
        echo -en "${CYAN}请输入你的选择: ${RESET}"
        read_tty choice

        case "$choice" in
            1)   apply_profile "台湾" "$PROFILE_TAIWAN_RATE" "$PROFILE_TAIWAN_RTT" ;;
            2)   apply_profile "中东" "$PROFILE_MIDEAST_RATE" "$PROFILE_MIDEAST_RTT" ;;
            3)   menu_custom ;;
            4)   show_status ;;
            5)   disable_cake ;;
            6)   uninstall_all ;;
            7)   install_shortcut ;;
            00)  show_help ;;
            0)   echo -e "${GREEN}已退出，再见！${RESET}"; exit 0 ;;
            *)   echo -e "${RED}输入无效，请重新选择。${RESET}" ;;
        esac

        echo
        echo -en "${YELLOW}按回车键返回主菜单...${RESET}"
        read_tty _
    done
}

main "$@"
