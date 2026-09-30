# sing-box 核心版本与本地依赖

当前客户端使用 `native/` 集成 **sing-box v1.14.2**，版本记录在 `sing-box-version.txt`。构建脚本会将 `../sing-box` 切换到该 tag，并使用上游 go.mod 匹配的 sing-tun 版本。需要 Go 1.25.5 或更新版本；Go 的自动工具链功能也可以满足要求。

```powershell
# 构建 Windows DLL 与发布版应用
.\build_all.ps1

# 仅构建 Windows DLL
.\build_all.ps1 -SkipFlutter

# 直接构建 DLL
dart run tools/prebuild.dart --force
```

默认不再根据目录是否存在，自动替换为旧的 `local-sing-tun`。旧版 sing-tun 与新版核心的平台接口不兼容，不能直接复用。原 sing-box `main` 分支保留 v1.12.20 及本地补丁，便于对照迁移。

若需要自行修改 sing-tun，应先基于当前上游依赖版本迁移补丁，再在 `native/go.mod` 中明确设置 replace 并手动编译。`prebuild.dart` 会重置核心依赖，因此定制构建不能依赖它保留手工 replace。

Windows DLL 在 `build/singbox-core/` 编译成功后复制到 `windows/`；构建失败时保留原 DLL。新版 `GetVersion` 返回实际核心版本，`TestConfig` 同时校验配置解析和核心组件的构造。

```powershell
flutter test --coverage
```

Windows 上存在 DLL 时，兼容性测试会使用它校验三种路由模式、TUN/混合代理、IPv4/IPv6、静态 DNS 映射和各节点协议。测试不代表真实节点联网成功。

Android 源码和构建脚本使用同一依赖版本，重新生成 `libsingbox.so` 还需要 Android NDK：

```powershell
.\native\build_android.ps1
```
