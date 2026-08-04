import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:carry_me/models/generation_task.dart';
import 'package:carry_me/models/model_catalog.dart';
import 'package:carry_me/services/ppio_service.dart';

GenerationTask task(String modelId, GenKind kind, Map<String, String> params) =>
    GenerationTask(
      id: 't',
      conversationId: 'c',
      kind: kind,
      modelId: modelId,
      prompt: 'a cat',
      params: params,
    );

void main() {
  group('buildRequest 各模型族坑位', () {
    final svc = PpioService(client: MockClient((_) async => http.Response('', 500)));

    test('seedream 同步端点与字段', () {
      final (path, body, isSync) = svc.buildRequest(task(
          'seedream-5.0-lite', GenKind.image,
          {'size': '2048x2048', 'watermark': 'false'}));
      expect(path, '/seedream-5.0-lite');
      expect(isSync, isTrue);
      expect(body['size'], '2048x2048');
      expect(body['watermark'], false);
    });

    test('gpt-image-2 固定 n=1 moderation=low', () {
      final (path, body, isSync) = svc.buildRequest(
          task('gpt-image-2', GenKind.image, {'quality': 'high'}));
      expect(path, '/gpt-image-2-text-to-image');
      expect(isSync, isTrue);
      expect(body['n'], 1);
      expect(body['moderation'], 'low');
      expect(body['quality'], 'high');
    });

    test('qwen size 用星号分隔', () {
      final (path, body, isSync) =
          svc.buildRequest(task('qwen-image', GenKind.image, {'size': '1024x1024'}));
      expect(path, '/async/qwen-image-txt2img');
      expect(isSync, isFalse);
      expect(body['size'], '1024*1024');
    });

    test('kling t2v：duration int、sound bool、负面提示词', () {
      final (path, body, _) = svc.buildRequest(task(
          'kling-v3.0-pro', GenKind.video, {
        'duration': '10',
        'aspectRatio': '9:16',
        'audio': 'false',
        'negativePrompt': '模糊',
      }));
      expect(path, '/async/kling-v3.0-pro-t2v');
      expect(body['duration'], 10);
      expect(body['sound'], false);
      expect(body['aspect_ratio'], '9:16');
      expect(body['negative_prompt'], '模糊');
    });

    test('hailuo：resolution 大写；1080P 强制 6 秒', () {
      final (_, body, _) = svc.buildRequest(task(
          'minimax-hailuo-2.3', GenKind.video,
          {'duration': '10', 'resolution': '1080p'}));
      expect(body['resolution'], '1080P');
      expect(body['duration'], 6); // 被钳制
    });

    test('veo：generate_audio 必填、duration_seconds 字段名', () {
      final (path, body, _) = svc.buildRequest(task('veo-3.1', GenKind.video,
          {'duration': '8', 'resolution': '720p', 'aspectRatio': '16:9'}));
      expect(path, '/async/veo-3.1-generate-text2video');
      expect(body['generate_audio'], true); // 未显式关闭 → true
      expect(body['duration_seconds'], 8);
    });

    test('resolveSize：档位×宽高比 → 具体像素（16 对齐、面积守恒）', () {
      expect(PpioService.resolveSize('2048x2048', null), '2048x2048');
      expect(PpioService.resolveSize('2048x2048', '1:1'), '2048x2048');
      expect(PpioService.resolveSize('2048x2048', '16:9'), '2736x1536');
      expect(PpioService.resolveSize('2048x2048', '9:16'), '1536x2736');
      expect(PpioService.resolveSize('1024x1024', '4:3'), '1184x880');
      // 宽高比换算后仍是合法整数尺寸
      final wh = PpioService.resolveSize('3072x3072', '16:9').split('x');
      expect(int.parse(wh[0]) % 16, 0);
      expect(int.parse(wh[1]) % 16, 0);
    });

    test('gpt 经典固定尺寸映射', () {
      expect(PpioService.gptSizeFor(null), '1024x1024');
      expect(PpioService.gptSizeFor('3:2'), '1536x1024');
      expect(PpioService.gptSizeFor('2:3'), '1024x1536');
    });

    test('参考图：kling 切 i2v 端点、带 image、不传 aspect_ratio', () {
      final (path, body, _) = svc.buildRequest(task(
          'kling-v3.0-std', GenKind.video, {
        'duration': '5',
        'aspectRatio': '16:9',
        'imageUrl': 'https://x/ref.png',
      }));
      expect(path, '/async/kling-v3.0-std-i2v');
      expect(body['image'], 'https://x/ref.png');
      expect(body.containsKey('aspect_ratio'), isFalse); // 跟随首帧
    });

    test('参考图：veo 切 img2video、hailuo 切 i2v、seedream 带 image 数组', () {
      final (vPath, vBody, _) = svc.buildRequest(task('veo-3.1', GenKind.video,
          {'imageUrl': 'https://x/r.png', 'resolution': '720p'}));
      expect(vPath, '/async/veo-3.1-generate-img2video');
      expect(vBody['image'], 'https://x/r.png');

      final (hPath, _, _) = svc.buildRequest(task(
          'minimax-hailuo-2.3', GenKind.video, {'imageUrl': 'https://x/r.png'}));
      expect(hPath, '/async/minimax-hailuo-2.3-i2v');

      final (sPath, sBody, _) = svc.buildRequest(task(
          'seedream-5.0-lite', GenKind.image, {'imageUrl': 'https://x/r.png'}));
      expect(sPath, '/seedream-5.0-lite');
      expect(sBody['image'], ['https://x/r.png']);

      final (gPath, gBody, _) = svc.buildRequest(task(
          'gpt-image-2', GenKind.image, {'imageUrl': 'https://x/r.png'}));
      expect(gPath, '/gpt-image-2-edit');
      expect(gBody['image'], ['https://x/r.png']);
    });

    test('seedance：Ark 根字段 + content 数组；i2v 加 image_url 且 ratio=adaptive', () {
      final t2v = PpioService.buildSeedanceBody(task(
          'seedance-2.0', GenKind.video,
          {'duration': '5', 'resolution': '720p', 'aspectRatio': '9:16'}));
      expect(t2v['model'], 'doubao-seedance-2-0-260128');
      expect(t2v['ratio'], '9:16');
      expect(t2v['duration'], 5);
      expect(t2v['resolution'], '720p');
      expect((t2v['content'] as List).single['type'], 'text');

      final i2v = PpioService.buildSeedanceBody(task(
          'seedance-2.0-fast', GenKind.video,
          {'imageUrl': 'https://x/f.png', 'aspectRatio': '16:9'}));
      expect(i2v['model'], 'doubao-seedance-2-0-fast-260128');
      expect(i2v['ratio'], 'adaptive'); // 跟随参考图
      final content = i2v['content'] as List;
      expect(content, hasLength(2));
      expect(content[1]['image_url']['url'], 'https://x/f.png');
      expect(content[1].containsKey('role'), isFalse); // i2v 裸 image_url
    });

    test('目录里的每个模型 buildRequest 都不抛异常（目录/服务一致性）', () {
      for (final m in [...ModelCatalog.imageModels, ...ModelCatalog.videoModels]) {
        final params = ModelCatalog.defaultsFor(m)
            .map((k, v) => MapEntry(k.name, v));
        expect(() => svc.buildRequest(task(m.id, m.kind, params)), returnsNormally,
            reason: '${m.id} 构造请求失败');
      }
    });
  });

  group('submit', () {
    test('同步模型直接返回 urls', () async {
      final svc = PpioService(
          client: MockClient((req) async {
        expect(req.url.path, endsWith('/seedream-5.0-lite'));
        expect(req.headers['authorization'], startsWith('Bearer '));
        return http.Response(
            jsonEncode({'images': ['https://x/1.png', {'url': 'https://x/2.png'}]}),
            200);
      }));
      final r = await svc.submit(task('seedream-5.0-lite', GenKind.image, {}));
      expect(r.isSync, isTrue);
      expect(r.urls, ['https://x/1.png', 'https://x/2.png']);
    });

    test('异步模型返回 task_id', () async {
      final svc = PpioService(
          client: MockClient((_) async =>
              http.Response(jsonEncode({'task_id': 'abc'}), 200)));
      final r = await svc.submit(task('kling-v3.0-std', GenKind.video, {}));
      expect(r.isSync, isFalse);
      expect(r.ppioTaskId, 'abc');
    });

    test('非 200 抛异常', () async {
      final svc = PpioService(
          client: MockClient((_) async => http.Response('{"error":"bad"}', 400)));
      expect(svc.submit(task('kling-v3.0-std', GenKind.video, {})),
          throwsA(isA<Exception>()));
    });
  });

  group('seedance 提交与轮询（Ark 协议）', () {
    test('提交走 novita bytedance、返回 {id}', () async {
      final svc = PpioService(client: MockClient((req) async {
        expect(req.url.host, 'api.novita.ai');
        expect(req.url.path, endsWith('/contents/generations/tasks'));
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['model'], startsWith('doubao-seedance'));
        return http.Response(jsonEncode({'id': 'ark-1'}), 200);
      }));
      final r = await svc.submit(task('seedance-2.0', GenKind.video, {}));
      expect(r.ppioTaskId, 'ark-1');
    });

    test('轮询映射：succeeded→video_url；running；failed 带 error', () async {
      Future<PpioPollResult> poll(Map<String, dynamic> data) async {
        final svc = PpioService(client: MockClient((req) async {
          expect(req.url.path, endsWith('/contents/generations/tasks/ark-1'));
          return http.Response.bytes(utf8.encode(jsonEncode(data)), 200);
        }));
        return svc.pollOnce('ark-1', modelId: 'seedance-2.0');
      }

      final ok = await poll({
        'status': 'succeeded',
        'content': {'video_url': 'https://x/v.mp4'}
      });
      expect(ok.status, PpioPollStatus.succeeded);
      expect(ok.urls, ['https://x/v.mp4']);

      for (final s in ['queued', 'running', 'processing']) {
        expect((await poll({'status': s})).status, PpioPollStatus.running);
      }

      final bad = await poll({
        'status': 'failed',
        'error': {'message': '内容不合规'}
      });
      expect(bad.status, PpioPollStatus.failed);
      expect(bad.error, '内容不合规');
      // expired fail-closed
      expect((await poll({'status': 'expired'})).status, PpioPollStatus.failed);
    });
  });

  group('pollOnce', () {
    PpioService withResp(Map<String, dynamic> data, [int code = 200]) =>
        PpioService(
            client: MockClient((req) async {
          expect(req.url.path, endsWith('/async/task-result'));
          expect(req.url.queryParameters['task_id'], 'abc');
          // 用 bytes 构造，避免默认 latin1 编不了中文。
          return http.Response.bytes(utf8.encode(jsonEncode(data)), code);
        }));

    test('成功：图片结果', () async {
      final r = await withResp({
        'task': {'status': 'TASK_STATUS_SUCCEED'},
        'images': [{'image_url': 'https://x/a.png'}],
      }).pollOnce('abc');
      expect(r.status, PpioPollStatus.succeeded);
      expect(r.urls, ['https://x/a.png']);
    });

    test('成功：视频结果 videos[].video_url', () async {
      final r = await withResp({
        'task': {'status': 'TASK_STATUS_SUCCEED'},
        'videos': [{'video_url': 'https://x/a.mp4'}],
      }).pollOnce('abc');
      expect(r.status, PpioPollStatus.succeeded);
      expect(r.urls, ['https://x/a.mp4']);
    });

    test('进行中与 UNKNOWN 都算 running', () async {
      for (final s in ['TASK_STATUS_QUEUED', 'TASK_STATUS_PROCESSING', 'TASK_STATUS_UNKNOWN']) {
        final r = await withResp({'task': {'status': s}}).pollOnce('abc');
        expect(r.status, PpioPollStatus.running, reason: s);
      }
    });

    test('失败带 reason；5xx 视为 running 交上层兜底', () async {
      final f = await withResp({
        'task': {'status': 'TASK_STATUS_FAILED', 'reason': '内容审核未通过'},
      }).pollOnce('abc');
      expect(f.status, PpioPollStatus.failed);
      expect(f.error, '内容审核未通过');

      final r = await withResp({}, 502).pollOnce('abc');
      expect(r.status, PpioPollStatus.running);
    });
  });
}
