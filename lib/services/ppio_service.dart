import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../logging/app_log.dart';
import '../models/generation_task.dart';
import '../models/model_catalog.dart';
import 'ppio_config.dart';

/// 提交结果：同步模型直接给 urls；异步模型给 ppioTaskId。
class PpioSubmitResult {
  final List<String>? urls; // 同步完成
  final String? ppioTaskId; // 异步任务
  final String? traceId; // 供应商 x-trace-id，反馈问题用
  const PpioSubmitResult.sync(this.urls, {this.traceId}) : ppioTaskId = null;
  const PpioSubmitResult.async(this.ppioTaskId, {this.traceId}) : urls = null;
  bool get isSync => urls != null;
}

/// 提交失败异常：带 traceId 便于反馈供应商。
class PpioException implements Exception {
  final String message;
  final String? traceId;
  const PpioException(this.message, {this.traceId});
  @override
  String toString() =>
      traceId == null ? message : '$message\ntrace: $traceId';
}

/// 轮询结果。
enum PpioPollStatus { running, succeeded, failed }

class PpioPollResult {
  final PpioPollStatus status;
  final List<String> urls;
  final String? error;
  final String? traceId;
  const PpioPollResult(this.status,
      {this.urls = const [], this.error, this.traceId});
}

/// PPIO 生成服务：按模型族构造请求体（含各家的坑），统一轮询。
///
/// 坑位清单（源码核实，见 docs/aigc-models-inventory.md）：
/// - qwen 的 size 用 `*` 分隔（1024*1024）
/// - Hailuo resolution 必须大写；1080P 仅支持 6 秒
/// - Veo 必须带 generate_audio；resolution 仅 720p/1080p
/// - gpt-image-2 固定 n=1、moderation=low
class PpioService {
  PpioService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'authorization': 'Bearer ${PpioConfig.apiKey}',
      };

  /// Seedance 走 PPIO 的 bytedance 代理（Ark 协议），与 PPIO 标准异步不同。
  static bool isSeedance(String modelId) => modelId.startsWith('seedance');

  /// 提交一个任务。抛异常 = 提交失败。
  Future<PpioSubmitResult> submit(GenerationTask task) async {
    if (isSeedance(task.modelId)) return _submitSeedance(task);

    final (path, body, isSync) = buildRequest(task);
    AppLog.i('ppio', '提交 ${task.modelId} → $path');

    final resp = await _client.post(
      Uri.parse('${PpioConfig.baseUrl}$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final trace = resp.headers['x-trace-id'];
    final text = utf8.decode(resp.bodyBytes);
    if (resp.statusCode != 200) {
      throw PpioException('PPIO ${resp.statusCode}：$text', traceId: trace);
    }
    final data = jsonDecode(text) as Map<String, dynamic>;

    if (isSync) {
      final urls = extractImageUrls(data);
      if (urls.isEmpty) {
        throw PpioException('PPIO 同步返回无图片：$text', traceId: trace);
      }
      return PpioSubmitResult.sync(urls, traceId: trace);
    }
    final taskId = data['task_id'] as String?;
    if (taskId == null || taskId.isEmpty) {
      throw PpioException('PPIO 未返回 task_id：$text', traceId: trace);
    }
    return PpioSubmitResult.async(taskId, traceId: trace);
  }

  /// Seedance 提交：POST /contents/generations/tasks → { id }。
  Future<PpioSubmitResult> _submitSeedance(GenerationTask task) async {
    final body = buildSeedanceBody(task);
    AppLog.i('ppio', '提交 ${task.modelId}（Ark）');
    final resp = await _client.post(
      Uri.parse(
          '${PpioConfig.bytedanceBaseUrl}/contents/generations/tasks'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final trace = resp.headers['x-trace-id'];
    final text = utf8.decode(resp.bodyBytes);
    if (resp.statusCode != 200) {
      throw PpioException('Seedance ${resp.statusCode}：$text', traceId: trace);
    }
    final id = (jsonDecode(text) as Map<String, dynamic>)['id'] as String?;
    if (id == null || id.isEmpty) {
      throw PpioException('Seedance 未返回 id：$text', traceId: trace);
    }
    return PpioSubmitResult.async(id, traceId: trace);
  }

  /// 查询一次任务状态。[modelId] 用于路由协议（Seedance 走 Ark）。
  Future<PpioPollResult> pollOnce(String ppioTaskId,
      {String modelId = ''}) async {
    if (isSeedance(modelId)) return _pollSeedance(ppioTaskId);
    final resp = await _client.get(
      Uri.parse('${PpioConfig.baseUrl}/async/task-result?task_id=$ppioTaskId'),
      headers: _headers,
    );
    final text = utf8.decode(resp.bodyBytes);
    final trace = resp.headers['x-trace-id'];
    if (resp.statusCode != 200) {
      // 查询接口偶发 5xx 当作仍在进行，交由上层重试/超时兜底。
      return const PpioPollResult(PpioPollStatus.running);
    }
    final data = jsonDecode(text) as Map<String, dynamic>;
    final status =
        ((data['task'] as Map<String, dynamic>?)?['status'] as String?) ?? '';

    switch (status) {
      case 'TASK_STATUS_SUCCEED':
        final urls = [...extractImageUrls(data), ...extractVideoUrls(data)];
        if (urls.isEmpty) {
          return const PpioPollResult(PpioPollStatus.failed,
              error: '任务成功但没有产物');
        }
        return PpioPollResult(PpioPollStatus.succeeded, urls: urls);
      case 'TASK_STATUS_FAILED':
        final reason =
            ((data['task'] as Map<String, dynamic>?)?['reason'] as String?) ??
                '生成失败';
        return PpioPollResult(PpioPollStatus.failed,
            error: reason, traceId: trace);
      case 'TASK_STATUS_QUEUED':
      case 'TASK_STATUS_PROCESSING':
      case 'TASK_STATUS_UNKNOWN': // 新任务短暂 unknown，视为进行中
        return const PpioPollResult(PpioPollStatus.running);
      default:
        return PpioPollResult(PpioPollStatus.failed, error: '未知状态 $status');
    }
  }

  /// Seedance 轮询：GET /contents/generations/tasks/{id}
  /// → { status: queued|running|processing|succeeded|failed|expired,
  ///     content: { video_url }, error }
  Future<PpioPollResult> _pollSeedance(String id) async {
    final resp = await _client.get(
      Uri.parse(
          '${PpioConfig.bytedanceBaseUrl}/contents/generations/tasks/$id'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      // 状态接口 4xx 视为任务侧故障（过期等），5xx 视为暂时不可用。
      if (resp.statusCode >= 500) {
        return const PpioPollResult(PpioPollStatus.running);
      }
      return PpioPollResult(PpioPollStatus.failed,
          error: 'Seedance 查询 ${resp.statusCode}');
    }
    final trace = resp.headers['x-trace-id'];
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final status = (data['status'] as String?) ?? '';
    switch (status) {
      case 'succeeded':
        final url = (data['content'] as Map<String, dynamic>?)?['video_url']
            as String?;
        if (url == null || url.isEmpty) {
          return const PpioPollResult(PpioPollStatus.failed,
              error: '任务成功但没有视频');
        }
        return PpioPollResult(PpioPollStatus.succeeded, urls: [url]);
      case 'queued':
      case 'running':
      case 'processing':
        return const PpioPollResult(PpioPollStatus.running);
      default: // failed / expired / 未知 → fail-closed
        final err = (data['error'] as Map<String, dynamic>?)?['message']
                as String? ??
            '生成失败（$status）';
        return PpioPollResult(PpioPollStatus.failed,
            error: err, traceId: trace);
    }
  }

  // ---------- 请求体构造（按模型族） ----------

  /// Seedance（Ark 协议）请求体：
  /// 根字段 model/resolution/ratio/duration/watermark + content 数组。
  /// i2v = content 里追加一个不带 role 的 image_url。
  static Map<String, dynamic> buildSeedanceBody(GenerationTask task) {
    final p = task.params;
    final ref = p['imageUrl'];
    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': task.prompt},
      if (ref != null)
        {
          'type': 'image_url',
          'image_url': {'url': ref},
        },
    ];
    return {
      'model': task.modelId == 'seedance-2.0-fast'
          ? 'doubao-seedance-2-0-fast-260128'
          : 'doubao-seedance-2-0-260128',
      'content': content,
      if (p['resolution'] != null) 'resolution': p['resolution'],
      // i2v 跟随参考图比例（adaptive），t2v 用所选宽高比。
      'ratio': ref != null ? 'adaptive' : (p['aspectRatio'] ?? '16:9'),
      if (p['duration'] != null) 'duration': int.parse(p['duration']!),
      'watermark': p['watermark'] == 'true',
    };
  }

  /// 把「size 档位（正方形基准）× 宽高比」换算成具体像素 `WxH`。
  /// 保持面积与基准档位相当，边长对齐到 16 的倍数。
  static String resolveSize(String baseSize, String? aspectRatio) {
    final side = int.tryParse(baseSize.split('x').first) ?? 2048;
    final ar = aspectRatio ?? '1:1';
    if (ar == '1:1') return '${side}x$side';
    final parts = ar.split(':');
    final w = double.parse(parts[0]), h = double.parse(parts[1]);
    final scale = side / math.sqrt(w * h);
    int align16(double v) => ((v / 16).round() * 16).clamp(256, 6144);
    return '${align16(w * scale)}x${align16(h * scale)}';
  }

  /// GPT Image 2 的经典固定尺寸。
  static String gptSizeFor(String? aspectRatio) => switch (aspectRatio) {
        '3:2' => '1536x1024',
        '2:3' => '1024x1536',
        _ => '1024x1024',
      };

  /// 返回 (端点路径, 请求体, 是否同步)。
  /// 暴露为公开方法便于单测校验各家坑位。
  /// 参考图（图生图/图生视频）：task.params['imageUrl']。
  (String, Map<String, dynamic>, bool) buildRequest(GenerationTask task) {
    final p = task.params;
    final ref = p['imageUrl'];
    switch (task.modelId) {
      case 'seedance-2.0':
      case 'seedance-2.0-fast':
        // Ark 协议（实际提交走 _submitSeedance；这里保证目录一致性）。
        return ('/contents/generations/tasks', buildSeedanceBody(task), false);
      case 'seedream-5.0-lite':
      case 'seedream-4.5':
        return (
          '/${task.modelId}',
          {
            'prompt': task.prompt,
            'size': resolveSize(p['size'] ?? '2048x2048', p['aspectRatio']),
            'watermark': p['watermark'] == 'true',
            if (ref != null) 'image': [ref], // 图生图
          },
          true,
        );
      case 'gpt-image-2':
        return (
          ref != null ? '/gpt-image-2-edit' : '/gpt-image-2-text-to-image',
          {
            'prompt': task.prompt,
            'n': 1,
            'moderation': 'low',
            'size': gptSizeFor(p['aspectRatio']),
            if (p['quality'] != null) 'quality': p['quality'],
            if (ref != null) 'image': [ref],
          },
          true,
        );
      case 'qwen-image':
        return (
          '/async/qwen-image-txt2img',
          {
            'prompt': task.prompt,
            // qwen 用 `*` 分隔尺寸；基准 1024，范围 256~1536。
            'size': resolveSize('1024x1024', p['aspectRatio'])
                .replaceAll('x', '*'),
            'watermark': p['watermark'] == 'true',
          },
          false,
        );
      case 'kling-v3.0-pro':
      case 'kling-v3.0-std':
        final mode = ref != null ? 'i2v' : 't2v';
        return (
          '/async/${task.modelId}-$mode',
          {
            'prompt': task.prompt,
            if (p['duration'] != null) 'duration': int.parse(p['duration']!),
            // i2v 跟随首帧比例，不传 aspect_ratio。
            if (ref == null && p['aspectRatio'] != null)
              'aspect_ratio': p['aspectRatio'],
            'image': ?ref,
            if (p['audio'] != null) 'sound': p['audio'] == 'true',
            if ((p['negativePrompt'] ?? '').isNotEmpty)
              'negative_prompt': p['negativePrompt'],
          },
          false,
        );
      case 'minimax-hailuo-2.3':
        final resolution = (p['resolution'] ?? '768P').toUpperCase();
        var duration = int.parse(p['duration'] ?? '6');
        if (resolution == '1080P') duration = 6; // 1080P 仅支持 6s
        final mode = ref != null ? 'i2v' : 't2v';
        return (
          '/async/minimax-hailuo-2.3-$mode',
          {
            'prompt': task.prompt,
            'image': ?ref,
            'duration': duration,
            'resolution': resolution,
            'aigc_watermark': p['watermark'] == 'true',
          },
          false,
        );
      case 'veo-3.1':
        final endpoint = ref != null
            ? '/async/veo-3.1-generate-img2video'
            : '/async/veo-3.1-generate-text2video';
        return (
          endpoint,
          {
            'prompt': task.prompt,
            'generate_audio': p['audio'] != 'false', // PPIO 必填
            'image': ?ref,
            if (p['duration'] != null)
              'duration_seconds': int.parse(p['duration']!),
            // img2video 跟随首帧，不传 aspect_ratio。
            if (ref == null && p['aspectRatio'] != null)
              'aspect_ratio': p['aspectRatio'],
            if (p['resolution'] != null) 'resolution': p['resolution'],
          },
          false,
        );
      default:
        throw ArgumentError('未知模型 ${task.modelId}');
    }
  }

  // ---------- 结果解析 ----------

  static List<String> extractImageUrls(Map<String, dynamic> data) {
    final images = data['images'];
    if (images is! List) return [];
    return images
        .map((e) {
          if (e is String) return e;
          if (e is Map<String, dynamic>) {
            return (e['image_url'] ?? e['url']) as String?;
          }
          return null;
        })
        .whereType<String>()
        .toList();
  }

  static List<String> extractVideoUrls(Map<String, dynamic> data) {
    final videos = data['videos'];
    if (videos is! List) return [];
    return videos
        .map((e) =>
            e is Map<String, dynamic> ? e['video_url'] as String? : null)
        .whereType<String>()
        .toList();
  }

  /// 该模型是否同步返回（无需轮询）。
  static bool isSyncModel(String modelId) =>
      modelId.startsWith('seedream') || modelId == 'gpt-image-2';

  /// 便捷：目录一致性校验用。
  static bool knowsModel(String modelId) => ModelCatalog.byId(modelId) != null;
}
