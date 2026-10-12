#!/bin/bash
#
# XrayR 一键安装脚本（已修复）
#
# ============================ 修复记录 ============================
# [严重] 原脚本引用的 longyi8/XrayR- 仓库已 404（3 处），261818813/XrayR 亦已 404，
#        导致：无法通过 API 获取最新版本号、无法从 releases 下载安装包、
#        无法下载 XrayR.service / XrayR.sh 管理脚本。安装必然失败。
#        -> release 二进制改从 XrayR-project/XrayR 下载（该库虽已停更，但仍保留全部资产）；
#           脚本文件改从 xhcyy1990/XrayR 的 main 分支下载。
# [严重] 仓库默认分支已由 master 更名为 main，raw.../master/... 全部返回 404。
# [严重] `cp ruelist` 文件名写错，安装包与实际文件名均为 rulelist
#        （config.yml 中 RuleListPath 指向 /etc/XrayR/rulelist）。
# [一般] check_status 的返回值被中间执行的 echo 覆盖，导致“重启成功”永远被打印。
# [一般] 32 位系统判断条件写反（`!= 32 && != 64` 恒为假），永远无法拦截 32 位系统。
# [一般] os_version 为空时被当作 0，导致误报“系统版本过低”。
# [一般] 下载无重试、无镜像、无完整性校验；wget 失败时 $? 判断同样被覆盖。
# [一般] 复制文件未判空，安装包缺文件时会连续刷报错。
# [一般] 未校验必要的依赖命令（unzip / systemctl）。
# ==================================================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# ============================ 可配置项 ============================
# release 二进制仓库（主下载源）
XrayR_REPO="${XrayR_REPO:-xhcyy1990/XrayR-project}"
# 备用仓库：主仓库没有对应 release 资产时自动回退。
# 官方 XrayR-project/XrayR 代码虽已删库停更，但仍保留全部历史 release 资产。
XrayR_FALLBACK_REPO="${XrayR_FALLBACK_REPO:-XrayR-project/XrayR}"
# 脚本仓库（install.sh / XrayR.sh / XrayR.service）及其分支
XrayR_SCRIPT_REPO="${XrayR_SCRIPT_REPO:-xhcyy1990/XrayR}"
XrayR_SCRIPT_BRANCH="${XrayR_SCRIPT_BRANCH:-main}"
# GitHub 下载镜像前缀（国内机器访问慢时可设成 https://ghproxy.com/ 等），留空则直连
XrayR_MIRROR="${XrayR_MIRROR:-}"

XrayR_INSTALL_DIR="/usr/local/XrayR"
XrayR_CONFIG_DIR="/etc/XrayR"
XrayR_SERVICE_FILE="/etc/systemd/system/XrayR.service"
XrayR_SERVICE_NAME="XrayR"

# 安装包内随附的配置文件（ruelist 为原作者笔误，正确文件名是 rulelist）
XrayR_CONFIG_FILES="geoip.dat geosite.dat dns.json route.json custom_outbound.json custom_inbound.json rulelist"

# ============================ 基础函数 ============================
# 注意：信息一律输出到 stderr，避免污染 get_latest_version() 等
# 通过 $() 捕获返回值的函数（否则提示文字会被当成版本号）

info()  { echo -e "${green}$1${plain}" >&2; }
warn()  { echo -e "${yellow}$1${plain}" >&2; }
error() { echo -e "${red}$1${plain}" >&2; }

# 统一下载入口：优先 wget，其次 curl；均带重试
fetch() {
    local url=$1
    local out=$2
    if command -v wget >/dev/null 2>&1; then
        wget -q --tries=3 --timeout=30 --no-check-certificate -O "${out}" "${url}"
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --connect-timeout 15 --max-time 600 -o "${out}" "${url}"
    else
        error "未找到 wget / curl，请先安装其中之一"
        return 1
    fi
}

# 校验下载到的是否为有效 zip（排除 GitHub 返回的 HTML 错误页/404 页面）
is_zip() {
    [[ -s "$1" ]] && unzip -l "$1" >/dev/null 2>&1
}

# 检查 root
[[ $EUID -ne 0 ]] && error "错误：必须使用root用户运行此脚本！" && exit 1

# 检查系统
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

arch=$(uname -m 2>/dev/null || arch)

case "${arch}" in
    x86_64|x64|amd64)
        arch="64"
        ;;
    aarch64|arm64)
        arch="arm64-v8a"
        ;;
    armv7l|armv6l|arm/v7|arm/v6)
        arch="arm32-v7a"
        ;;
    s390x)
        arch="s390x"
        ;;
    i386|i486|i586|i686|x86)
        error "检测到 32 位架构(${arch})，本软件仅支持 64 位系统，请更换 x86_64 / arm64 系统"
        exit 2
        ;;
    *)
        arch="64"
        warn "检测架构失败，使用默认架构: ${arch}"
        ;;
esac

echo "架构: ${arch}"

# 修正后的位数判断：仅当明确为 32 位时才退出
if [[ "$(getconf LONG_BIT 2>/dev/null)" == "32" ]]; then
    error "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

os_version=""

# 系统版本
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi
# 取主版本号（如 22.04 -> 22）
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

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
    else
        apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y wget curl unzip tar cron socat
    fi

    # 缺少 systemctl 时尝试补装 systemd（XrayR 依赖 systemd 管理服务）
    if ! command -v systemctl >/dev/null 2>&1; then
        warn "未检测到 systemctl，尝试安装 systemd..."
        if [[ x"${release}" == x"centos" ]]; then
            yum install systemd -y
        else
            DEBIAN_FRONTEND=noninteractive apt-get install -y systemd
        fi
    fi

    # 依赖自检，缺失时明确报错而不是在后面莫名其妙失败
    local missing=()
    local cmd
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        missing+=("wget/curl (至少需要其一)")
    fi
    command -v unzip >/dev/null 2>&1 || missing+=("unzip")
    command -v systemctl >/dev/null 2>&1 || missing+=("systemd (需支持systemd的系统)")

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "以下依赖未能自动安装，请手动安装后重试：${missing[*]}"
        exit 1
    fi
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

install_acme() {
    # acme.sh 仅在使用 DNS 申请证书(CertMode: dns)时才需要，装不上不应阻断 XrayR 安装
    if curl -fsSL --connect-timeout 15 --max-time 300 https://get.acme.sh | sh; then
        info "acme.sh 安装完成"
    else
        warn "acme.sh 安装失败（不影响 XrayR 运行，仅在 CertMode 为 dns 时需要）"
    fi
    return 0
}

# 获取单个仓库的最新 release tag：API 正常时用 API；被限流时回退到 releases/latest 的 302 跳转地址
github_latest_tag() {
    local repo=$1
    local ver=""
    if command -v curl >/dev/null 2>&1; then
        ver=$(curl -fsSL --connect-timeout 15 --max-time 30 \
            "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
            | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n1)
        if [[ -z "${ver}" ]]; then
            ver=$(curl -Ls -o /dev/null -w '%{url_effective}' --connect-timeout 15 --max-time 30 \
                "https://github.com/${repo}/releases/latest" 2>/dev/null \
                | sed -nE 's#.*/releases/tag/([^/?#]+).*#\1#p')
        fi
    fi
    echo "${ver}"
}

# 获取最新版本号：依次尝试主仓库、备用仓库
get_latest_version() {
    local repo ver=""
    for repo in "${XrayR_REPO}" "${XrayR_FALLBACK_REPO}"; do
        [[ -z "${repo}" ]] && continue
        ver=$(github_latest_tag "${repo}")
        if [[ -n "${ver}" ]]; then
            echo "${ver}"
            return 0
        fi
        warn "仓库 ${repo} 未检测到 release，尝试下一个仓库"
    done
    echo ""
}

# 生成某仓库 + 某 tag 的下载地址（含可选镜像）
emit_release_urls() {
    local repo=$1
    local ver=$2
    local asset="XrayR-linux-${arch}.zip"
    local url="https://github.com/${repo}/releases/download/${ver}/${asset}"
    echo "${url}"
    if [[ -n "${XrayR_MIRROR}" ]]; then
        echo "${XrayR_MIRROR%/}/${url}"
    fi
}

# 构造下载地址候选列表。
# 官方库 tag 形如 v0.9.4，而自建库常用 0.9.4（无 v 前缀），
# 因此对每个仓库都尝试原始 tag 和去掉/补上 v 前缀的变体，避免因前缀不一致而下载失败。
release_url_candidates() {
    local ver=$1
    local repo form
    local forms=("${ver}")
    if [[ "${ver}" == v* ]]; then
        forms+=("${ver#v}")
    else
        forms+=("v${ver}")
    fi

    for repo in "${XrayR_REPO}" "${XrayR_FALLBACK_REPO}"; do
        [[ -z "${repo}" ]] && continue
        for form in "${forms[@]}"; do
            emit_release_urls "${repo}" "${form}"
        done
    done
}

# 下载 release 压缩包，依次尝试各候选地址，并校验 zip 有效性
download_release() {
    local ver=$1
    local out=$2
    local url
    while read -r url; do
        [[ -z "${url}" ]] && continue
        info "正在下载：${url}"
        if fetch "${url}" "${out}" && is_zip "${out}"; then
            return 0
        fi
        warn "下载失败或文件损坏，尝试下一个地址"
        rm -f "${out}"
    done < <(release_url_candidates "${ver}")
    return 1
}

# install.sh 自身所在目录。注意：通过 `bash <(curl -Ls ...)` 执行时，
# BASH_SOURCE[0] 是管道而非普通文件，此时 -f 判断为假，从而回退到在线下载
script_dir=""
if [[ -n "${BASH_SOURCE[0]}" && -f "${BASH_SOURCE[0]}" ]]; then
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
fi

# 获取脚本文件：优先使用本地副本（git clone 后直接运行 install.sh 的场景，
# 保证安装的就是仓库里已修好的脚本），其次在线下载，最后退回当前目录副本
fetch_script_file() {
    local name=$1
    local out=$2
    if [[ -n "${script_dir}" && -s "${script_dir}/${name}" ]]; then
        info "使用本地脚本：${script_dir}/${name}"
        cp -f "${script_dir}/${name}" "${out}" && return 0
    fi
    if fetch "https://raw.githubusercontent.com/${XrayR_SCRIPT_REPO}/${XrayR_SCRIPT_BRANCH}/${name}" "${out}"; then
        return 0
    fi
    warn "下载 ${name} 失败，尝试使用当前目录副本"
    if [[ -n "${cur_dir}" && -s "${cur_dir}/${name}" ]]; then
        cp -f "${cur_dir}/${name}" "${out}" && return 0
    fi
    return 1
}

install_XrayR() {
    if [[ -e "${XrayR_INSTALL_DIR}/" ]]; then
        rm "${XrayR_INSTALL_DIR}/" -rf
    fi

    mkdir -p "${XrayR_INSTALL_DIR}/"
    cd "${XrayR_INSTALL_DIR}/" || { error "无法进入 ${XrayR_INSTALL_DIR}"; exit 1; }

    local last_version=""

    if [[ $# == 0 ]]; then
        last_version=$(get_latest_version)
        if [[ ! -n "$last_version" ]]; then
            error "检测 XrayR 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 XrayR 版本安装"
            exit 1
        fi
        info "检测到 XrayR 最新版本：${last_version}，开始安装"
    else
        last_version=$1
        # 用户可能传 v0.9.4 也可能传 0.9.4，这里直接原样使用，避免出现 "vv0.9.4"
        info "开始安装 XrayR ${last_version}"
    fi

    if ! download_release "${last_version}" "${XrayR_INSTALL_DIR}/XrayR-linux.zip"; then
        error "下载 XrayR ${last_version} (${arch}) 失败，请确保你的服务器能够下载 Github 的文件"
        echo -e "已尝试以下地址：" >&2
        local u
        while read -r u; do
            [[ -n "${u}" ]] && echo -e "  ${u}" >&2
        done < <(release_url_candidates "${last_version}")
        echo -e "" >&2
        echo -e "提示：主仓库 ${XrayR_REPO} 目前没有任何 release 资产。" >&2
        echo -e "     若希望完全使用自己的仓库，请把 XrayR-linux-*.zip 作为 release 资产上传到该仓库，" >&2
        echo -e "     或调整 XrayR_REPO / XrayR_FALLBACK_REPO / XrayR_MIRROR 变量。" >&2
        exit 1
    fi

    if ! unzip -o XrayR-linux.zip; then
        error "解压 XrayR-linux.zip 失败"
        rm -f XrayR-linux.zip
        exit 1
    fi
    rm -f XrayR-linux.zip

    if [[ ! -f XrayR ]]; then
        error "安装包中未找到 XrayR 可执行文件，安装中止"
        exit 1
    fi
    chmod +x XrayR

    mkdir -p "${XrayR_CONFIG_DIR}/"

    # 管理脚本与 service 文件
    if ! fetch_script_file "XrayR.service" "${XrayR_SERVICE_FILE}"; then
        error "获取 XrayR.service 失败，请检查网络或手动放置该文件"
        exit 1
    fi

    # 兼容修正：线上历史版本的 service 文件使用 `-config`（单横线），
    # 会被 cobra 误解析为 `-c onfig` 导致服务永远无法启动，此处统一改为 `--config`
    if grep -qE '^ExecStart=.*XrayR[[:space:]]+-config([[:space:]]|$)' "${XrayR_SERVICE_FILE}"; then
        sed -i -E 's#^ExecStart=(.*XrayR)[[:space:]]+-config([[:space:]]|$)#ExecStart=\1 --config \2#' "${XrayR_SERVICE_FILE}"
        warn "已修正 XrayR.service 的 ExecStart 参数：-config -> --config（否则服务无法启动）"
    fi

    systemctl daemon-reload
    systemctl stop ${XrayR_SERVICE_NAME} 2>/dev/null
    systemctl enable ${XrayR_SERVICE_NAME} >/dev/null 2>&1

    # 复制随附配置文件（已存在则不覆盖，保留用户配置）
    local f missing_files=()
    for f in ${XrayR_CONFIG_FILES}; do
        if [[ -f "${f}" ]]; then
            if [[ ! -f "${XrayR_CONFIG_DIR}/${f}" ]]; then
                cp -f "${f}" "${XrayR_CONFIG_DIR}/${f}"
            fi
        else
            missing_files+=("${f}")
        fi
    done
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        warn "安装包中缺少以下文件（已跳过）：${missing_files[*]}"
    fi

    if [[ ! -f "${XrayR_CONFIG_DIR}/config.yml" ]]; then
        if [[ -f config.yml ]]; then
            cp -f config.yml "${XrayR_CONFIG_DIR}/"
        fi
        echo -e ""
        echo -e "全新安装，请先参看教程：https://github.com/XrayR-project/XrayR ，配置必要的内容"
    else
        systemctl start ${XrayR_SERVICE_NAME}
        sleep 2
        # 注意：必须直接判断 check_status 的返回值，中间不能插入任何命令，
        # 否则 $? 会被覆盖，导致永远提示“重启成功”
        if check_status; then
            info "XrayR 重启成功"
        else
            error "XrayR 可能启动失败，请稍后使用 XrayR log 查看日志信息，若无法启动，则可能更改了配置格式，请前往 wiki 查看：https://github.com/XrayR-project/XrayR/wiki"
        fi
    fi

    info "XrayR ${last_version} 安装完成，已设置开机自启"

    # 管理脚本（兼容大写 XrayR 与小写 xrayr）
    if ! fetch_script_file "XrayR.sh" "/usr/bin/XrayR"; then
        error "获取管理脚本 XrayR.sh 失败"
        exit 1
    fi
    chmod +x /usr/bin/XrayR
    ln -sf /usr/bin/XrayR /usr/bin/xrayr
    chmod +x /usr/bin/xrayr

    echo -e ""
    echo "XrayR 管理脚本使用方法 (兼容使用xrayr执行，大小写不敏感): "
    echo "------------------------------------------"
    echo "XrayR                    - 显示管理菜单 (功能更多)"
    echo "XrayR start              - 启动 XrayR"
    echo "XrayR stop               - 停止 XrayR"
    echo "XrayR restart            - 重启 XrayR"
    echo "XrayR status             - 查看 XrayR 状态"
    echo "XrayR enable             - 设置 XrayR 开机自启"
    echo "XrayR disable            - 取消 XrayR 开机自启"
    echo "XrayR log                - 查看 XrayR 日志"
    echo "XrayR update             - 更新 XrayR"
    echo "XrayR update x.x.x       - 更新 XrayR 指定版本"
    echo "XrayR config             - 显示配置文件内容"
    echo "XrayR install            - 安装 XrayR"
    echo "XrayR uninstall          - 卸载 XrayR"
    echo "XrayR version            - 查看 XrayR 版本"
    echo "------------------------------------------"
}

echo -e "${green}开始安装${plain}"
install_base
install_acme
install_XrayR "$@"
