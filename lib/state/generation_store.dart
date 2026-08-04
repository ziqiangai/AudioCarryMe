import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging/app_log.dart';
import '../models/generation_task.dart';
import '../models/model_catalog.dart';
import '../services/ppio_config.dart';
import '../services/ppio_service.dart';
import '../storage/chat_storage.dart';

/// 生成任务状态管理：创建 → 提交 PPIO → 轮询 → 落库。
///
/// 恢复语义：App 切出 / 假死 / 被杀后回来，调用 [recover]，
/// 对所有 needsRecovery 的任务凭 ppioTaskId 重新起轮询；
/// 没有 ppioTaskId 的 submitting 任务视为提交失败。
class GenerationStore extends ChangeNotifier {
  GenerationStore(this._ppio, this._storage,
      {Duration? pollInterval})
      : _pollInterval = pollInterval ?? PpioConfig.pollInterval;

  final PpioService _ppio;
  final ChatStorage _storage;
  final Duration _pollInterval;
  final Map<String, GenerationTask> _tasks = {};
  final Set<String> _polling = {}; // 防止同一任务起多个轮询循环

  int _seq = 0;
  String newTaskId() =>
      'gen-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  GenerationTask? byId(String id) => _tasks[id];

  /// 全部任务，最新发起的在最前。
  List<GenerationTask> get all {
    final list = _tasks.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// 启动时加载 + 恢复轮询。
  Future<void> load() async {
    final loaded = await _storage.loadGenerationTasks();
    _tasks
      ..clear()
      ..addEntries(loaded.map((t) => MapEntry(t.id, t)));
    notifyListeners();
    await recover();
  }

  /// 对非终态任务恢复轮询（App 回前台也调用）。
  Future<void> recover() async {
    for (final t in _tasks.values) {
      if (!t.status.needsRecovery || _polling.contains(t.id)) continue;
      if (t.ppioTaskId != null) {
        AppLog.i('gen', '恢复轮询 ${t.id}（ppio=${t.ppioTaskId}）');
        unawaited(_pollLoop(t));
      } else {
        // 提交中但没拿到远端 id：无从恢复，判失败。
        await _update(t, (t) {
          t.status = GenTaskStatus.failed;
          t.error = '提交中断（App 退出），请重试';
        });
      }
    }
  }

  /// 创建任务并提交。返回任务（气泡据此渲染）。
  Future<GenerationTask> start({
    required String conversationId,
    required GenKind kind,
    required String modelId,
    required String prompt,
    required Map<String, String> params,
    String? id,
  }) async {
    final task = GenerationTask(
      id: id ?? newTaskId(),
      conversationId: conversationId,
      kind: kind,
      modelId: modelId,
      prompt: prompt,
      params: params,
      status: GenTaskStatus.submitting,
    );
    _tasks[task.id] = task;
    await _storage.upsertGenerationTask(task);
    notifyListeners();
    unawaited(_submit(task));
    return task;
  }

  /// 「再生一张」：以旧任务同参数新建并提交。
  Future<GenerationTask> regenerate(GenerationTask old) => start(
        conversationId: old.conversationId,
        kind: old.kind,
        modelId: old.modelId,
        prompt: old.prompt,
        params: Map.of(old.params),
      );

  /// 失败重试（同一个任务原地重提交）。
  Future<void> retry(GenerationTask task) async {
    await _update(task, (t) {
      t.status = GenTaskStatus.submitting;
      t.error = null;
      t.ppioTaskId = null;
      t.resultUrls = [];
    });
    unawaited(_submit(task));
  }

  Future<void> _submit(GenerationTask task) async {
    try {
      final result = await _ppio.submit(task);
      if (result.isSync) {
        await _update(task, (t) {
          t.status = GenTaskStatus.succeeded;
          t.resultUrls = result.urls!;
        });
        AppLog.i('gen', '任务 ${task.id} 同步完成 ${result.urls!.length} 个产物');
        return;
      }
      await _update(task, (t) {
        t.ppioTaskId = result.ppioTaskId;
        t.status = GenTaskStatus.queued;
      });
      unawaited(_pollLoop(task));
    } catch (e) {
      AppLog.e('gen', '任务 ${task.id} 提交失败：$e');
      await _update(task, (t) {
        t.status = GenTaskStatus.failed;
        t.error = e.toString();
      });
    }
  }

  Future<void> _pollLoop(GenerationTask task) async {
    final remoteId = task.ppioTaskId;
    if (remoteId == null || _polling.contains(task.id)) return;
    _polling.add(task.id);
    try {
      for (var i = 0; i < PpioConfig.maxPollAttempts; i++) {
        await Future.delayed(_pollInterval);
        // 任务可能已被其他路径终结（如恢复时判失败）。
        if (task.status.isTerminal) return;

        final r = await _ppio.pollOnce(remoteId, modelId: task.modelId);
        switch (r.status) {
          case PpioPollStatus.running:
            if (task.status != GenTaskStatus.processing) {
              await _update(task, (t) => t.status = GenTaskStatus.processing);
            }
          case PpioPollStatus.succeeded:
            await _update(task, (t) {
              t.status = GenTaskStatus.succeeded;
              t.resultUrls = r.urls;
            });
            AppLog.i('gen', '任务 ${task.id} 完成，${r.urls.length} 个产物');
            return;
          case PpioPollStatus.failed:
            await _update(task, (t) {
              t.status = GenTaskStatus.failed;
              t.error = r.error ?? '生成失败';
            });
            AppLog.w('gen', '任务 ${task.id} 失败：${r.error}');
            return;
        }
      }
      await _update(task, (t) {
        t.status = GenTaskStatus.failed;
        t.error = '轮询超时';
      });
    } finally {
      _polling.remove(task.id);
    }
  }

  Future<void> _update(
      GenerationTask task, void Function(GenerationTask) mutate) async {
    mutate(task);
    task.updatedAt = DateTime.now();
    await _storage.upsertGenerationTask(task);
    notifyListeners();
  }
}
