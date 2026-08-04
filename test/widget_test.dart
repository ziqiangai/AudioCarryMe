import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carry_me/main.dart';
import 'package:carry_me/services/agent_service.dart';
import 'package:carry_me/services/ppio_service.dart';
import 'package:carry_me/state/chat_store.dart';
import 'package:carry_me/state/generation_store.dart';
import 'package:carry_me/state/log_store.dart';
import 'package:carry_me/state/request_log_store.dart';
import 'package:carry_me/storage/chat_storage.dart';

CarryMeApp _buildApp() {
  final storage = NoopChatStorage();
  return CarryMeApp(
    store: ChatStore(StubAgentService(), storage),
    logStore: RequestLogStore(storage),
    appLogStore: AppLogStore(storage),
    genStore: GenerationStore(PpioService(), storage),
  );
}

void main() {
  testWidgets('打开显示空会话列表与「微信」标题', (tester) async {
    await tester.pumpWidget(_buildApp());

    // 「微信」同时出现在顶栏标题与底部导航，至少一个。
    expect(find.text('微信'), findsWidgets);
    expect(find.text('还没有会话\n点右上角「+」新建'), findsOneWidget);
    // 右上角新建按钮存在。
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
  });

  testWidgets('点新建进入聊天界面', (tester) async {
    await tester.pumpWidget(_buildApp());

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();

    expect(find.text('发送'), findsOneWidget); // 已进入聊天界面
  });
}
