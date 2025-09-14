@echo off
REM 极简构建脚本：避免复杂的 for/delayed expansion/本地化导致的解析问题
setlocal

REM 1) Go + cgo 环境
set CGO_ENABLED=1
set GOOS=windows
set GOARCH=amd64

REM 2) 注入 MSYS2 MinGW-w64 到 PATH（如存在）并指定 CC
if exist "C:\msys64\mingw64\bin\gcc.exe" (
  set "PATH=C:\msys64\mingw64\bin;%PATH%"
)
if exist "C:\msys64\mingw64\bin\x86_64-w64-mingw32-gcc.exe" (
  set CC=x86_64-w64-mingw32-gcc
)

echo Build configuration:
echo   CGO_ENABLED=%CGO_ENABLED%  GOOS=%GOOS%  GOARCH=%GOARCH%
echo   PATH prefix=C:\msys64\mingw64\bin  CC=%CC%

REM 3) 依赖
go mod tidy || exit /b 1
go mod download || exit /b 1

REM 4) 编译 DLL（含 WinTUN）
go build -tags "with_gvisor,with_quic,with_utls,with_clash_api,with_wintun" -trimpath -ldflags "-s -w -buildid= -checklinkname=0" -buildmode=c-shared -o ..\windows\singbox.dll singbox_lib.go || exit /b 1

echo Build OK: ..\windows\singbox.dll
exit /b 0
