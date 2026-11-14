# Android Release 构建脚本
# 用法：.\build_android_release.ps1 [-SplitAbi] [-Bundle] [-Clean] [-Arm64]

param(
    [switch]$SplitAbi,    # 按架构分别构建
    [switch]$Bundle,      # 构建 App Bundle（AAB）
    [switch]$Clean,       # 构建前清理
    [switch]$Arm64        # 只打包 ARM64，匹配默认的 Android 原生库构建
)

# 设置 UTF-8 编码
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   Android Release 构建工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 清理旧构建
if ($Clean) {
    Write-Host "[1/3] 清理旧构建..." -ForegroundColor Yellow
    flutter clean
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ 清理失败！" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ 清理完成" -ForegroundColor Green
    Write-Host ""
}

# 获取依赖
Write-Host "$(if ($Clean) { '[2/3]' } else { '[1/2]' }) 获取依赖..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 获取依赖失败！" -ForegroundColor Red
    exit 1
}
Write-Host "✅ 依赖获取完成" -ForegroundColor Green
Write-Host ""

# 构建
$targetArgs = @()
if ($Arm64) { $targetArgs = @('--target-platform', 'android-arm64') }
Write-Host "$(if ($Clean) { '[3/3]' } else { '[2/2]' }) 开始构建..." -ForegroundColor Yellow

if ($Bundle) {
    Write-Host "构建类型：App Bundle (AAB)" -ForegroundColor Cyan
    flutter build appbundle --release @targetArgs
    $outputPath = "build\app\outputs\bundle\release\app-release.aab"
} elseif ($SplitAbi) {
    Write-Host "构建类型：分架构 APK" -ForegroundColor Cyan
    flutter build apk --release --split-per-abi @targetArgs
    $outputPath = "build\app\outputs\flutter-apk\"
} else {
    Write-Host "构建类型：$(if ($Arm64) { 'ARM64 APK' } else { '通用 APK' })" -ForegroundColor Cyan
    flutter build apk --release @targetArgs
    $outputPath = "build\app\outputs\flutter-apk\app-release.apk"
}

Write-Host ""

# 检查构建结果
if ($LASTEXITCODE -eq 0) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "   ✅ 构建成功！" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "输出文件位置：" -ForegroundColor Cyan
    
    if ($SplitAbi) {
        # 显示文件大小
        Get-ChildItem "$outputPath\app-*-release.apk" | ForEach-Object {
            $sizeMB = [math]::Round($_.Length / 1MB, 2)
            Write-Host "     └─ $($_.Name): ${sizeMB} MB" -ForegroundColor Gray
        }
    } else {
        Write-Host "  📦 $outputPath" -ForegroundColor White
        
        # 显示文件大小
        if (Test-Path $outputPath) {
            $file = Get-Item $outputPath
            $sizeMB = [math]::Round($file.Length / 1MB, 2)
            Write-Host "     └─ 大小: ${sizeMB} MB" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "📋 后续步骤：" -ForegroundColor Cyan
    Write-Host "  1. 在真实设备上测试 APK" -ForegroundColor White
    Write-Host "  2. 检查应用权限和功能" -ForegroundColor White
    Write-Host "  3. 如需发布，配置正式签名（参见 BUILD_ANDROID_RELEASE.md）" -ForegroundColor White
    Write-Host ""
    
} else {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "   ❌ 构建失败！" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "可能的解决方案：" -ForegroundColor Yellow
    Write-Host "  1. 运行 'flutter clean' 清理缓存" -ForegroundColor White
    Write-Host "  2. 检查签名配置（android/app/build.gradle.kts）" -ForegroundColor White
    Write-Host "  3. 运行 'flutter doctor' 检查环境" -ForegroundColor White
    Write-Host "  4. 查看详细日志：flutter build apk --release --verbose" -ForegroundColor White
    Write-Host ""
    exit 1
}
