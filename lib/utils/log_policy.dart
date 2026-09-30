import 'dart:async';

/// 默认关闭调试输出，错误、状态及崩溃日志仍保留。
class LogPolicy {
  static const debugEnabled = false;

  static bool shouldLog(String line) =>
      debugEnabled || !line.trimLeft().startsWith('[DEBUG]');

  static final consoleZone = ZoneSpecification(
    print: (self, parent, zone, line) {
      if (shouldLog(line)) parent.print(zone, line);
    },
  );
}
