/// 日志级别。
enum LogLevel { debug, info, warn, error }

extension LogLevelX on LogLevel {
  String get label => switch (this) {
        LogLevel.debug => 'DEBUG',
        LogLevel.info => 'INFO',
        LogLevel.warn => 'WARN',
        LogLevel.error => 'ERROR',
      };
}

/// 一条运行日志。
class LogEntry {
  final String id;
  final DateTime time;
  final LogLevel level;

  /// 模块标签，如 'app' / 'agent' / 'chat' / 'db'。
  final String tag;
  final String message;

  const LogEntry({
    required this.id,
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
  });
}
