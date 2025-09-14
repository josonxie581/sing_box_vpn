# 使用 local-sing-tun 编译 sing-box DLL

本文档说明如何在编译 sing-box DLL 时使用本地的 sing-tun 源码。

## 功能说明

当您运行构建脚本时，系统会自动检测是否存在 `local-sing-tun` 目录，如果存在，会自动使用本地版本替换远程依赖。

## 使用方法

### 1. 确保目录结构正确

确保您的项目目录结构如下：
```
D:\TEMP\VPN\
├── sing-box\                    # sing-box 主项目
│   ├── local-sing-tun\         # 本地 sing-tun 源码
│   ├── go.mod
│   └── ...
└── sing_box_vpn\               # VPN 项目
    ├── build_all.ps1           # PowerShell 构建脚本
    ├── tools\prebuild.dart     # Dart 预构建脚本
    ├── native\                 # Go native 代码
    └── ...
```

### 2. 运行构建脚本

使用 PowerShell 脚本：
```powershell
.\build_all.ps1
```

或者只编译 DLL（跳过 Flutter 编译）：
```powershell
.\build_all.ps1 -SkipFlutter
```

使用 Dart 预构建脚本：
```powershell
dart run tools/prebuild.dart --force
```

## 自动检测机制

### Dart 脚本 (tools/prebuild.dart)
- 检查 `$parentSingBoxPath/local-sing-tun` 目录是否存在
- 如果存在，自动在 `native/go.mod` 中添加：
  ```go
  // 使用本地的 sing-tun 源码
  replace github.com/sagernet/sing-tun => /path/to/local-sing-tun
  ```
- 控制台输出：`✅ 检测到 local-sing-tun，将使用本地版本: /path/to/local-sing-tun`

### PowerShell 脚本 (build_all.ps1)
- 在 `Reset-GoMod-Minimal` 函数中检查 local-sing-tun 目录
- 如果存在，自动添加相应的 replace 指令
- 控制台输出：`检测到 local-sing-tun，将使用本地版本: /path/to/local-sing-tun`

## 验证方法

构建完成后，您可以检查 `native/go.mod` 文件，应该包含类似以下内容：
```go
// 使用上层目录的 sing-box 源码
replace github.com/sagernet/sing-box => D:/TEMP/VPN/sing-box

// 使用本地的 sing-tun 源码
replace github.com/sagernet/sing-tun => D:/TEMP/VPN/sing-box/local-sing-tun
```

## 注意事项

1. **local-sing-tun 必须是有效的 Go 模块**：确保 `local-sing-tun` 目录包含有效的 `go.mod` 文件
2. **兼容性**：确保您的 local-sing-tun 版本与 sing-box 主项目兼容
3. **自动清理**：每次构建前，系统会自动删除 `go.sum` 文件以避免校验冲突
4. **构建标签**：DLL 编译使用标签：`with_utls,with_quic,with_clash_api,with_gvisor,with_wintun`

## 故障排除

如果遇到编译问题：

1. **检查 local-sing-tun 完整性**：
   ```bash
   cd D:\TEMP\VPN\sing-box\local-sing-tun
   go mod tidy
   ```

2. **手动清理缓存**：
   ```bash
   cd D:\TEMP\VPN\sing_box_vpn\native
   go clean -cache
   go mod tidy
   ```

3. **强制重新构建**：
   ```powershell
   .\build_all.ps1 -SkipFlutter
   # 或
   dart run tools/prebuild.dart --force
   ```