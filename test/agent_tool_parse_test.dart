import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:carry_me/models/conversation.dart';
import 'package:carry_me/models/message.dart';
import 'package:carry_me/services/agent_service.dart';
import 'package:carry_me/services/deepseek_agent_service.dart';

/// 把事件对象序列化成一段 SSE 文本。
String sse(List<Map<String, dynamic>> events) =>
    events.map((e) => 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n').join('\n');

Conversation conv() {
  final c = Conversation(id: 'c1', name: '助手');
  c.messages.add(Message(
      id: 'm1', text: '画一只猫', sender: Sender.me, time: DateTime.now()));
  return c;
}

DeepseekAgentService serviceWith(String body) => DeepseekAgentService(
      client: MockClient.streaming((request, bodyStream) async {
        // 断言请求里带了工具集定义
        final reqBody = await bodyStream.transform(utf8.decoder).join();
        final req = jsonDecode(reqBody) as Map<String, dynamic>;
        expect(req['tools'], isNotEmpty);
        expect((req['tools'] as List).map((t) => t['name']),
            containsAll(['generate_image', 'generate_video']));
        return http.StreamedResponse(
          Stream.value(utf8.encode(body)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );

void main() {
  test('解析 text_delta 与 tool_use（input_json_delta 分片累积）', () async {
    final body = sse([
      {
        'type': 'message_start',
        'message': {
          'usage': {'input_tokens': 10, 'cache_read_input_tokens': 5}
        }
      },
      {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'text_delta', 'text': '好的，我来画'}
      },
      {
        'type': 'content_block_start',
        'index': 1,
        'content_block': {'type': 'tool_use', 'id': 'call_1', 'name': 'generate_image'}
      },
      {
        'type': 'content_block_delta',
        'index': 1,
        'delta': {'type': 'input_json_delta', 'partial_json': '{"prom'}
      },
      {
        'type': 'content_block_delta',
        'index': 1,
        'delta': {'type': 'input_json_delta', 'partial_json': 'pt":"一只可爱的橘猫"}'}
      },
      {'type': 'content_block_stop', 'index': 1},
      {
        'type': 'message_delta',
        'usage': {'output_tokens': 42}
      },
    ]);

    final events = await serviceWith(body).respond(conv()).toList();

    final texts = events.whereType<AgentTextDelta>().map((e) => e.text).join();
    expect(texts, '好的，我来画');

    final calls = events.whereType<AgentToolCall>().toList();
    expect(calls, hasLength(1));
    expect(calls.first.name, 'generate_image');
    expect(calls.first.id, 'call_1');
    expect(calls.first.input['prompt'], '一只可爱的橘猫');
  });

  test('纯工具调用（无文本）也能产出事件', () async {
    final body = sse([
      {
        'type': 'content_block_start',
        'index': 0,
        'content_block': {'type': 'tool_use', 'id': 'c2', 'name': 'generate_video'}
      },
      {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'input_json_delta', 'partial_json': '{"prompt":"海浪"}'}
      },
      {'type': 'content_block_stop', 'index': 0},
    ]);
    final events = await serviceWith(body).respond(conv()).toList();
    expect(events.whereType<AgentTextDelta>(), isEmpty);
    final call = events.whereType<AgentToolCall>().single;
    expect(call.name, 'generate_video');
    expect(call.input['prompt'], '海浪');
  });

  test('thinking_delta 被忽略，不进入文本', () async {
    final body = sse([
      {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'thinking_delta', 'thinking': '我想想'}
      },
      {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'text_delta', 'text': '答案'}
      },
    ]);
    final events = await serviceWith(body).respond(conv()).toList();
    expect(events.whereType<AgentTextDelta>().map((e) => e.text).join(), '答案');
  });
}
