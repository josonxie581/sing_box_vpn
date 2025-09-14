@echo off
echo Building integrated sing-box library for Windows...

REM --- GCC auto-discovery (MSYS2 / w64devkit / custom) ---------------------------------
REM If gcc is not in PATH, try to prepend common installation directories.
where gcc >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    for %%D in ("C:\msys64\mingw64\bin" "C:\msys64\ucrt64\bin" "C:\msys64\clang64\bin" "C:\w64devkit\bin") do (
        if exist %%D\gcc.exe (
            set "PATH=%%D;%PATH%"
            echo Added %%D to PATH for gcc autodetect.
            goto :_gcc_check
        )
    )
:_gcc_check
)

where gcc >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo WARNING: gcc not found in PATH. CGO build will fail.
    echo If you installed MSYS2, ensure you installed the mingw64 toolchain:
    echo   Open MSYS2 MinGW64 shell and run: pacman -S --needed base-devel mingw-w64-x86_64-toolchain
    echo Then add C:\msys64\mingw64\bin to your PATH (PowerShell example):
    echo   $env:PATH='C:\msys64\mingw64\bin;' + $env:PATH
    echo Or install w64devkit and add its bin directory.
    echo.
)

REM 检查 Go 环境
go version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Go 环境未安装或未添加到 PATH
    echo 请从 https://go.dev/dl/ 下载并安装 Go 1.21+
    pause
    exit /b 1
)

REM 设置环境变量
set CGO_ENABLED=1
set GOOS=windows
set GOARCH=amd64
set CC=gcc

echo 正在下载 sing-box 依赖...
go mod tidy
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: 依赖下载失败
    echo 尝试设置代理: 
    echo   go env -w GOPROXY=https://goproxy.cn,direct
    pause
    exit /b 1
)

echo 正在下载所有依赖包...
go mod download
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: 依赖包下载失败
    pause
    exit /b 1
)

REM 构建标签说明：
REM  - with_utls       启用 uTLS 指纹伪装
REM  - with_quic       启用 QUIC 支持
REM  - with_clash_api  启用 Clash 兼容 API
REM  - with_gvisor     启用 gVisor 用户态 TUN 栈（当前默认使用 gVisor，必须加）
REM  - with_wintun     启用 Windows Wintun/system TUN 栈（作为 gVisor 不可用的回退）
set SBOX_TAGS=with_utls,with_quic,with_clash_api,with_gvisor,with_wintun

echo 正在编译 sing-box 集成库（%SBOX_TAGS%）...
go build -tags "%SBOX_TAGS%" -trimpath -ldflags "-s -w -buildid= -checklinkname=0" -buildmode=c-shared -o ..\windows\singbox.dll singbox.go

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ✅ 编译成功!
    echo DLL 文件: ..\windows\singbox.dll
    echo 头文件: ..\windows\singbox.h
    echo.
    echo 现在可以运行 Flutter 应用了:
    echo   cd ..
    echo   flutter run -d windows
    pause
) else (
    echo.
    echo ❌ 编译失败!
    echo 请检查错误信息并解决后重试
    pause
    exit /b 1
)