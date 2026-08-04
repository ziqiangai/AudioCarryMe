import 'package:flutter/foundation.dart';

import '../models/log_entry.dart';
import '../storage/chat_storage.dart';

/// 运行日志状态。持有日志（最新在前），持久化到本地，支持清空。
class AppLogStore extends ChangeNotifier {
  AppLogStore(this._storage);

  final ChatStorage _storage;
  final List<LogEntry> _logs = [];

  /// 内存中最多保留的条数（防止无限增长；数据库仍有全量，可自行加清理策略）。
  static const int _maxInMemory = 2000;

  /// 最新的在最前面。
  List<LogEntry> get logs => List.unmodifiable(_logs);

  Future<void> load() async {
    final loaded = await _storage.loadLogs();
    _logs
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  Future<void> add(LogEntry entry) async {
    _logs.insert(0, entry);
    if (_logs.length > _maxInMemory) {
      _logs.removeRange(_maxInMemory, _logs.length);
    }
    await _storage.insertLog(entry);
    notifyListeners();
  }

  Future<void> clear() async {
    _logs.clear();
    await _storage.clearLogs();
    notifyListeners();
  }
}
