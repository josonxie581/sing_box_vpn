# Omarchy / Linux 原生版

项目已添加 Linux Flutter 工程，构建会同时生成原生 ELF 程序和 `libsingbox.so`。
当前窗口插件使用 X11，因此在 Omarchy / Hyprland 下通过 XWayland 显示。
不需要 Wine，也不运行 Windows EXE。

## 环境

在目标 Omarchy 机器上编译，使用与机器架构匹配的 Flutter SDK。
当前项目本地验证使用 Flutter 3.35.4 / Dart 3.9.2；Go 要求 1.25.5 或更新版本。
SDK 不包含在项目中。先安装 Flutter 并确保 `flutter` 在 PATH 中。

Omarchy / Arch 依赖：

```bash
sudo pacman -S --needed base-devel clang cmake ninja pkgconf gtk3 \
  libayatana-appindicator go git libcap patchelf binutils xorg-xwayland
flutter doctor -v
```

Ubuntu 22.04 / 24.04 构建机可使用（本次使用 WSL Ubuntu 22.04）：

```bash
sudo apt install build-essential clang cmake ninja-build pkg-config libgtk-3-dev \
  libayatana-appindicator3-dev libcap2-bin patchelf binutils git xwayland
```

Ubuntu 的 Go 版本也必须满足 `native/go.mod`，不要直接假设发行版自带版本足够。
不同发行版构建产物的系统库版本可能不同，优先在目标 Omarchy 上构建。

Windows 上可以用 WSL 编译。需要在 WSL 内安装 **Linux 版** Flutter 和 Go，
并将源码复制到 Linux 文件系统的独立构建目录，避免与 Windows 共用 `.dart_tool`。
本次构建目录为 `/home/xie/gsou-builds/omarchy`，Release 产物已复制到
Windows 项目的 `dist/Gsou-Omarchy-linux-x64/`。

## 构建与安装

在项目根目录执行：

```bash
bash build_linux.sh
```

脚本保留 `pubspec.lock` 依赖版本，按 `sing-box-version.txt` 获取核心源码，
然后执行 Flutter Release 构建。核心源码与临时 Go modfile 放在 `build/linux-core/`，
不会切换或修改项目旁边现有的 `sing-box` 工作区。
需要使用自己的核心源码时，可显式设置 `SING_BOX_SOURCE=/绝对路径/sing-box`。

x86_64 输出目录：`build/linux/x64/release/bundle/`。
ARM64 输出目录：`build/linux/arm64/release/bundle/`，需要对应架构的 Linux Flutter SDK。
必须保留整个 bundle，不能只复制 `gsou`。

```bash
sudo bash build/linux/x64/release/bundle/install_linux.sh
gsou
```

安装器会检查完整产物、共享库依赖和核心导出函数，然后安装到 `/opt/gsou`，
注册桌面入口和 systemd 用户服务。更新前先从托盘退出 Gsou；旧目录保留为
`/opt/gsou.backup.<时间>.<进程号>`，方便回退。
从 Windows / 9p 共享目录安装时，仅复制文件内容，再重新设置 Linux 权限，
不保留共享目录的 ACL 或扩展属性。

### TUN 权限

程序以普通桌面用户运行。安装器将整个程序目录设为 root 所有、普通用户不可写，
仅给 `gsou` 可执行文件授予 `CAP_NET_ADMIN` 和 `CAP_NET_RAW`，用于 TUN、路由和物理网卡测速。
安装器同步修正库搜索路径，避免 file capabilities 导致相对路径库无法加载。
不要给可由普通用户写入的开发目录或整个 Flutter SDK 授权。

直接运行未安装的 bundle 可以打开界面和手动代理，但 TUN 会明确提示缺少权限。
若系统、容器或文件系统禁止 capabilities，TUN 仍不可用，不能把构建成功当作联网成功。

### 自启动和退出

在“设置 → DNS 设置”打开“开机自动启动”，读取和修改的是
`systemctl --user is-enabled/enable/disable gsou.service` 的真实状态。
服务随 `graphical-session.target` 启动，适用于 Omarchy 的 systemd 桌面会话。
自定义非 systemd 桌面会话需要自行配置桌面自启动。

关闭窗口后留在托盘；从托盘退出时断开 VPN。SIGTERM / SIGINT 也会先尝试断开连接。
Linux 单实例由 GtkApplication / D-Bus 负责，再次启动会唤回现有窗口。
Linux 退出在连接清理完成后结束进程，避开本次实测发现的 Flutter 3.35 X11
窗口销毁时 GLX BadAccess 错误。

## 首版范围

- 接入现有节点、订阅、规则分流、核心、流量统计和原生节点 RTT 测试流程。
- Linux TUN 使用 `gsou-tun`、自动路由和 `auto_redirect`。
- 支持 PNG 托盘图标、桌面入口、用户会话自启动。
- Linux 不提供 Windows 系统代理开关；可使用 TUN，或手动配置应用使用 `127.0.0.1:7890`。
- Windows 悬浮窗在 Linux 暂不启用，最小化由桌面管理。
- VPS SSH 出口管控、DMIT 监控/账单桥接、Windows 专用截图及剪贴板图片路径尚未移植。
  节点链接粘贴和图片文件导入仍可使用。

## 验证

构建脚本最后会检查 bundle 文件、`ldd` 依赖和 Go 核心导出函数。
这只代表产物检查，不代表已通过 Omarchy 桌面或真实联网验收。

```bash
flutter test --coverage
bash tools/verify_linux.sh build/linux/x64/release/bundle
getcap /opt/gsou/gsou
```

核心兼容性测试会使用 `build/linux-core/libsingbox.so`；PAC 测试还需要支持
`node:vm` 的 Node.js（本次使用 Node 22）。

在 Omarchy 的普通用户桌面终端中，可以运行 bundle 自带的完整检查脚本：

```bash
bash /mnt/host/Gsou-Omarchy-linux-x64/test_omarchy.sh
```

此路径适用于本机 Try Omarchy 共享目录。其他机器请替换为 bundle 的实际路径。
脚本安装缺少的依赖和程序，然后验证核心、SOCKS、隔离网络中的 TUN、
Hyprland 窗口、桌面托盘注册、单实例与退出，并将程序重新打开。它不导入个人节点、不改变自启动设置。
日志为 bundle 旁的 `omarchy-test.log` 和 `omarchy-gui.log`。

真实节点的订阅/导入、外网 TUN 连接、DNS、IPv4/IPv6、节点切换、
自启动和休眠唤醒仍需单独验证。

本次实际验证（2026-11-06）：

- WSL Ubuntu 22.04、Flutter 3.35.4、Dart 3.9.2、Go 1.25.5，Linux x86_64 Release 构建成功。
- bundle 文件、共享库依赖、核心导出函数检查通过。
- Linux Flutter `test --coverage`：130 通过、4 跳过；Linux Go 核心测试全部通过。
- 两轮真实 SOCKS HTTP 转发通过；隔离网络中两轮透明 TUN HTTP 转发通过，
  停止后网卡、路由、策略规则及 nftables 表恢复到测试前状态。
- WSL 中安装到 `/opt/gsou` 后，以 UID 1000 启动，确认有效 capabilities 为 `0x3000`。
  Xvfb 下界面已截图检查，单实例与 SIGTERM 正常退出通过。
- 原 Windows Flutter 测试为 133 通过、1 跳过；Windows Go 核心测试通过。
  全项目分析仍有 17 个既有 warning，不能称全项目静态检查零警告。

本机 Try Omarchy（Arch Linux 7.2.11、Hyprland）已实测通过安装、普通用户
capabilities、两轮 SOCKS 和隔离 TUN 转发及清理。Hyprland 确认 Gsou 窗口
已映射，使用 XWayland，窗口尺寸为 621×699。
2026-11-06 19:04 的最终检查全部通过：桌面 Watcher 确认 Gsou 的托盘项为
Active，重复启动保持单实例，SIGTERM 退出返回成功。测试结束后程序已重新启动。
原始结果见共享目录的 `omarchy-test.log` 和 `omarchy-gui.log`；项目内留存于
`build/wsl/omarchy-final-test.log` 和 `build/wsl/omarchy-final-gui.log`。

跨发行版检查发现的托盘旧库依赖和 Ayatana 库名问题已修正；共享目录 ACL
读取失败也已改为复制内容后重新设置 Linux 权限。托盘检查改为查询桌面
Watcher 的实际注册列表及所属进程，不再假定服务名称前缀；Omarchy 复测通过。

Omarchy 日志存在 GTK 读取桌面门户设置时的权限警告（带 capabilities 的进程
`/proc/<pid>/root` 不可由门户读取）。此警告未阻止本次窗口及核心测试，
桌面主题和其他门户相关功能尚未验收。

依赖参考：[Flutter Linux](https://docs.flutter.dev/platform-integration/linux/setup)、
[Arch AppIndicator](https://archlinux.org/packages/extra/x86_64/libayatana-appindicator/files/)。
