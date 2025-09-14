# SingBox VPN One-Click Publisher (Windows / PowerShell 5+)
param(
    [string]$Version = "",
    [switch]$NoBuild,
    [switch]$Sign,                               # Use signtool if available
    [switch]$SkipDaemon,                         # Skip building daemon if specified
    [switch]$EmbeddedDaemon,                     # Use daemon/build_embedded.ps1 instead of build.bat
    [string]$CertPath = "",                     # PFX path (optional)
    [SecureString]$CertPasswordSecure = $null,   # PFX password (optional, SecureString)
    [string]$TimestampUrl = "http://timestamp.digicert.com" # Timestamp server
)

$ErrorActionPreference = "Stop"

function Get-AppVersionFromPubspec {
    $pubspec = Join-Path $PSScriptRoot 'pubspec.yaml'
    if (-not (Test-Path $pubspec)) { return $null }
    # PowerShell 5.1 has no native YAML parser; use simple regex
    $line = (Get-Content $pubspec | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1)
    if (-not $line) { return $null }
    $v = ($line -replace '^version:\s*', '').Trim()
    return $v
}

function Test-Tool($name, $checkArgs) {
    try {
        $null = & $name $checkArgs 2>&1
        if ($LASTEXITCODE -ne 0) { throw "$name not available" }
    }
    catch {
        throw ("{0} is not available. Please install it first." -f $name)
    }
}

Write-Host 'SingBox VPN Publisher' -ForegroundColor Green

# 0) Ensure Git submodules are ready
try {
    $null = git --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'Syncing Git submodules...' -ForegroundColor Yellow
        git submodule sync --recursive | Out-Host
        git submodule update --init --recursive | Out-Host
        Write-Host 'Submodules ready' -ForegroundColor Green
    }
}
catch { Write-Host 'Skip submodule update (git not available)' -ForegroundColor Yellow }

# 1) Resolve version
if (-not $Version -or [string]::IsNullOrWhiteSpace($Version)) {
    $auto = Get-AppVersionFromPubspec
    if ($auto) {
        $Version = $auto
        Write-Host ("Using version from pubspec.yaml: {0}" -f $Version) -ForegroundColor Yellow
    }
    else {
        throw 'Failed to read version from pubspec.yaml. Specify with -Version, e.g. 1.0.0+1'
    }
}

# Normalize folder tag (replace + with _)
$versionTag = ($Version -replace '\+', '_')

# 2) Build (unless skipped)
if (-not $NoBuild) {
    Write-Host '[1/4] Checking environment...' -ForegroundColor Yellow
    Test-Tool flutter '--version'
    Test-Tool dart '--version'

    Write-Host '[2/4] Running prebuild (sing-box) with force rebuild...' -ForegroundColor Yellow
    try {
        # 始终强制重建集成 DLL
        dart run tools/prebuild.dart --force
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'Prebuild failed (forced mode). Will attempt manual fallback later.' -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host 'Prebuild error (forced). Will attempt manual fallback later.' -ForegroundColor Yellow
    }

    Write-Host '[3/4] Building Windows Release (App)...' -ForegroundColor Yellow
    flutter build windows --release

    if (-not $SkipDaemon) {
        Write-Host '[3.1] Building daemon...' -ForegroundColor Yellow
        $daemonDir = Join-Path $PSScriptRoot 'daemon'
        if (-not (Test-Path $daemonDir)) {
            Write-Host 'Daemon directory not found, skip.' -ForegroundColor Yellow
        } else {
            $daemonExe = Join-Path $daemonDir 'gsou_daemon.exe'
            # 删除旧的以避免混淆
            if (Test-Path $daemonExe) { Remove-Item $daemonExe -Force -ErrorAction SilentlyContinue }
            try {
                if ($EmbeddedDaemon) {
                    $embeddedScript = Join-Path $daemonDir 'build_embedded.ps1'
                    if (Test-Path $embeddedScript) {
                        Write-Host 'Using embedded daemon build script...' -ForegroundColor Yellow
                        powershell -ExecutionPolicy Bypass -File $embeddedScript
                    } else { Write-Host 'Embedded build script not found, fallback to build.bat' -ForegroundColor Yellow }
                }
                if (-not (Test-Path $daemonExe)) {
                    $buildBat = Join-Path $daemonDir 'build.bat'
                    if (Test-Path $buildBat) {
                        Write-Host 'Running build.bat for daemon...' -ForegroundColor Yellow
                        cmd /c $buildBat
                    } else {
                        # 使用内联 go build 作为回退
                        Write-Host 'No daemon build script found, fallback to inline go build...' -ForegroundColor Yellow
                        try {
                            Push-Location $daemonDir
                            $env:CGO_ENABLED = '1'
                            $env:GOTOOLCHAIN = 'local'
                            # 尽量与 embedded 构建保持一致的 GUI 隐藏参数
                            go build -trimpath -tags "with_utls,with_quic,with_clash_api,with_gvisor,with_wintun" -ldflags "-s -w -buildid= -H=windowsgui" -o gsou_daemon.exe .
                        } catch {
                            Write-Host "Inline go build for daemon failed: $_" -ForegroundColor Yellow
                        } finally { Pop-Location }
                    }
                }
                if (Test-Path $daemonExe) { Write-Host 'Daemon built successfully.' -ForegroundColor Green } else { Write-Host 'Daemon build failed or executable missing.' -ForegroundColor Yellow }
            } catch {
                Write-Host "Daemon build error: $_" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host 'Skip daemon build as requested.' -ForegroundColor Yellow
    }

    # 由于 prebuild 使用 --force 已尝试重建，这里仅做存在性校验与极简回退
    Write-Host '[3.2] Verifying sing-box integrated DLL...' -ForegroundColor Yellow
    $integratedDll = Join-Path $PSScriptRoot 'windows/singbox.dll'
    if (-not (Test-Path $integratedDll)) {
        Write-Host 'Integrated DLL missing after forced prebuild. Attempting minimal inline fallback...' -ForegroundColor Yellow
        $nativeDir = Join-Path $PSScriptRoot 'native'
        if (Test-Path $nativeDir) {
            try {
                Push-Location $nativeDir
                $env:CGO_ENABLED = '1'
                $env:GOOS = 'windows'
                $env:GOARCH = 'amd64'
                $gcc = Get-Command gcc -ErrorAction SilentlyContinue
                if (-not $gcc) { $clang = Get-Command clang -ErrorAction SilentlyContinue }
                if ($gcc) { $env:CC = 'gcc' } elseif ($clang) { $env:CC = 'clang'; Write-Host 'Using clang (gcc missing).' -ForegroundColor Yellow } else { Write-Host 'No gcc/clang found; cannot fallback build integrated DLL.' -ForegroundColor Yellow }
                if ($env:CC) {
                    go build -tags "with_utls,with_quic,with_clash_api,with_gvisor,with_wintun" -trimpath -ldflags "-s -w -buildid= -checklinkname=0" -buildmode=c-shared -o ..\windows\singbox.dll singbox.go
                }
            } catch { Write-Host "Minimal inline fallback failed: $_" -ForegroundColor Yellow } finally { Pop-Location }
        } else { Write-Host 'native directory missing; cannot fallback build integrated DLL.' -ForegroundColor Yellow }
    }
    if (Test-Path $integratedDll) { Write-Host 'Integrated DLL ready.' -ForegroundColor Green } else { Write-Host 'Integrated DLL still missing (package will proceed without it).' -ForegroundColor Yellow }
}

# 3) Collect outputs
$releaseDir = Join-Path $PSScriptRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path $releaseDir)) {
    throw ("Release directory not found: {0}. Please build first." -f $releaseDir)
}

$distRoot = Join-Path $PSScriptRoot 'dist'
if (-not (Test-Path $distRoot)) { New-Item -ItemType Directory -Path $distRoot | Out-Null }

$packageName = "gsou-$versionTag-windows-x64"
$packageDir  = Join-Path $distRoot $packageName

if (Test-Path $packageDir) {
    try {
        Remove-Item -Recurse -Force $packageDir -ErrorAction Stop
    } catch {
        Write-Host 'Initial removal of existing package directory failed (maybe file locked). Retrying...' -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        try { Remove-Item -Recurse -Force $packageDir -ErrorAction Stop } catch { Write-Host 'Retry failed; will reuse and overwrite contents.' -ForegroundColor Yellow }
    }
}
New-Item -ItemType Directory -Path $packageDir | Out-Null

Write-Host '[4/4] Preparing package directory...' -ForegroundColor Yellow

# Copy all build outputs
Copy-Item -Path (Join-Path $releaseDir '*') -Destination $packageDir -Recurse -Force

# Include daemon executable if built
$daemonBuiltExe = Join-Path $PSScriptRoot 'daemon/gsou_daemon.exe'
if ((-not $SkipDaemon) -and (Test-Path $daemonBuiltExe)) {
    try {
        Copy-Item $daemonBuiltExe -Destination $packageDir -Force
        Write-Host 'Included gsou_daemon.exe in package' -ForegroundColor Green
    } catch {
        Write-Host 'Failed to include gsou_daemon.exe' -ForegroundColor Yellow
    }
}

# If integrated DLL exists in project windows/, copy it next to the exe as well
$projDll = Join-Path $PSScriptRoot 'windows/singbox.dll'
if (Test-Path $projDll) {
    try {
        Copy-Item -Path $projDll -Destination $packageDir -Force
        Write-Host 'Included singbox.dll in package' -ForegroundColor Green
    } catch {
        Write-Host 'Failed to include singbox.dll' -ForegroundColor Yellow
    }
}

# Optional: include wintun.dll if available (needed for TUN on Windows)
$wintunDll = Join-Path $PSScriptRoot 'windows/wintun.dll'
if (Test-Path $wintunDll) {
    try {
        Copy-Item -Path $wintunDll -Destination $packageDir -Force
        Write-Host 'Included wintun.dll in package' -ForegroundColor Green
    } catch {
        Write-Host 'Failed to include wintun.dll' -ForegroundColor Yellow
    }
} else {
    Write-Host 'Warning: wintun.dll not found; TUN will fail without it.' -ForegroundColor Yellow
}

# Optional: include helpful docs if exist
foreach ($doc in @('README_USAGE.md','START_HERE.md','README_CN.md','README.md','LICENSE')) {
    $p = Join-Path $PSScriptRoot $doc
    if (Test-Path $p) { Copy-Item $p -Destination $packageDir -Force }
}

# Include PAC files directory if it exists
$pacDir = Join-Path $PSScriptRoot 'pac_files'
if (Test-Path $pacDir) {
    try {
        $packagePacDir = Join-Path $packageDir 'pac_files'
        Copy-Item -Path $pacDir -Destination $packageDir -Recurse -Force
        Write-Host 'Included pac_files directory in package' -ForegroundColor Green
        
        # Count PAC files for information
        $pacFiles = Get-ChildItem -Path $packagePacDir -Filter "*.pac" | Measure-Object
        if ($pacFiles.Count -gt 0) {
            Write-Host "Found $($pacFiles.Count) PAC file(s) in package" -ForegroundColor Green
        }
    } catch {
        Write-Host 'Failed to include pac_files directory' -ForegroundColor Yellow
    }
} else {
    Write-Host 'No pac_files directory found, users can create custom PAC files after installation' -ForegroundColor Yellow
}

# Optional code signing
function Invoke-CodeSign($file) {
    try {
        $signtool = (Get-Command signtool.exe -ErrorAction SilentlyContinue)
        if (-not $signtool) { Write-Host 'signtool.exe not found, skip code signing' -ForegroundColor Yellow; return }

        $sigArgs = @('sign','/fd','sha256','/tr', $TimestampUrl, '/td','sha256')
        if ($CertPath) {
            $sigArgs += @('/f', $CertPath)
            if ($CertPasswordSecure) {
                $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($CertPasswordSecure)
                try {
                    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
                }
                finally {
                    if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
                }
                if ($plain) { $sigArgs += @('/p', $plain) }
            }
        }
        # If no cert provided, signtool may prompt to select from cert store; skip in CI
        & $signtool.Path @sigArgs $file
        if ($LASTEXITCODE -eq 0) { Write-Host ("Signed: {0}" -f $file) -ForegroundColor Green }
        else { Write-Host ("Signing failed: {0}" -f $file) -ForegroundColor Yellow }
    }
    catch {
        Write-Host ("Signing exception: {0}" -f $file) -ForegroundColor Yellow
    }
}

if ($Sign) {
    $exe = Join-Path $packageDir 'Gsou.exe'
    if (Test-Path $exe) { Invoke-CodeSign $exe }
}

# Zip artifact
$zipPath = Join-Path $distRoot ("$packageName.zip")
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }

Compress-Archive -Path (Join-Path $packageDir '*') -DestinationPath $zipPath -Force

Write-Host ''
Write-Host 'Package generated' -ForegroundColor Green
Write-Host ("Folder: {0}" -f $packageDir) -ForegroundColor Cyan
Write-Host ("Zip: {0}" -f $zipPath) -ForegroundColor Cyan
Write-Host ''
Write-Host 'Next:' -ForegroundColor Yellow
Write-Host '1) Upload the zip to GitHub Release or your distribution channel' -ForegroundColor Gray
Write-Host ("2) In the release notes, include version {0} and changelog" -f $Version) -ForegroundColor Gray
