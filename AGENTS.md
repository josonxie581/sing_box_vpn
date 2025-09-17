# Repository Guidelines
本仓库是 Sing Box VPN 桌面客户端的 Flutter 实现，本文档为贡献者提供快速上手指引。

## 项目结构与模块组织
- `lib/`：核心源码。`screens/` 页面，`providers/` 状态管理，`services/` 后端交互，`models/` 数据模型，`widgets/` 复用组件，`utils/` 工具方法，`theme/` 主题样式。
- `test/`：单元与 Widget 测试，命名采用 `<feature>_test.dart`。
- `assets/`：静态资源；`native/`、`windows/`：平台特定产物；`tools/prebuild.dart` 负责生成 `singbox` 动态库。
- `go/`：封装底层代理服务源码，更新后需重新执行 `make prebuild`。

## 构建、测试与开发命令
- `flutter pub get` / `make setup`：同步依赖并初始化环境。
- `dart run tools/prebuild.dart` 或 `make prebuild`：生成 Windows 所需的 `singbox.dll`。
- `make dev`：以 Windows 目标设备启动调试会话。
- `make build`：编译发布版，产物存于 `build/windows/x64/runner/Release/`。
- `flutter test` / `flutter test --coverage`：运行全部测试并导出覆盖率。

## 代码风格与命名规范
- 遵循 `analysis_options.yaml` 中的 lints，提交前执行 `dart format .`（2 空格缩进）。
- 类与类型使用 `PascalCase`，变量与方法使用 `camelCase`，常量使用 `SCREAMING_SNAKE_CASE`。
- Widget 文件与类保持同名，如 `vpn_home_screen.dart` → `VpnHomeScreen`。

## 测试指南
- 新功能需在 `test/` 下补充覆盖核心逻辑的单元或 Widget 测试。
- 模拟外部依赖时使用 `mocktail` 或 `mockito`，沿用现有模式。
- 在提交前至少运行 `flutter test --coverage`，并在 PR 描述中说明关键覆盖率变化。

## 提交与合并请求规范
- Git 提交信息沿用仓库历史的简洁中文动宾结构（示例：“修复延时统计”）。
- 单次提交聚焦单一改动，如需说明专业术语可在正文附英文注释。
- PR 需包含：变更摘要、关联 issue、验证截图/日志；若影响界面请附 UI 截图。
- 合并前需确保 CI 通过，并在本地执行 `make build` 验证发布构建。
