# 测试PowerShell截图功能
Write-Host "=== 测试截图功能 ===" -ForegroundColor Green

# 测试1：从剪贴板获取图片
Write-Host "`n测试1: 从剪贴板读取图片" -ForegroundColor Yellow
Write-Host "请复制一个图片到剪贴板，然后按任意键继续..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
    $image = [System.Windows.Forms.Clipboard]::GetImage()
    if ($image -ne $null) {
        $testPath = "$env:TEMP\clipboard_test.png"
        $image.Save($testPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $image.Dispose()
        Write-Host "✓ 成功保存剪贴板图片到: $testPath" -ForegroundColor Green

        # 检查文件大小
        $fileInfo = Get-Item $testPath
        Write-Host "  文件大小: $($fileInfo.Length) bytes" -ForegroundColor Cyan
    } else {
        Write-Host "✗ 无法获取剪贴板图片" -ForegroundColor Red
    }
} else {
    Write-Host "✗ 剪贴板中没有图片" -ForegroundColor Red
}

# 测试2：触发截图工具
Write-Host "`n测试2: 触发Windows截图工具" -ForegroundColor Yellow
Write-Host "即将触发Win+Shift+S，请截取屏幕区域..."
Write-Host "按任意键开始..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# 添加Windows API类型定义
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class KeyPress {
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public const int VK_LWIN = 0x5B;
    public const int VK_SHIFT = 0x10;
    public const int S_KEY = 0x53;
    public const int KEYEVENTF_KEYUP = 0x0002;
}
"@

# 清空剪贴板
[System.Windows.Forms.Clipboard]::Clear()

# 触发截图
Write-Host "正在触发截图工具..."
[KeyPress]::keybd_event([KeyPress]::VK_LWIN, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 50
[KeyPress]::keybd_event([KeyPress]::VK_SHIFT, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 50
[KeyPress]::keybd_event([KeyPress]::S_KEY, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 50

# 释放按键
[KeyPress]::keybd_event([KeyPress]::S_KEY, 0, [KeyPress]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 50
[KeyPress]::keybd_event([KeyPress]::VK_SHIFT, 0, [KeyPress]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 50
[KeyPress]::keybd_event([KeyPress]::VK_LWIN, 0, [KeyPress]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)

Write-Host "等待截图完成（最多15秒）..."

# 等待用户完成截图
$maxWait = 15
$waited = 0

while ($waited -lt $maxWait) {
    Start-Sleep -Seconds 1
    $waited++
    Write-Host "." -NoNewline

    # 检查剪贴板是否有图片
    if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
        $image = [System.Windows.Forms.Clipboard]::GetImage()
        if ($image -ne $null) {
            $testPath = "$env:TEMP\screenshot_test.png"
            $image.Save($testPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $image.Dispose()
            Write-Host ""
            Write-Host "✓ 成功保存截图到: $testPath" -ForegroundColor Green

            # 检查文件大小
            $fileInfo = Get-Item $testPath
            Write-Host "  文件大小: $($fileInfo.Length) bytes" -ForegroundColor Cyan
            break
        }
    }

    if ($waited -eq $maxWait) {
        Write-Host ""
        Write-Host "✗ 超时：未检测到截图" -ForegroundColor Red
    }
}

Write-Host "`n测试完成！" -ForegroundColor Green