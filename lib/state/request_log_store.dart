import 'package:flutter/foundation.dart';

import '../models/request_log.dart';
import '../storage/chat_storage.dart';

/// 大模型请求记录状态。持有全部记录（最新在前），并持久化。
class RequestLogStore extends ChangeNotifier {
  RequestLogStore(this._storage);

  final ChatStorage _storage;
  final List<RequestLog> _logs = [];

  /// 最新的在最前面。
  List<RequestLog> get logs => List.unmodifiable(_logs);

  Future<void> load() async {
    final loaded = await _storage.loadRequestLogs();
    _logs
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  Future<void> add(RequestLog log) async {
    _logs.insert(0, log);
    await _storage.insertRequestLog(log);
    notifyListeners();
  }
}
