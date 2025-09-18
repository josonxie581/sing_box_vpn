#!/bin/bash
# VPS Monitor Script Creator

# Color definitions
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
re="\033[0m"

# Output functions
green() { echo -e "\e[1;32m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }

echo "Creating VPS monitoring tool..."

# Detect permissions and path
if [[ $EUID -eq 0 ]]; then
    INSTALL_PATH="/usr/local/bin/vps-monitor"
    purple "Installing to system directory with root privileges"
else
    mkdir -p "$HOME/bin"
    INSTALL_PATH="$HOME/bin/vps-monitor"
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc 2>/dev/null || true
    yellow "Installing to user directory with regular user privileges"
fi

# Create monitoring script
cat > "$INSTALL_PATH" << 'MONITOR_SCRIPT'
#!/bin/bash
# VPS Monitor Script

# Color definitions
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
blue="\e[1;34m"
purple="\e[1;35m"
re="\033[0m"

# Get system information
get_system_info() {
    echo -e "${blue}========== System Information ==========${re}"
    echo -e "${green}Hostname:${re} $(hostname)"
    echo -e "${green}System:${re} $(uname -s) $(uname -r)"
    echo -e "${green}Architecture:${re} $(uname -m)"
    echo -e "${green}Uptime:${re} $(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}')"
    echo -e "${green}Current Time:${re} $(date)"
    echo
}

# Get resource usage
get_resource_usage() {
    echo -e "${blue}========== Resource Usage ==========${re}"

    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'u' -f1 2>/dev/null || echo "N/A")
    echo -e "${green}CPU Usage:${re} ${cpu_usage}%"

    # Memory usage
    local mem_info=$(free -h | grep "Mem:" 2>/dev/null)
    if [[ -n "$mem_info" ]]; then
        local mem_total=$(echo $mem_info | awk '{print $2}')
        local mem_used=$(echo $mem_info | awk '{print $3}')
        local mem_percent=$(free | grep "Mem:" | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null || echo "N/A")
        echo -e "${green}Memory Usage:${re} ${mem_used}/${mem_total} (${mem_percent}%)"
    else
        echo -e "${green}Memory Usage:${re} Unable to retrieve"
    fi

    # Disk usage
    echo -e "${green}Disk Usage:${re}"
    df -h 2>/dev/null | grep -E '^/dev/' | awk '{printf "  %s: %s/%s (%s)\n", $6, $3, $2, $5}' || echo "  Unable to retrieve disk info"

    # Network connections
    local tcp_connections=$(ss -t state connected 2>/dev/null | wc -l || netstat -tn 2>/dev/null | grep ESTABLISHED | wc -l || echo "0")
    echo -e "${green}TCP Connections:${re} $tcp_connections"

    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' 2>/dev/null || echo " Unable to retrieve")
    echo -e "${green}Load Average:${re}$load_avg"
    echo
}

# Check network status
get_network_status() {
    echo -e "${blue}========== Network Status ==========${re}"

    # Get public IP
    local public_ip=$(curl -s --max-time 5 "http://ipv4.icanhazip.com" 2>/dev/null || echo "Failed to retrieve")
    echo -e "${green}Public IP:${re} $public_ip"

    # Network latency test
    echo -e "${green}Network Latency Test:${re}"
    for host in "8.8.8.8" "1.1.1.1" "baidu.com"; do
        local ping_result=$(ping -c 1 -W 3 $host 2>/dev/null | grep "time=" | awk -F'time=' '{print $2}' | awk '{print $1}')
        if [[ -n "$ping_result" ]]; then
            echo -e "  $host: ${ping_result}ms"
        else
            echo -e "  $host: ${red}Timeout${re}"
        fi
    done
    echo
}

# Check service status
get_service_status() {
    echo -e "${blue}========== Service Status ==========${re}"

    # Check sing-box service
    if pgrep -f "sing-box" > /dev/null 2>&1; then
        echo -e "${green}✅ sing-box: Running${re}"
        local sing_pid=$(pgrep -f "sing-box" 2>/dev/null)
        if [[ -n "$sing_pid" ]]; then
            echo -e "   PID: $sing_pid"
            # Check listening ports
            local listening_ports=$(ss -tulpn 2>/dev/null | grep "$sing_pid" | awk '{print $5}' | cut -d':' -f2 | sort -n | xargs || netstat -tulpn 2>/dev/null | grep "$sing_pid" | awk '{print $4}' | cut -d':' -f2 | sort -n | xargs || echo "")
            if [[ -n "$listening_ports" ]]; then
                echo -e "   Listening Ports: $listening_ports"
            fi
        fi
    else
        echo -e "${red}❌ sing-box: Stopped${re}"
    fi

    # Check cloudflared service
    if pgrep -f "cloudflared" > /dev/null 2>&1; then
        echo -e "${green}✅ cloudflared: Running${re}"
        local cf_pid=$(pgrep -f "cloudflared" 2>/dev/null)
        if [[ -n "$cf_pid" ]]; then
            echo -e "   PID: $cf_pid"
        fi
    else
        echo -e "${yellow}⚠️  cloudflared: Stopped${re}"
    fi

    # Check firewall status
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status 2>/dev/null | grep "Status:" | awk '{print $2}' || echo "unknown")
        echo -e "${green}Firewall(ufw):${re} $ufw_status"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        local firewall_status=$(systemctl is-active firewalld 2>/dev/null || echo "inactive")
        echo -e "${green}Firewall(firewalld):${re} $firewall_status"
    fi
    echo
}

# Check system security
get_security_info() {
    echo -e "${blue}========== Security Check ==========${re}"

    # Check recent logins
    echo -e "${green}Recent Logins:${re}"
    last -n 5 2>/dev/null | head -5 || echo "Unable to retrieve login records"

    # Check failed login attempts
    local failed_logins=$(lastb 2>/dev/null | wc -l || echo "0")
    if [[ $failed_logins -gt 0 ]]; then
        echo -e "${yellow}Failed Login Attempts:${re} $failed_logins times"
    else
        echo -e "${green}Failed Login Attempts:${re} 0 times"
    fi

    # Check available updates
    if command -v apt >/dev/null 2>&1; then
        local updates=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "0")
        echo -e "${green}Available Updates:${re} $updates packages"
    elif command -v yum >/dev/null 2>&1; then
        local updates=$(yum check-update 2>/dev/null | grep -c "updates" || echo "0")
        echo -e "${green}Available Updates:${re} $updates packages"
    fi
    echo
}

# Real-time monitoring mode
monitor_realtime() {
    while true; do
        clear
        echo -e "${purple}VPS Real-time Monitor - Press Ctrl+C to exit${re}"
        echo -e "${purple}Update Time: $(date)${re}"
        echo
        get_resource_usage
        get_service_status
        sleep 5
    done
}

# Quick status
quick_status() {
    echo -e "${blue}========== Quick Status Check ==========${re}"

    # CPU and memory
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'u' -f1 2>/dev/null || echo "N/A")
    local mem_percent=$(free | grep "Mem:" | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null || echo "N/A")
    echo -e "${green}CPU: ${cpu_usage}% | Memory: ${mem_percent}%${re}"

    # Service status
    local sing_status=$(pgrep -f "sing-box" > /dev/null 2>&1 && echo "Running" || echo "Stopped")
    local cf_status=$(pgrep -f "cloudflared" > /dev/null 2>&1 && echo "Running" || echo "Stopped")
    echo -e "${green}sing-box: $sing_status | cloudflared: $cf_status${re}"

    # Load and uptime
    local load_1min=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs 2>/dev/null || echo "N/A")
    local uptime_info=$(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}' 2>/dev/null || echo "unknown")
    echo -e "${green}Load: $load_1min | Uptime: $uptime_info${re}"
}

# Show help
show_help() {
    echo "VPS Monitor Tool Usage:"
    echo "  vps-monitor            - Full system status check"
    echo "  vps-monitor quick      - Quick status check"
    echo "  vps-monitor realtime   - Real-time monitoring mode"
    echo "  vps-monitor system     - System information"
    echo "  vps-monitor network    - Network status"
    echo "  vps-monitor service    - Service status"
    echo "  vps-monitor security   - Security check"
    echo "  vps-monitor help       - Show help"
}

# Main function
main() {
    case "${1:-full}" in
        "quick"|"q")
            quick_status
            ;;
        "realtime"|"rt"|"real")
            monitor_realtime
            ;;
        "system"|"sys")
            get_system_info
            ;;
        "network"|"net")
            get_network_status
            ;;
        "service"|"svc")
            get_service_status
            ;;
        "security"|"sec")
            get_security_info
            ;;
        "help"|"h"|"-h"|"--help")
            show_help
            ;;
        "full"|*)
            get_system_info
            get_resource_usage
            get_network_status
            get_service_status
            get_security_info
            ;;
    esac
}

main "$@"
MONITOR_SCRIPT

# Set execute permissions
chmod +x "$INSTALL_PATH"

green "✅ VPS monitoring script created successfully!"
echo "Installation path: $INSTALL_PATH"
echo
echo "You can now use the following commands:"
echo "  vps-monitor         - Full system status check"
echo "  vps-monitor quick   - Quick status check"
echo "  vps-monitor realtime - Real-time monitoring mode"
echo "  vps-monitor help    - Show help"
echo
if [[ $EUID -ne 0 ]]; then
    echo "If command is not available, run: source ~/.bashrc"
fi