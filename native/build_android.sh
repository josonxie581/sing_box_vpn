#!/usr/bin/env bash
set -euo pipefail

# 简易脚本：构建 Android 用 libsingbox.so 到 android/app/src/main/jniLibs/
# 依赖：Go 1.22+/1.23、Android NDK r26+、gomobile/gobind（可选）

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/android/app/src/main/jniLibs"
mkdir -p "$OUT_DIR/armeabi-v7a" "$OUT_DIR/arm64-v8a" "$OUT_DIR/x86_64"

echo "NOTE: 此脚本为占位示例。实际项目中需根据 sing-box 的 go.mod 和 cgo/依赖配置调整。"
echo "将编译产物复制为 libsingbox.so 到对应 ABI 目录。"

exit 0
