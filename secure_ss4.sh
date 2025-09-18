#!/bin/bash

# ===========================================
# Sing-box 安全安装脚本
# 基于原sb4.sh脚本，使用官方二进制文件
# ===========================================

set -e  # 遇到错误立即退出

# 颜色定义
re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
blue="\e[1;34m"

# 输出函数
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
blue() { echo -e "\e[1;34m$1\033[0m"; }
reading() { read -p "$(red "$1")" "$2"; }

# 设置环境变量
export LC_ALL=C
HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')

# 安全随机UUID生成
generate_secure_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        # 备用方法：使用openssl
        openssl rand -hex 16 | sed 's/\(..\)/\1-/g; s/.$//' | sed 's/\(.\{8\}\)-\(.\{4\}\)-\(.\{4\}\)-\(.\{4\}\)-\(.\{12\}\)/\1-\2-\3-\4-\5/'
    fi
}

export UUID=${UUID:-$(generate_secure_uuid)}
export PASSWORD=${PASSWORD:-"admin123"}

# 配置变量（移除敏感默认值）
export NEZHA_SERVER=${NEZHA_SERVER:-''}
export NEZHA_PORT=${NEZHA_PORT:-''}
export NEZHA_KEY=${NEZHA_KEY:-''}
export ARGO_DOMAIN=${ARGO_DOMAIN:-''}
export ARGO_AUTH=${ARGO_AUTH:-''}
export CFIP=${CFIP:-'www.visa.com.sg'}
export CFPORT=${CFPORT:-'443'}
export SUB_TOKEN=${SUB_TOKEN:-${UUID:0:8}}
export CHAT_ID=${CHAT_ID:-''}
export BOT_TOKEN=${BOT_TOKEN:-''}
export UPLOAD_URL=${UPLOAD_URL:-''}

# 官方sing-box配置
OFFICIAL_REPO="SagerNet/sing-box"
GITHUB_API="https://api.github.com/repos/$OFFICIAL_REPO"
GITHUB_RELEASES="https://github.com/$OFFICIAL_REPO/releases/download"

# 检测运行环境
detect_environment() {
    if command -v devil &>/dev/null; then
        echo "serv00"
    else
        echo "vps"
    fi
}

# 检测运行环境并设置路径
setup_paths() {
    env=$(detect_environment)

    if [[ "$env" == "serv00" ]]; then
        #环境
        if [[ "$HOSTNAME" =~ ct8 ]]; then
            CURRENT_DOMAIN="ct8.pl"
        elif [[ "$HOSTNAME" =~ hostuno ]]; then
            CURRENT_DOMAIN="useruno.com"
        else
            CURRENT_DOMAIN="serv00.net"
        fi
        WORKDIR="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/logs"
        FILE_PATH="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/public_html"
    else
        # 普通VPS环境
        CURRENT_DOMAIN="localhost"
        # 使用当前目录避免权限问题
        WORKDIR="$(pwd)/sing-box"
        FILE_PATH="$(pwd)/sing-box/web"
    fi
}

# 调用路径设置
setup_paths

# 安全初始化
secure_init() {
    # 创建工作目录
    rm -rf "$WORKDIR" "$FILE_PATH"
    mkdir -p "$WORKDIR" "$FILE_PATH"
    chmod 755 "$WORKDIR" "$FILE_PATH"

    # 安全清理进程（只清理自己的进程）
    pkill -u "$USERNAME" -f "sing-box\|cloudflared\|nezha" 2>/dev/null || true

    # 检查必要的命令
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        red "错误：系统缺少curl或wget，请联系管理员安装"
        exit 1
    fi

    command -v curl &>/dev/null && COMMAND="curl -fsSL -o" || COMMAND="wget -qO"
}

# 检测系统架构
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        i386|i686) echo "386" ;;
        *) red "不支持的架构: $arch"; exit 1 ;;
    esac
}

# 检测操作系统
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "freebsd"* ]]; then
        echo "freebsd"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        red "错误：此脚本只能在Linux服务器上运行"
        echo "当前环境: Windows ($OSTYPE)"
        echo "请在Linux VPS或Serv00/CT8主机上运行此脚本"
        exit 1
    else
        red "不支持的操作系统: $OSTYPE"
        echo "此脚本只支持 Linux 和 FreeBSD 系统"
        exit 1
    fi
}

# 获取最新版本
get_latest_version() {
    yellow "正在获取官方最新版本..." >&2
    local version
    version=$(curl -s --max-time 10 "$GITHUB_API/releases/latest" | grep -o '"tag_name": "[^"]*' | grep -o '[^"]*$')

    if [[ -z "$version" ]]; then
        red "无法获取最新版本，使用备用版本" >&2
        echo "v1.8.0"  # 备用版本
    else
        green "最新版本: $version" >&2
        echo "$version"
    fi
}

# 安全下载官方sing-box
download_official_singbox() {
    purple "正在从官方仓库下载sing-box..."

    local os=$(detect_os)
    local arch=$(detect_arch)
    local version=$(get_latest_version)

    # 从版本号中移除v前缀用于文件名
    local version_clean=${version#v}

    local filename="sing-box-${version_clean}-${os}-${arch}.tar.gz"
    local download_url="$GITHUB_RELEASES/$version/$filename"
    local checksum_url="$GITHUB_RELEASES/$version/sing-box-${version_clean}-checksums.txt"

    purple "下载地址: $download_url"

    # 创建临时目录
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"

    # 下载二进制文件
    purple "正在下载: $filename"
    purple "下载地址: $download_url"

    # 尝试下载
    if ! curl -L --progress-bar --max-time 300 -o "$filename" "$download_url"; then
        red "主下载地址失败，尝试使用镜像地址..."

        # 备用下载地址 (使用GitHub镜像)
        local mirror_url="https://hub.fastgit.xyz/SagerNet/sing-box/releases/download/$version/$filename"
        purple "镜像地址: $mirror_url"

        if ! curl -L --progress-bar --max-time 300 -o "$filename" "$mirror_url"; then
            red "所有下载地址都失败，请检查网络连接"
            rm -rf "$temp_dir"
            exit 1
        fi
    fi

    # 验证下载的文件
    if [[ ! -f "$filename" ]] || [[ ! -s "$filename" ]]; then
        red "下载的文件不存在或为空"
        rm -rf "$temp_dir"
        exit 1
    fi

    # 检查文件大小和基本信息
    echo "文件大小: $(du -h "$filename" 2>/dev/null | cut -f1 || echo "未知")"
    echo "文件详情: $(ls -la "$filename" 2>/dev/null || echo "无法获取文件信息")"

    # 检查文件头部 - 使用od命令（更通用）
    local file_header=""
    if command -v od &>/dev/null; then
        file_header=$(od -t x1 -N 2 "$filename" 2>/dev/null | head -1 | awk '{print $2 $3}')
        echo "文件头部(hex): $file_header"
    else
        echo "无法检查文件头部（系统缺少od命令）"
    fi

    # 尝试直接解压测试
    purple "尝试解压测试..."
    if tar -tzf "$filename" &>/dev/null; then
        green "✅ 文件格式验证通过（tar可以正常读取）"
    else
        red "❌ 文件格式错误，tar无法读取"
        echo ""
        echo "诊断信息："
        echo "文件大小: $(du -h "$filename" 2>/dev/null | cut -f1)"
        echo "文件头部: $file_header"
        echo ""
        echo "可能的原因："
        echo "1. 网络传输错误"
        echo "2. GitHub访问受限，下载到错误页面"
        echo "3. 代理或防火墙拦截"
        echo ""
        echo "建议："
        echo "1. 检查网络连接"
        echo "2. 尝试手动下载测试: curl -L '$download_url' -o test.tar.gz"
        echo "3. 检查是否需要配置代理"
        rm -rf "$temp_dir"
        exit 1
    fi

    green "✅ 文件下载成功，格式验证通过"

    # 下载并验证校验和（如果可用）
    if curl -s --max-time 10 -o checksums.txt "$checksum_url" 2>/dev/null; then
        if sha256sum -c --ignore-missing checksums.txt 2>/dev/null; then
            green "✅ 文件完整性验证通过"
        else
            yellow "⚠️  校验和验证失败，但文件格式正确，继续安装"
        fi
    else
        yellow "⚠️  无法下载校验和文件，跳过验证"
    fi

    # 解压文件
    purple "正在解压文件..."
    if ! tar -xzf "$filename"; then
        red "解压失败"
        ls -la "$filename"
        rm -rf "$temp_dir"
        exit 1
    fi

    # 查找sing-box二进制文件
    local binary_path
    binary_path=$(find . -name "sing-box" -type f | head -1)

    if [[ -z "$binary_path" ]]; then
        red "未找到sing-box二进制文件"
        rm -rf "$temp_dir"
        exit 1
    fi

    # 复制到工作目录
    cp "$binary_path" "$WORKDIR/sing-box"
    chmod +x "$WORKDIR/sing-box"

    # 验证二进制文件
    if "$WORKDIR/sing-box" version &>/dev/null; then
        local installed_version=$("$WORKDIR/sing-box" version 2>/dev/null | head -1)
        green "✅ 官方sing-box安装成功: $installed_version"
    else
        red "❌ 二进制文件验证失败"
        rm -rf "$temp_dir"
        exit 1
    fi

    # 清理临时文件
    cd "$WORKDIR"
    rm -rf "$temp_dir"
}

# 安全下载cloudflared
download_official_cloudflared() {
    purple "正在下载官方cloudflared..."

    local arch=$(detect_arch)
    local os=$(detect_os)

    # cloudflared官方下载链接
    local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-${os}-${arch}"

    if curl -L --progress-bar --max-time 300 -o "$WORKDIR/cloudflared" "$cf_url"; then
        chmod +x "$WORKDIR/cloudflared"
        if "$WORKDIR/cloudflared" version &>/dev/null; then
            green "✅ 官方cloudflared下载成功"
        else
            red "❌ cloudflared验证失败"
            rm -f "$WORKDIR/cloudflared"
        fi
    else
        yellow "⚠️  cloudflared下载失败，将使用临时隧道"
    fi
}

# 下载qrencode工具
download_qrencode() {
    purple "正在下载qrencode工具..."

    # 检查系统是否已安装qrencode
    if command -v qrencode &>/dev/null; then
        green "✅ 系统已安装qrencode"
        return 0
    fi

    local arch=$(detect_arch)
    local os=$(detect_os)

    # 创建简单的二维码生成脚本
    cat > "$WORKDIR/qr_generator.py" <<'EOF'
#!/usr/bin/env python3
import sys
import os

def generate_qr_ascii(text, size=2):
    """生成ASCII字符二维码（简化版）"""
    try:
        import qrcode
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=size,
            border=1,
        )
        qr.add_data(text)
        qr.make(fit=True)
        qr.print_ascii(invert=True)
    except ImportError:
        # 如果没有qrcode库，显示链接
        print("=" * 50)
        print("订阅链接:")
        print(text)
        print("=" * 50)
        print("请手动复制链接到客户端")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        generate_qr_ascii(sys.argv[1])
    else:
        print("用法: python3 qr_generator.py <链接>")
EOF

    chmod +x "$WORKDIR/qr_generator.py"
    green "✅ 二维码生成器创建成功"
}

# 端口检查和配置
check_port() {
    clear
    purple "正在检查端口配置..."

    local env=$(detect_environment)

    if [[ "$env" == "serv00" ]]; then
        # Serv00/CT8环境
        check_port_serv00
    else
        # 普通VPS环境
        check_port_vps
    fi
}

# Serv00/CT8端口检查
check_port_serv00() {
    local port_list=$(devil port list 2>/dev/null || echo "")
    if [[ -z "$port_list" ]]; then
        red "无法获取端口列表，请检查devil命令"
        exit 1
    fi

    local tcp_ports=$(echo "$port_list" | grep -c "tcp" || echo "0")
    local udp_ports=$(echo "$port_list" | grep -c "udp" || echo "0")

    if [[ $tcp_ports -ne 1 || $udp_ports -ne 2 ]]; then
        yellow "端口数量不符合要求，正在调整..."

        # 删除多余的TCP端口
        if [[ $tcp_ports -gt 1 ]]; then
            local tcp_to_delete=$((tcp_ports - 1))
            echo "$port_list" | awk '/tcp/ {print $1, $2}' | head -n $tcp_to_delete | while read port type; do
                devil port del $type $port
                green "已删除TCP端口: $port"
            done
        fi

        # 删除多余的UDP端口
        if [[ $udp_ports -gt 2 ]]; then
            local udp_to_delete=$((udp_ports - 2))
            echo "$port_list" | awk '/udp/ {print $1, $2}' | head -n $udp_to_delete | while read port type; do
                devil port del $type $port
                green "已删除UDP端口: $port"
            done
        fi

        # 添加缺少的TCP端口
        if [[ $tcp_ports -lt 1 ]]; then
            local attempts=0
            while [[ $attempts -lt 10 ]]; do
                local tcp_port=$(shuf -i 10000-65535 -n 1)
                if devil port add tcp $tcp_port 2>&1 | grep -q "Ok"; then
                    green "已添加TCP端口: $tcp_port"
                    break
                fi
                ((attempts++))
            done
        fi

        # 添加缺少的UDP端口
        if [[ $udp_ports -lt 2 ]]; then
            local udp_needed=$((2 - udp_ports))
            local added=0
            local attempts=0

            while [[ $added -lt $udp_needed && $attempts -lt 20 ]]; do
                local udp_port=$(shuf -i 10000-65535 -n 1)
                if devil port add udp $udp_port 2>&1 | grep -q "Ok"; then
                    green "已添加UDP端口: $udp_port"
                    ((added++))
                fi
                ((attempts++))
            done
        fi

        yellow "端口调整完成，请重新连接SSH并重新运行脚本"
        devil binexec on >/dev/null 2>&1
        exit 0
    else
        local tcp_port=$(echo "$port_list" | awk '/tcp/ {print $1}' | head -1)
        local udp_ports_list=$(echo "$port_list" | awk '/udp/ {print $1}')
        local udp_port1=$(echo "$udp_ports_list" | sed -n '1p')
        local udp_port2=$(echo "$udp_ports_list" | sed -n '2p')

        export VMESS_PORT=$tcp_port
        export TUIC_PORT=$udp_port1
        export HY2_PORT=$udp_port2

        green "端口配置正常:"
        purple "VMESS端口: $tcp_port"
        purple "TUIC端口: $udp_port1"
        purple "Hysteria2端口: $udp_port2"
    fi
}

# 普通VPS端口检查
check_port_vps() {
    purple "检测到普通VPS环境，使用随机端口..."

    # 生成随机端口
    local tcp_port=$(shuf -i 10000-65535 -n 1)
    local udp_port1=$(shuf -i 10000-65535 -n 1)
    local udp_port2=$(shuf -i 10000-65535 -n 1)

    # 确保端口不重复
    while [[ $udp_port1 -eq $tcp_port ]]; do
        udp_port1=$(shuf -i 10000-65535 -n 1)
    done

    while [[ $udp_port2 -eq $tcp_port || $udp_port2 -eq $udp_port1 ]]; do
        udp_port2=$(shuf -i 10000-65535 -n 1)
    done

    export VMESS_PORT=$tcp_port
    export TUIC_PORT=$udp_port1
    export HY2_PORT=$udp_port2

    green "端口配置完成:"
    purple "VMESS端口: $tcp_port"
    purple "TUIC端口: $udp_port1"
    purple "Hysteria2端口: $udp_port2"
}

# Serv00网站检查
check_website_serv00() {
    local FULL_DOMAIN="${USERNAME}.${CURRENT_DOMAIN}"
    local CURRENT_SITE=$(devil www list | awk -v domain="$FULL_DOMAIN" '$1 == domain && $2 == "php"')

    if [[ -n "$CURRENT_SITE" ]]; then
        green "PHP站点已存在: ${FULL_DOMAIN}"
    else
        local EXIST_SITE=$(devil www list | awk -v domain="$FULL_DOMAIN" '$1 == domain')

        if [[ -n "$EXIST_SITE" ]]; then
            devil www del "$FULL_DOMAIN" >/dev/null 2>&1
        fi

        devil www add "$FULL_DOMAIN" php "$HOME/domains/$FULL_DOMAIN" >/dev/null 2>&1
        green "已创建PHP站点: ${FULL_DOMAIN}"
    fi
}

# 普通VPS网站检查
check_website_vps() {
    green "普通VPS环境，跳过网站配置"
    green "订阅文件将保存到: ${FILE_PATH}/v2.log"
}

# 网站检查
check_website() {
    local env=$(detect_environment)

    if [[ "$env" == "serv00" ]]; then
        check_website_serv00
    else
        check_website_vps
    fi

    # 创建安全的首页
    cat > "${FILE_PATH}/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Welcome</title>
    <meta charset="UTF-8">
</head>
<body>
    <h1>服务正常运行</h1>
    <p>Service is running normally.</p>
</body>
</html>
EOF
}

# Argo隧道配置
argo_configure() {
    if [[ -z $ARGO_AUTH || -z $ARGO_DOMAIN ]]; then
        green "使用临时隧道模式"
        return
    fi

    if [[ $ARGO_AUTH =~ TunnelSecret ]]; then
        echo "$ARGO_AUTH" > "$WORKDIR/tunnel.json"
        cat > "$WORKDIR/tunnel.yml" <<EOF
tunnel: $(echo "$ARGO_AUTH" | grep -o '"TunnelID":"[^"]*' | cut -d'"' -f4)
credentials-file: tunnel.json
protocol: http2

ingress:
  - hostname: $ARGO_DOMAIN
    service: http://localhost:$VMESS_PORT
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
    else
        yellow "使用Token模式，请在Cloudflare后台设置隧道端口为: $VMESS_PORT"
    fi
}

# 生成配置文件
generate_config() {
    purple "正在生成配置文件..."

    # 生成证书
    openssl ecparam -genkey -name prime256v1 -out "$WORKDIR/private.key" 2>/dev/null
    openssl req -new -x509 -days 3650 -key "$WORKDIR/private.key" -out "$WORKDIR/cert.pem" \
        -subj "/CN=$USERNAME.${CURRENT_DOMAIN}" 2>/dev/null

    # 获取可用IP
    yellow "正在获取服务器IP..."
    local available_ip=$(get_ip)
    purple "使用IP: $available_ip"

    # 生成sing-box配置
    cat > "$WORKDIR/config.json" <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true,
    "output": "./sing-box.log"
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "type": "udp",
        "server": "8.8.8.8"
      },
      {
        "tag": "local",
        "type": "local"
      }
    ],
    "final": "google"
  },
  "inbounds": [
    {
      "tag": "hysteria-in",
      "type": "hysteria2",
      "listen": "0.0.0.0",
      "listen_port": $HY2_PORT,
      "users": [
        {
          "password": "$UUID"
        }
      ],
      "masquerade": "https://bing.com",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "cert.pem",
        "key_path": "private.key"
      }
    },
    {
      "tag": "vmess-ws-in",
      "type": "vmess",
      "listen": "$available_ip",
      "listen_port": $VMESS_PORT,
      "users": [
        {
          "uuid": "$UUID",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/vmess",
        "max_early_data": 0,
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    },
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "$available_ip",
      "listen_port": $TUIC_PORT,
      "users": [
        {
          "name": "user",
          "uuid": "$UUID",
          "password": "$UUID"
        }
      ],
      "congestion_control": "bbr",
      "auth_timeout": "3s",
      "zero_rtt_handshake": false,
      "heartbeat": "10s",
      "tls": {
        "enabled": true,
        "server_name": "$USERNAME.${CURRENT_DOMAIN}",
        "alpn": ["h3"],
        "certificate_path": "cert.pem",
        "key_path": "private.key"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "domain_resolver": {
        "server": "google"
      }
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": ["vmess-ws-in", "tuic-in", "hysteria-in"],
        "outbound": "direct"
      }
    ],
    "final": "direct",
    "auto_detect_interface": true,
    "default_domain_resolver": {
      "server": "google"
    }
  }
}
EOF
}

# 获取服务器IP
get_ip() {
    local env=$(detect_environment)

    if [[ "$env" == "serv00" ]]; then
        # Serv00/CT8环境，使用devil命令
        local IP_LIST=($(devil vhost list 2>/dev/null | awk '/^[0-9]+/ {print $1}' || echo ""))

        if [[ ${#IP_LIST[@]} -gt 0 ]]; then
            echo "${IP_LIST[0]}"
            return
        fi
    fi

    # 普通VPS环境或devil命令失败，获取公网IP
    local public_ip=""

    # 尝试多个IP获取服务
    for service in "https://ipv4.icanhazip.com" "https://api.ipify.org" "https://ifconfig.me/ip"; do
        public_ip=$(curl -s --max-time 10 "$service" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
        if [[ -n "$public_ip" ]]; then
            echo "$public_ip"
            return
        fi
    done

    # 最后尝试获取本机主IP（非127.0.0.1）
    local local_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')
    if [[ -n "$local_ip" && "$local_ip" != "127.0.0.1" ]]; then
        echo "$local_ip"
        return
    fi

    # 如果都失败，使用127.0.0.1
    echo "127.0.0.1"
}

# 获取Argo域名
get_argodomain() {
    if [[ -n $ARGO_AUTH ]]; then
        echo "$ARGO_DOMAIN"
    else
        local retry=0
        local max_retries=6
        local argodomain=""

        while [[ $retry -lt $max_retries ]]; do
            ((retry++))
            if [[ -f "$WORKDIR/boot.log" ]]; then
                argodomain=$(grep -oE 'https://[[:alnum:]+\.-]+\.trycloudflare\.com' "$WORKDIR/boot.log" | sed 's@https://@@' | head -1)
            fi
            if [[ -n $argodomain ]]; then
                break
            fi
            sleep 1
        done
        echo "$argodomain"
    fi
}

# 生成二维码
generate_qr_code() {
    local url="$1"

    # 方法1: 使用系统qrencode
    if command -v qrencode &>/dev/null; then
        echo -e "\n${blue}订阅链接二维码:${re}"
        qrencode -m 2 -t UTF8 "$url"
        return 0
    fi

    # 方法2: 使用Python脚本
    if [[ -f "$WORKDIR/qr_generator.py" ]] && command -v python3 &>/dev/null; then
        echo -e "\n${blue}订阅链接二维码:${re}"
        python3 "$WORKDIR/qr_generator.py" "$url"
        return 0
    fi

    # 方法3: 在线二维码服务（备用）
    local qr_api="https://api.qrserver.com/v1/create-qr-code/?size=200x200&data="
    local encoded_url=$(echo "$url" | sed 's/ /%20/g' | sed 's/&/%26/g')

    echo -e "\n${blue}二维码链接（在浏览器中打开查看）:${re}"
    echo "${qr_api}${encoded_url}"

    # 方法4: 显示ASCII二维码（最后备用）
    echo -e "\n${yellow}如需二维码，请复制以下链接到在线二维码生成器:${re}"
    echo "$url"
}

# 启动服务
start_services() {
    cd "$WORKDIR"

    # 启动sing-box
    if [[ -f "./sing-box" ]]; then
        # 首先验证配置文件
        purple "验证配置文件..."
        if ! ./sing-box check -c config.json; then
            red "❌ 配置文件有语法错误"
            ./sing-box check -c config.json 2>&1
            return 1
        fi
        green "✅ 配置文件验证通过"

        # 启动sing-box
        purple "正在启动sing-box..."

        # 清理旧进程
        pkill -f "./sing-box" 2>/dev/null || true
        sleep 1

        # 启动新进程
        nohup ./sing-box run -c config.json >sing-box.log 2>&1 &
        local sing_box_pid=$!

        # 等待启动
        sleep 5

        # 检查进程状态
        if pgrep -f "./sing-box" >/dev/null; then
            green "✅ sing-box启动成功 (PID: $(pgrep -f "./sing-box"))"

            # 显示启动日志前几行
            if [[ -f sing-box.log ]]; then
                echo "启动日志："
                head -5 sing-box.log
            fi
        else
            red "❌ sing-box启动失败"
            echo "错误日志："
            cat sing-box.log 2>/dev/null || echo "无法读取日志文件"
            return 1
        fi
    fi

    # 启动cloudflared
    if [[ -f "./cloudflared" ]]; then
        local args
        if [[ $ARGO_AUTH =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
            args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}"
        elif [[ $ARGO_AUTH =~ TunnelSecret ]]; then
            args="tunnel --edge-ip-version auto --config tunnel.yml run"
        else
            args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --loglevel info --url http://localhost:$VMESS_PORT"
        fi

        nohup ./cloudflared $args >/dev/null 2>&1 &
        sleep 2
        if pgrep -f "./cloudflared" > /dev/null; then
            green "✅ cloudflared启动成功"
        else
            yellow "⚠️  cloudflared启动失败，使用直连模式"
        fi
    fi
}

# 生成连接信息
generate_links() {
    local argodomain=$(get_argodomain)
    local available_ip=$(get_ip)

    echo -e "\n${green}=== 连接信息 ===${re}"
    echo -e "${purple}Argo域名: ${argodomain}${re}"

    local ISP=$(curl -s --max-time 2 https://speed.cloudflare.com/meta | awk -F\" '{print $26}' | sed -e 's/ /_/g' || echo "Unknown")
    local SERVER_NAME
    if [[ "$HOSTNAME" == "s1.ct8.pl" ]]; then
        SERVER_NAME="CT8"
    else
        SERVER_NAME=$(echo "$HOSTNAME" | cut -d '.' -f 1)
    fi
    local NAME="$ISP-$SERVER_NAME"

    yellow "注意：客户端的跳过证书验证需设置为true\n"

    # 生成节点信息
    cat > "${FILE_PATH}/list.txt" <<EOF
vmess://$(echo "{ \"v\": \"2\", \"ps\": \"$NAME-vmess\", \"add\": \"$available_ip\", \"port\": \"$VMESS_PORT\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"\", \"path\": \"/vmess\", \"tls\": \"\", \"sni\": \"\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)

hysteria2://$UUID@$available_ip:$HY2_PORT/?sni=www.bing.com&alpn=h3&insecure=1#$NAME-hy2

tuic://$UUID:$UUID@$available_ip:$TUIC_PORT?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1&insecure=1#$NAME-tuic
EOF

    cat "${FILE_PATH}/list.txt"

    # 生成base64订阅
    base64 -w0 "${FILE_PATH}/list.txt" > "${FILE_PATH}/v2.log"

    # 根据环境生成订阅链接
    local env=$(detect_environment)
    local V2rayN_LINK

    if [[ "$env" == "serv00" ]]; then
        V2rayN_LINK="https://${USERNAME}.${CURRENT_DOMAIN}/v2.log"

        # 创建安全的.htaccess
        cat > "${FILE_PATH}/.htaccess" <<EOF
RewriteEngine On
DirectoryIndex index.html

# 只允许访问必要文件
<FilesMatch "^(index\.html|v2\.log)$">
    Order Allow,Deny
    Allow from all
</FilesMatch>

# 拒绝访问其他文件
<FilesMatch "^(?!index\.html|v2\.log$).*">
    Order Allow,Deny
    Deny from all
</FilesMatch>
EOF

        echo -e "\n${green}订阅链接: ${V2rayN_LINK}${re}"
        # 生成二维码
        purple "正在生成订阅链接二维码..."
        generate_qr_code "$V2rayN_LINK"
    else
        echo -e "\n${yellow}VPS环境检测到，无法生成网页订阅链接${re}"
        echo -e "${blue}节点配置已保存到: ${FILE_PATH}/list.txt${re}"
        echo -e "${blue}Base64订阅文件: ${FILE_PATH}/v2.log${re}"
        echo -e "\n${green}请手动将以下节点添加到客户端:${re}"
        echo "=================================================="
        cat "${FILE_PATH}/list.txt"
        echo "=================================================="

        # 也可以生成单个节点的二维码
        purple "正在生成节点二维码..."
        echo -e "\n${blue}VMESS节点二维码:${re}"
        vmess_line=$(grep "vmess://" "${FILE_PATH}/list.txt" | head -1)
        if [[ -n "$vmess_line" ]]; then
            generate_qr_code "$vmess_line"
        fi
    fi

    echo -e "${green}安装完成！${re}\n"
}

# 创建快捷命令
create_quick_command() {
    local COMMAND_NAME="singbox"
    local SCRIPT_PATH="$HOME/bin/$COMMAND_NAME"

    mkdir -p "$HOME/bin"

    cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash
# Secure Sing-box Quick Command
cd "${WORKDIR}"

case "\$1" in
    start)
        ./sing-box run -c config.json &
        [[ -f "./cloudflared" ]] && ./cloudflared tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --url http://localhost:${VMESS_PORT} &
        echo "服务已启动"
        ;;
    stop)
        pkill -f "./sing-box"
        pkill -f "./cloudflared"
        echo "服务已停止"
        ;;
    status)
        pgrep -f "./sing-box" >/dev/null && echo "sing-box: 运行中" || echo "sing-box: 已停止"
        pgrep -f "./cloudflared" >/dev/null && echo "cloudflared: 运行中" || echo "cloudflared: 已停止"
        ;;
    logs)
        [[ -f "sing-box.log" ]] && tail -50 sing-box.log || echo "日志文件不存在"
        ;;
    logx)
        if [[ -f "sing-box.log" ]]; then
            echo "正在持续监控 sing-box 日志... (按 Ctrl+C 退出)"
            echo "========================================"
            tail -f sing-box.log
        else
            echo "日志文件不存在"
        fi
        ;;
    qr|qrcode)
        if [[ -f "${FILE_PATH}/v2.log" ]]; then
            env=$(detect_environment)
            if [[ "$env" == "serv00" ]]; then
                sub_url="https://${USERNAME}.${CURRENT_DOMAIN}/v2.log"
                echo "正在生成订阅链接二维码..."
                echo "订阅链接: $sub_url"
                echo "=================================================="
                if command -v qrencode &>/dev/null; then
                    qrencode -m 2 -t UTF8 "$sub_url"
                elif [[ -f "qr_generator.py" ]] && command -v python3 &>/dev/null; then
                    python3 qr_generator.py "$sub_url"
                else
                    echo "二维码生成工具不可用，请使用在线生成："
                    echo "https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=$sub_url"
                fi
                echo "=================================================="
                echo "请手动复制链接到客户端"
            else
                echo -e "${yellow}VPS环境，生成节点二维码${re}"
                echo "=================================================="
                vmess_line=$(grep "vmess://" "${FILE_PATH}/list.txt" | head -1)
                if [[ -n "$vmess_line" ]]; then
                    echo "VMESS节点: $vmess_line"
                    if command -v qrencode &>/dev/null; then
                        qrencode -m 2 -t UTF8 "$vmess_line"
                    elif [[ -f "qr_generator.py" ]] && command -v python3 &>/dev/null; then
                        python3 qr_generator.py "$vmess_line"
                    else
                        echo "二维码生成工具不可用，请使用在线生成："
                        echo "https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=$(echo "$vmess_line" | sed 's/+/%2B/g')"
                    fi
                fi
                echo "=================================================="
                echo "请手动复制节点到客户端"
            fi
        else
            echo "订阅文件不存在，请先安装服务"
        fi
        ;;
    link|url)
        if [[ -f "${FILE_PATH}/v2.log" ]]; then
            env=$(detect_environment)
            if [[ "$env" == "serv00" ]]; then
                echo "订阅链接: https://${USERNAME}.${CURRENT_DOMAIN}/v2.log"
            else
                echo -e "${yellow}VPS环境，无法提供网页订阅链接${re}"
                echo -e "${blue}节点配置文件: ${FILE_PATH}/list.txt${re}"
                echo -e "${blue}Base64订阅文件: ${FILE_PATH}/v2.log${re}"
                echo -e "\n${green}节点配置:${re}"
                cat "${FILE_PATH}/list.txt"
            fi
        else
            echo "订阅文件不存在，请先安装服务"
        fi
        ;;
    *)
        echo "用法: singbox {start|stop|status|logs|logx|qr|link}"
        echo "  start  - 启动服务"
        echo "  stop   - 停止服务"
        echo "  status - 查看状态"
        echo "  logs   - 查看日志"
        echo "  logx   - 持续监控日志"
        echo "  qr     - 显示订阅二维码"
        echo "  link   - 显示订阅链接"
        ;;
esac
EOF

    chmod +x "$SCRIPT_PATH"

    # 添加到PATH
    if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
        echo "export PATH=\"\$HOME/bin:\$PATH\"" >> "$HOME/.bashrc"
        export PATH="$HOME/bin:$PATH"
    fi

    green "快捷命令 'singbox' 创建成功"
    echo "可用命令: singbox start, singbox stop, singbox status, singbox logs"
}

# 主安装函数
install_singbox() {
    clear
    echo -e "${blue}================================================${re}"
    echo -e "${blue}    Serv00/CT8 安全Sing-box安装脚本${re}"
    echo -e "${blue}    使用官方二进制文件，移除安全风险${re}"
    echo -e "${blue}================================================${re}\n"

    # 安全初始化
    secure_init

    # 检查端口
    check_port

    # 检查网站
    check_website

    # 下载官方文件
    download_official_singbox
    download_official_cloudflared
    download_qrencode

    # 配置服务
    argo_configure
    generate_config

    # 启动服务
    start_services

    # 生成连接信息
    generate_links

    # 创建管理命令
    create_quick_command

    # 清理临时文件
    rm -f "$WORKDIR/boot.log" "$WORKDIR/tunnel.json" "$WORKDIR/tunnel.yml" 2>/dev/null

    green "安装完成！请使用生成的订阅链接配置客户端。"
    purple "管理命令: singbox {start|stop|status|logs|qr|link}"
}

# 错误处理
handle_error() {
    red "安装过程中发生错误，正在清理..."
    pkill -f "sing-box\|cloudflared" 2>/dev/null || true
    cd "$HOME"
    exit 1
}

# 设置错误处理
trap handle_error ERR

# 主程序入口
main() {
    # 检查运行环境
    if [[ -z "$USERNAME" || -z "$HOSTNAME" ]]; then
        red "无法获取用户名或主机名，请检查环境"
        exit 1
    fi

    # 开始安装
    install_singbox
}

# 脚本入口
main "$@"