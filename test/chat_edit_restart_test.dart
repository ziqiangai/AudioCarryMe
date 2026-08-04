import 'package:flutter_test/flutter_test.dart';

import 'package:carry_me/models/conversation.dart';
import 'package:carry_me/models/message.dart';
import 'package:carry_me/services/agent_service.dart';
import 'package:carry_me/state/chat_store.dart';
import 'package:carry_me/storage/chat_storage.dart';

/// 计数 agent：respond 被调次数可断言，并回一句短文本。
class CountingAgent implements AgentService {
  int calls = 0;
  @override
  Stream<AgentEvent> respond(Conversation c) async* {
    calls++;
    yield const AgentTextDelta('答');
  }
}

Conversation seed() {
  final c = Conversation(id: 'c1', name: '助手');
  c.messages.addAll([
    Message(id: 'm1', text: '问1', sender: Sender.me, time: DateTime(2026, 1, 1, 0, 0, 1)),
    Message(id: 'm2', text: '答1', sender: Sender.agent, time: DateTime(2026, 1, 1, 0, 0, 2)),
    Message(id: 'm3', text: '问2', sender: Sender.me, time: DateTime(2026, 1, 1, 0, 0, 3)),
    Message(id: 'm4', text: '答2', sender: Sender.agent, time: DateTime(2026, 1, 1, 0, 0, 4)),
  ]);
  return c;
}

Future<void> pump() => Future.delayed(const Duration(milliseconds: 60));

void main() {
  test('restartFrom 用户消息：截断其后并重新生成', () async {
    final agent = CountingAgent();
    final store = ChatStore(agent, NoopChatStorage());
    final conv = seed();

    await store.restartFrom(conv, conv.messages[0]); // 从「问1」重来
    await pump();
    // 保留 m1，删掉 m2/m3/m4，重新生成 1 条回复
    expect(conv.messages.first.id, 'm1');
    expect(conv.messages.any((m) => m.id == 'm3'), isFalse);
    expect(agent.calls, 1);
    expect(conv.messages.last.isMine, isFalse); // 末尾是新回复
  });

  test('restartFrom AI 消息：只截断，不重新生成', () async {
    final agent = CountingAgent();
    final store = ChatStore(agent, NoopChatStorage());
    final conv = seed();

    await store.restartFrom(conv, conv.messages[1]); // 从「答1」处
    await pump();
    expect(conv.messages.map((m) => m.id), ['m1', 'm2']);
    expect(agent.calls, 0);
  });

  test('editAndRegenerate：改文本 + 截断其后 + 重新回答', () async {
    final agent = CountingAgent();
    final store = ChatStore(agent, NoopChatStorage());
    final conv = seed();

    await store.editAndRegenerate(conv, conv.messages[2], '问2改'); // 编辑「问2」
    await pump();
    // m1,m2 保留；m3 文本改；m4 删；新增回复
    expect(conv.messages[0].id, 'm1');
    expect(conv.messages[2].id, 'm3');
    expect(conv.messages[2].text, '问2改');
    expect(conv.messages.any((m) => m.id == 'm4'), isFalse);
    expect(agent.calls, 1);
  });
}
