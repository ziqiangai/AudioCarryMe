import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging/app_log.dart';
import '../models/generation_task.dart';
import '../models/model_catalog.dart';
import '../services/media_cache.dart';
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
      {Duration? pollInterval, MediaCache? mediaCache})
      : _pollInterval = pollInterval ?? PpioConfig.pollInterval,
        // ignore: prefer_initializing_formals
        _mediaCache = mediaCache;

  final PpioService _ppio;
  final ChatStorage _storage;
  final Duration _pollInterval;

  /// 产物本地缓存（PPIO 链接会过期）；测试可不注入。
  final MediaCache? _mediaCache;
  final Map<String, GenerationTask> _tasks = {};
  final Set<String> _polling = {}; // 防止同一任务起多个轮询循环
  final Set<String> _inFlight = {}; // 提交请求飞行中（本会话内），recover 跳过

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
      if (!t.status.needsRecovery ||
          _polling.contains(t.id) ||
          _inFlight.contains(t.id)) {
        continue; // 本会话请求仍在飞行中，勿误判为中断
      }
      if (t.ppioTaskId != null) {
        AppLog.i('gen', '恢复轮询 ${t.id}（ppio=${t.ppioTaskId}）');
        unawaited(_pollLoop(t));
      } else if (t.kind == GenKind.image) {
        // 同步生图无远端 id 可续查；图片便宜，自动重新提交，体验无感。
        AppLog.i('gen', '恢复：自动重提交生图任务 ${t.id}');
        unawaited(_submit(t));
      } else {
        // 视频较贵：不自动重提交（原任务可能已在远端计费执行），交用户决定。
        await _update(t, (t) {
          t.status = GenTaskStatus.failed;
          t.error = '提交在完成前被中断（App 退出）。为避免重复扣费未自动重试，'
              '可点「重试」重新提交';
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
    _inFlight.add(task.id);
    try {
      final result = await _ppio.submit(task);
      if (result.isSync) {
        await _update(task, (t) {
          t.status = GenTaskStatus.succeeded;
          t.resultUrls = result.urls!;
          t.traceId = result.traceId ?? t.traceId;
        });
        AppLog.i('gen', '任务 ${task.id} 同步完成 ${result.urls!.length} 个产物');
        return;
      }
      await _update(task, (t) {
        t.ppioTaskId = result.ppioTaskId;
        t.status = GenTaskStatus.queued;
        t.traceId = result.traceId ?? t.traceId;
      });
      unawaited(_pollLoop(task));
    } catch (e) {
      AppLog.e('gen', '任务 ${task.id} 提交失败：$e');
      await _update(task, (t) {
        t.status = GenTaskStatus.failed;
        t.error = e.toString();
        if (e is PpioException && e.traceId != null) t.traceId = e.traceId;
      });
    } finally {
      _inFlight.remove(task.id);
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
              t.traceId = r.traceId ?? t.traceId;
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

  final Set<String> _downloading = {};

  /// 任务是否正在下载产物。
  bool isDownloading(String taskId) => _downloading.contains(taskId);

  /// 任务产物是否已全部缓存到本地。
  static bool isFullyCached(GenerationTask task) =>
      task.resultUrls.isNotEmpty &&
      task.localPaths.where((p) => p.isNotEmpty).length >=
          task.resultUrls.length;

  /// 用户主动下载任务产物到本地（幂等：已缓存下标跳过）。
  /// 返回是否全部成功。
  Future<bool> downloadMedia(GenerationTask task) async {
    final cache = _mediaCache;
    if (cache == null || _downloading.contains(task.id)) return false;
    _downloading.add(task.id);
    notifyListeners();
    try {
      final paths = List<String>.generate(
          task.resultUrls.length,
          (i) => i < task.localPaths.length ? task.localPaths[i] : '');
      var changed = false;
      for (var i = 0; i < task.resultUrls.length; i++) {
        if (paths[i].isNotEmpty) continue;
        final local =
            await cache.download(task.resultUrls[i], '${task.id}_$i');
        if (local != null) {
          paths[i] = local;
          changed = true;
        }
      }
      if (changed) {
        await _update(task, (t) => t.localPaths = paths);
      }
      return isFullyCached(task);
    } finally {
      _downloading.remove(task.id);
      notifyListeners();
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
