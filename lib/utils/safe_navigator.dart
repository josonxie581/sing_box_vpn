import 'package:flutter/widgets.dart';

/// 提供安全的导航操作，避免在空路由栈或已卸载上下文上调用 pop 导致断言。
class SafeNavigator {
  /// 安全 pop：只有在 canPop=true 时才执行。
  static bool safePop(BuildContext context, {Object? result}) {
    final navigator = Navigator.maybeOf(context);
    if (navigator == null) return false; // context 已无效
    if (!navigator.canPop()) return false;
    navigator.pop(result);
    return true;
  }

  /// 安全 push：如果 context 不在导航树中则忽略。
  static Future<T?>? pushIfMounted<T extends Object?>(
    BuildContext context,
    Route<T> route,
  ) {
    final navigator = Navigator.maybeOf(context);
    if (navigator == null) return null;
    return navigator.push(route);
  }
}

/// 顶层函数便捷调用。
bool safePop(BuildContext context, {Object? result}) =>
    SafeNavigator.safePop(context, result: result);
