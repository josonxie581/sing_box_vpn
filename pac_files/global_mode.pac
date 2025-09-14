// 全局模式 PAC 文件 - 可自定义修改
// 使用 {{PROXY_PORT}} 作为端口占位符，系统会自动替换
function FindProxyForURL(url, host) {
    // 本地地址直连
    if (isPlainHostName(host) ||
        isInNet(host, "127.0.0.0", "255.0.0.0") ||
        isInNet(host, "10.0.0.0", "255.0.0.0") ||
        isInNet(host, "172.16.0.0", "255.240.0.0") ||
        isInNet(host, "192.168.0.0", "255.255.0.0") ||
        isInNet(host, "169.254.0.0", "255.255.0.0")) {
        return "DIRECT";
    }
    
    // 全局模式：所有外网流量走代理
    return "PROXY {{PROXY_HOST}}:{{PROXY_PORT}}; SOCKS5 {{PROXY_HOST}}:{{PROXY_PORT}}; DIRECT";
}
