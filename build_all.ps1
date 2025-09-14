# Flash-Connect Style VPN Build Script (Dual-EXE Architecture)
# Modern PowerShell replacement for build_all.bat

param(
    [string]$Mode = "release",
    [switch]$SkipDLL,
    [switch]$SkipFlutter,
    [switch]$UpdateSingBox,     # 若本地已有上层 sing-box 目录则执行 git pull
    [string]$SingBoxRepo = "https://github.com/SagerNet/sing-box.git", # 自定义仓库地址
    [string]$SingBoxRef = "",   # 指定分支/Tag/Commit
    [switch]$NoUtf8,             # 不强制 UTF-8 控制台输出
    [switch]$Help
)

function Write-Step {
    param([string]$Message)
    Write-Host "[BUILD] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Failure {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# 为避免控制台乱码（例如“鈥?”），默认将输出编码设置为 UTF-8（可用 -NoUtf8 禁用）
if (-not $NoUtf8) {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Ensure-SingBoxSource {
    param(
        [string]$Repo,
        [string]$Ref
    )
    $parent = (Resolve-Path '..').Path
    $targetDir = Join-Path $parent 'sing-box'

    if (-not (Test-Path $targetDir)) {
        Write-Step "sing-box source not found in parent, cloning..."
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Failure "git not found. Please install Git or place sing-box at: $targetDir"
            throw 'Missing git'
        }
        git clone $Repo $targetDir | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "git clone failed ($Repo)" }
    } elseif ($UpdateSingBox) {
        Write-Step "Updating existing sing-box repo (git pull)"
        Push-Location $targetDir
        git fetch --all --tags | Out-Host
        git pull --ff-only | Out-Host
        Pop-Location
    } else {
        Write-Info "Found existing sing-box source: $targetDir"
    }

    if ($Ref -and $Ref.Trim().Length -gt 0) {
        Write-Step "Checkout sing-box ref: $Ref"
        Push-Location $targetDir
        git fetch --all --tags | Out-Host
        git checkout $Ref | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Failed to checkout ref $Ref" }
        Pop-Location
    }

    # 不创建任何联结，prebuild 将直接使用上层目录的 sing-box 绝对路径
}

if ($Help) {
    Write-Host "Flash-Connect Style VPN Build Script" -ForegroundColor Yellow
    Write-Host "Usage: .\build_all.ps1 [options]" -ForegroundColor White
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  -Mode         Build mode (release/debug, default: release)" -ForegroundColor White
    Write-Host "  -SkipDLL      Skip sing-box DLL compilation" -ForegroundColor White
    Write-Host "  -SkipDaemon   Skip daemon compilation" -ForegroundColor White
    Write-Host "  -SkipFlutter  Skip Flutter app compilation" -ForegroundColor White
    Write-Host "  -UpdateSingBox Update existing ..\\sing-box via git pull" -ForegroundColor White
    Write-Host "  -SingBoxRepo   Specify sing-box git repo (default official)" -ForegroundColor White
    Write-Host "  -SingBoxRef    Checkout to specific ref (tag/branch/commit)" -ForegroundColor White
    Write-Host "  -NoUtf8        Do NOT force UTF-8 console (avoid if terminal already configured)" -ForegroundColor White
    Write-Host "  -Help         Show this help" -ForegroundColor White
    exit 0
}

Write-Host "========================================"
Write-Host "Flash-Connect Style VPN Build (Single-EXE)"
Write-Host "========================================"
Write-Host ""

$startTime = Get-Date

try {
    # 设置 MSYS2/MinGW64 环境
    $msys2Path = "C:\msys64\mingw64\bin"
    if (Test-Path $msys2Path) {
        $env:PATH = "$msys2Path;$env:PATH"
        Write-Info "Added MSYS2/MinGW64 to PATH: $msys2Path"
    }
    
    # Step 0: 准备上层 sing-box 源码（不创建联结）
    # 仅在需要生成 DLL 时准备 sing-box 源码
    if (-not $SkipDLL) { Ensure-SingBoxSource -Repo $SingBoxRepo -Ref $SingBoxRef }

    function Set-GoModReplaceToParent {
        param(
            [Parameter(Mandatory=$true)][string]$GoModPath,
            [Parameter(Mandatory=$true)][string]$ParentSingBoxDir
        )
        if (-not (Test-Path $GoModPath)) { return }
        if (-not (Test-Path $ParentSingBoxDir)) { return }
        try {
            $content = Get-Content -LiteralPath $GoModPath -Raw
            $absPath = (Resolve-Path $ParentSingBoxDir).Path -replace '\\','/'
            # 1) 删除任何已存在的 sing-box replace（单行形式）
            $content = [Regex]::Replace($content, '(?m)^\s*replace\s+github\.com/sagernet/sing-box\s*=>.*\r?\n?', '')
            # 2) 删除 replace 块内针对 sing-box 的行
            $content = [Regex]::Replace($content, '(?m)^\s*github\.com/sagernet/sing-box\s*=>.*\r?\n?', '')
            # 3) 清理可能出现的空的 replace() 块
            $content = [Regex]::Replace($content, '(?ms)^\s*replace\s*\(\s*\)\s*\r?\n?', '')
            # 4) 追加唯一的 replace 到文件末尾
            if (-not $content.TrimEnd().EndsWith("`n")) { $content += "`n" }
            $content += "`n// 使用上层目录的 sing-box 源码`nreplace github.com/sagernet/sing-box => $absPath`n"
            # 使用无 BOM 的 UTF-8 写入，避免 go 工具报 \ufeff 错误
            if (-not $content.TrimEnd().EndsWith("`n")) { $content += "`n" }
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($GoModPath, $content, $utf8NoBom)
            Write-Info "Patched replace in $(Split-Path -Leaf $GoModPath) -> $absPath"
        } catch {
            Write-Host "[WARNING] Failed to patch ${GoModPath}: $_" -ForegroundColor Yellow
        }
    }

    function Reset-GoMod-Minimal {
        param(
            [Parameter(Mandatory=$true)][string]$ModuleDir,
            [Parameter(Mandatory=$true)][string]$ParentSingBoxDir
        )
        $goMod = Join-Path $ModuleDir 'go.mod'
        if (-not (Test-Path $ParentSingBoxDir)) { return }
        $moduleName = 'daemon'
        if (Test-Path $goMod) {
            try {
                $raw = Get-Content -LiteralPath $goMod -Raw
                $m = [Regex]::Match($raw, '(?m)^\s*module\s+([^\r\n]+)')
                if ($m.Success) { $moduleName = $m.Groups[1].Value.Trim() }
            } catch {}
        }
        $absPath = (Resolve-Path $ParentSingBoxDir).Path -replace '\\','/'
        $content = @()
        $content += "module $moduleName"
        $content += ""
        $content += "go 1.23.1"
        $content += ""
        $content += "require github.com/sagernet/sing-box v0.0.0"
        $content += ""
        $content += "// 使用上层目录的 sing-box 源码"
        $content += "replace github.com/sagernet/sing-box => $absPath"

        # 检查是否存在 local-sing-tun 目录
        $localSingTunDir = Join-Path $ParentSingBoxDir 'local-sing-tun'
        if (Test-Path $localSingTunDir) {
            $localSingTunPath = (Resolve-Path $localSingTunDir).Path -replace '\\','/'
            $content += ""
            $content += "// 使用本地的 sing-tun 源码"
            $content += "replace github.com/sagernet/sing-tun => $localSingTunPath"
            Write-Info "检测到 local-sing-tun，将使用本地版本: $localSingTunPath"
        }

        $text = ($content -join "`n") + "`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($goMod, $text, $utf8NoBom)
        # 删除 go.sum，避免旧校验干扰
        $goSum = Join-Path $ModuleDir 'go.sum'
        if (Test-Path $goSum) { Remove-Item -LiteralPath $goSum -Force -ErrorAction SilentlyContinue }
        Write-Info "Rewrote minimal go.mod for module '$moduleName' and removed go.sum"
    }
    
    # Step 1: Compile sing-box DLL
    if (-not $SkipDLL) {
        Write-Step "[1/3] Compiling sing-box DLL with gVisor..."
        
        # 使用 Dart prebuild 脚本编译（推荐方式）
        Write-Host "Using Dart prebuild script for optimal compilation..." -ForegroundColor Cyan
        $preArgs = @('run','tools/prebuild.dart','--force')
        if ($SingBoxRef -and $SingBoxRef.Trim().Length -gt 0) { $preArgs += @('--ref', $SingBoxRef) }
        dart @preArgs | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "DLL compilation failed" }
        Write-Success "sing-box DLL compilation completed"
    }
    else {
        Write-Host "[SKIP] sing-box DLL compilation" -ForegroundColor Yellow
    }

    # (Removed) Step 2 previously built daemon

    # Step 2: Flutter dependencies
    if (-not $SkipFlutter) {
        Write-Step "[2/3] Getting Flutter dependencies..."
        flutter pub get | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Flutter dependencies failed" }
        Write-Success "Flutter dependencies completed"
    }

    # Step 3: Compile Flutter app
    if (-not $SkipFlutter) {
        Write-Step "[3/3] Compiling Flutter app ($Mode mode)..."
        
        if ($Mode -eq "release") {
            flutter build windows --release | Out-Host
        }
        else {
            flutter build windows | Out-Host
        }
        
        if ($LASTEXITCODE -ne 0) { throw "Flutter app compilation failed" }
        Write-Success "Flutter app compilation completed"
    }
    else {
        Write-Host "[SKIP] Flutter app compilation" -ForegroundColor Yellow
    }

    # After build: Copy supplementary files (only if Flutter build not skipped)
    if (-not $SkipFlutter) {
        Write-Step "[POST] Organizing output files..."
        $outputDir = if ($Mode -eq "release") { "build\windows\x64\runner\Release" } else { "build\windows\x64\runner\Debug" }
        if (-not (Test-Path $outputDir)) {
            throw "Flutter output directory not found: $outputDir"
        }

        # Copy wintun.dll (if present) for TUN support
        if (Test-Path "windows\wintun.dll") {
            try {
                Copy-Item "windows\wintun.dll" $outputDir -Force
                Write-Success "wintun.dll copied to output directory"
            } catch { Write-Host "[WARNING] Failed to copy wintun.dll to output: $_" -ForegroundColor Yellow }
        } else {
            Write-Info "wintun.dll not found under windows/, skipping copy (stack=system will not use it)"
        }

        # Check files
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "BUILD COMPLETED SUCCESSFULLY!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Output directory: $outputDir" -ForegroundColor Cyan
        
        if (Test-Path "$outputDir\Gsou.exe") {
            $size = [math]::Round((Get-Item "$outputDir\Gsou.exe").Length / 1MB, 2)
            Write-Host "  Gsou.exe (Flutter main app) - $size MB" -ForegroundColor White
        }
        
        if (Test-Path "$outputDir\singbox.dll") {
            $size = [math]::Round((Get-Item "$outputDir\singbox.dll").Length / 1MB, 2)
            Write-Host "  singbox.dll (core) - $size MB" -ForegroundColor White
        }

        Write-Host ""
    Write-Host "Features:" -ForegroundColor Yellow
    Write-Host "  [OK] sing-box DLL (with gVisor support)" -ForegroundColor White
    Write-Host "  [OK] Flutter UI (modern interface)" -ForegroundColor White
    Write-Host "  [OK] Optional wintun.dll (TUN support)" -ForegroundColor White
    Write-Host "" 
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  1. Run Gsou.exe" -ForegroundColor White
    Write-Host "  2. Configure nodes & enable TUN if needed" -ForegroundColor White
    } else {
        Write-Info "Skip output organization because Flutter build was skipped"
    }

}
catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Failure "BUILD FAILED!"
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Failure "Error: $($_.Exception.Message)"
    exit 1
}

$endTime = Get-Date
$duration = $endTime - $startTime
Write-Host ""
Write-Host "Build time: $($duration.ToString('mm\:ss'))" -ForegroundColor Cyan

Remove-Item Env:\CGO_ENABLED -ErrorAction SilentlyContinue
Remove-Item Env:\GOOS -ErrorAction SilentlyContinue  
Remove-Item Env:\GOARCH -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Build completed successfully! Ready to test." -ForegroundColor Green
exit 0