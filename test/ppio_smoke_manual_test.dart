// 手动冒烟：真实调用 PPIO 生成一张图（会产生少量费用）。
// 默认 skip；手动跑：flutter test test/ppio_smoke_manual_test.dart --run-skipped
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';

import 'package:carry_me/models/generation_task.dart';
import 'package:carry_me/models/model_catalog.dart';
import 'package:carry_me/services/ppio_service.dart';

void main() {
  test('真实生成一张 seedream-5.0-lite 图片', () async {
    final svc = PpioService();
    final task = GenerationTask(
      id: 'smoke',
      conversationId: 'smoke',
      kind: GenKind.image,
      modelId: 'seedream-5.0-lite',
      prompt: '一只戴着宇航员头盔的橘猫，卡通风格，简洁背景',
      params: {'size': '2048x2048', 'watermark': 'false'},
    );
    final sw = Stopwatch()..start();
    final r = await svc.submit(task);
    if (r.isSync) {
      print('✓ 同步完成 ${sw.elapsed.inSeconds}s：${r.urls}');
      expect(r.urls, isNotEmpty);
      return;
    }
    print('异步 task_id=${r.ppioTaskId}');
    for (var i = 0; i < 100; i++) {
      await Future.delayed(const Duration(seconds: 3));
      final p = await svc.pollOnce(r.ppioTaskId!);
      print('[${sw.elapsed.inSeconds}s] ${p.status}');
      if (p.status == PpioPollStatus.succeeded) {
        expect(p.urls, isNotEmpty);
        print('✓ 完成：${p.urls}');
        return;
      }
      if (p.status == PpioPollStatus.failed) fail('生成失败：${p.error}');
    }
    fail('轮询超时');
  }, skip: '手动冒烟：flutter test test/ppio_smoke_manual_test.dart --run-skipped',
      timeout: const Timeout(Duration(minutes: 6)));
}
