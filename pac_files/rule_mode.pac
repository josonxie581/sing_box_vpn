// 规则模式 PAC 文件 - 可自定义修改
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
    
    // 国外重要网站走代理
    var proxyDomains = [
        ".google.com", ".youtube.com", ".facebook.com", ".twitter.com", 
        ".github.com", ".openai.com", ".anthropic.com", ".wikipedia.org"
    ];
    
    for (var i = 0; i < proxyDomains.length; i++) {
        if (dnsDomainIs(host, proxyDomains[i])) {
            return "PROXY {{PROXY_HOST}}:{{PROXY_PORT}}; SOCKS5 {{PROXY_HOST}}:{{PROXY_PORT}}; DIRECT";
        }
    }
    
    // 国内网站直连
    var directDomains = [
        ".cn", ".baidu.com", ".qq.com", ".taobao.com", ".bilibili.com"
    ];
    
    for (var i = 0; i < directDomains.length; i++) {
        if (dnsDomainIs(host, directDomains[i])) {
            return "DIRECT";
        }
    }
    
    // 其他网站走代理
    return "PROXY {{PROXY_HOST}}:{{PROXY_PORT}}; SOCKS5 {{PROXY_HOST}}:{{PROXY_PORT}}; DIRECT";
}
