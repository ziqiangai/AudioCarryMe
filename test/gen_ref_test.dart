import 'package:flutter_test/flutter_test.dart';

import 'package:carry_me/models/gen_ref.dart';

void main() {
  test('GenRef JSON round-trip（列表）', () {
    final refs = [
      const GenRef(
        kind: GenRefKind.promptCard,
        targetId: 'msg-1',
        targetIsTask: false,
        snapshotText: '场景1：傍晚老宅厨房…',
      ),
      const GenRef(
        kind: GenRefKind.referenceImage,
        targetId: 'gen-9',
        targetIsTask: true,
        snapshotImage: '/media/gen-9_0.jpg',
      ),
    ];
    final back = GenRef.decode(GenRef.encode(refs));
    expect(back, hasLength(2));
    expect(back[0].kind, GenRefKind.promptCard);
    expect(back[0].targetId, 'msg-1');
    expect(back[0].targetIsTask, isFalse);
    expect(back[0].snapshotText, '场景1：傍晚老宅厨房…');
    expect(back[1].kind, GenRefKind.referenceImage);
    expect(back[1].targetIsTask, isTrue);
    expect(back[1].snapshotImage, '/media/gen-9_0.jpg');
  });

  test('空列表 round-trip', () {
    expect(GenRef.decode(GenRef.encode([])), isEmpty);
    expect(GenRef.decode('[]'), isEmpty);
  });

  test('类型中文名', () {
    expect(GenRefKind.promptCard.label, '提示词');
    expect(GenRefKind.referenceImage.label, '参考图');
    expect(GenRefKind.firstFrame.label, '首帧');
    expect(GenRefKind.lastFrame.label, '尾帧');
  });
}
