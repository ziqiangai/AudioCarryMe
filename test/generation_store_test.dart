import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:carry_me/models/generation_task.dart';
import 'package:carry_me/models/model_catalog.dart';
import 'package:carry_me/services/media_cache.dart';
import 'package:carry_me/services/ppio_service.dart';
import 'package:carry_me/state/generation_store.dart';
import 'package:carry_me/storage/chat_storage.dart';

/// 假封面生成：不碰原生插件，直接返回一个约定路径。
class FakeMediaCache extends MediaCache {
  int coverCalls = 0;
  @override
  Future<String?> generateCover(String videoSource, String stem) async {
    coverCalls++;
    return '/covers/$stem.jpg';
  }
}

/// 记录 upsert 的内存 storage，兼作断言。
class RecordingStorage extends NoopChatStorage {
  final List<GenerationTask> preloaded = [];
  final List<String> upserts = [];

  @override
  Future<List<GenerationTask>> loadGenerationTasks() async => preloaded;

  @override
  Future<void> upsertGenerationTask(GenerationTask task) async {
    upserts.add('${task.id}:${task.status.name}');
  }
}

http.Response _json(Map<String, dynamic> data, [int code = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), code);

Future<void> pump([int ms = 50]) =>
    Future.delayed(Duration(milliseconds: ms));

void main() {
  test('同步模型：start 后直接 succeeded 且落库', () async {
    final storage = RecordingStorage();
    final ppio = PpioService(
        client: MockClient((_) async => _json({
              'images': ['https://x/1.png']
            })));
    final store = GenerationStore(ppio, storage,
        pollInterval: const Duration(milliseconds: 1));

    final t = await store.start(
      conversationId: 'c1',
      kind: GenKind.image,
      modelId: 'seedream-5.0-lite',
      prompt: 'cat',
      params: {'size': '2048x2048'},
    );
    await pump();
    expect(t.status, GenTaskStatus.succeeded);
    expect(t.resultUrls, ['https://x/1.png']);
    expect(storage.upserts.last, '${t.id}:succeeded');
  });

  test('异步模型：queued → processing → succeeded 全链路', () async {
    final storage = RecordingStorage();
    var polls = 0;
    final ppio = PpioService(client: MockClient((req) async {
      if (req.method == 'POST') return _json({'task_id': 'r1'});
      polls++;
      if (polls < 2) {
        return _json({'task': {'status': 'TASK_STATUS_PROCESSING'}});
      }
      return _json({
        'task': {'status': 'TASK_STATUS_SUCCEED'},
        'videos': [{'video_url': 'https://x/v.mp4'}],
      });
    }));
    final store = GenerationStore(ppio, storage,
        pollInterval: const Duration(milliseconds: 5));

    final t = await store.start(
      conversationId: 'c1',
      kind: GenKind.video,
      modelId: 'kling-v3.0-std',
      prompt: 'sea',
      params: {'duration': '5'},
    );
    await pump(200);
    expect(t.status, GenTaskStatus.succeeded);
    expect(t.resultUrls, ['https://x/v.mp4']);
    // 状态流转按序落库
    final seq = storage.upserts.where((s) => s.startsWith(t.id)).toList();
    expect(seq.first, endsWith('submitting'));
    expect(seq, contains('${t.id}:queued'));
    expect(seq.last, endsWith('succeeded'));
  });

  test('视频成功后自动生成第一帧封面并落库', () async {
    final storage = RecordingStorage();
    var polls = 0;
    final ppio = PpioService(client: MockClient((req) async {
      if (req.method == 'POST') return _json({'task_id': 'r1'});
      polls++;
      return _json({
        'task': {'status': 'TASK_STATUS_SUCCEED'},
        'videos': [{'video_url': 'https://x/v.mp4'}],
      });
    }));
    final cache = FakeMediaCache();
    final store = GenerationStore(ppio, storage,
        pollInterval: const Duration(milliseconds: 5), mediaCache: cache);

    final t = await store.start(
      conversationId: 'c1',
      kind: GenKind.video,
      modelId: 'kling-v3.0-std',
      prompt: 'sea',
      params: {'duration': '5'},
    );
    await pump(200);
    expect(t.status, GenTaskStatus.succeeded);
    expect(cache.coverCalls, 1);
    expect(t.coverPath, '/covers/${t.id}_cover.jpg');
    expect(polls, greaterThan(0));
  });

  test('提交失败 → failed 带错误', () async {
    final storage = RecordingStorage();
    final ppio = PpioService(
        client: MockClient((_) async => _json({'error': 'quota'}, 429)));
    final store = GenerationStore(ppio, storage,
        pollInterval: const Duration(milliseconds: 1));

    final t = await store.start(
      conversationId: 'c1',
      kind: GenKind.image,
      modelId: 'seedream-4.5',
      prompt: 'x',
      params: {},
    );
    await pump();
    expect(t.status, GenTaskStatus.failed);
    expect(t.error, contains('429'));
  });

  test('恢复：有 ppioTaskId 的 processing 任务重启轮询并完成', () async {
    final storage = RecordingStorage();
    storage.preloaded.add(GenerationTask(
      id: 'old1',
      conversationId: 'c1',
      kind: GenKind.video,
      modelId: 'veo-3.1',
      prompt: 'x',
      params: {},
      status: GenTaskStatus.processing,
      ppioTaskId: 'r9',
    ));
    final ppio = PpioService(client: MockClient((req) async {
      expect(req.method, 'GET'); // 恢复只应查询，不应重复提交
      return _json({
        'task': {'status': 'TASK_STATUS_SUCCEED'},
        'videos': [{'video_url': 'https://x/v.mp4'}],
      });
    }));
    final store = GenerationStore(ppio, storage,
        pollInterval: const Duration(milliseconds: 5));

    await store.load();
    await pump(100);
    expect(store.byId('old1')!.status, GenTaskStatus.succeeded);
  });

  test('恢复：submitting 无 id 的生图 → 自动重提交并完成', () async {
    final storage = RecordingStorage();
    storage.preloaded.add(GenerationTask(
      id: 'old2',
      conversationId: 'c1',
      kind: GenKind.image,
      modelId: 'seedream-4.5',
      prompt: 'x',
      params: {},
      status: GenTaskStatus.submitting,
    ));
    final store = GenerationStore(
        PpioService(
            client: MockClient((_) async => _json({
                  'images': ['https://x/auto.png']
                }))),
        storage,
        pollInterval: const Duration(milliseconds: 1));

    await store.load();
    await pump(100);
    final t = store.byId('old2')!;
    expect(t.status, GenTaskStatus.succeeded); // 无感恢复
    expect(t.resultUrls, ['https://x/auto.png']);
  });

  test('恢复：submitting 无 id 的视频 → 判失败提示手动重试（防重复扣费）', () async {
    final storage = RecordingStorage();
    storage.preloaded.add(GenerationTask(
      id: 'old3',
      conversationId: 'c1',
      kind: GenKind.video,
      modelId: 'kling-v3.0-std',
      prompt: 'x',
      params: {},
      status: GenTaskStatus.submitting,
    ));
    final store = GenerationStore(
        PpioService(client: MockClient((_) async => _json({}))), storage,
        pollInterval: const Duration(milliseconds: 1));

    await store.load();
    await pump();
    final t = store.byId('old3')!;
    expect(t.status, GenTaskStatus.failed);
    expect(t.error, contains('重试'));
  });

  test('血缘：findImageByLabel 找到同会话同标签最新成功图', () async {
    final storage = RecordingStorage();
    final ppio = PpioService(
        client: MockClient((_) async => _json({
              'images': ['https://x/s1.png']
            })));
    final store = GenerationStore(ppio, storage,
        pollInterval: const Duration(milliseconds: 1));

    final t1 = await store.start(
      conversationId: 'c1',
      kind: GenKind.image,
      modelId: 'seedream-5.0-lite',
      prompt: '场景一的画面',
      params: {},
      label: '场景1',
    );
    await pump();
    expect(t1.status, GenTaskStatus.succeeded);

    // ref_label 解析：命中
    final found = store.findImageByLabel('c1', '场景1');
    expect(found, isNotNull);
    expect(found!.id, t1.id);
    // 其他会话/标签不命中
    expect(store.findImageByLabel('c2', '场景1'), isNull);
    expect(store.findImageByLabel('c1', '场景2'), isNull);

    // 视频任务带血缘
    final v = await store.start(
      conversationId: 'c1',
      kind: GenKind.video,
      modelId: 'kling-v3.0-std',
      prompt: '场景一的画面',
      params: {'imageUrl': found.resultUrls.first},
      label: '场景1',
      parentTaskId: found.id,
    );
    expect(v.parentTaskId, t1.id);
    expect(v.label, '场景1');
  });

  test('regenerate 用同参数新建任务', () async {
    final storage = RecordingStorage();
    final ppio = PpioService(
        client: MockClient((_) async => _json({
              'images': ['https://x/2.png']
            })));
    final store = GenerationStore(ppio, storage,
        pollInterval: const Duration(milliseconds: 1));

    final t1 = await store.start(
      conversationId: 'c1',
      kind: GenKind.image,
      modelId: 'seedream-5.0-lite',
      prompt: 'cat',
      params: {'size': '3072x3072'},
    );
    await pump();
    final t2 = await store.regenerate(t1);
    await pump();
    expect(t2.id, isNot(t1.id));
    expect(t2.modelId, t1.modelId);
    expect(t2.prompt, t1.prompt);
    expect(t2.params, t1.params);
    expect(t2.status, GenTaskStatus.succeeded);
  });
}
