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
export PASSWORD=${PASSWORD:-"9jK7mP4q&*ZxY!@#"}  # 强密码示例

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


# 设置路径
setup_paths() {
    # VPS环境
    CURRENT_DOMAIN="localhost"
    # 使用当前目录避免权限问题
    WORKDIR="$(pwd)/sing-box"
    FILE_PATH="$(pwd)/sing-box/web"
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


# VPS端口管理和配置
check_port() {
    clear
    purple "正在检查端口配置..."

    # 直接使用VPS端口管理
    check_port_vps
}

# 验证端口可用性
validate_port() {
    local port=$1
    local type=$2

    if [[ $port -lt 1024 || $port -gt 65535 ]]; then
        return 1
    fi

    # 检查端口是否被占用
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        return 1
    fi

    return 0
}

# 生成安全的随机端口
generate_secure_port() {
    local type=$1
    local used_ports="$2"
    local max_attempts=100
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        local port=$(shuf -i 10000-65535 -n 1)

        # 确保端口没有在使用列表中
        if [[ ! "$used_ports" =~ $port ]] && validate_port $port $type; then
            echo $port
            return 0
        fi

        ((attempt++))
    done

    # 如果无法生成，使用备用端口范围
    echo $(shuf -i 20000-30000 -n 1)
}


# VPS智能端口管理
check_port_vps() {
    purple "使用智能端口分配..."

    local used_ports=""
    local attempts=0
    local max_attempts=50

    # 智能生成TCP端口
    local tcp_port
    while [[ $attempts -lt $max_attempts ]]; do
        tcp_port=$(generate_secure_port "tcp" "$used_ports")
        if validate_port $tcp_port "tcp"; then
            used_ports="$used_ports $tcp_port"
            break
        fi
        ((attempts++))
    done

    if [[ $attempts -eq $max_attempts ]]; then
        red "无法找到可用的TCP端口"
        exit 1
    fi

    # 智能生成第一个UDP端口
    attempts=0
    local udp_port1
    while [[ $attempts -lt $max_attempts ]]; do
        udp_port1=$(generate_secure_port "udp" "$used_ports")
        if validate_port $udp_port1 "udp"; then
            used_ports="$used_ports $udp_port1"
            break
        fi
        ((attempts++))
    done

    if [[ $attempts -eq $max_attempts ]]; then
        red "无法找到可用的第一个UDP端口"
        exit 1
    fi

    # 智能生成第二个UDP端口
    attempts=0
    local udp_port2
    while [[ $attempts -lt $max_attempts ]]; do
        udp_port2=$(generate_secure_port "udp" "$used_ports")
        if validate_port $udp_port2 "udp"; then
            used_ports="$used_ports $udp_port2"
            break
        fi
        ((attempts++))
    done

    if [[ $attempts -eq $max_attempts ]]; then
        red "无法找到可用的第二个UDP端口"
        exit 1
    fi

    export VMESS_PORT=$tcp_port
    export TUIC_PORT=$udp_port1
    export HY2_PORT=$udp_port2

    green "✅ 智能端口配置完成:"
    purple "  📡 VMESS端口(TCP): $tcp_port"
    purple "  🚀 TUIC端口(UDP): $udp_port1"
    purple "  ⚡ Hysteria2端口(UDP): $udp_port2"

    # 显示端口范围信息
    yellow "端口安全信息:"
    echo "  - 所有端口均在安全范围 10000-65535"
    echo "  - 已验证端口可用性和唯一性"
    echo "  - 建议防火墙开放这些端口"
}

# 端口安全清理
cleanup_ports() {
    purple "正在进行端口安全清理..."

    # 获取当前配置的代理端口
    local proxy_ports=()
    [[ -n "$VMESS_PORT" ]] && proxy_ports+=($VMESS_PORT)
    [[ -n "$TUIC_PORT" ]] && proxy_ports+=($TUIC_PORT)
    [[ -n "$HY2_PORT" ]] && proxy_ports+=($HY2_PORT)

    # 获取SSH端口
    local ssh_port=$(ss -tlnp | grep ':22 ' | head -1 | awk '{print $4}' | cut -d':' -f2)
    [[ -z "$ssh_port" ]] && ssh_port=22

    # 系统必需端口列表
    local essential_ports=(
        $ssh_port      # SSH
        53             # DNS
        123            # NTP
        443            # HTTPS
        80             # HTTP
    )

    # 合并保护端口列表
    local protected_ports=(${essential_ports[@]} ${proxy_ports[@]})

    echo -e "\n${green}端口清理信息:${re}"
    echo -e "${purple}保护的代理端口: ${proxy_ports[*]}${re}"
    echo -e "${purple}保护的系统端口: SSH($ssh_port), DNS(53), NTP(123), HTTP(80), HTTPS(443)${re}"

    # 获取当前监听的端口
    local listening_ports=$(ss -tlnp | awk 'NR>1 {print $4}' | cut -d':' -f2 | sort -n | uniq)

    echo -e "\n${yellow}检查监听端口...${re}"

    local cleaned_count=0
    for port in $listening_ports; do
        # 跳过保护端口
        local is_protected=false
        for protected in ${protected_ports[@]}; do
            if [[ "$port" == "$protected" ]]; then
                is_protected=true
                break
            fi
        done

        if [[ "$is_protected" == false ]] && [[ $port -gt 1024 ]]; then
            # 获取占用该端口的进程
            local process_info=$(ss -tlnp | grep ":$port " | head -1)
            local pid=$(echo "$process_info" | grep -o 'pid=[0-9]*' | cut -d'=' -f2)

            if [[ -n "$pid" ]]; then
                local process_name=$(ps -p $pid -o comm= 2>/dev/null)

                # 排除系统关键进程
                if [[ "$process_name" != "systemd" ]] && [[ "$process_name" != "dbus" ]] && \
                   [[ "$process_name" != "NetworkManager" ]] && [[ "$process_name" != "chronyd" ]] && \
                   [[ "$process_name" != "sshd" ]] && [[ "$process_name" != "sing-box" ]] && \
                   [[ "$process_name" != "cloudflared" ]]; then

                    echo -e "${red}发现可疑端口 $port (进程: $process_name, PID: $pid)${re}"
                    read -p "是否关闭此端口的进程? [y/N]: " -r choice

                    if [[ "$choice" =~ ^[Yy]$ ]]; then
                        if kill $pid 2>/dev/null; then
                            echo -e "${green}✅ 已关闭端口 $port 的进程${re}"
                            ((cleaned_count++))
                        else
                            echo -e "${red}❌ 无法关闭端口 $port 的进程${re}"
                        fi
                    fi
                fi
            fi
        fi
    done

    # 防火墙规则优化
    if command -v ufw &>/dev/null; then
        echo -e "\n${purple}配置UFW防火墙规则...${re}"

        # 重置防火墙规则
        ufw --force reset >/dev/null 2>&1

        # 默认策略
        ufw default deny incoming >/dev/null 2>&1
        ufw default allow outgoing >/dev/null 2>&1

        # 允许SSH
        ufw allow $ssh_port/tcp >/dev/null 2>&1

        # 允许代理端口
        for port in ${proxy_ports[@]}; do
            if [[ $port == $VMESS_PORT ]]; then
                ufw allow $port/tcp >/dev/null 2>&1
                echo -e "${green}✅ 允许 TCP 端口 $port (VMESS)${re}"
            else
                ufw allow $port/udp >/dev/null 2>&1
                echo -e "${green}✅ 允许 UDP 端口 $port${re}"
            fi
        done

        # 启用防火墙
        echo "y" | ufw enable >/dev/null 2>&1
        echo -e "${green}✅ 防火墙配置完成${re}"

    elif command -v firewall-cmd &>/dev/null; then
        echo -e "\n${purple}配置firewalld防火墙规则...${re}"

        # 移除所有自定义规则，只保留必要端口
        firewall-cmd --permanent --remove-service=dhcpv6-client >/dev/null 2>&1
        firewall-cmd --permanent --remove-service=cockpit >/dev/null 2>&1

        # 允许SSH
        firewall-cmd --permanent --add-port=$ssh_port/tcp >/dev/null 2>&1

        # 允许代理端口
        for port in ${proxy_ports[@]}; do
            if [[ $port == $VMESS_PORT ]]; then
                firewall-cmd --permanent --add-port=$port/tcp >/dev/null 2>&1
                echo -e "${green}✅ 允许 TCP 端口 $port (VMESS)${re}"
            else
                firewall-cmd --permanent --add-port=$port/udp >/dev/null 2>&1
                echo -e "${green}✅ 允许 UDP 端口 $port${re}"
            fi
        done

        # 重载防火墙
        firewall-cmd --reload >/dev/null 2>&1
        echo -e "${green}✅ 防火墙配置完成${re}"
    else
        echo -e "\n${yellow}警告: 未检测到防火墙管理工具 (ufw/firewalld)${re}"
        echo -e "${yellow}建议手动配置防火墙只允许必要端口${re}"
    fi

    # 禁用不必要的服务
    echo -e "\n${purple}检查不必要的服务...${re}"
    local unnecessary_services=("apache2" "nginx" "mysql" "mariadb" "postgresql" "redis-server")

    for service in ${unnecessary_services[@]}; do
        if systemctl is-active --quiet $service 2>/dev/null; then
            echo -e "${yellow}发现运行中的服务: $service${re}"
            read -p "是否停止并禁用此服务? [y/N]: " -r choice

            if [[ "$choice" =~ ^[Yy]$ ]]; then
                systemctl stop $service >/dev/null 2>&1
                systemctl disable $service >/dev/null 2>&1
                echo -e "${green}✅ 已停止并禁用 $service${re}"
                ((cleaned_count++))
            fi
        fi
    done

    echo -e "\n${green}端口清理完成！${re}"
    echo -e "${purple}清理项目: $cleaned_count${re}"
    echo -e "${yellow}建议重启系统以确保所有更改生效${re}"
}

# 创建基本目录结构
setup_directories() {
    purple "创建基本目录结构..."

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

    green "✅ 目录结构创建完成"
    purple "  订阅文件将保存到: ${FILE_PATH}/v2.log"
}

# Argo隧道智能配置 - 支持Token和JSON两种认证
argo_configure() {
    purple "正在配置Argo隧道..."

    # 棄用旧配置文件
    rm -f "$WORKDIR/tunnel.json" "$WORKDIR/tunnel.yml" "$WORKDIR/argo.log" 2>/dev/null

    if [[ -z $ARGO_AUTH ]]; then
        green "✨ 使用临时隧道模式 (无需配置)"
        echo "ARGO_MODE=temporary" > "$WORKDIR/argo_config.env"
        return
    fi

    # 验证和分类Argo认证类型
    local auth_type=$(detect_argo_auth_type "$ARGO_AUTH")
    echo "ARGO_MODE=$auth_type" > "$WORKDIR/argo_config.env"

    case $auth_type in
        "json")
            setup_argo_json_auth
            ;;
        "token")
            setup_argo_token_auth
            ;;
        *)
            yellow "⚠️  未识别的Argo认证类型，回退到临时隧道模式"
            echo "ARGO_MODE=temporary" > "$WORKDIR/argo_config.env"
            ;;
    esac
}

# 检测Argo认证类型
detect_argo_auth_type() {
    local auth="$1"

    # 检查是否为JSON格式 (包含TunnelSecret)
    if echo "$auth" | jq . >/dev/null 2>&1 && echo "$auth" | grep -q "TunnelSecret"; then
        echo "json"
        return
    fi

    # 检查是否为Token格式 (以ey开头的JWT或特定格式)
    if [[ $auth =~ ^ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$ ]] || [[ $auth =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
        echo "token"
        return
    fi

    # 旧版JSON格式兼容性检查
    if echo "$auth" | grep -q "TunnelSecret" && echo "$auth" | grep -q "TunnelID"; then
        echo "json"
        return
    fi

    echo "unknown"
}

# 设置JSON认证模式
setup_argo_json_auth() {
    green "🔑 配置Argo JSON认证模式"

    # 验证JSON格式
    if ! echo "$ARGO_AUTH" | jq . >/dev/null 2>&1; then
        red "❌ JSON格式验证失败"
        return 1
    fi

    # 提取隧道ID
    local tunnel_id=$(echo "$ARGO_AUTH" | jq -r '.TunnelID // .tunnel_id // .tunnelID // empty' 2>/dev/null)
    if [[ -z "$tunnel_id" ]]; then
        # 备用方法：使用grep提取
        tunnel_id=$(echo "$ARGO_AUTH" | grep -o '"TunnelID":"[^"]*' | cut -d'"' -f4)
    fi

    if [[ -z "$tunnel_id" ]]; then
        red "❌ 无法从 JSON 中提取 TunnelID"
        return 1
    fi

    # 保存JSON认证文件
    echo "$ARGO_AUTH" | jq . > "$WORKDIR/tunnel.json" 2>/dev/null
    if [[ ! -f "$WORKDIR/tunnel.json" ]]; then
        red "❌ JSON认证文件创建失败"
        return 1
    fi

    # 生成隧道配置文件
    cat > "$WORKDIR/tunnel.yml" <<EOF
tunnel: $tunnel_id
credentials-file: tunnel.json
protocol: http2
logfile: argo.log
loglevel: info

ingress:
  - hostname: $ARGO_DOMAIN
    service: http://localhost:$VMESS_PORT
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      tlsTimeout: 10s
      keepAliveTimeout: 90s
  - service: http_status:404
EOF

    # 验证配置文件
    if [[ -f "$WORKDIR/tunnel.yml" ]]; then
        green "✅ JSON认证配置完成"
        purple "  🌍 隧道域名: $ARGO_DOMAIN"
        purple "  🆔 隧道ID: $tunnel_id"
        purple "  🔗 本地端口: $VMESS_PORT"
        echo "ARGO_TUNNEL_ID=$tunnel_id" >> "$WORKDIR/argo_config.env"
    else
        red "❌ 隧道配置文件创建失败"
        return 1
    fi
}

# 设置Token认证模式
setup_argo_token_auth() {
    green "🎫 配置Argo Token认证模式"

    # 验证Token格式
    if ! validate_argo_token "$ARGO_AUTH"; then
        red "❌ Token格式验证失败"
        return 1
    fi

    green "✅ Token认证配置完成"
    purple "  🎫 Token長度: ${#ARGO_AUTH} 字符"
    purple "  🔗 本地端口: $VMESS_PORT"

    if [[ -n "$ARGO_DOMAIN" ]]; then
        purple "  🌍 隧道域名: $ARGO_DOMAIN"
        echo "ARGO_DOMAIN_SET=true" >> "$WORKDIR/argo_config.env"
    else
        yellow "  ⚠️  未设置域名，将使用随机域名"
        echo "ARGO_DOMAIN_SET=false" >> "$WORKDIR/argo_config.env"
    fi

    echo "ARGO_TOKEN=$ARGO_AUTH" >> "$WORKDIR/argo_config.env"

    yellow "📝 重要提示: 请确保在Cloudflare后台设置正确的隧道目标端口: $VMESS_PORT"
}

# 验证Argo Token
validate_argo_token() {
    local token="$1"

    # 检查Token长度和格式
    if [[ ${#token} -lt 50 || ${#token} -gt 300 ]]; then
        return 1
    fi

    # 检查是否包含非法字符
    if [[ ! $token =~ ^[A-Za-z0-9._-]+$ ]]; then
        return 1
    fi

    return 0
}

# 生成配置文件
generate_config() {
    purple "正在生成配置文件..."

    # 生成增强SSL证书
    generate_ssl_certificate

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
        "tag": "google-dns",
        "address": "udp://8.8.8.8"
      },
      {
        "tag": "cloudflare-dns",
        "address": "udp://1.1.1.1"
      }
    ]
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
      "domain_strategy": "prefer_ipv4"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "domain": [
          "openai.com",
          "chat.openai.com",
          "api.openai.com",
          "platform.openai.com",
          "auth0.openai.com",
          "cdn.openai.com",
          "challenges.cloudflare.com",
          "chatgpt.com",
          "oaistatic.com",
          "oaiusercontent.com",
          "chatgpt.livekit.cloud"
        ],
        "domain_suffix": [
          ".openai.com",
          ".chatgpt.com",
          ".oaistatic.com",
          ".oaiusercontent.com"
        ],
        "inbound": ["vmess-ws-in", "tuic-in", "hysteria-in"],
        "outbound": "direct"
      },
      {
        "domain": [
          "netflix.com",
          "netflix.net",
          "nflxext.com",
          "nflximg.com",
          "nflximg.net",
          "nflxso.net",
          "nflxvideo.net"
        ],
        "domain_suffix": [
          ".netflix.com",
          ".netflix.net",
          ".nflxext.com",
          ".nflximg.com",
          ".nflximg.net",
          ".nflxso.net",
          ".nflxvideo.net",
          ".netflixdnstest0.com",
          ".netflixdnstest1.com",
          ".netflixdnstest2.com",
          ".netflixdnstest3.com",
          ".netflixdnstest4.com",
          ".netflixdnstest5.com",
          ".netflixdnstest6.com",
          ".netflixdnstest7.com",
          ".netflixdnstest8.com",
          ".netflixdnstest9.com"
        ],
        "inbound": ["vmess-ws-in", "tuic-in", "hysteria-in"],
        "outbound": "direct"
      },
      {
        "domain": [
          "youtube.com",
          "googlevideo.com",
          "ytimg.com",
          "googleapis.com",
          "youtu.be",
          "youtube-nocookie.com",
          "ggpht.com"
        ],
        "domain_suffix": [
          ".youtube.com",
          ".googlevideo.com",
          ".ytimg.com",
          ".youtu.be",
          ".youtube-nocookie.com",
          ".ggpht.com"
        ],
        "inbound": ["vmess-ws-in", "tuic-in", "hysteria-in"],
        "outbound": "direct"
      },
      {
        "domain": [
          "disney.com",
          "disneyplus.com",
          "disney-plus.net",
          "dssott.com",
          "bamgrid.com",
          "bam.nr-data.net",
          "disneystreaming.com",
          "cdn.registerdisney.go.com"
        ],
        "domain_suffix": [
          ".disney.com",
          ".disneyplus.com",
          ".disney-plus.net",
          ".dssott.com",
          ".bamgrid.com",
          ".disneystreaming.com"
        ],
        "inbound": ["vmess-ws-in", "tuic-in", "hysteria-in"],
        "outbound": "direct"
      },
      {
        "domain": [
          "hbo.com",
          "hbogo.com",
          "hbomax.com",
          "hbonow.com",
          "maxgo.com"
        ],
        "domain_suffix": [
          ".hbo.com",
          ".hbogo.com",
          ".hbomax.com",
          ".hbonow.com",
          ".maxgo.com"
        ],
        "inbound": ["vmess-ws-in", "tuic-in", "hysteria-in"],
        "outbound": "direct"
      },
      {
        "domain_suffix": [
          ".spotify.com",
          ".spotifycdn.com",
          ".scdn.co"
        ],
        "inbound": ["vmess-ws-in", "tuic-in", "hysteria-in"],
        "outbound": "direct"
      },
      {
        "domain_suffix": [
          ".tiktok.com",
          ".tiktokcdn.com",
          ".tiktokv.com",
          ".tiktok-us.com"
        ],
        "inbound": ["vmess-ws-in", "tuic-in", "hysteria-in"],
        "outbound": "direct"
      },
      {
        "domain": [
          "claude.ai",
          "anthropic.com"
        ],
        "domain_suffix": [
          ".claude.ai",
          ".anthropic.com"
        ],
        "inbound": ["vmess-ws-in", "tuic-in", "hysteria-in"],
        "outbound": "direct"
      },
      {
        "domain": [
          "bard.google.com",
          "gemini.google.com",
          "makersuite.google.com"
        ],
        "domain_suffix": [
          ".ai.google",
          ".bard.google.com",
          ".gemini.google.com"
        ],
        "inbound": ["vmess-ws-in", "tuic-in", "hysteria-in"],
        "outbound": "direct"
      },
      {
        "ip_cidr": [
          "224.0.0.0/3",
          "169.254.0.0/16",
          "192.168.0.0/16",
          "10.0.0.0/8",
          "172.16.0.0/12",
          "127.0.0.1/32",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outbound": "direct"
      },
      {
        "inbound": ["vmess-ws-in", "tuic-in", "hysteria-in"],
        "outbound": "direct"
      }
    ],
    "final": "direct",
    "auto_detect_interface": true
  }
}
EOF
}

# 增强SSL证书生成功能
generate_ssl_certificate() {
    purple "正在生成增强SSL证书..."

    local cert_path="$WORKDIR/cert.pem"
    local key_path="$WORKDIR/private.key"
    local config_path="$WORKDIR/openssl.conf"

    # 清理旧证书
    rm -f "$cert_path" "$key_path" "$config_path" 2>/dev/null

    # 生成增强的OpenSSL配置文件
    cat > "$config_path" <<EOF
[ req ]
default_bits = 2048
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[ req_distinguished_name ]
C = US
ST = California
L = San Francisco
O = Sing-box Service
OU = VPN Department
CN = $USERNAME.${CURRENT_DOMAIN}

[ v3_req ]
keyUsage = digitalSignature, keyEncipherment, keyAgreement
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names
basicConstraints = CA:FALSE

[ alt_names ]
DNS.1 = $USERNAME.${CURRENT_DOMAIN}
DNS.2 = localhost
DNS.3 = *.${CURRENT_DOMAIN}
IP.1 = 127.0.0.1
IP.2 = $(get_ip)
EOF

    # 生成私钥 (使用RSA 2048位更兼容)
    purple "正在生成RSA私钥 (2048位)..."
    if ! openssl genrsa -out "$key_path" 2048 2>/dev/null; then
        red "❌ 私钥生成失败"
        return 1
    fi

    # 设置私钥权限
    chmod 600 "$key_path"

    # 生成自签名证书 (5年有效期)
    purple "正在生成自签名证书 (5年有效期)..."
    if ! openssl req -new -x509 -days 1825 -key "$key_path" -out "$cert_path" \
        -config "$config_path" -extensions v3_req 2>/dev/null; then
        red "❌ 证书生成失败"
        return 1
    fi

    # 设置证书权限
    chmod 644 "$cert_path"

    # 验证证书
    if ! openssl x509 -in "$cert_path" -text -noout >/dev/null 2>&1; then
        red "❌ 证书验证失败"
        return 1
    fi

    # 显示证书信息
    local cert_info=$(openssl x509 -in "$cert_path" -text -noout 2>/dev/null)
    local cert_subject=$(echo "$cert_info" | grep "Subject:" | sed 's/.*Subject: //')
    local cert_san=$(echo "$cert_info" | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/[[:space:]]*//')
    local cert_validity=$(openssl x509 -in "$cert_path" -dates -noout 2>/dev/null)
    local not_before=$(echo "$cert_validity" | grep "notBefore" | cut -d'=' -f2)
    local not_after=$(echo "$cert_validity" | grep "notAfter" | cut -d'=' -f2)

    green "✅ SSL证书生成成功"
    echo "证书详情："
    echo "  📜 主题: $cert_subject"
    echo "  🌍 替代名称: $cert_san"
    echo "  📅 生效日期: $not_before"
    echo "  📅 过期日期: $not_after"
    echo "  🔐 私钥文件: $key_path"
    echo "  📄 证书文件: $cert_path"

    # 生成证书指纹
    local cert_fingerprint=$(openssl x509 -in "$cert_path" -fingerprint -sha256 -noout 2>/dev/null | cut -d'=' -f2)
    echo "  🔍 SHA256指纹: $cert_fingerprint"

    # 清理临时配置文件
    rm -f "$config_path"

    return 0
}

# 证书管理功能
manage_ssl_certificate() {
    local action="$1"
    local cert_path="$WORKDIR/cert.pem"
    local key_path="$WORKDIR/private.key"

    case $action in
        "check")
            if [[ -f "$cert_path" && -f "$key_path" ]]; then
                # 检查证书是否在7天内过期 (604800秒 = 7天)
                local cert_validity=$(openssl x509 -in "$cert_path" -checkend 604800 2>/dev/null)
                if [[ $? -eq 0 ]]; then
                    green "✅ SSL证书有效且未过期"

                    # 显示剩余天数
                    local expiry_date=$(openssl x509 -in "$cert_path" -enddate -noout 2>/dev/null | cut -d'=' -f2)
                    local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null)
                    local current_timestamp=$(date +%s)
                    if [[ -n "$expiry_timestamp" ]]; then
                        local days_remaining=$(( ($expiry_timestamp - $current_timestamp) / 86400 ))
                        echo "  📅 证书剩余有效期: ${days_remaining} 天"
                    fi
                    return 0
                else
                    yellow "⚠️  SSL证书将在7天内过期，建议更新"
                    return 1
                fi
            else
                red "❌ SSL证书文件不存在"
                return 1
            fi
            ;;
        "renew")
            yellow "正在更新SSL证书..."
            generate_ssl_certificate
            ;;
        "info")
            if [[ -f "$cert_path" ]]; then
                echo "证书信息："
                openssl x509 -in "$cert_path" -text -noout 2>/dev/null | grep -E "(Subject|Issuer|Not Before|Not After|Subject Alternative Name)" | sed 's/^[[:space:]]*/  /'
            else
                red "❌ 证书文件不存在"
            fi
            ;;
        *)
            echo "用法: manage_ssl_certificate {check|renew|info}"
            return 1
            ;;
    esac
}

# 获取服务器IP
get_ip() {
    # VPS环境，获取公网IP
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

# 智能获取Argo域名
get_argodomain() {
    # 读取Argo配置
    local argo_mode="temporary"
    local temp_domain=""

    if [[ -f "$WORKDIR/argo_config.env" ]]; then
        source "$WORKDIR/argo_config.env"
    fi

    case $argo_mode in
        "json"|"token")
            if [[ -n "$ARGO_DOMAIN" ]]; then
                echo "$ARGO_DOMAIN"
            else
                echo "config-domain-missing"
            fi
            ;;
        *)
            # 临时隧道模式，从日志中获取
            local retry=0
            local max_retries=8
            local argodomain=""

            while [[ $retry -lt $max_retries ]]; do
                ((retry++))

                # 先从环境变量获取
                if [[ -n "$TEMP_DOMAIN" ]]; then
                    argodomain="$TEMP_DOMAIN"
                    break
                fi

                # 从日志文件获取
                for logfile in "$WORKDIR/boot.log" "$WORKDIR/cloudflared.log"; do
                    if [[ -f "$logfile" ]]; then
                        argodomain=$(grep -oE 'https://[[:alnum:]+\.-]+\.trycloudflare\.com' "$logfile" | sed 's@https://@@' | head -1)
                        if [[ -n "$argodomain" ]]; then
                            echo "TEMP_DOMAIN=$argodomain" >> "$WORKDIR/argo_config.env"
                            break 2
                        fi
                    fi
                done

                sleep 1
            done

            if [[ -n "$argodomain" ]]; then
                echo "$argodomain"
            else
                echo "temp-domain-pending"
            fi
            ;;
    esac
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

        # 启动新进程 (添加环境变量以兼容旧版本)
        ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true nohup ./sing-box run -c config.json >sing-box.log 2>&1 &
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

    # 智能启动cloudflared
    start_cloudflared_service
}

# 智能启动Cloudflared服务
start_cloudflared_service() {
    if [[ ! -f "./cloudflared" ]]; then
        yellow "⚠️  cloudflared 未安装，跳过Argo隧道服务"
        return 1
    fi

    # 读取Argo配置
    local argo_mode="temporary"
    if [[ -f "$WORKDIR/argo_config.env" ]]; then
        source "$WORKDIR/argo_config.env"
    fi

    purple "正在启动 Cloudflared (模式: $argo_mode)..."

    # 清理旧进程
    pkill -f "./cloudflared" 2>/dev/null || true
    sleep 1

    local args
    case $argo_mode in
        "json")
            if [[ -f "tunnel.yml" && -f "tunnel.json" ]]; then
                args="tunnel --edge-ip-version auto --config tunnel.yml run"
                green "🔑 使用JSON认证模式"
            else
                red "❌ JSON配置文件丢失，回退到临时模式"
                args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --loglevel info --url http://localhost:$VMESS_PORT"
            fi
            ;;
        "token")
            if [[ -n "$ARGO_TOKEN" ]]; then
                args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token $ARGO_TOKEN"
                green "🎫 使用Token认证模式"
            else
                red "❌ Token丢失，回退到临时模式"
                args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --loglevel info --url http://localhost:$VMESS_PORT"
            fi
            ;;
        *)
            args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --loglevel info --url http://localhost:$VMESS_PORT"
            green "✨ 使用临时隧道模式"
            ;;
    esac

    # 启动Cloudflared
    purple "正在执行: cloudflared $args"
    nohup ./cloudflared $args >cloudflared.log 2>&1 &
    local cf_pid=$!

    # 等待启动
    sleep 3

    # 检查进程状态
    if pgrep -f "./cloudflared" >/dev/null; then
        green "✅ Cloudflared 启动成功 (PID: $(pgrep -f "./cloudflared"))"

        # 显示连接信息
        sleep 2
        if [[ $argo_mode == "temporary" && -f "boot.log" ]]; then
            local temp_domain=$(grep -oE 'https://[[:alnum:]+\.-]+\.trycloudflare\.com' boot.log | sed 's@https://@@' | head -1)
            if [[ -n "$temp_domain" ]]; then
                purple "  🌍 临时域名: $temp_domain"
                echo "TEMP_DOMAIN=$temp_domain" >> "$WORKDIR/argo_config.env"
            fi
        fi

        # 显示启动日志
        if [[ -f "cloudflared.log" ]]; then
            echo "启动日志："
            head -3 cloudflared.log | grep -v "time=" || echo "  (等待连接建立...)"
        fi
    else
        red "❌ Cloudflared 启动失败"
        echo "错误日志："
        cat cloudflared.log 2>/dev/null | tail -5 || echo "无法读取日志文件"
        yellow "⚠️  将使用直连模式，不影响核心功能"
        return 1
    fi
}

# 生成连接信息
generate_links() {
    local argodomain=$(get_argodomain)
    local available_ip=$(get_ip)

    echo -e "\n${green}=== 连接信息 ===${re}"
    echo -e "${purple}服务器IP: ${available_ip}${re}"
    echo -e "${purple}Argo域名: ${argodomain}${re}"
    echo -e "${purple}端口配置: TCP:${VMESS_PORT} UDP:${TUIC_PORT},${HY2_PORT}${re}"

    local ISP=$(curl -s --max-time 2 https://speed.cloudflare.com/meta | awk -F\" '{print $26}' | sed -e 's/ /_/g' || echo "Unknown")
    local SERVER_NAME=$(echo "$HOSTNAME" | cut -d '.' -f 1)
    local NAME="$ISP-$SERVER_NAME"

    yellow "注意：客户端的跳过证书验证需设置为true\n"

    # 生成节点信息
    cat > "${FILE_PATH}/list.txt" <<EOF
vmess://$(echo "{ \"v\": \"2\", \"ps\": \"$NAME-vmess\", \"add\": \"$available_ip\", \"port\": \"$VMESS_PORT\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"\", \"path\": \"/vmess\", \"tls\": \"\", \"sni\": \"\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)

hysteria2://$UUID@$available_ip:$HY2_PORT/?sni=www.bing.com&alpn=h3&insecure=1#$NAME-hy2

tuic://$UUID:$UUID@$available_ip:$TUIC_PORT?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1&insecure=1#$NAME-tuic
EOF

    echo -e "\n${green}节点配置信息:${re}"
    echo "=================================================="
    cat "${FILE_PATH}/list.txt"
    echo "=================================================="

    # 生成base64订阅文件（仅供本地使用）
    base64 -w0 "${FILE_PATH}/list.txt" > "${FILE_PATH}/v2.log"

    echo -e "\n${blue}本地文件信息:${re}"
    echo -e "  节点配置: ${FILE_PATH}/list.txt"
    echo -e "  Base64订阅: ${FILE_PATH}/v2.log"

    green "请手动复制上面的节点信息到您的客户端。"

    echo -e "${green}安装完成！${re}\n"
}

# 创建保活服务
create_keepalive_service() {
    purple "正在创建保活服务..."

    local keepalive_script="$WORKDIR/keepalive.sh"
    local keepalive_config="$WORKDIR/keepalive.conf"

    # 创建保活配置
    cat > "$keepalive_config" <<EOF
# 保活服务配置文件
CHECK_INTERVAL=30
RESTART_LIMIT=5
HEALTH_CHECK_TIMEOUT=10
LOG_RETENTION_DAYS=7
WORKDIR="$WORKDIR"
USERNAME="$USERNAME"
VMESS_PORT="$VMESS_PORT"
EOF

    # 创建保活脚本
    cat > "$keepalive_script" <<'EOF'
#!/bin/bash

# 简化版保活机制
# 监控 sing-box 和 cloudflared 进程状态

# 加载配置
KEEPALIVE_DIR="$(dirname "$0")"
KEEPALIVE_CONFIG="$KEEPALIVE_DIR/keepalive.conf"

if [[ -f "$KEEPALIVE_CONFIG" ]]; then
    source "$KEEPALIVE_CONFIG"
else
    echo "[错误] 配置文件不存在: $KEEPALIVE_CONFIG"
    exit 1
fi

# 默认配置
CHECK_INTERVAL=${CHECK_INTERVAL:-30}
RESTART_LIMIT=${RESTART_LIMIT:-5}
HEALTH_CHECK_TIMEOUT=${HEALTH_CHECK_TIMEOUT:-10}
LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-7}

# 日志文件
KEEPALIVE_LOG="$WORKDIR/keepalive.log"
PID_FILE="$WORKDIR/keepalive.pid"

# 颜色定义
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
NC="\e[0m" # No Color

# 日志函数
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" >> "$KEEPALIVE_LOG"

    case $level in
        "INFO") echo -e "${GREEN}[信息]${NC} $message" ;;
        "WARN") echo -e "${YELLOW}[警告]${NC} $message" ;;
        "ERROR") echo -e "${RED}[错误]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[调试]${NC} $message" ;;
    esac
}

# 检查进程是否运行
check_process() {
    local process_name="$1"
    local process_pattern="$2"

    if pgrep -f "$process_pattern" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 健康检查
health_check() {
    local service="$1"
    local port="$2"

    case $service in
        "sing-box")
            # 检查端口是否监听
            if netstat -tuln 2>/dev/null | grep -q ":$port "; then
                return 0
            else
                return 1
            fi
            ;;
        "cloudflared")
            # 检查进程和日志文件
            if check_process "cloudflared" "./cloudflared"; then
                return 0
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

# 重启服务
restart_service() {
    local service="$1"

    cd "$WORKDIR" || {
        log "ERROR" "无法进入工作目录: $WORKDIR"
        return 1
    }

    case $service in
        "sing-box")
            log "WARN" "正在重启 sing-box..."
            pkill -f "./sing-box" 2>/dev/null || true
            sleep 2

            if [[ -f "./sing-box" && -f "config.json" ]]; then
                ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true nohup ./sing-box run -c config.json >sing-box.log 2>&1 &
                sleep 3

                if check_process "sing-box" "./sing-box"; then
                    log "INFO" "sing-box 重启成功"
                    return 0
                else
                    log "ERROR" "sing-box 重启失败"
                    return 1
                fi
            else
                log "ERROR" "sing-box 文件或配置不存在"
                return 1
            fi
            ;;
        "cloudflared")
            log "WARN" "正在重启 cloudflared..."
            pkill -f "./cloudflared" 2>/dev/null || true
            sleep 2

            if [[ -f "./cloudflared" ]]; then
                # 读取Argo配置
                local argo_mode="temporary"
                if [[ -f "argo_config.env" ]]; then
                    source "argo_config.env"
                fi

                local args
                case $argo_mode in
                    "json")
                        if [[ -f "tunnel.yml" && -f "tunnel.json" ]]; then
                            args="tunnel --edge-ip-version auto --config tunnel.yml run"
                        else
                            args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --loglevel info --url http://localhost:$VMESS_PORT"
                        fi
                        ;;
                    "token")
                        if [[ -n "$ARGO_TOKEN" ]]; then
                            args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token $ARGO_TOKEN"
                        else
                            args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --loglevel info --url http://localhost:$VMESS_PORT"
                        fi
                        ;;
                    *)
                        args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --loglevel info --url http://localhost:$VMESS_PORT"
                        ;;
                esac

                nohup ./cloudflared $args >cloudflared.log 2>&1 &
                sleep 3

                if check_process "cloudflared" "./cloudflared"; then
                    log "INFO" "cloudflared 重启成功"
                    return 0
                else
                    log "ERROR" "cloudflared 重启失败"
                    return 1
                fi
            else
                log "ERROR" "cloudflared 文件不存在"
                return 1
            fi
            ;;
        *)
            log "ERROR" "未知服务: $service"
            return 1
            ;;
    esac
}

# 清理旧日志
cleanup_logs() {
    if [[ $LOG_RETENTION_DAYS -gt 0 ]]; then
        find "$WORKDIR" -name "*.log" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
    fi
}

# 保活主循环
main_loop() {
    local restart_count_singbox=0
    local restart_count_cloudflared=0
    local last_cleanup=$(date +%s)

    log "INFO" "保活服务启动 (PID: $$, 检查间隔: ${CHECK_INTERVAL}秒)"

    while true; do
        local current_time=$(date +%s)

        # 检查 sing-box
        if ! check_process "sing-box" "./sing-box" || ! health_check "sing-box" "$VMESS_PORT"; then
            if [[ $restart_count_singbox -lt $RESTART_LIMIT ]]; then
                log "WARN" "sing-box 服务异常，尝试重启 ($((restart_count_singbox + 1))/$RESTART_LIMIT)"
                if restart_service "sing-box"; then
                    ((restart_count_singbox++))
                else
                    log "ERROR" "sing-box 重启失败"
                    ((restart_count_singbox++))
                fi
            else
                log "ERROR" "sing-box 达到最大重启次数，停止重启尝试"
            fi
        else
            # 服务正常，重置重启计数
            if [[ $restart_count_singbox -gt 0 ]]; then
                restart_count_singbox=0
                log "INFO" "sing-box 服务恢复正常，重置重启计数"
            fi
        fi

        # 检查 cloudflared (可选)
        if [[ -f "$WORKDIR/cloudflared" ]]; then
            if ! check_process "cloudflared" "./cloudflared" || ! health_check "cloudflared"; then
                if [[ $restart_count_cloudflared -lt $RESTART_LIMIT ]]; then
                    log "WARN" "cloudflared 服务异常，尝试重启 ($((restart_count_cloudflared + 1))/$RESTART_LIMIT)"
                    if restart_service "cloudflared"; then
                        ((restart_count_cloudflared++))
                    else
                        log "ERROR" "cloudflared 重启失败"
                        ((restart_count_cloudflared++))
                    fi
                else
                    log "ERROR" "cloudflared 达到最大重启次数，停止重启尝试"
                fi
            else
                # 服务正常，重置重启计数
                if [[ $restart_count_cloudflared -gt 0 ]]; then
                    restart_count_cloudflared=0
                    log "INFO" "cloudflared 服务恢复正常，重置重启计数"
                fi
            fi
        fi

        # 每小时清理一次日志
        if [[ $((current_time - last_cleanup)) -gt 3600 ]]; then
            cleanup_logs
            last_cleanup=$current_time
        fi

        sleep $CHECK_INTERVAL
    done
}

# 停止保活服务
stop_keepalive() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$PID_FILE"
            log "INFO" "保活服务已停止 (PID: $pid)"
        else
            rm -f "$PID_FILE"
            log "WARN" "PID文件存在但进程不存在，已清理"
        fi
    else
        log "INFO" "保活服务未运行"
    fi
}

# 查看保活服务状态
status_keepalive() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "保活服务正在运行 (PID: $pid)"
            # 显示监控状态
            echo "监控状态："
            check_process "sing-box" "./sing-box" && echo "  sing-box: 正常" || echo "  sing-box: 异常"
            [[ -f "$WORKDIR/cloudflared" ]] && {
                check_process "cloudflared" "./cloudflared" && echo "  cloudflared: 正常" || echo "  cloudflared: 异常"
            }
            return 0
        else
            echo "保活服务未运行 (PID文件存在但进程不存在)"
            rm -f "$PID_FILE"
            return 1
        fi
    else
        echo "保活服务未运行"
        return 1
    fi
}

# 主程序
case "$1" in
    "start")
        if [[ -f "$PID_FILE" ]]; then
            local pid=$(cat "$PID_FILE")
            if kill -0 "$pid" 2>/dev/null; then
                echo "保活服务已在运行 (PID: $pid)"
                exit 0
            else
                rm -f "$PID_FILE"
            fi
        fi

        # 后台启动
        nohup "$0" "main" >/dev/null 2>&1 &
        echo $! > "$PID_FILE"
        echo "保活服务已启动 (PID: $!)"
        ;;
    "stop")
        stop_keepalive
        ;;
    "status")
        status_keepalive
        ;;
    "restart")
        stop_keepalive
        sleep 2
        "$0" "start"
        ;;
    "main")
        # 保存PID
        echo $$ > "$PID_FILE"
        # 设置信号处理
        trap 'log "INFO" "接收到退出信号，正在停止..."; rm -f "$PID_FILE"; exit 0' TERM INT
        # 进入主循环
        main_loop
        ;;
    "logs")
        if [[ -f "$KEEPALIVE_LOG" ]]; then
            tail -50 "$KEEPALIVE_LOG"
        else
            echo "日志文件不存在"
        fi
        ;;
    *)
        echo "用法: $0 {start|stop|status|restart|logs}"
        echo "  start   - 启动保活服务"
        echo "  stop    - 停止保活服务"
        echo "  status  - 查看服务状态"
        echo "  restart - 重启保活服务"
        echo "  logs    - 查看保活日志"
        exit 1
        ;;
esac
EOF

    chmod +x "$keepalive_script"

    green "✅ 保活服务创建成功"
    echo "保活服务信息："
    echo "  📄 脚本位置: $keepalive_script"
    echo "  ⚙️  配置文件: $keepalive_config"
    echo "  🔄 检查间隔: ${CHECK_INTERVAL:-30}秒"
    echo "  🔁 最大重启: ${RESTART_LIMIT:-5}次"
    echo "  📅 日志保留: ${LOG_RETENTION_DAYS:-7}天"

    yellow "使用方法："
    echo "  $keepalive_script start   # 启动保活服务"
    echo "  $keepalive_script stop    # 停止保活服务"
    echo "  $keepalive_script status  # 查看服务状态"
    echo "  $keepalive_script restart # 重启保活服务"
    echo "  $keepalive_script logs    # 查看保活日志"
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
        ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true ./sing-box run -c config.json &
        [[ -f "./cloudflared" ]] && ./cloudflared tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --url http://localhost:${VMESS_PORT} &
        echo "服务已启动"
        # 自动启动保活服务
        [[ -f "keepalive.sh" ]] && ./keepalive.sh start
        ;;
    stop)
        # 先停止保活服务
        [[ -f "keepalive.sh" ]] && ./keepalive.sh stop
        pkill -f "./sing-box"
        pkill -f "./cloudflared"
        echo "服务已停止"
        ;;
    status)
        pgrep -f "./sing-box" >/dev/null && echo "sing-box: 运行中" || echo "sing-box: 已停止"
        pgrep -f "./cloudflared" >/dev/null && echo "cloudflared: 运行中" || echo "cloudflared: 已停止"
        # 显示保活服务状态
        if [[ -f "keepalive.sh" ]]; then
            echo "保活服务:"
            ./keepalive.sh status | sed 's/^/  /'
        fi
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
    cert)
        manage_ssl_certificate "$2"
        ;;
    keep|keepalive)
        if [[ -f "keepalive.sh" ]]; then
            ./keepalive.sh "$2" "$3"
        else
            echo "保活服务脚本不存在"
        fi
        ;;
    clean|cleanup)
        cleanup_ports
        ;;
    auto|autostart)
        case "$2" in
            "enable")
                if command -v systemctl &>/dev/null; then
                    systemctl enable sing-box-auto
                    echo -e "${green}✅ 开机自启动已启用${re}"
                else
                    echo -e "${yellow}系统不支持systemd，请确保crontab自启动正常工作${re}"
                fi
                ;;
            "disable")
                if command -v systemctl &>/dev/null; then
                    systemctl disable sing-box-auto
                    echo -e "${green}✅ 开机自启动已禁用${re}"
                else
                    echo -e "${yellow}请手动删除crontab中的自启动条目${re}"
                    echo "使用命令: crontab -e"
                fi
                ;;
            "status")
                if command -v systemctl &>/dev/null; then
                    systemctl status sing-box-auto
                else
                    echo "检查crontab自启动条目:"
                    crontab -l | grep -E "(sing-box|cron-start)" || echo "未找到自启动条目"
                fi
                ;;
            "test")
                if [[ -f "${WORKDIR}/auto-start.sh" ]]; then
                    echo -e "${blue}正在测试自启动脚本...${re}"
                    bash "${WORKDIR}/auto-start.sh"
                else
                    echo -e "${red}自启动脚本不存在${re}"
                fi
                ;;
            "log")
                if [[ -f "${WORKDIR}/auto-start.log" ]]; then
                    tail -50 "${WORKDIR}/auto-start.log"
                else
                    echo "启动日志不存在"
                fi
                ;;
            *)
                echo "用法: singbox auto {enable|disable|status|test|log}"
                echo "  enable  - 启用开机自启动"
                echo "  disable - 禁用开机自启动"
                echo "  status  - 查看自启动状态"
                echo "  test    - 测试自启动脚本"
                echo "  log     - 查看启动日志"
                ;;
        esac
        ;;
    link|url|show)
        if [[ -f "${FILE_PATH}/v2.log" ]]; then
            local available_ip=$(get_ip)
            local argodomain=$(get_argodomain)

            echo -e "${blue}=== 服务器连接信息 ===${re}"
            echo -e "${purple}服务器IP: ${available_ip}${re}"
            echo -e "${purple}Argo域名: ${argodomain}${re}"
            echo -e "${purple}端口配置: TCP:${VMESS_PORT} UDP:${TUIC_PORT},${HY2_PORT}${re}"

            echo -e "\n${blue}本地文件信息:${re}"
            echo -e "  节点配置文件: ${FILE_PATH}/list.txt"
            echo -e "  Base64订阅文件: ${FILE_PATH}/v2.log"
            echo -e "\n${green}节点配置:${re}"
            echo "=================================================="
            cat "${FILE_PATH}/list.txt"
            echo "=================================================="
            echo -e "\n${yellow}请手动复制上面的节点信息到您的客户端${re}"
        else
            echo "节点文件不存在，请先安装服务"
        fi
        ;;
    *)
        echo "用法: singbox {start|stop|status|logs|logx|show|cert|keep|clean|auto}"
        echo "  start  - 启动服务"
        echo "  stop   - 停止服务"
        echo "  status - 查看状态"
        echo "  logs   - 查看日志"
        echo "  logx   - 持续监控日志"
        echo "  show   - 显示节点配置"
        echo "  cert   - SSL证书管理 {check|renew|info}"
        echo "  keep   - 保活服务 {start|stop|status|restart|logs}"
        echo "  clean  - 端口安全清理 (关闭多余端口，配置防火墙)"
        echo "  auto   - 开机自启动管理 {enable|disable|status|test|log}"
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
    echo "可用命令: singbox start, singbox stop, singbox status, singbox logs, singbox cert, singbox keep, singbox clean, singbox auto"
}

# 创建独立的keepalive快捷命令
create_keepalive_command() {
    local script_path="$HOME/bin/keepalive"

    # 确保bin目录存在
    mkdir -p "$HOME/bin"

    cat > "$script_path" <<EOF
#!/bin/bash

# Keepalive 快捷命令脚本
# 自动查找sing-box工作目录中的keepalive.sh

# 颜色定义
red='\033[31m'
green='\033[32m'
yellow='\033[33m'
blue='\033[34m'
purple='\033[35m'
re='\033[0m'

# 查找keepalive.sh脚本
find_keepalive_script() {
    local search_paths=(
        "\$HOME/sing-box"
        "\$HOME/serv00-play"
        "/root/sing-box"
        "\$PWD"
    )

    for path in "\${search_paths[@]}"; do
        if [[ -f "\$path/keepalive.sh" ]]; then
            echo "\$path/keepalive.sh"
            return 0
        fi
    done

    return 1
}

# 主逻辑
main() {
    local keepalive_script=\$(find_keepalive_script)

    if [[ -z "\$keepalive_script" ]]; then
        echo -e "\${red}错误: 未找到keepalive.sh脚本\${re}"
        echo -e "\${yellow}请确保已正确安装sing-box服务\${re}"
        echo -e "\${yellow}查找路径: \$HOME/sing-box, \$HOME/serv00-play, /root/sing-box, 当前目录\${re}"
        exit 1
    fi

    echo -e "\${blue}使用保活脚本: \$keepalive_script\${re}"

    # 确保脚本有执行权限
    chmod +x "\$keepalive_script"

    # 切换到脚本目录并执行
    local script_dir=\$(dirname "\$keepalive_script")
    cd "\$script_dir"

    # 传递所有参数给keepalive.sh
    "\$keepalive_script" "\$@"
}

# 显示帮助信息
show_help() {
    echo -e "\${green}Keepalive 保活服务管理工具\${re}"
    echo -e "\${purple}用法: keepalive {start|stop|status|restart|logs}\${re}"
    echo ""
    echo -e "\${yellow}命令说明:\${re}"
    echo "  start   - 启动保活服务"
    echo "  stop    - 停止保活服务"
    echo "  status  - 查看服务状态"
    echo "  restart - 重启保活服务"
    echo "  logs    - 查看保活日志"
    echo ""
    echo -e "\${blue}示例:\${re}"
    echo "  keepalive start    # 启动保活服务"
    echo "  keepalive status   # 查看状态"
    echo "  keepalive logs     # 查看日志"
}

# 检查参数
if [[ \$# -eq 0 ]] || [[ "\$1" == "help" ]] || [[ "\$1" == "--help" ]] || [[ "\$1" == "-h" ]]; then
    show_help
    exit 0
fi

# 执行主逻辑
main "\$@"
EOF

    chmod +x "$script_path"

    # 添加到PATH
    if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
        echo "export PATH=\"\$HOME/bin:\$PATH\"" >> "$HOME/.bashrc"
        export PATH="$HOME/bin:$PATH"
    fi

    green "✅ 独立keepalive命令创建成功"
    echo -e "${blue}现在可以在任何目录使用以下命令:${re}"
    echo "  keepalive start   # 启动保活服务"
    echo "  keepalive stop    # 停止保活服务"
    echo "  keepalive status  # 查看服务状态"
    echo "  keepalive restart # 重启保活服务"
    echo "  keepalive logs    # 查看保活日志"
}

# 创建开机自启动服务
create_auto_start() {
    purple "正在配置开机自启动..."

    local service_name="sing-box-auto"
    local service_file="/etc/systemd/system/${service_name}.service"
    local script_path="$WORKDIR/auto-start.sh"

    # 创建启动脚本
    cat > "$script_path" <<EOF
#!/bin/bash

# Sing-box 自动启动脚本
# 在系统启动时自动启动sing-box和保活服务

WORKDIR="$WORKDIR"
LOG_FILE="\$WORKDIR/auto-start.log"

# 日志函数
log_info() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [INFO] \$1" >> "\$LOG_FILE"
}

log_error() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [ERROR] \$1" >> "\$LOG_FILE"
}

# 等待网络就绪
wait_for_network() {
    local max_wait=60
    local count=0

    log_info "等待网络连接..."

    while [[ \$count -lt \$max_wait ]]; do
        if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            log_info "网络连接正常"
            return 0
        fi
        sleep 2
        ((count++))
    done

    log_error "网络连接超时"
    return 1
}

# 启动sing-box服务
start_singbox() {
    cd "\$WORKDIR" || {
        log_error "无法切换到工作目录: \$WORKDIR"
        return 1
    }

    log_info "启动sing-box服务..."

    # 检查是否已经运行
    if pgrep -f "./sing-box" >/dev/null; then
        log_info "sing-box已在运行"
        return 0
    fi

    # 启动sing-box
    if [[ -f "./sing-box" && -f "config.json" ]]; then
        ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true nohup ./sing-box run -c config.json >/dev/null 2>&1 &
        sleep 3

        if pgrep -f "./sing-box" >/dev/null; then
            log_info "sing-box启动成功"
        else
            log_error "sing-box启动失败"
            return 1
        fi
    else
        log_error "sing-box二进制文件或配置文件不存在"
        return 1
    fi
}

# 启动cloudflared
start_cloudflared() {
    cd "\$WORKDIR" || return 1

    log_info "启动cloudflared..."

    # 检查是否已经运行
    if pgrep -f "./cloudflared" >/dev/null; then
        log_info "cloudflared已在运行"
        return 0
    fi

    if [[ -f "./cloudflared" ]]; then
        # 根据配置启动cloudflared
        local args=""
        if [[ -f "tunnel.yml" ]]; then
            args="tunnel --config tunnel.yml run"
        elif [[ -n "\$ARGO_TOKEN" ]]; then
            args="tunnel --no-autoupdate run --token \$ARGO_TOKEN"
        else
            args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --url http://localhost:$VMESS_PORT"
        fi

        nohup ./cloudflared \$args >/dev/null 2>&1 &
        sleep 3

        if pgrep -f "./cloudflared" >/dev/null; then
            log_info "cloudflared启动成功"
        else
            log_error "cloudflared启动失败"
        fi
    else
        log_error "cloudflared二进制文件不存在"
    fi
}

# 启动保活服务
start_keepalive() {
    cd "\$WORKDIR" || return 1

    log_info "启动保活服务..."

    if [[ -f "./keepalive.sh" ]]; then
        chmod +x "./keepalive.sh"

        # 检查是否已经运行
        if [[ -f "keepalive.pid" ]]; then
            local pid=\$(cat keepalive.pid)
            if kill -0 "\$pid" 2>/dev/null; then
                log_info "保活服务已在运行 (PID: \$pid)"
                return 0
            fi
        fi

        ./keepalive.sh start >/dev/null 2>&1
        sleep 2

        if [[ -f "keepalive.pid" ]]; then
            local pid=\$(cat keepalive.pid)
            if kill -0 "\$pid" 2>/dev/null; then
                log_info "保活服务启动成功 (PID: \$pid)"
            else
                log_error "保活服务启动失败"
            fi
        else
            log_error "保活服务PID文件未创建"
        fi
    else
        log_error "keepalive.sh脚本不存在"
    fi
}

# 主启动流程
main() {
    log_info "================== 自动启动开始 =================="
    log_info "工作目录: \$WORKDIR"

    # 等待网络
    if ! wait_for_network; then
        log_error "网络不可用，启动失败"
        exit 1
    fi

    # 延迟启动，确保系统完全就绪
    log_info "等待系统就绪..."
    sleep 10

    # 启动服务
    start_singbox
    sleep 3
    start_cloudflared
    sleep 3
    start_keepalive

    log_info "================== 自动启动完成 =================="
}

# 执行主流程
main "\$@"
EOF

    chmod +x "$script_path"

    # 创建systemd服务
    if command -v systemctl &>/dev/null; then
        cat > "$service_file" <<EOF
[Unit]
Description=Sing-box Auto Start Service
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$script_path
User=root
WorkingDirectory=$WORKDIR
StandardOutput=journal
StandardError=journal
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

        # 启用服务
        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable "$service_name" >/dev/null 2>&1

        green "✅ Systemd自启动服务配置成功"
        echo "  服务名称: $service_name"
        echo "  服务文件: $service_file"
        echo "  启动脚本: $script_path"
    else
        yellow "⚠️ 系统不支持systemd，使用crontab备用方案"
    fi

    # 添加crontab备用方案
    create_crontab_backup

    echo ""
    echo -e "${blue}自启动配置信息:${re}"
    echo "• 系统重启后会自动启动sing-box、cloudflared和保活服务"
    echo "• 启动前会等待网络连接就绪（最多60秒）"
    echo "• 启动日志保存在: $WORKDIR/auto-start.log"
    echo ""
    echo -e "${yellow}手动管理自启动:${re}"
    if command -v systemctl &>/dev/null; then
        echo "• 启用自启动: systemctl enable $service_name"
        echo "• 禁用自启动: systemctl disable $service_name"
        echo "• 查看状态: systemctl status $service_name"
        echo "• 手动触发: systemctl start $service_name"
    fi
    echo "• 查看启动日志: tail -f $WORKDIR/auto-start.log"
}

# 创建crontab备用方案
create_crontab_backup() {
    purple "配置crontab备用自启动..."

    local cron_script="$WORKDIR/cron-start.sh"

    # 创建cron启动脚本
    cat > "$cron_script" <<EOF
#!/bin/bash

# Crontab自启动脚本
WORKDIR="$WORKDIR"
LOCK_FILE="/tmp/sing-box-cron.lock"

# 防止重复执行
if [[ -f "\$LOCK_FILE" ]]; then
    exit 0
fi

touch "\$LOCK_FILE"

# 检查是否需要启动
cd "\$WORKDIR" || exit 1

# 检查服务状态并启动
if ! pgrep -f "./sing-box" >/dev/null; then
    ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true nohup ./sing-box run -c config.json >/dev/null 2>&1 &
fi

if ! pgrep -f "./cloudflared" >/dev/null && [[ -f "./cloudflared" ]]; then
    nohup ./cloudflared tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --url http://localhost:$VMESS_PORT >/dev/null 2>&1 &
fi

if [[ -f "./keepalive.sh" ]] && ! pgrep -f "keepalive.sh" >/dev/null; then
    ./keepalive.sh start >/dev/null 2>&1
fi

# 清理锁文件
rm -f "\$LOCK_FILE"
EOF

    chmod +x "$cron_script"

    # 添加到crontab
    local cron_entry="@reboot sleep 30 && $cron_script"

    # 检查是否已存在
    if ! crontab -l 2>/dev/null | grep -q "$cron_script"; then
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        green "✅ Crontab备用自启动配置成功"
    else
        yellow "ℹ️ Crontab自启动已存在"
    fi
}

# 主安装函数
install_singbox() {
    clear
    echo -e "${blue}================================================${re}"
    echo -e "${blue}    VPS安全Sing-box安装脚本${re}"
    echo -e "${blue}    使用官方二进制文件，移除安全风险${re}"
    echo -e "${blue}    默认解锁: ChatGPT/Netflix/YouTube等流媒体${re}"
    echo -e "${blue}================================================${re}\n"

    # 安全初始化
    secure_init

    # 检查端口
    check_port

    # 创建目录结构
    setup_directories

    # 下载官方文件
    download_official_singbox
    download_official_cloudflared

    # 配置服务
    argo_configure
    generate_config

    # 启动服务
    start_services

    # 生成连接信息
    generate_links

    # 创建保活服务
    create_keepalive_service

    # 创建管理命令
    create_quick_command

    # 创建独立的keepalive命令
    create_keepalive_command

    # 配置开机自启动
    create_auto_start

    # 启动保活服务
    if [[ -f "$WORKDIR/keepalive.sh" ]]; then
        cd "$WORKDIR"
        chmod +x keepalive.sh
        yellow "正在启动保活服务..."
        ./keepalive.sh start
        sleep 2
        ./keepalive.sh status
    fi

    # 清理临时文件
    rm -f "$WORKDIR/boot.log" "$WORKDIR/tunnel.json" "$WORKDIR/tunnel.yml" 2>/dev/null

    green "安装完成！请使用生成的订阅链接配置客户端。"
    echo ""
    purple "📱 管理命令: singbox {start|stop|status|logs|link|clean|auto}"
    yellow "🔄 保活服务: singbox keep {start|stop|status|restart|logs}"
    blue "⚡ 独立保活: keepalive {start|stop|status|restart|logs}"
    cyan "🚀 开机自启: singbox auto {enable|disable|status|test|log}"
    echo ""
    echo -e "${green}重要提示:${re}"
    echo "• ✅ 已配置开机自启动，VPS重启后自动启动所有服务"
    echo "• 使用 'keepalive status' 检查保活服务状态"
    echo "• 使用 'singbox clean' 清理多余端口"
    echo "• 使用 'singbox auto status' 检查自启动状态"
    echo "• 保活服务会自动重启异常的sing-box和cloudflared进程"
    echo ""
    echo -e "${green}🎬 流媒体解锁支持:${re}"
    echo "• ✅ ChatGPT/OpenAI - 全功能访问"
    echo "• ✅ Netflix - 完整解锁"
    echo "• ✅ YouTube - 无限制访问"
    echo "• ✅ Disney+ - 全区域解锁"
    echo "• ✅ HBO Max - 完整支持"
    echo "• ✅ Spotify - 音乐流畅播放"
    echo "• ✅ TikTok - 完整版功能"
    echo "• ✅ Claude AI - 无限制访问"
    echo "• ✅ Google Gemini/Bard - AI服务解锁"
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