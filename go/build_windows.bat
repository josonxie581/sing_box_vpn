@echo off
setlocal enableextensions enabledelayedexpansion
echo Building sing-box library for Windows...

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

REM 下载依赖
echo Downloading dependencies...
go mod tidy
go mod download

REM 编译为 DLL (包含 gVisor 支持)
echo Building DLL with gVisor + WinTUN support...
go build -tags "with_gvisor,with_quic,with_utls,with_clash_api,with_wintun" -trimpath -ldflags "-s -w -buildid= -checklinkname=0" -buildmode=c-shared -o ..\windows\singbox.dll singbox_lib.go

if %ERRORLEVEL% EQU 0 (
    echo Build successful!
    echo DLL created at: ..\windows\singbox.dll
) else (
    echo Build failed!
    exit /b 1
)
