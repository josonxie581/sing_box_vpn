# 放置 Android 原生库

将各架构的 libsingbox.so 放到对应目录：

- armeabi-v7a/libsingbox.so
- arm64-v8a/libsingbox.so
- x86_64/libsingbox.so（可选）

建议使用 NDK 或 gomobile/gobind 编译 sing-box 的 Android 版本，并确保与 Go 版本及依赖匹配。
