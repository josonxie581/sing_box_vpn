Param(
    [switch]$AllAbis
)

$ErrorActionPreference = 'Stop'
function Write-Info {
    Param([string]$msg)
    Write-Host "[INFO] $msg" -ForegroundColor Cyan
}
function Write-Warn {
    Param([string]$msg)
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}
function Write-Fail {
    Param([string]$msg)
    Write-Host "[FAIL] $msg" -ForegroundColor Red
    exit 1
}

# 1) Check Go
$goCmd = Get-Command go -ErrorAction SilentlyContinue
if (-not $goCmd) {
    Write-Fail "Go not found in PATH. Please install Go and reopen the terminal."
}
$goVer = & go version
Write-Info "Go: $goVer"

# 2) Resolve SDK/NDK
$sdkRoot = $env:ANDROID_SDK_ROOT
if ([string]::IsNullOrEmpty($sdkRoot)) {
    $sdkRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
}
Write-Info "SDK Root: $sdkRoot"
if (-not (Test-Path $sdkRoot)) {
    Write-Fail "SDK directory not found: $sdkRoot"
}

$ndkRoot = $env:ANDROID_NDK_ROOT
if ([string]::IsNullOrEmpty($ndkRoot)) {
    $ndkDir = Join-Path $sdkRoot 'ndk'
    if (-not (Test-Path $ndkDir)) {
        Write-Fail "NDK directory not found. Please install NDK via Android Studio SDK Manager."
    }
    $ndkRoot = (Get-ChildItem -Directory $ndkDir | Sort-Object Name -Descending | Select-Object -First 1).FullName
}
Write-Info "NDK Root: $ndkRoot"

$toolBin = Join-Path $ndkRoot 'toolchains\llvm\prebuilt\windows-x86_64\bin'
if (-not (Test-Path $toolBin)) {
    Write-Fail "NDK toolchain bin not found: $toolBin"
}

# 3) Build targets
$projRoot = (Resolve-Path "$PSScriptRoot\..\").Path
Set-Location $projRoot
Write-Info "Project: $projRoot"

$Env:CGO_ENABLED = '1'

# Optional: Go build tags (enable QUIC by default). You can override via env SINGBOX_GO_TAGS.
$GoTags = $env:SINGBOX_GO_TAGS
if ([string]::IsNullOrWhiteSpace($GoTags)) {
    # Default to essential features; override via SINGBOX_GO_TAGS to customize.
    # Note: 'with_reality_server' is deprecated/merged into 'with_utls' in sing-box.
    # IMPORTANT: Include with_gvisor so Android can use userspace stack and accept file_descriptor schema
    $GoTags = 'with_quic,with_utls,with_grpc,with_clash_api,with_gvisor'
} else {
    # Always ensure with_gvisor present
    if ($GoTags -notmatch '(?i)with_gvisor') {
        $GoTags = "$GoTags,with_gvisor"
    }
}
Write-Info "Go build tags: $GoTags"

$nativeDir = Join-Path $projRoot 'native'
if (-not (Test-Path (Join-Path $nativeDir 'go.mod'))) {
    Write-Fail "native/go.mod not found."
}
Push-Location $nativeDir
Write-Info "Running 'go mod download' in $nativeDir"
& go mod download
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Fail "go mod download failed"
}
Pop-Location

function BuildAbi {
    Param(
        [string]$arch,
        [string]$ccName,
        [string]$abiDir
    )
    $outDir = Join-Path $projRoot "android\app\src\main\jniLibs\$abiDir"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $Env:GOOS = 'android'
    $Env:GOARCH = $arch
    if ($arch -eq 'arm') {
        $Env:GOARM = '7'
    } else {
        Remove-Item Env:GOARM -ErrorAction SilentlyContinue
    }
    $ccPathExe = Join-Path $toolBin $ccName
    $ccPath = $ccPathExe
    if (-not (Test-Path $ccPathExe)) {
        $ccNameCmd = [System.IO.Path]::GetFileNameWithoutExtension($ccName) + '.cmd'
        $ccPathCmd = Join-Path $toolBin $ccNameCmd
        if (Test-Path $ccPathCmd) {
            $ccPath = $ccPathCmd
        } else {
            Write-Fail "Compiler not found: $ccPathExe or $ccPathCmd"
        }
    }
    $Env:CC = $ccPath
    Write-Info "Building $abiDir with CC=$ccPath"
    Push-Location $nativeDir
    & go build -tags $GoTags -buildmode=c-shared -o (Join-Path $outDir 'libsingbox.so') singbox.go
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) {
        Write-Fail "Build failed for $abiDir"
    }
    Write-Info ("OK -> " + (Join-Path $outDir 'libsingbox.so'))
}

# Default: build arm64-v8a; with -AllAbis also build armeabi-v7a and x86_64
BuildAbi 'arm64' 'aarch64-linux-android21-clang.exe' 'arm64-v8a'
if ($AllAbis) {
    BuildAbi 'arm'   'armv7a-linux-androideabi21-clang.exe' 'armeabi-v7a'
    BuildAbi 'amd64' 'x86_64-linux-android21-clang.exe'     'x86_64'
}

Write-Info "All done."