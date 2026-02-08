# Android Release APK 安装脚本
# 用法：.\install_android_release.ps1 [-Apk <路径>] [-Uninstall]

param(
    [string]$Apk = "build\app\outputs\flutter-apk\app-release.apk",
    [switch]$Uninstall,
    [switch]$DeviceInfo
)

# 设置 UTF-8 编码
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   Android APK 安装工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 查找 ADB
function Find-ADB {
    # 1. 检查 PATH 中是否有 adb
    $adbInPath = Get-Command adb -ErrorAction SilentlyContinue
    if ($adbInPath) {
        return $adbInPath.Source
    }
    
    # 2. 检查 ANDROID_HOME 环境变量
    if ($env:ANDROID_HOME) {
        $adbPath = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
        if (Test-Path $adbPath) {
            return $adbPath
        }
    }
    
    # 3. 检查默认 Android SDK 位置
    $defaultSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
    if (Test-Path $defaultSdk) {
        return $defaultSdk
    }
    
    # 4. 尝试使用 Flutter 的 adb
    try {
        $flutterDoctor = flutter doctor -v 2>&1 | Select-String "Android SDK at"
        if ($flutterDoctor) {
            $sdkPath = ($flutterDoctor -replace ".*Android SDK at ", "").Trim()
            $adbPath = Join-Path $sdkPath "platform-tools\adb.exe"
            if (Test-Path $adbPath) {
                return $adbPath
            }
        }
    } catch {}
    
    return $null
}

$adb = Find-ADB

if (-not $adb) {
    Write-Host "❌ 找不到 ADB 命令！" -ForegroundColor Red
    Write-Host ""
    Write-Host "解决方案：" -ForegroundColor Yellow
    Write-Host "  1. 使用 Flutter 命令安装：flutter install --release" -ForegroundColor White
    Write-Host "  2. 安装 Android SDK Platform Tools" -ForegroundColor White
    Write-Host "  3. 设置 ANDROID_HOME 环境变量" -ForegroundColor White
    Write-Host ""
    
    # 尝试使用 Flutter 安装
    Write-Host "正在尝试使用 Flutter 安装..." -ForegroundColor Yellow
    flutter install --release
    exit $LASTEXITCODE
}

Write-Host "✅ 找到 ADB：$adb" -ForegroundColor Green
Write-Host ""

# 检查设备连接
Write-Host "检查设备连接..." -ForegroundColor Yellow
$devices = & $adb devices | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne "" }

if (-not $devices -or $devices.Count -eq 0) {
    Write-Host "❌ 没有检测到连接的设备！" -ForegroundColor Red
    Write-Host ""
    Write-Host "请确保：" -ForegroundColor Yellow
    Write-Host "  1. 设备已通过 USB 连接" -ForegroundColor White
    Write-Host "  2. 设备已开启 USB 调试" -ForegroundColor White
    Write-Host "  3. 已授权电脑调试权限" -ForegroundColor White
    Write-Host ""
    exit 1
}

# 显示设备信息
$deviceCount = ($devices | Measure-Object).Count
Write-Host "✅ 检测到 $deviceCount 个设备：" -ForegroundColor Green
$devices | ForEach-Object {
    $parts = $_ -split '\s+'
    $deviceId = $parts[0]
    $status = $parts[1]
    Write-Host "  📱 $deviceId [$status]" -ForegroundColor White
}
Write-Host ""

# 如果只是查看设备信息
if ($DeviceInfo) {
    $deviceId = ($devices[0] -split '\s+')[0]
    Write-Host "设备详细信息：" -ForegroundColor Cyan
    & $adb -s $deviceId shell getprop ro.product.model
    & $adb -s $deviceId shell getprop ro.build.version.release
    exit 0
}

# 卸载应用
if ($Uninstall) {
    Write-Host "正在卸载应用..." -ForegroundColor Yellow
    $packageName = "com.example.gsou"
    & $adb uninstall $packageName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ 应用已卸载" -ForegroundColor Green
    } else {
        Write-Host "❌ 卸载失败（应用可能未安装）" -ForegroundColor Red
    }
    exit $LASTEXITCODE
}

# 检查 APK 文件
if (-not (Test-Path $Apk)) {
    Write-Host "❌ APK 文件不存在：$Apk" -ForegroundColor Red
    Write-Host ""
    Write-Host "请先构建 APK：" -ForegroundColor Yellow
    Write-Host "  flutter build apk --release" -ForegroundColor White
    Write-Host ""
    exit 1
}

$apkFile = Get-Item $Apk
$apkSizeMB = [math]::Round($apkFile.Length / 1MB, 2)

Write-Host "APK 信息：" -ForegroundColor Cyan
Write-Host "  📦 文件：$Apk" -ForegroundColor White
Write-Host "  💾 大小：${apkSizeMB} MB" -ForegroundColor White
Write-Host ""

# 安装 APK
Write-Host "开始安装..." -ForegroundColor Yellow
$deviceId = ($devices[0] -split '\s+')[0]

# 如果已安装，先卸载旧版本
Write-Host "  检查旧版本..." -ForegroundColor Gray
& $adb -s $deviceId uninstall com.example.gsou 2>&1 | Out-Null

Write-Host "  安装中..." -ForegroundColor Gray
& $adb -s $deviceId install -r $Apk

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "   ✅ 安装成功！" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "现在可以在设备上打开应用了" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "   ❌ 安装失败！" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "可能的原因：" -ForegroundColor Yellow
    Write-Host "  1. 签名不匹配（设备上已有不同签名的版本）" -ForegroundColor White
    Write-Host "  2. 存储空间不足" -ForegroundColor White
    Write-Host "  3. 应用权限限制" -ForegroundColor White
    Write-Host ""
    Write-Host "解决方案：" -ForegroundColor Yellow
    Write-Host "  1. 手动卸载设备上的旧版本" -ForegroundColor White
    Write-Host "  2. 运行：.\install_android_release.ps1 -Uninstall" -ForegroundColor White
    Write-Host "  3. 然后重新安装" -ForegroundColor White
    Write-Host ""
    exit 1
}
