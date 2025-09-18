# 🛡️ 安全版Sing-box使用说明

## 🚀 一键安装

### 标准安装（推荐）
```bash
# 使用sudo获得最佳兼容性
sudo bash <(curl -fsSL https://raw.githubusercontent.com/josonxie581/sing_box_vpn/main/install.sh)

# 或普通用户运行（部分功能可能受限）
bash <(curl -fsSL https://raw.githubusercontent.com/josonxie581/sing_box_vpn/main/install.sh)
```

### 交互式安装
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/josonxie581/sing_box_vpn/main/interactive_install.sh)
```

### 🔥 新增功能
- ✅ **自动BBR优化**: 启用TCP BBR拥塞控制
- ✅ **VPS系统监控**: 实时监控系统状态
- ✅ **TUIC协议修复**: 自动修复境外访问问题
- ✅ **智能权限处理**: 支持root和普通用户
- ✅ **回退机制**: 网络问题时使用内置备份

## 🔧 管理命令

安装完成后，使用以下命令管理服务：

```bash
# 服务管理
singbox start      # 启动服务
singbox stop       # 停止服务
singbox status     # 查看状态
singbox logs       # 查看日志（最近50行）
singbox logx       # 持续监控日志（实时）

# 订阅管理
singbox qr         # 显示订阅二维码
singbox link       # 显示订阅链接

# 独立二维码查看器
qr-viewer          # 显示订阅二维码和详细信息
qr-viewer link     # 仅显示订阅链接
qr-viewer info     # 显示客户端兼容性信息

# 🆕 VPS系统监控
vps-monitor        # 完整系统状态检查
vps-monitor quick  # 快速状态检查
vps-monitor realtime # 实时监控模式（每5秒刷新）
vps-monitor network  # 网络状态检查
vps-monitor service  # 服务状态检查
vps-monitor security # 安全状态检查
vps-monitor help     # 显示帮助信息
```

### 📊 监控功能详细说明

**完整监控** (`vps-monitor`)：
- 💻 系统信息：主机名、系统版本、运行时间
- ⚡ 资源使用：CPU、内存、磁盘、网络连接数
- 🌐 网络状态：公网IP、延迟测试
- 🔧 服务状态：sing-box、cloudflared进程
- 🛡️ 安全检查：登录记录、系统更新

**实时监控** (`vps-monitor realtime`)：
- 🔄 每5秒自动刷新
- 📈 实时资源使用情况
- 🎯 适合故障排查和性能调优

## 📱 使用流程

### 1. **安装脚本**
```bash
# 推荐使用sudo
sudo bash <(curl -fsSL https://raw.githubusercontent.com/josonxie581/sing_box_vpn/main/install.sh)
```

### 2. **系统检查**
```bash
# 检查安装是否成功
vps-monitor quick

# 检查服务状态
singbox status
```

### 3. **获取订阅**
```bash
singbox qr        # 显示二维码
singbox link      # 显示链接/节点
```

### 4. **客户端配置**
- **Serv00/CT8环境**：扫描二维码或复制订阅链接
- **VPS环境**：手动复制节点配置到客户端
- 在客户端添加订阅或单个节点

### 5. **日常管理**
```bash
# 服务管理
singbox status    # 检查服务状态
singbox logs      # 查看运行日志（最近50行）
singbox logx      # 实时监控日志

# 系统监控
vps-monitor quick # 快速系统检查
vps-monitor       # 完整系统状态
```

## 🔧 故障排除

### ❌ 安装失败
```bash
# 检查系统环境
vps-monitor system

# 检查网络连接
vps-monitor network

# 手动安装监控工具
sudo bash <(curl -fsSL https://raw.githubusercontent.com/josonxie581/sing_box_vpn/main/create_monitor.sh)

# 重新运行安装（使用sudo）
sudo bash <(curl -fsSL https://raw.githubusercontent.com/josonxie581/sing_box_vpn/main/install.sh)
```

### ❌ 服务启动失败
```bash
# 查看详细日志
singbox logs      # 查看最近50行日志
singbox logx      # 实时监控日志（适合调试）

# 系统状态检查
vps-monitor service

# 手动启动测试
cd ~/domains/*/logs && ./sing-box run -c config.json
```

### ❌ 监控命令不可用
```bash
# 检查命令是否存在
which vps-monitor
which singbox

# 重新加载PATH
source ~/.bashrc

# 手动创建监控脚本
sudo tee /usr/local/bin/vps-monitor > /dev/null << 'EOF'
#!/bin/bash
echo "CPU: $(top -bn1 | grep Cpu | awk '{print $2}' | cut -d'%' -f1)"
echo "内存: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
echo "sing-box: $(pgrep -f sing-box > /dev/null && echo 运行 || echo 停止)"
EOF
sudo chmod +x /usr/local/bin/vps-monitor
```

### ❌ 订阅无法访问

**Serv00/CT8环境**：
```bash
# 检查网站状态
curl -I https://用户名.域名/v2.log

# 重新生成订阅
cd ~/domains/*/logs
base64 -w0 ../public_html/list.txt > ../public_html/v2.log
```

**VPS环境**：
```bash
# 查看节点配置
singbox link

# 手动复制节点到客户端
cat ~/domains/*/logs/list.txt
```

### ❌ TUIC协议无法访问境外

**已自动修复**：新版本安装脚本已包含以下修复：
- ✅ TUIC监听地址配置 (`$available_ip` 替代 `0.0.0.0`)
- ✅ 启用零RTT握手 (`zero_rtt_handshake: true`)
- ✅ 正确的SNI配置 (`sni=www.bing.com`)
- ✅ 服务器名称匹配 (`server_name` 与证书一致)

**手动检查**：
```bash
# 检查TUIC服务状态
vps-monitor service

# 查看TUIC配置
grep -A 20 "tuic-in" ~/domains/*/logs/config.json

# 重新生成配置（如果需要）
sudo bash <(curl -fsSL https://raw.githubusercontent.com/josonxie581/sing_box_vpn/main/install.sh)
```

## 📁 文件位置

```
~/domains/用户名.域名/
├── logs/                    # 工作目录
│   ├── sing-box            # 主程序
│   ├── config.json         # 配置文件
│   └── sing-box.log        # 日志文件
└── public_html/            # 网站目录
    ├── v2.log              # 订阅文件
    └── .htaccess           # 访问控制
```

## 🌟 特色功能

### 🔒 安全可靠
- ✅ **官方二进制**: 直接从GitHub下载，SHA256验证
- ✅ **无后门风险**: 移除所有第三方依赖
- ✅ **权限智能**: 支持root和普通用户安装

### 🚀 性能优化
- ✅ **BBR优化**: 自动启用TCP BBR拥塞控制
- ✅ **TUIC修复**: 解决境外访问问题
- ✅ **监听优化**: 智能IP地址配置

### 📊 监控管理
- ✅ **VPS监控**: 实时系统状态监控
- ✅ **服务监控**: sing-box和cloudflared状态
- ✅ **网络检测**: 延迟测试和连接监控
- ✅ **安全检查**: 登录记录和系统更新

### 🎯 易用性
- ✅ **多协议支持**: VMESS、Hysteria2、TUIC
- ✅ **智能环境检测**: 自动适配Serv00/CT8和VPS
- ✅ **订阅管理**: 自动生成Base64订阅和二维码
- ✅ **便捷管理**: 简单命令操作

### 🔧 容错性
- ✅ **回退机制**: 网络问题时使用内置版本
- ✅ **错误恢复**: 自动检测和修复常见问题
- ✅ **多种安装方式**: 适应不同网络环境

## ⚠️ 注意事项

### 📋 系统要求
- 支持Linux系统（Ubuntu、Debian、CentOS等）
- 支持Serv00/CT8主机和普通VPS
- 推荐使用sudo权限获得最佳体验

### 🔍 使用建议
1. **安装前检查**: 确保网络连接正常
2. **权限处理**: 推荐使用sudo运行安装脚本
3. **定期监控**: 使用`vps-monitor`检查系统状态
4. **服务管理**: 定期检查`singbox status`
5. **TUIC问题**: 新版本已自动修复境外访问问题

### 🌐 环境说明
- **VPS环境**: 手动复制节点配置，无网页订阅
- **Serv00/CT8环境**: 自动配置网页订阅功能

---

## 📝 更新日志

### v2.1.0 (最新版本)
🔥 **重大更新 - 修复版本**

#### 🆕 新增功能
- ✅ **VPS系统监控**: 全新的 `vps-monitor` 命令系列
- ✅ **实时日志监控**: 新增 `singbox logx` 命令持续监控日志
- ✅ **智能权限处理**: 支持root和普通用户安装
- ✅ **BBR优化支持**: 自动启用TCP BBR拥塞控制

#### 🐛 重要修复
- 🔧 **TUIC境外访问**: 修复监听地址配置问题
- 🔧 **下载函数**: 修复curl/wget命令语法错误
- 🔧 **权限问题**: 改进非root环境的兼容性
- 🔧 **SNI配置**: 修复TUIC协议的SNI参数

#### ⚡ 性能优化
- 📈 **启用零RTT握手**: 提高TUIC连接性能
- 📈 **智能IP监听**: 使用动态IP替代固定地址
- 📈 **回退机制**: 网络问题时使用内置版本

#### 🛠️ 技术改进
- 🔄 **模块化设计**: 监控脚本独立维护
- 🔄 **错误处理**: 更完善的异常处理机制
- 🔄 **兼容性**: 支持多种Linux发行版

### 使用新功能
安装后立即可用：
```bash
# 系统监控
vps-monitor quick

# 检查修复效果
singbox status
```

---

## 💬 支持与反馈

- 🐛 **问题报告**: [GitHub Issues](https://github.com/josonxie581/sing_box_vpn/issues)
- 📚 **使用文档**: [完整文档](https://github.com/josonxie581/sing_box_vpn)
- 🔄 **版本更新**: 定期检查GitHub获取最新版本