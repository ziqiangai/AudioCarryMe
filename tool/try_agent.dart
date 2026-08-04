// 冒烟测试：用 App 里真实的 DeepseekAgentService 流式打一次 DeepSeek。
// 运行：dart run tool/try_agent.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:carry_me/models/conversation.dart';
import 'package:carry_me/models/message.dart';
import 'package:carry_me/services/deepseek_agent_service.dart';

Future<void> main() async {
  final conv = Conversation(id: 't', name: '智能助手');
  conv.messages.add(Message(
    id: 'm1',
    text: '用一句话介绍你自己，并说今天适合做什么',
    sender: Sender.me,
    time: DateTime.now(),
  ));

  print('→ 发送: ${conv.messages.first.text}');
  stdout.write('← 回复(流式): ');
  await for (final chunk in DeepseekAgentService().respond(conv)) {
    stdout.write(chunk); // 逐段打印，观察打字机效果
  }
  print('');
}
