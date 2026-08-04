import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logging/app_log.dart';
import '../models/conversation.dart';
import '../models/request_log.dart';
import '../state/request_log_store.dart';
import 'agent_config.dart';
import 'agent_service.dart';

/// 创作 Agent 的工具集定义（Anthropic tools 格式）。
const List<Map<String, dynamic>> kCreationTools = [
  {
    'name': 'design_prompt',
    'description': '设计或改写一段生成提示词文案，产出一张「提示词卡片」给用户确认。'
        '当用户要求写提示词/文案/脚本，或引用了某张提示词卡片要求修改时调用。'
        '视频提示词要用镜头语言（景别、运镜、动态、节奏）写足细节。',
    'input_schema': {
      'type': 'object',
      'properties': {
        'prompt': {'type': 'string', 'description': '完整的提示词文案'},
        'label': {
          'type': 'string',
          'description': '场景标签（如 场景1），批量时给每张卡片标注，'
              '后续生图生视频用同名 label 关联成创作链'
        },
      },
      'required': ['prompt'],
    },
  },
  {
    'name': 'generate_image',
    'description': '生成图片。prompt 必须忠实于用户给定的文案：'
        '用户引用了提示词卡片就原文使用，否则用用户的原始描述，不要自行扩写添加想象内容。'
        '批量时一轮内多次调用本工具，每次配 label（如「场景1」）标记所属场景。',
    'input_schema': {
      'type': 'object',
      'properties': {
        'prompt': {'type': 'string', 'description': '用户给定的画面文案（忠实原文）'},
        'label': {
          'type': 'string',
          'description': '场景标签（如 场景1），用于把提示词/图片/视频串成一条创作链'
        },
      },
      'required': ['prompt'],
    },
  },
  {
    'name': 'generate_video',
    'description': '生成视频。prompt 必须忠实于用户给定的文案。'
        '要以某个场景已生成的图片为首帧（图生视频）时，传 ref_label=该场景的 label，'
        'App 会自动找到对应图片，无需 URL。批量时一轮内多次调用。',
    'input_schema': {
      'type': 'object',
      'properties': {
        'prompt': {'type': 'string', 'description': '用户给定的视频文案（忠实原文）'},
        'label': {'type': 'string', 'description': '场景标签（如 场景1）'},
        'ref_label': {
          'type': 'string',
          'description': '以哪个场景的已生成图片作为首帧（填该场景的 label）'
        },
      },
      'required': ['prompt'],
    },
  },
];

/// 真实 Agent：调用 DeepSeek 的 Anthropic 兼容 Messages 接口（SSE 流式）。
///
/// 产出 [AgentEvent]：text_delta → [AgentTextDelta]；
/// tool_use 块（content_block_start + input_json_delta 累积）→ [AgentToolCall]。
class DeepseekAgentService implements AgentService {
  DeepseekAgentService({http.Client? client, RequestLogStore? logStore})
      : _client = client ?? http.Client(),
        // ignore: prefer_initializing_formals
        _logStore = logStore;

  final http.Client _client;
  final RequestLogStore? _logStore;

  int _seq = 0;

  @override
  Stream<AgentEvent> respond(Conversation conversation) async* {
    final messages = conversation.messages
        .where((m) => m.text.trim().isNotEmpty && !m.isError)
        .map((m) {
      final content = m.hasQuote
          ? '> ${m.quotedAuthor}：${m.quotedText}\n\n${m.text}'
          : m.text;
      return {
        'role': m.isMine ? 'user' : 'assistant',
        'content': content,
      };
    }).toList();

    http.Request buildRequest() =>
        http.Request('POST', Uri.parse('${AgentConfig.baseUrl}/v1/messages'))
          ..headers.addAll({
            'content-type': 'application/json',
            'anthropic-version': AgentConfig.anthropicVersion,
            'authorization': 'Bearer ${AgentConfig.authToken}',
            'accept': 'text/event-stream',
            'accept-encoding': 'identity',
          })
          ..body = jsonEncode({
            'model': AgentConfig.model,
            'max_tokens': AgentConfig.maxTokens,
            'temperature': AgentConfig.temperature,
            'system': AgentConfig.systemPrompt,
            'tools': kCreationTools,
            'stream': true,
            'messages': messages,
          });

    // —— 指标采集 ——
    final startedAt = DateTime.now();
    final sw = Stopwatch()..start();
    Duration? firstTokenAt;
    var inputTokens = 0, cacheRead = 0, cacheCreate = 0, outputTokens = 0;
    var ok = false;
    String? error;

    AppLog.i('agent',
        '请求开始 model=${AgentConfig.model} 消息数=${messages.length}');

    // tool_use 累积状态（按 content block index）。
    final toolNames = <int, String>{};
    final toolIds = <int, String>{};
    final toolJson = <int, StringBuffer>{};

    try {
      // 5xx/503 瞬时故障自动重试（最多 3 次，指数退避 1s/2s）。
      // 此时还未产出任何事件，重试对上层完全透明。
      http.StreamedResponse resp;
      var attempt = 0;
      while (true) {
        attempt++;
        resp = await _client.send(buildRequest());
        if (resp.statusCode == 200) break;
        final body = await resp.stream.bytesToString();
        final retryable = resp.statusCode >= 500 || resp.statusCode == 429;
        if (retryable && attempt < 3) {
          AppLog.w('agent',
              '模型 ${resp.statusCode}，${attempt}s 后重试（$attempt/2）');
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }
        throw Exception('接口返回 ${resp.statusCode}：$body');
      }

      final lines =
          resp.stream.transform(utf8.decoder).transform(const LineSplitter());

      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;

        final evt = jsonDecode(payload) as Map<String, dynamic>;
        switch (evt['type']) {
          case 'message_start':
            final u = (evt['message'] as Map?)?['usage'] as Map?;
            if (u != null) {
              inputTokens = (u['input_tokens'] as int?) ?? 0;
              cacheRead = (u['cache_read_input_tokens'] as int?) ?? 0;
              cacheCreate = (u['cache_creation_input_tokens'] as int?) ?? 0;
            }
          case 'content_block_start':
            final block = evt['content_block'] as Map<String, dynamic>?;
            if (block != null && block['type'] == 'tool_use') {
              final idx = (evt['index'] as num?)?.toInt() ?? 0;
              final name = (block['name'] as String?) ?? '';
              toolNames[idx] = name;
              toolIds[idx] = (block['id'] as String?) ?? '';
              toolJson[idx] = StringBuffer();
              // 立即通知：接下来在流式传输本次工具的参数（可能较久）。
              yield AgentToolStart(name);
            }
          case 'content_block_delta':
            final idx = (evt['index'] as num?)?.toInt() ?? 0;
            final delta = evt['delta'] as Map<String, dynamic>?;
            if (delta == null) break;
            if (delta['type'] == 'text_delta') {
              final t = delta['text'] as String?;
              if (t != null && t.isNotEmpty) {
                firstTokenAt ??= sw.elapsed;
                yield AgentTextDelta(t);
              }
            } else if (delta['type'] == 'input_json_delta') {
              toolJson[idx]?.write(delta['partial_json'] as String? ?? '');
            }
          case 'content_block_stop':
            final idx = (evt['index'] as num?)?.toInt() ?? 0;
            final name = toolNames.remove(idx);
            if (name != null && name.isNotEmpty) {
              final raw = toolJson.remove(idx)?.toString() ?? '{}';
              Map<String, dynamic> input;
              try {
                input = raw.isEmpty
                    ? <String, dynamic>{}
                    : jsonDecode(raw) as Map<String, dynamic>;
              } catch (_) {
                input = {'prompt': raw};
              }
              firstTokenAt ??= sw.elapsed;
              AppLog.i('agent', '工具调用 $name input=$input');
              yield AgentToolCall(
                  id: toolIds.remove(idx) ?? '', name: name, input: input);
            }
          case 'message_delta':
            final u = evt['usage'] as Map?;
            if (u != null && u['output_tokens'] != null) {
              outputTokens = u['output_tokens'] as int;
            }
          case 'error':
            throw Exception('流式错误：${jsonEncode(evt['error'])}');
        }
      }
      ok = true;
    } catch (e) {
      error = e.toString();
      AppLog.e('agent', '请求失败：$e');
      rethrow;
    } finally {
      sw.stop();
      if (ok) {
        final hit = (inputTokens + cacheRead + cacheCreate) == 0
            ? 0
            : (cacheRead * 100) ~/ (inputTokens + cacheRead + cacheCreate);
        AppLog.i('agent',
            '请求完成 tokens(in=$inputTokens,out=$outputTokens,cacheRead=$cacheRead) 首字=${(firstTokenAt ?? sw.elapsed).inMilliseconds}ms 总耗时=${sw.elapsed.inMilliseconds}ms 命中=$hit%');
      }
      _logStore?.add(RequestLog(
        id: 'req-${startedAt.microsecondsSinceEpoch}-${_seq++}',
        conversationId: conversation.id,
        startedAt: startedAt,
        inputTokens: inputTokens,
        cacheReadTokens: cacheRead,
        cacheCreationTokens: cacheCreate,
        outputTokens: outputTokens,
        responseLatency: firstTokenAt ?? sw.elapsed,
        totalDuration: sw.elapsed,
        ok: ok,
        error: error,
      ));
    }
  }
}
