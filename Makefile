# SingBox VPN Makefile for Windows
.PHONY: help dev build clean setup prebuild

# 默认目标
help:
	@echo "SingBox VPN 编译命令:"
	@echo "  make setup     - 设置开发环境"
	@echo "  make prebuild  - 预编译 sing-box DLL"
	@echo "  make dev       - 运行开发版本"
	@echo "  make build     - 编译发布版本"
	@echo "  make clean     - 清理编译文件"

# 设置开发环境
setup:
	@echo "🔧 设置开发环境..."
	flutter pub get
	@echo "✅ 开发环境设置完成"

# 预编译 sing-box
prebuild:
	@echo "🚀 预编译 sing-box..."
	dart run tools/prebuild.dart

# 开发模式
dev: setup
	@echo "🔨 启动开发模式..."
	flutter run -d windows

# 编译发布版本
build: setup prebuild
	@echo "🔨 编译发布版本..."
	flutter build windows --release
	@echo "✅ 编译完成: build/windows/x64/runner/Release/"

# 清理文件
clean:
	@echo "🧹 清理编译文件..."
	flutter clean
	if exist "windows\singbox.dll" del "windows\singbox.dll"
	if exist "windows\singbox.h" del "windows\singbox.h"
	if exist "build" rmdir /s /q "build"
	@echo "✅ 清理完成"