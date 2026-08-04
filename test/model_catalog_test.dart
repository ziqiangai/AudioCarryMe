import 'package:flutter_test/flutter_test.dart';

import 'package:carry_me/models/model_catalog.dart';

void main() {
  group('ModelCatalog', () {
    test('生图/生视频目录非空且 id 唯一', () {
      final all = [...ModelCatalog.imageModels, ...ModelCatalog.videoModels];
      expect(ModelCatalog.imageModels, isNotEmpty);
      expect(ModelCatalog.videoModels, isNotEmpty);
      expect(all.map((m) => m.id).toSet().length, all.length);
    });

    test('byId 能找到每个模型；未知 id 返回 null', () {
      for (final m in [...ModelCatalog.imageModels, ...ModelCatalog.videoModels]) {
        expect(ModelCatalog.byId(m.id), same(m));
      }
      expect(ModelCatalog.byId('nope'), isNull);
    });

    test('每个模型的默认值必须落在自身选项集合内', () {
      for (final m in [...ModelCatalog.imageModels, ...ModelCatalog.videoModels]) {
        for (final e in m.supports.entries) {
          final spec = e.value;
          if (spec.defaultValue != null && spec.options.isNotEmpty) {
            expect(
              spec.options.map((o) => o.value),
              contains(spec.defaultValue),
              reason: '${m.id}.${e.key.name} 默认值不在选项里',
            );
          }
        }
      }
    });

    test('支持矩阵：不在 supports 里的参数 = 不支持（角标依据）', () {
      final hailuo = ModelCatalog.byId('minimax-hailuo-2.3')!;
      expect(hailuo.supportsParam(ParamKey.aspectRatio), isFalse); // Hailuo 无宽高比
      expect(hailuo.supportsParam(ParamKey.duration), isTrue);

      final veo = ModelCatalog.byId('veo-3.1')!;
      expect(veo.supportsParam(ParamKey.negativePrompt), isFalse);
      expect(veo.supportsParam(ParamKey.audio), isTrue);

      final gpt = ModelCatalog.byId('gpt-image-2')!;
      expect(gpt.supportsParam(ParamKey.quality), isTrue); // 仅 gpt 有质量档
      expect(ModelCatalog.byId('seedream-4.5')!.supportsParam(ParamKey.quality), isFalse);
    });

    test('defaultsFor 覆盖模型支持的全部有默认值参数', () {
      final m = ModelCatalog.byId('kling-v3.0-std')!;
      final d = ModelCatalog.defaultsFor(m);
      expect(d[ParamKey.duration], '5');
      expect(d[ParamKey.aspectRatio], '9:16');
      expect(d[ParamKey.audio], 'true');
      expect(d.containsKey(ParamKey.negativePrompt), isFalse); // 无默认值的自由输入
    });

    test('面板参数顺序包含每类模型用到的所有参数键', () {
      for (final m in ModelCatalog.imageModels) {
        for (final k in m.supports.keys) {
          expect(ModelCatalog.imageParamOrder, contains(k),
              reason: '${m.id} 的 ${k.name} 不在生图面板顺序里');
        }
      }
      for (final m in ModelCatalog.videoModels) {
        for (final k in m.supports.keys) {
          expect(ModelCatalog.videoParamOrder, contains(k),
              reason: '${m.id} 的 ${k.name} 不在视频面板顺序里');
        }
      }
    });
  });
}
