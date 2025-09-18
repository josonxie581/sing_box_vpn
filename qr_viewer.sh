#!/bin/bash

# ===========================================
# 订阅链接二维码查看器
# 支持多种二维码生成方式
# ===========================================

# 颜色定义
green="\e[1;32m"
yellow="\e[1;33m"
blue="\e[1;34m"
purple="\e[1;35m"
red="\e[1;91m"
re="\033[0m"

# 输出函数
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
blue() { echo -e "\e[1;34m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
red() { echo -e "\e[1;91m$1\033[0m"; }

# 获取用户信息
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')
HOSTNAME=$(hostname)

# 检测运行环境
detect_environment() {
    if command -v devil &>/dev/null; then
        echo "serv00"
    else
        echo "vps"
    fi
}

# 根据环境设置路径
ENV_TYPE=$(detect_environment)

if [[ "$ENV_TYPE" == "serv00" ]]; then
    # 检测域名
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
    # VPS环境
    CURRENT_DOMAIN="localhost"
    WORKDIR="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/logs"
    FILE_PATH="${WORKDIR}"
fi

# 生成ASCII二维码的Python脚本
create_qr_generator() {
    cat > "/tmp/qr_gen.py" <<'EOF'
#!/usr/bin/env python3
import sys

def simple_qr_ascii(text):
    """简单的ASCII二维码替代"""
    print("=" * 60)
    print("📱 扫描此二维码或复制链接到客户端:")
    print("=" * 60)

    # 尝试导入qrcode库
    try:
        import qrcode
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=2,
            border=2,
        )
        qr.add_data(text)
        qr.make(fit=True)

        # 生成ASCII二维码
        matrix = qr.get_matrix()
        for row in matrix:
            line = ""
            for col in row:
                line += "██" if col else "  "
            print(line)

        print("=" * 60)
        print("链接:", text)
        print("=" * 60)

    except ImportError:
        # 备用显示方式
        print("🔗 订阅链接:")
        print(text)
        print("=" * 60)
        print("📋 请复制上述链接到以下客户端:")
        print("• V2rayN/V2rayNG")
        print("• Clash/ClashX")
        print("• Shadowrocket")
        print("• Sing-box")
        print("• Nekoray")
        print("=" * 60)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        simple_qr_ascii(sys.argv[1])
    else:
        print("用法: python3 qr_gen.py <订阅链接>")
EOF
    chmod +x "/tmp/qr_gen.py"
}

# 方法1: 使用系统qrencode命令
show_qr_qrencode() {
    local url="$1"

    if command -v qrencode &>/dev/null; then
        blue "📱 使用qrencode生成二维码:"
        echo
        qrencode -m 2 -t UTF8 "$url"
        echo
        green "✅ 二维码生成成功"
        return 0
    else
        return 1
    fi
}

# 方法2: 使用Python qrcode库
show_qr_python() {
    local url="$1"

    if command -v python3 &>/dev/null; then
        create_qr_generator
        blue "📱 使用Python生成二维码:"
        echo
        python3 "/tmp/qr_gen.py" "$url"
        rm -f "/tmp/qr_gen.py"
        return 0
    else
        return 1
    fi
}

# 方法3: 在线二维码服务
show_qr_online() {
    local url="$1"
    local encoded_url=$(echo "$url" | sed 's/ /%20/g' | sed 's/&/%26/g' | sed 's/#/%23/g')

    blue "🌐 在线二维码服务:"
    echo
    echo "方式1 - 复制以下链接到浏览器查看:"
    echo "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${encoded_url}"
    echo
    echo "方式2 - 使用curl下载二维码图片:"
    echo "curl -o qrcode.png \"https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${encoded_url}\""
    echo
}

# 方法4: 使用curl+图片转ASCII
show_qr_curl_ascii() {
    local url="$1"

    if command -v curl &>/dev/null; then
        blue "🔄 尝试生成在线ASCII二维码..."

        # 使用在线ASCII二维码服务
        local encoded_url=$(echo "$url" | sed 's/ /%20/g' | sed 's/&/%26/g' | sed 's/#/%23/g')
        local ascii_qr=$(curl -s --max-time 10 "https://qrenco.de/${encoded_url}" 2>/dev/null)

        if [[ -n "$ascii_qr" && "$ascii_qr" != *"error"* ]]; then
            echo
            echo "$ascii_qr"
            echo
            green "✅ 在线ASCII二维码生成成功"
            return 0
        fi
    fi
    return 1
}

# 显示订阅链接信息
show_subscription_info() {
    local url="$1"

    purple "📋 订阅信息:"
    echo "链接: $url"
    echo
    echo "🔧 支持的客户端:"
    echo "• V2rayN (Windows)"
    echo "• V2rayNG (Android)"
    echo "• ClashX (macOS)"
    echo "• Clash for Windows"
    echo "• Shadowrocket (iOS)"
    echo "• Sing-box"
    echo "• Nekoray"
    echo "• Loon (iOS)"
    echo "• Quantumult X (iOS)"
    echo
    echo "📱 使用方法:"
    echo "1. 复制订阅链接"
    echo "2. 在客户端添加订阅"
    echo "3. 更新订阅获取节点"
    echo
}

# VPS环境显示节点信息
show_vps_nodes() {
    blue "📱 VPS环境节点信息:"
    echo

    if [[ -f "${FILE_PATH}/list.txt" ]]; then
        green "✅ 节点配置文件存在"
        echo
        purple "📋 节点配置:"
        cat "${FILE_PATH}/list.txt"
        echo

        # 生成VMESS节点二维码
        local vmess_line=$(grep "vmess://" "${FILE_PATH}/list.txt" | head -1)
        if [[ -n "$vmess_line" ]]; then
            blue "📱 VMESS节点二维码:"
            echo

            # 尝试生成二维码
            if show_qr_qrencode "$vmess_line"; then
                echo
            elif show_qr_curl_ascii "$vmess_line"; then
                echo
            elif show_qr_python "$vmess_line"; then
                echo
            else
                yellow "⚠️  本地二维码生成失败，使用在线服务"
                show_qr_online "$vmess_line"
            fi
        fi

        echo
        purple "📝 使用说明:"
        echo "1. 复制上述节点配置到支持的客户端"
        echo "2. 或扫描VMESS节点二维码"
        echo "3. 客户端会自动识别节点信息"
    else
        red "❌ 节点配置文件不存在: ${FILE_PATH}/list.txt"
        echo
        yellow "请先运行安装脚本生成节点配置"
    fi
}

# 主函数
main() {
    clear
    echo -e "${blue}============================================${re}"
    echo -e "${blue}        订阅链接二维码查看器${re}"
    echo -e "${blue}============================================${re}"
    echo

    if [[ "$ENV_TYPE" == "serv00" ]]; then
        # Serv00/CT8环境
        # 检查订阅文件是否存在
        if [[ ! -f "${FILE_PATH}/v2.log" ]]; then
            red "❌ 订阅文件不存在: ${FILE_PATH}/v2.log"
            echo
            yellow "请先运行安装脚本生成订阅文件"
            exit 1
        fi

        # 构建订阅链接
        local sub_url="https://${USERNAME}.${CURRENT_DOMAIN}/v2.log"

        green "✅ 发现订阅文件"
        echo

        # 显示订阅信息
        show_subscription_info "$sub_url"

        # 尝试不同的二维码生成方法
        blue "🔍 正在尝试生成二维码..."
        echo

        # 方法1: qrencode
        if show_qr_qrencode "$sub_url"; then
            echo
            show_subscription_info "$sub_url"
            exit 0
        fi

        # 方法2: 在线ASCII二维码
        if show_qr_curl_ascii "$sub_url"; then
            echo
            show_subscription_info "$sub_url"
            exit 0
        fi

        # 方法3: Python
        if show_qr_python "$sub_url"; then
            exit 0
        fi

        # 方法4: 在线服务
        yellow "⚠️  本地二维码生成失败，使用在线服务"
        show_qr_online "$sub_url"
        echo
        show_subscription_info "$sub_url"
    else
        # VPS环境
        yellow "🖥️  检测到VPS环境，显示节点配置信息"
        echo
        show_vps_nodes
    fi
}

# 命令行参数处理
case "${1:-main}" in
    -h|--help|help)
        echo "用法: $0 [选项]"
        echo "选项:"
        echo "  无参数    - 显示订阅二维码"
        echo "  link      - 仅显示订阅链接"
        echo "  info      - 显示详细信息"
        echo "  -h        - 显示帮助"
        ;;
    link)
        if [[ "$ENV_TYPE" == "serv00" ]]; then
            if [[ -f "${FILE_PATH}/v2.log" ]]; then
                echo "https://${USERNAME}.${CURRENT_DOMAIN}/v2.log"
            else
                red "订阅文件不存在"
                exit 1
            fi
        else
            # VPS环境
            if [[ -f "${FILE_PATH}/list.txt" ]]; then
                echo "VPS环境节点配置:"
                cat "${FILE_PATH}/list.txt"
            else
                red "节点配置文件不存在"
                exit 1
            fi
        fi
        ;;
    info)
        if [[ "$ENV_TYPE" == "serv00" ]]; then
            if [[ -f "${FILE_PATH}/v2.log" ]]; then
                local sub_url="https://${USERNAME}.${CURRENT_DOMAIN}/v2.log"
                show_subscription_info "$sub_url"
            else
                red "订阅文件不存在"
                exit 1
            fi
        else
            # VPS环境
            if [[ -f "${FILE_PATH}/list.txt" ]]; then
                purple "📋 VPS节点信息:"
                cat "${FILE_PATH}/list.txt"
                echo
                purple "📝 使用说明:"
                echo "1. 复制上述节点配置到支持的客户端"
                echo "2. 客户端会自动识别节点信息"
            else
                red "节点配置文件不存在"
                exit 1
            fi
        fi
        ;;
    *)
        main
        ;;
esac