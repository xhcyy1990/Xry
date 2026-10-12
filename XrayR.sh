#!/bin/bash
#
# XrayR 管理脚本（已修复）
#
# ============================ 修复记录 ============================
# [严重] 261818813/XrayR/master/install.sh、longyi8/XrayR/master/install.sh、
#        longyi8/XrayR/master/XrayR.sh 三个地址均已 404，
#        导致菜单“安装/更新 XrayR”和“升级维护脚本”全部不可用。
#        -> 统一改为 xhcyy1990/XrayR 的 main 分支（仓库默认分支已由 master 更名为 main）。
# [一般] 主菜单提示“请输入选择 [0-13]”，但实际选项有 0-14，14(关闭VMESS AEAD)无法被提示。
# [一般] “关闭VMESS AEAD”用 sed 硬编码插入到第 18 行，service 文件一旦改动就会插错位置，
#        且重复执行会插入多行。改为锚定 [Service] 段并做幂等判断。
# [一般] check_status 用 grep/awk 解析 systemctl status，输出格式变化就会失效，
#        改为 systemctl is-active。
# [一般] 卸载时遗漏 /usr/bin/xrayr 小写兼容软链接。
# [一般] 安装/更新/升级脚本均无失败提示，下载失败会被静默吞掉。
# ==================================================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

version="v1.0.0"

# ============================ 可配置项 ============================
XrayR_SCRIPT_REPO="${XrayR_SCRIPT_REPO:-xhcyy1990/XrayR}"
XrayR_SCRIPT_BRANCH="${XrayR_SCRIPT_BRANCH:-main}"
XrayR_SERVICE_FILE="/etc/systemd/system/XrayR.service"
XrayR_SERVICE_NAME="XrayR"
XrayR_INSTALL_DIR="/usr/local/XrayR"

raw_base="https://raw.githubusercontent.com/${XrayR_SCRIPT_REPO}/${XrayR_SCRIPT_BRANCH}"
# 本脚本所在目录（用于在 git clone 后优先使用仓库内的 install.sh）
script_dir=""
if [[ -n "${BASH_SOURCE[0]}" && -f "${BASH_SOURCE[0]}" ]]; then
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
fi

info()  { echo -e "${green}$1${plain}"; }
warn()  { echo -e "${yellow}$1${plain}"; }
error() { echo -e "${red}$1${plain}"; }

# check root
[[ $EUID -ne 0 ]] && error "错误: 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue 2>/dev/null | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue 2>/dev/null | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue 2>/dev/null | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version 2>/dev/null | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version 2>/dev/null | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version 2>/dev/null | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    error "未检测到系统版本，请联系脚本作者！" && exit 1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi
os_version=${os_version%%.*}

if [[ x"${release}" == x"centos" ]]; then
    if [[ -n "${os_version}" && ${os_version} -le 6 ]]; then
        error "请使用 CentOS 7 或更高版本的系统！" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ -n "${os_version}" && ${os_version} -lt 16 ]]; then
        error "请使用 Ubuntu 16 或更高版本的系统！" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ -n "${os_version}" && ${os_version} -lt 8 ]]; then
        error "请使用 Debian 8 或更高版本的系统！" && exit 1
    fi
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "是否重启XrayR" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

# 执行安装脚本：优先使用本地副本（git clone 后直接运行），否则从脚本仓库下载
run_install_script() {
    if command -v curl >/dev/null 2>&1; then
        if [[ -n "${script_dir}" && -f "${script_dir}/install.sh" ]]; then
            bash "${script_dir}/install.sh" "$@"
        else
            bash <(curl -fsSL --retry 3 --connect-timeout 15 "${raw_base}/install.sh") "$@"
        fi
    elif command -v wget >/dev/null 2>&1; then
        if [[ -n "${script_dir}" && -f "${script_dir}/install.sh" ]]; then
            bash "${script_dir}/install.sh" "$@"
        else
            bash <(wget -q -O - --tries=3 --timeout=30 --no-check-certificate "${raw_base}/install.sh") "$@"
        fi
    else
        error "未找到 wget / curl，无法下载安装脚本"
        return 1
    fi
}

install() {
    if ! run_install_script "$@"; then
        error "安装失败，请检查上方输出的错误信息"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    if [[ $# == 0 ]]; then
        start
    else
        start 0
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "输入指定版本(默认最新版): " && read version
    else
        version=$2
    fi

    if ! run_install_script ${version}; then
        error "更新失败，请检查上方输出的错误信息"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    info "更新完成，已自动重启 XrayR，请使用 XrayR log 查看运行日志"
    exit
}

config() {
    echo "XrayR在修改配置后会自动尝试重启"
    vi /etc/XrayR/config.yml
    sleep 2
    check_status
    case $? in
        0)
            echo -e "XrayR状态: ${green}已运行${plain}"
            ;;
        1)
            echo -e "检测到您未启动XrayR或XrayR自动重启失败，是否查看日志？[Y/n]" && echo
            read -e -p "(默认: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               show_log
            fi
            ;;
        2)
            echo -e "XrayR状态: ${red}未安装${plain}"
    esac
}

uninstall() {
    confirm "确定要卸载 XrayR 吗?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop ${XrayR_SERVICE_NAME} 2>/dev/null
    systemctl disable ${XrayR_SERVICE_NAME} 2>/dev/null
    rm "${XrayR_SERVICE_FILE}" -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/XrayR/ -rf
    rm "${XrayR_INSTALL_DIR}/" -rf
    rm /usr/bin/XrayR -f
    rm /usr/bin/xrayr -f

    echo ""
    echo -e "卸载成功"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}XrayR已运行，无需再次启动，如需重启请选择重启${plain}"
    else
        systemctl start ${XrayR_SERVICE_NAME}
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}XrayR 启动成功，请使用 XrayR log 查看运行日志${plain}"
        else
            echo -e "${red}XrayR可能启动失败，请稍后使用 XrayR log 查看日志信息${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    systemctl stop ${XrayR_SERVICE_NAME}
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}XrayR 停止成功${plain}"
    else
        echo -e "${red}XrayR停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart ${XrayR_SERVICE_NAME}
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}XrayR 重启成功，请使用 XrayR log 查看运行日志${plain}"
    else
        echo -e "${red}XrayR可能启动失败，请稍后使用 XrayR log 查看日志信息${plain}"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status ${XrayR_SERVICE_NAME} --no-pager -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable ${XrayR_SERVICE_NAME}
    if [[ $? == 0 ]]; then
        echo -e "${green}XrayR 设置开机自启成功${plain}"
    else
        echo -e "${red}XrayR 设置开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable ${XrayR_SERVICE_NAME}
    if [[ $? == 0 ]]; then
        echo -e "${green}XrayR 取消开机自启成功${plain}"
    else
        echo -e "${red}XrayR 取消开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u ${XrayR_SERVICE_NAME}.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_bbr() {
    bash <(curl -L -s https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh)
}

update_shell() {
    local tmp
    tmp=$(mktemp /tmp/XrayR.sh.XXXXXX) || { error "创建临时文件失败"; return 1; }

    if command -v wget >/dev/null 2>&1; then
        wget -q --tries=3 --timeout=30 --no-check-certificate -O "${tmp}" "${raw_base}/XrayR.sh"
    else
        curl -fsSL --retry 3 --connect-timeout 15 -o "${tmp}" "${raw_base}/XrayR.sh"
    fi

    if [[ $? != 0 || ! -s "${tmp}" ]]; then
        rm -f "${tmp}"
        echo ""
        echo -e "${red}下载脚本失败，请检查本机能否连接 Github${plain}"
        before_show_menu
        return 1
    fi

    # 基本校验，避免把 404 页面写进 /usr/bin/XrayR
    if ! head -n 5 "${tmp}" | grep -q 'bash'; then
        rm -f "${tmp}"
        error "下载到的内容不是有效的脚本，已取消升级"
        before_show_menu
        return 1
    fi

    mv -f "${tmp}" /usr/bin/XrayR
    chmod +x /usr/bin/XrayR
    ln -sf /usr/bin/XrayR /usr/bin/xrayr
    chmod +x /usr/bin/xrayr
    info "升级脚本成功，请重新运行脚本" && exit 0
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f "${XrayR_SERVICE_FILE}" ]]; then
        return 2
    fi
    if ! command -v systemctl >/dev/null 2>&1; then
        return 1
    fi
    if [[ "$(systemctl is-active ${XrayR_SERVICE_NAME} 2>/dev/null)" == "active" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled ${XrayR_SERVICE_NAME} 2>/dev/null)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1;
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}XrayR已安装，请不要重复安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}请先安装XrayR${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "XrayR状态: ${green}已运行${plain}"
            show_enable_status
            ;;
        1)
            echo -e "XrayR状态: ${yellow}未运行${plain}"
            show_enable_status
            ;;
        2)
            echo -e "XrayR状态: ${red}未安装${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

show_XrayR_version() {
    echo -n "XrayR 版本："
    if [[ -x "${XrayR_INSTALL_DIR}/XrayR" ]]; then
        # XrayR 基于 cobra，版本号通过 `version` 子命令获取；
        # `-version` / `--version` 都不是合法参数（cobra 会把 -version 解析成 -c onfig 之类的怪错）
        ${XrayR_INSTALL_DIR}/XrayR version
    else
        echo -e "${red}未找到 ${XrayR_INSTALL_DIR}/XrayR${plain}"
    fi
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_usage() {
    echo "XrayR 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "XrayR              - 显示管理菜单 (功能更多)"
    echo "XrayR start        - 启动 XrayR"
    echo "XrayR stop         - 停止 XrayR"
    echo "XrayR restart      - 重启 XrayR"
    echo "XrayR status       - 查看 XrayR 状态"
    echo "XrayR enable       - 设置 XrayR 开机自启"
    echo "XrayR disable      - 取消 XrayR 开机自启"
    echo "XrayR log          - 查看 XrayR 日志"
    echo "XrayR update       - 更新 XrayR"
    echo "XrayR update x.x.x - 更新 XrayR 指定版本"
    echo "XrayR install      - 安装 XrayR"
    echo "XrayR uninstall    - 卸载 XrayR"
    echo "XrayR version      - 查看 XrayR 版本"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}XrayR 后端管理脚本，${plain}${red}不适用于docker${plain}
 --- https://github.com/xhcyy1990/XrayR ---
  ${green}0.${plain} 修改配置
———————————————
  ${green}1.${plain} 安装 XrayR
  ${green}2.${plain} 更新 XrayR
  ${green}3.${plain} 卸载 XrayR
———————————————
  ${green}4.${plain} 启动 XrayR
  ${green}5.${plain} 停止 XrayR
  ${green}6.${plain} 重启 XrayR
  ${green}7.${plain} 查看 XrayR 状态
  ${green}8.${plain} 查看 XrayR 日志
———————————————
  ${green}9.${plain} 设置 XrayR 开机自启
 ${green}10.${plain} 取消 XrayR 开机自启
———————————————
 ${green}11.${plain} 一键安装 bbr (最新内核)
 ${green}12.${plain} 查看 XrayR 版本
 ${green}13.${plain} 升级维护脚本
 ${green}14.${plain} 关闭VMESS AEAD
 "
 #后续更新可加入上方字符串中
    show_status
    echo && read -p "请输入选择 [0-14]: " num

    case "${num}" in
        0) config
        ;;
        1) check_uninstall && install
        ;;
        2) check_install && update
        ;;
        3) check_install && uninstall
        ;;
        4) check_install && start
        ;;
        5) check_install && stop
        ;;
        6) check_install && restart
        ;;
        7) check_install && status
        ;;
        8) check_install && show_log
        ;;
        9) check_install && enable
        ;;
        10) check_install && disable
        ;;
        11) install_bbr
        ;;
        12) check_install && show_XrayR_version
        ;;
        13) update_shell
        ;;
        14)
            # 关闭 VMESS AEAD 强制加密：向 [Service] 段插入环境变量，幂等且不依赖行号
            if [[ ! -f "${XrayR_SERVICE_FILE}" ]]; then
                error "未找到 ${XrayR_SERVICE_FILE}，请先安装 XrayR"
            elif grep -q '^Environment="XRAY_VMESS_AEAD_FORCED=' "${XrayR_SERVICE_FILE}"; then
                echo -e "${yellow}AEAD 强制加密已是关闭状态，无需重复操作${plain}"
            else
                sed -i '/^\[Service\]/a Environment="XRAY_VMESS_AEAD_FORCED=false"' "${XrayR_SERVICE_FILE}" \
                    && systemctl daemon-reload \
                    && echo "正在关闭AEAD强制加密..."
                check_install && restart
            fi
        ;;
        *) echo -e "${red}请输入正确的数字 [0-14]${plain}"
        ;;
    esac
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0
        ;;
        "stop") check_install 0 && stop 0
        ;;
        "restart") check_install 0 && restart 0
        ;;
        "status") check_install 0 && status 0
        ;;
        "enable") check_install 0 && enable 0
        ;;
        "disable") check_install 0 && disable 0
        ;;
        "log") check_install 0 && show_log 0
        ;;
        "update") check_install 0 && update 0 $2
        ;;
        "config") config $*
        ;;
        "install") check_uninstall 0 && install 0
        ;;
        "uninstall") check_install 0 && uninstall 0
        ;;
        "version") check_install 0 && show_XrayR_version 0
        ;;
        "update_shell") update_shell
        ;;
        *) show_usage
    esac
else
    show_menu
fi
