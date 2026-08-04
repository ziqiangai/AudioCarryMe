import 'dart:developer' as developer;

import '../models/log_entry.dart';
import '../state/log_store.dart';

/// 统一日志框架。全局静态入口，任何地方都能 `AppLog.i('tag', '...')`。
///
/// 绑定一个 [AppLogStore] 后，日志会同时输出到控制台并持久化到本地数据库。
/// 未绑定时（如测试）只输出控制台，不落库。
class AppLog {
  AppLog._();

  static AppLogStore? _store;
  static int _seq = 0;

  /// 在 App 启动时绑定日志仓库。
  static void bind(AppLogStore store) => _store = store;

  static void d(String tag, String message) => _log(LogLevel.debug, tag, message);
  static void i(String tag, String message) => _log(LogLevel.info, tag, message);
  static void w(String tag, String message) => _log(LogLevel.warn, tag, message);
  static void e(String tag, String message) => _log(LogLevel.error, tag, message);

  static void _log(LogLevel level, String tag, String message) {
    final entry = LogEntry(
      id: 'log-${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
      time: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
    );
    // 控制台输出（开发时可见）。
    developer.log(message, name: '$tag/${level.label}', time: entry.time);
    // 持久化 + 通知 UI。
    _store?.add(entry);
  }
}
