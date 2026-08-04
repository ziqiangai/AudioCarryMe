import 'package:flutter_test/flutter_test.dart';

import 'package:carry_me/models/generation_task.dart';
import 'package:carry_me/models/model_catalog.dart';

void main() {
  group('GenerationTask', () {
    GenerationTask makeTask() => GenerationTask(
          id: 't1',
          conversationId: 'c1',
          kind: GenKind.image,
          modelId: 'seedream-5.0-lite',
          prompt: '月球上的橘猫',
          params: {'size': '2048x2048', 'watermark': 'false'},
        );

    test('params/resultUrls JSON round-trip', () {
      final t = makeTask()..resultUrls = ['https://a/1.png', 'https://a/2.png'];
      expect(GenerationTask.decodeParams(t.paramsJson), t.params);
      expect(GenerationTask.decodeUrls(t.resultUrlsJson), t.resultUrls);
    });

    test('状态机：终态与恢复判定', () {
      expect(GenTaskStatus.succeeded.isTerminal, isTrue);
      expect(GenTaskStatus.failed.isTerminal, isTrue);
      expect(GenTaskStatus.processing.isTerminal, isFalse);
      // 切出 App 回来需要重查的状态
      expect(GenTaskStatus.submitting.needsRecovery, isTrue);
      expect(GenTaskStatus.queued.needsRecovery, isTrue);
      expect(GenTaskStatus.processing.needsRecovery, isTrue);
      expect(GenTaskStatus.draft.needsRecovery, isFalse);
      expect(GenTaskStatus.succeeded.needsRecovery, isFalse);
    });

    test('regenerate 复制全部参数为新草稿（「再生一张」）', () {
      final t = makeTask()
        ..status = GenTaskStatus.succeeded
        ..ppioTaskId = 'remote-1'
        ..resultUrls = ['https://a/1.png'];
      final r = t.regenerate('t2');
      expect(r.id, 't2');
      expect(r.modelId, t.modelId);
      expect(r.prompt, t.prompt);
      expect(r.params, t.params);
      expect(r.params, isNot(same(t.params))); // 深拷贝
      expect(r.status, GenTaskStatus.draft);
      expect(r.ppioTaskId, isNull);
      expect(r.resultUrls, isEmpty);
    });
  });
}
