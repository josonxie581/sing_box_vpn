# Android Release 构建指南

## 快速构建（使用 Debug 签名）

最简单的方式，适合测试和个人使用：

```powershell
# 构建 APK
flutter build apk --release

# 构建后的文件位置：
# build\app\outputs\flutter-apk\app-release.apk
```

构建完成后，APK 文件会保存在：
- `build\app\outputs\flutter-apk\app-release.apk`

---

## 正式发布（使用正式签名）

如果要发布到应用商店或给其他用户使用，需要配置正式的签名密钥。

### 第一步：创建签名密钥

```powershell
# 使用 Java keytool 创建密钥库
keytool -genkey -v -keystore D:\TEMP\VPN\sing_box_vpn\android\app\upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

按提示输入：
- **密钥库密码**（记住它！）
- **密钥密码**（建议与密钥库密码相同）
- 你的名字、组织等信息

### 第二步：配置签名

创建文件 `android\key.properties`：

```properties
storePassword=你的密钥库密码
keyPassword=你的密钥密码
keyAlias=upload
storeFile=D:\\TEMP\\VPN\\sing_box_vpn\\android\\app\\upload-keystore.jks
```

**重要**：将 `key.properties` 添加到 `.gitignore`，**不要**提交到 Git！

### 第三步：修改 build.gradle.kts

在 `android/app/build.gradle.kts` 中添加签名配置：

```kotlin
// 在 android { } 块之前添加
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    // ... 现有配置 ...
    
    // 添加签名配置
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
    
    buildTypes {
        release {
            // 使用正式签名，而不是 debug 签名
            signingConfig signingConfigs.release
            
            // 可选：启用代码混淆（减小体积，增加反编译难度）
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
}
```

### 第四步：构建正式版本

```powershell
# 构建正式签名的 APK
flutter build apk --release

# 或构建 App Bundle（推荐用于 Google Play）
flutter build appbundle --release
```

构建产物：
- **APK**：`build\app\outputs\flutter-apk\app-release.apk`
- **AAB**：`build\app\outputs\bundle\release\app-release.aab`

---

## 构建选项

### 构建不同架构

```powershell
# 构建所有架构的 APK（单个文件，体积较大）
flutter build apk --release

# 按架构分别构建（体积更小，但需要为不同设备提供不同 APK）
flutter build apk --release --split-per-abi

# 生成的文件：
# - app-armeabi-v7a-release.apk  (32位 ARM)
# - app-arm64-v8a-release.apk    (64位 ARM，推荐)
# - app-x86_64-release.apk       (64位 x86，模拟器)
```

### 查看 APK 信息

```powershell
# 查看签名信息
keytool -printcert -jarfile build\app\outputs\flutter-apk\app-release.apk

# 查看 APK 大小和内容
flutter build apk --release --analyze-size
```

---

## 发布检查清单

在发布前，确保检查以下项目：

- [ ] 修改 `android/app/build.gradle.kts` 中的 `applicationId`（改成你自己的包名）
- [ ] 修改 `android/app/build.gradle.kts` 中的 `versionCode` 和 `versionName`
- [ ] 确保使用正式签名密钥，而不是 debug 密钥
- [ ] 测试 Release 版本在真实设备上运行
- [ ] 检查权限声明是否合理
- [ ] 准备应用图标、截图、描述等商店资源

---

## 常见问题

### Q: 构建时提示找不到签名密钥？
A: 检查 `key.properties` 文件路径是否正确，密钥库文件是否存在。

### Q: 安装时提示"未经授权的应用"？
A: 这是因为使用了 debug 签名。要么配置正式签名，要么在设备上允许安装来自未知来源的应用。

### Q: APK 体积太大？
A: 使用 `--split-per-abi` 选项，或启用代码混淆和资源压缩。

### Q: 如何更新版本号？
A: 修改 `pubspec.yaml` 中的 `version` 字段，格式：`版本名+版本号`，例如 `1.0.0+1`

---

## 自动化构建脚本

你可以创建一个 PowerShell 脚本来自动化构建过程：

```powershell
# build_android_release.ps1
param(
    [switch]$SplitAbi,
    [switch]$Bundle
)

Write-Host "开始构建 Android Release..." -ForegroundColor Cyan

# 清理旧的构建
flutter clean
flutter pub get

if ($Bundle) {
    Write-Host "构建 App Bundle..." -ForegroundColor Yellow
    flutter build appbundle --release
    $output = "build\app\outputs\bundle\release\app-release.aab"
} elseif ($SplitAbi) {
    Write-Host "构建分架构 APK..." -ForegroundColor Yellow
    flutter build apk --release --split-per-abi
    $output = "build\app\outputs\flutter-apk\"
} else {
    Write-Host "构建通用 APK..." -ForegroundColor Yellow
    flutter build apk --release
    $output = "build\app\outputs\flutter-apk\app-release.apk"
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ 构建成功！" -ForegroundColor Green
    Write-Host "输出文件：$output" -ForegroundColor Green
} else {
    Write-Host "❌ 构建失败！" -ForegroundColor Red
    exit 1
}
```

使用方法：
```powershell
# 构建通用 APK
.\build_android_release.ps1

# 构建分架构 APK
.\build_android_release.ps1 -SplitAbi

# 构建 App Bundle
.\build_android_release.ps1 -Bundle
```

---

## 相关链接

- [Flutter 构建和发布文档](https://docs.flutter.dev/deployment/android)
- [Android 应用签名文档](https://developer.android.com/studio/publish/app-signing)
- [Google Play 发布指南](https://support.google.com/googleplay/android-developer/answer/9859152)
