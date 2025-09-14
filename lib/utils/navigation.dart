import 'package:flutter/widgets.dart';

/// 提供安全的 pop，避免在根路由或已被系统清空时调用导致
/// Navigator 断言 `_history.isNotEmpty` 触发。
///
/// 使用方式：safePop(context); 或 safePop(context, result);
void safePop<T extends Object?>(BuildContext context, [T? result]) {
  final navigator = Navigator.maybeOf(context);
  if (navigator != null && navigator.canPop()) {
    try {
      navigator.pop<T>(result);
    } catch (_) {
      // 忽略潜在的并发 pop 异常
    }
  }
}
