@echo off
setlocal enableextensions enabledelayedexpansion
echo ========================================
echo Building sing-box library with FULL features for Windows
echo ========================================

REM 设置环境变量
set CGO_ENABLED=1
set GOOS=windows
set GOARCH=amd64

REM 尝试自动检测/注入 MinGW-w64 (MSYS2) 编译器到 PATH
where gcc >NUL 2>&1
if %ERRORLEVEL% NEQ 0 (
    if exist "C:\msys64\mingw64\bin\gcc.exe" (
        set "PATH=C:\msys64\mingw64\bin;%PATH%"
        echo Detected MSYS2 MinGW-w64 at C:\msys64\mingw64\bin
    ) else if exist "C:\Program Files\mingw-w64\x86_64-12.2.0-posix-seh-rt_v10-rev0\mingw64\bin\gcc.exe" (
        set "PATH=C:\Program Files\mingw-w64\x86_64-12.2.0-posix-seh-rt_v10-rev0\mingw64\bin;%PATH%"
        echo Detected MinGW-w64 under Program Files
    ) else (
        echo [WARN] 未找到 gcc 于 PATH；如已安装 MSYS2，通常位于 C:\msys64\mingw64\bin
    )
)

REM 如存在三方前缀编译器，显式指定 CC 以避免 cgo 误判
if exist "C:\msys64\mingw64\bin\x86_64-w64-mingw32-gcc.exe" (
    set CC=x86_64-w64-mingw32-gcc
)

REM 设置编译标签 - 包含所有重要功能
REM with_gvisor: gVisor 用户空间网络栈（关键！）
REM with_quic: QUIC 协议支持
REM with_utls: uTLS 支持（绕过 TLS 指纹检测）
REM with_clash_api: Clash API 兼容
REM with_wireguard: WireGuard 协议支持（可选）
set BUILD_TAGS=with_gvisor,with_quic,with_utls,with_clash_api,with_wintun

echo.
echo Build configuration:
echo - CGO_ENABLED=%CGO_ENABLED%
echo - GOOS=%GOOS%
echo - GOARCH=%GOARCH%
echo - Tags=%BUILD_TAGS%
echo.

REM 下载依赖
echo [1/3] Downloading dependencies...
go mod tidy
if %ERRORLEVEL% NEQ 0 (
    echo Failed to tidy modules!
    exit /b 1
)

go mod download
if %ERRORLEVEL% NEQ 0 (
    echo Failed to download dependencies!
    exit /b 1
)

REM 验证 gVisor 依赖
echo [2/3] Verifying gVisor dependencies...
go list -m github.com/sagernet/gvisor
if %ERRORLEVEL% NEQ 0 (
    echo Warning: gVisor dependency not found, trying to add...
    go get github.com/sagernet/gvisor@latest
)

REM 编译为 DLL
echo [3/3] Building DLL with full features (WinTUN enabled)...
go build -tags "%BUILD_TAGS%" ^
    -trimpath ^
    -ldflags "-s -w -buildid= -checklinkname=0" ^
    -buildmode=c-shared ^
    -o ..\windows\singbox.dll ^
    singbox_lib.go

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo Build SUCCESSFUL!
    echo ========================================
    echo DLL created at: ..\windows\singbox.dll
    echo Features included:
    echo - [x] gVisor user-space network stack
    echo - [x] QUIC protocol support
    echo - [x] uTLS fingerprint bypass
    echo - [x] Clash API compatibility
    echo ========================================
    
    REM 验证 DLL 大小（gVisor 会显著增加文件大小）
    if exist ..\windows\singbox.dll (
        for %%F in (..\windows\singbox.dll) do set "size=%%~zF"
        echo DLL size: !size! bytes
        if "!size!"=="" (
            echo Skipping size check (size unknown)
        ) else (
            REM 仅当 size 存在且为数字时再比较
            for /f "delims=0123456789" %%X in ("!size!") do set NONNUM=%%X
            if "!NONNUM!"=="" (
                if !size! LSS 10000000 (
                    echo Warning: DLL seems too small, gVisor might not be included!
                )
            ) else (
                echo Skipping size compare (non-numeric size)
            )
        )
    ) else (
        echo DLL not found; skip size check.
    )
) else (
    echo.
    echo ========================================
    echo Build FAILED!
    echo ========================================
    echo Please check the error messages above.
    echo Common issues:
    echo - Missing Go installation
    echo - Missing C compiler (MinGW-w64 or Visual Studio)
    echo - Network issues downloading dependencies
    exit /b 1
)

echo.
echo Next steps:
echo 1. Run Flutter app to test the new DLL
echo 2. Check logs for "gVisor is not included" errors
echo 3. If gVisor works, TUN mode will work without Wintun.dll
pause
