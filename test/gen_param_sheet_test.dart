import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carry_me/models/model_catalog.dart';
import 'package:carry_me/screens/gen_param_sheet.dart';

Widget _host(void Function(BuildContext) onTap) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => onTap(context),
            child: const Text('open'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('批量参考图模式（refImageUrl=null + batchRef）面板不崩溃', (tester) async {
    // 复现年夜饭 6 镜头 i2v 场景：曾因对 null 的 refImageUrl 强解包白屏崩溃。
    await tester.pumpWidget(_host((c) => showGenParamSheet(
          c,
          kind: GenKind.video,
          prompt: '',
          batchCount: 6,
          batchRef: true,
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull); // 无空指针崩溃
    expect(find.text('生成视频 ×6'), findsOneWidget);
    expect(find.textContaining('将对 6 张参考图分别生成'), findsOneWidget);
  });

  testWidgets('单张参考图模式显示参考图预览区', (tester) async {
    await tester.pumpWidget(_host((c) => showGenParamSheet(
          c,
          kind: GenKind.video,
          prompt: '一个镜头',
          refImageUrl: '/tmp/not-exist.png', // 本地路径走 errorBuilder，不发网络
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('参考图'), findsOneWidget);
    expect(find.textContaining('将以这张图为首帧'), findsOneWidget);
  });
}
