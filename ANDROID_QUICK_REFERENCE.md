# Android 开发快速参考

## 🚀 快速命令

### 构建
```powershell
# 构建 Debug APK（开发测试）
flutter build apk --debug
flutter install

# 构建 Release APK（正式发布）
flutter build apk --release
flutter install --release

# 或使用脚本
.\build_android_release.ps1          # 通用 APK
.\build_android_release.ps1 -SplitAbi  # 分架构（体积更小）
.\build_android_release.ps1 -Clean     # 清理后构建
```

### 安装
```powershell
# 方法 1：使用 Flutter（推荐）
flutter install --release

# 方法 2：使用脚本
.\install_android_release.ps1

# 方法 3：直接使用 ADB（需要配置 PATH）
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

### 运行和调试
```powershell
# 运行 Debug 模式（热重载）
flutter run

# 运行 Release 模式
flutter run --release

# 指定设备
flutter run -d DEVICE_ID

# 查看日志
flutter logs
```

### 设备管理
```powershell
# 查看连接的设备
flutter devices
adb devices

# 查看设备详细信息
.\install_android_release.ps1 -DeviceInfo

# 卸载应用
.\install_android_release.ps1 -Uninstall
adb uninstall com.example.gsou
```

### 清理和维护
```powershell
# 清理构建缓存
flutter clean

# 获取依赖
flutter pub get

# 升级依赖
flutter pub upgrade

# 检查环境
flutter doctor -v

# 检查过期的依赖
flutter pub outdated
```

---

## 📁 重要文件和目录

### 输出文件
- **Debug APK**：`build/app/outputs/flutter-apk/app-debug.apk`
- **Release APK**：`build/app/outputs/flutter-apk/app-release.apk`
- **分架构 APK**：
  - `app-armeabi-v7a-release.apk` (ARM 32位)
  - `app-arm64-v8a-release.apk` (ARM 64位，推荐)
  - `app-x86_64-release.apk` (x86 64位)
- **App Bundle**：`build/app/outputs/bundle/release/app-release.aab`

### 配置文件
- **应用信息**：`pubspec.yaml`
- **Android 配置**：`android/app/build.gradle.kts`
- **签名配置**：`android/key.properties` (需要自己创建)
- **应用图标**：`android/app/src/main/res/mipmap-*/`

---

## 🔧 常见问题

### Q: ADB 命令不可用？
```powershell
# 临时添加到 PATH（当前会话）
$env:Path += ";C:\Users\xiesa\AppData\Local\Android\Sdk\platform-tools"

# 或直接使用 Flutter 命令
flutter install --release
```

### Q: 设备未检测到？
1. 检查 USB 连接
2. 开启"USB 调试"（设置 → 开发者选项 → USB 调试）
3. 授权电脑调试权限（设备上弹出提示）
4. 尝试：`adb kill-server` 然后 `adb start-server`

### Q: 安装失败 "INSTALL_FAILED_UPDATE_INCOMPATIBLE"？
```powershell
# 签名不匹配，先卸载旧版本
.\install_android_release.ps1 -Uninstall
# 或
adb uninstall com.example.gsou
# 然后重新安装
flutter install --release
```

### Q: 构建失败？
```powershell
# 1. 清理缓存
flutter clean

# 2. 删除 build 目录
Remove-Item -Recurse -Force build

# 3. 获取依赖
flutter pub get

# 4. 重新构建
flutter build apk --release
```

### Q: 如何减小 APK 体积？
```powershell
# 按架构分别构建
flutter build apk --release --split-per-abi

# 启用代码混淆（需修改 build.gradle.kts）
# minifyEnabled true
# shrinkResources true
```

---

## 📱 设备架构说明

| 架构 | 说明 | 适用设备 |
|------|------|----------|
| **armeabi-v7a** | ARM 32位 | 老旧 Android 设备 |
| **arm64-v8a** | ARM 64位 | 现代 Android 设备（推荐） |
| **x86_64** | x86 64位 | 模拟器、少数平板 |

大多数现代设备使用 **arm64-v8a**。

---

## 🎯 发布检查清单

发布前检查：

- [ ] 修改 `applicationId`（包名）
- [ ] 更新 `versionCode` 和 `versionName`
- [ ] 配置正式签名密钥
- [ ] 测试 Release 版本
- [ ] 检查应用权限
- [ ] 准备应用商店资源（图标、截图、描述）
- [ ] 启用代码混淆（可选）
- [ ] 测试不同设备和系统版本

---

## 📚 相关脚本

- `build_android_release.ps1` - 自动化构建脚本
- `install_android_release.ps1` - 自动化安装脚本
- `BUILD_ANDROID_RELEASE.md` - 完整发布指南

---

## 💡 有用的技巧

### 快速重装
```powershell
# 一键构建并安装
flutter build apk --release && flutter install --release
```

### 查看 APK 信息
```powershell
# 查看签名
keytool -printcert -jarfile build\app\outputs\flutter-apk\app-release.apk

# 分析 APK 大小
flutter build apk --release --analyze-size
```

### 实时日志
```powershell
# 查看应用日志
adb logcat | Select-String "flutter|gsou"

# 或使用 Flutter
flutter logs
```

### 截屏和录屏
```powershell
# 截屏
adb shell screencap /sdcard/screenshot.png
adb pull /sdcard/screenshot.png

# 录屏（4.4+）
adb shell screenrecord /sdcard/demo.mp4
# Ctrl+C 停止
adb pull /sdcard/demo.mp4
```
