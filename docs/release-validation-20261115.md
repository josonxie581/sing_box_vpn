# 全量变更验证记录（2026-11-15）

本次将现有 PR #4 的范围扩展到工作区全部工程变更：Android 扫码和内核、Linux 原生工程、sing-box 1.14.4 协议支持、VPS 出口管理与恢复、AWS/DMIT 安装脚本。

## 当前验证

- `flutter test --no-pub --coverage`：166 通过、1 跳过；覆盖 3212/15227 行（21.1%）。相较 PR 原先的 99 个通过用例增加 67 个；整体覆盖率包含新增 Linux/VPS 功能，不能直接与原扫码页的局部覆盖率比较。
- Windows Go 原生测试通过，包含 TCP/QUIC RTT、Salamander/Gecko 混淆和错误密码行为。
- Python 脚本测试：Windows 31 项、跳过 7 项；WSL Ubuntu 31 项、跳过 5 项。平台专属用例按平台跳过，两边均成功。
- `dart analyze lib test`：0 error；仍有 21 warning 和 882 info，不能宣称全工程分析无告警。
- `make build`：Windows Release 成功，包含更新内核和 Cronet；预构建脚本的源码路径改为相对于 native 目录，随后单独重跑预构建成功。
- Android ARM64 Release APK 成功，版本 1.0.6+3，内核 1.14.4；最终打包的原生库与源码目录发布库哈希一致。
- 原生 Android 测试此前已在连接的 ASUS 手机运行通过，包含现代协议初始化及混淆 QUIC 测速；1.0.6 安装与启动已验证。最后补入的 Hysteria2 分享修复本次已重新打包，但未再次安装手机。
- Hysteria2 分享/扫码往返测试验证混淆密码、拥塞配置、端口跳跃、IPv6 和特殊字符密码保持一致。
- DMIT 使用当前服务端参数，从 Windows 连续 3 次 HTTPS 出站实测成功；这不代表手机上旧节点的参数已修正。
- 暂存改动 Gitleaks 扫描无发现；CRLF 文件按 `cr-at-eol` 执行 Git whitespace 检查。

## 范围与限制

- Linux 原生工程、安装服务和测试脚本纳入本次提交；本轮运行 Linux Python 验证，未重新构建 Linux GUI 或重新验证 Omarchy 桌面行为。
- 当前 Linux 内核构建标签尚未启用 Naive；Windows/Android 的 Naive 验证不能用于声称 Linux Naive 可用。
- 手机相机对实物二维码的光学识别、手机当前 DMIT 节点的实际联网仍未确认。
- APK 使用已有测试签名。SDK、APK/桌面发布目录、凭据和浏览器临时记录不进入 Git；已跟踪的 ARM64 原生库以去除符号后的发布文件提交，保持 16 KB ELF 对齐。
- 安卓界面参考原 PR 的 [首页截图](screenshots/android-home-20261028.png) 和 [相机权限截图](screenshots/android-scanner-permission-20261028.png)，它们是此前的 Widget 截图，不是本次实拍扫码证据。
