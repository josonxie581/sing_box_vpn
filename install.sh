#!/bin/bash

# ===========================================
# 安全版Sing-box一键安装器
# 自动下载并运行安全版本脚本
# ===========================================

set -e

# 颜色定义
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
blue="\e[1;34m"
re="\033[0m"

# 输出函数
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
blue() { echo -e "\e[1;34m$1\033[0m"; }

# 脚本信息
SCRIPT_NAME="secure_ss4.sh"
QR_SCRIPT_NAME="qr_viewer.sh"
GITHUB_USER="josonxie581"
REPO_NAME="sing_box_vpn"
BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/main"

# 备用下载地址（可以是你的VPS或其他服务器）
BACKUP_URL=""  # 暂不使用

# 检查系统环境
check_system() {
    # 检查是否为root用户（给出警告但不强制退出）
    if [[ $EUID -ne 0 ]]; then
        yellow "警告：检测到非root用户运行"
        echo "某些功能可能需要sudo权限"
        echo "如果遇到权限问题，请使用: sudo bash $0"
        echo ""
        read -p "是否继续？(Y/n): " continue_choice
        if [[ "$continue_choice" =~ ^[Nn]$ ]]; then
            yellow "用户选择退出"
            exit 0
        fi
    fi

    # 检查网络工具
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        red "错误：系统缺少curl或wget工具"
        if [[ $EUID -eq 0 ]]; then
            echo "正在尝试安装curl..."
            if command -v apt &>/dev/null; then
                apt update && apt install -y curl wget
            elif command -v yum &>/dev/null; then
                yum install -y curl wget
            elif command -v apk &>/dev/null; then
                apk add curl wget
            else
                echo "请手动安装: curl wget"
                exit 1
            fi
        else
            echo "请先安装: sudo apt update && sudo apt install curl wget"
            exit 1
        fi
    fi
}

# 显示欢迎信息
show_welcome() {
    clear
    echo -e "${blue}============================================${re}"
    echo -e "${blue}    安全版Sing-box一键安装器${re}"
    echo -e "${blue}    使用官方二进制，移除安全风险${re}"
    echo -e "${blue}============================================${re}"
    echo
    echo -e "${green}脚本特点:${re}"
    echo "• ✅ 使用官方GitHub仓库下载二进制文件"
    echo "• ✅ SHA256完整性验证"
    echo "• ✅ 移除所有第三方依赖和潜在后门"
    echo "• ✅ 支持VLESS、Hysteria2、TUIC协议"
    echo "• ✅ 自动生成订阅链接和二维码"
    echo "• ✅ 提供便捷的管理命令"
    echo
}

# 下载脚本
download_script() {
    local script_name="$1"
    local download_url="$2"

    purple "正在下载 $script_name..."

    # 尝试主要下载地址
    if command -v curl &>/dev/null; then
        if curl -fsSL "$download_url" -o "/tmp/$script_name" 2>/dev/null; then
            green "✅ 从主地址下载成功"
            return 0
        fi
    elif command -v wget &>/dev/null; then
        if wget -qO "/tmp/$script_name" "$download_url" 2>/dev/null; then
            green "✅ 从主地址下载成功"
            return 0
        fi
    fi

    # 尝试备用下载地址
    yellow "⚠️  主地址失败，尝试备用地址..."
    if [[ -n "$BACKUP_URL" ]]; then
        if command -v curl &>/dev/null; then
            if curl -fsSL "${BACKUP_URL}/$script_name" -o "/tmp/$script_name" 2>/dev/null; then
                green "✅ 从备用地址下载成功"
                return 0
            fi
        elif command -v wget &>/dev/null; then
            if wget -qO "/tmp/$script_name" "${BACKUP_URL}/$script_name" 2>/dev/null; then
                green "✅ 从备用地址下载成功"
                return 0
            fi
        fi
    fi

    red "❌ 下载失败"
    return 1
}

# 验证脚本
verify_script() {
    local script_path="$1"

    # 检查文件是否存在
    if [[ ! -f "$script_path" ]]; then
        red "错误：脚本文件不存在"
        return 1
    fi

    # 检查文件大小
    local file_size=$(stat -c%s "$script_path" 2>/dev/null || echo 0)
    if [[ $file_size -lt 1000 ]]; then
        red "错误：脚本文件异常（文件过小）"
        return 1
    fi

    # 检查脚本头
    if ! head -1 "$script_path" | grep -q "#!/bin/bash"; then
        red "错误：不是有效的bash脚本"
        return 1
    fi

    # 基本安全检查通过

    green "✅ 脚本验证通过"
    return 0
}

# 主安装函数
install_main() {
    # 下载主脚本
    if ! download_script "$SCRIPT_NAME" "${BASE_URL}/${SCRIPT_NAME}"; then
        red "主脚本下载失败，安装终止"
        exit 1
    fi

    # 验证主脚本
    if ! verify_script "/tmp/$SCRIPT_NAME"; then
        red "主脚本验证失败，安装终止"
        exit 1
    fi

    # 下载二维码查看器（可选）
    if download_script "$QR_SCRIPT_NAME" "${BASE_URL}/${QR_SCRIPT_NAME}"; then
        green "✅ 二维码查看器下载成功"
        chmod +x "/tmp/$QR_SCRIPT_NAME"
        cp "/tmp/$QR_SCRIPT_NAME" "/usr/local/bin/qr-viewer"
    else
        yellow "⚠️  二维码查看器下载失败（不影响主功能）"
    fi

    # 设置权限
    chmod +x "/tmp/$SCRIPT_NAME"

    # 执行主脚本
    purple "开始执行安装脚本..."
    echo
    bash "/tmp/$SCRIPT_NAME"

    # 下载并运行VPS监控脚本创建器
    purple "正在安装VPS监控工具..."
    if download_script "create_monitor.sh" "${BASE_URL}/create_monitor.sh"; then
        chmod +x "/tmp/create_monitor.sh"
        if [[ $EUID -eq 0 ]]; then
            bash "/tmp/create_monitor.sh"
            green "✅ VPS监控工具安装完成"
        else
            echo "需要sudo权限安装监控工具..."
            if sudo bash "/tmp/create_monitor.sh" 2>/dev/null; then
                green "✅ VPS监控工具安装完成"
            else
                yellow "⚠️  权限不足，将使用内置版本"
                create_monitor_script_fallback
            fi
        fi
    else
        yellow "⚠️  VPS监控工具下载失败，将使用内置版本"
        create_monitor_script_fallback
    fi
}

# 回退监控脚本创建函数
create_monitor_script_fallback() {
    local monitor_script

    # 根据权限选择安装路径
    if [[ $EUID -eq 0 ]] || sudo -n true 2>/dev/null; then
        monitor_script="/usr/local/bin/vps-monitor"
    else
        # 非root用户，安装到用户目录
        mkdir -p "$HOME/bin"
        monitor_script="$HOME/bin/vps-monitor"
        export PATH="$HOME/bin:$PATH"
        echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc 2>/dev/null || true
        yellow "以非root权限安装到用户目录: $monitor_script"
    fi

    # 使用适当的方法创建脚本
    if [[ $EUID -eq 0 ]]; then
        # Root用户直接创建
        cat > "$monitor_script" <<'EOF'
#!/bin/bash
# VPS监控脚本 - 简化版本

# 颜色定义
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
blue="\e[1;34m"
re="\033[0m"

# 简要状态检查
quick_status() {
    echo -e "${blue}========== 快速状态检查 ==========${re}"
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'u' -f1 2>/dev/null || echo "N/A")
    local mem_percent=$(free | grep "Mem:" | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null || echo "N/A")
    echo -e "${green}CPU: ${cpu_usage}% | 内存: ${mem_percent}%${re}"
    local sing_status=$(pgrep -f "sing-box" > /dev/null && echo "运行" || echo "停止")
    local cf_status=$(pgrep -f "cloudflared" > /dev/null && echo "运行" || echo "停止")
    echo -e "${green}sing-box: $sing_status | cloudflared: $cf_status${re}"
    local load_1min=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)
    local uptime_info=$(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}')
    echo -e "${green}负载: $load_1min | 运行时间: $uptime_info${re}"
}

show_help() {
    echo "VPS 监控工具使用说明："
    echo "  vps-monitor quick   - 快速状态检查"
    echo "  vps-monitor help    - 显示帮助"
}

case "${1:-quick}" in
    "quick"|"q") quick_status ;;
    "help"|"h") show_help ;;
    *) quick_status ;;
esac
EOF
        chmod +x "$monitor_script"
    elif sudo -n true 2>/dev/null; then
        # 有sudo权限
        sudo tee "$monitor_script" > /dev/null <<'EOF'
#!/bin/bash
# VPS监控脚本 - 简化版本

red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
blue="\e[1;34m"
re="\033[0m"

quick_status() {
    echo -e "${blue}========== 快速状态检查 ==========${re}"
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'u' -f1 2>/dev/null || echo "N/A")
    local mem_percent=$(free | grep "Mem:" | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null || echo "N/A")
    echo -e "${green}CPU: ${cpu_usage}% | 内存: ${mem_percent}%${re}"
    local sing_status=$(pgrep -f "sing-box" > /dev/null && echo "运行" || echo "停止")
    echo -e "${green}sing-box: $sing_status${re}"
}

case "${1:-quick}" in
    *) quick_status ;;
esac
EOF
        sudo chmod +x "$monitor_script"
    else
        # 用户目录创建
        cat > "$monitor_script" <<'EOF'
#!/bin/bash
# VPS监控脚本 - 用户版本

red="\033[1;91m"
green="\e[1;32m"
blue="\e[1;34m"
re="\033[0m"

quick_status() {
    echo -e "${blue}========== 快速状态检查 ==========${re}"
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'u' -f1 2>/dev/null || echo "N/A")
    echo -e "${green}CPU: ${cpu_usage}%${re}"
    local sing_status=$(pgrep -f "sing-box" > /dev/null && echo "运行" || echo "停止")
    echo -e "${green}sing-box: $sing_status${re}"
}

case "${1:-quick}" in
    *) quick_status ;;
esac
EOF
        chmod +x "$monitor_script"
    fi

    green "✅ VPS监控脚本（简化版）已创建: $monitor_script"
}

# 显示使用说明
show_usage() {
    echo -e "${yellow}使用说明:${re}"
    echo "1. 安装完成后，使用以下命令管理："
    echo "   singbox start    - 启动服务"
    echo "   singbox stop     - 停止服务"
    echo "   singbox status   - 查看状态"
    echo "   singbox logs     - 查看日志"
    echo "   singbox qr       - 显示二维码"
    echo "   singbox link     - 显示订阅链接"
    echo
    echo "2. VPS系统监控："
    echo "   vps-monitor         - 完整系统状态检查"
    echo "   vps-monitor quick   - 快速状态检查"
    echo "   vps-monitor realtime - 实时监控模式"
    echo "   vps-monitor network - 网络状态检查"
    echo "   vps-monitor service - 服务状态检查"
    echo "   vps-monitor security - 安全状态检查"
    echo
    echo "3. 查看二维码："
    echo "   qr-viewer           - 显示订阅二维码"
    echo "   qr-viewer link      - 仅显示链接"
    echo "   qr-viewer info      - 显示详细信息"
    echo
    echo "4. 配置文件位置："
    echo "   配置: ~/domains/用户名.域名/logs/config.json"
    echo "   日志: ~/domains/用户名.域名/logs/sing-box.log"
    echo "   订阅: https://用户名.域名/v2.log"
    echo
}

# 清理临时文件
cleanup() {
    rm -f "/tmp/$SCRIPT_NAME" "/tmp/$QR_SCRIPT_NAME" 2>/dev/null
}

# 错误处理
handle_error() {
    red "安装过程中发生错误"
    cleanup
    exit 1
}

# 主程序
main() {
    # 设置错误处理
    trap handle_error ERR
    trap cleanup EXIT

    # 检查系统
    check_system

    # 显示欢迎信息
    show_welcome

    # 确认安装
    read -p "是否开始安装？(Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        yellow "用户取消安装"
        exit 0
    fi

    # 开始安装
    install_main

    # 显示使用说明
    echo
    show_usage

    green "🎉 安装完成！"
}

# 脚本入口
main "$@"