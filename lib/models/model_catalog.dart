/// PPIO 生图 / 生视频模型目录与参数支持矩阵。
///
/// 数据来源：docs/aigc-models-inventory.md（iplex 生产源码 + PPIO 文档核实）。
/// 参数面板依据 [ModelSpec.supports] 决定每个参数是可编辑还是显示「不支持」角标。
library;

/// 生成类型。
enum GenKind { image, video }

/// 参数面板里展示的「全量参数」键。
/// 面板对每个模型都展示全集，不支持的打角标——这是产品要求。
enum ParamKey {
  size, // 生图：分辨率档位
  numOutputs, // 生图：张数
  watermark, // 水印
  quality, // 生图：质量档（gpt-image-2）
  duration, // 视频：时长（秒）
  resolution, // 视频：分辨率
  aspectRatio, // 宽高比
  audio, // 视频：是否带声音
  negativePrompt, // 反向提示词
}

extension ParamKeyX on ParamKey {
  String get label => switch (this) {
        ParamKey.size => '分辨率',
        ParamKey.numOutputs => '生成张数',
        ParamKey.watermark => '水印',
        ParamKey.quality => '质量',
        ParamKey.duration => '时长',
        ParamKey.resolution => '清晰度',
        ParamKey.aspectRatio => '宽高比',
        ParamKey.audio => '声音',
        ParamKey.negativePrompt => '反向提示词',
      };
}

/// 一个可选项（用于枚举型参数）。
class ParamOption {
  final String value;
  final String label;
  const ParamOption(this.value, this.label);
}

/// 单个参数在某模型上的规格。
class ParamSpec {
  /// 枚举可选值；空表示自由输入（如反向提示词）或布尔。
  final List<ParamOption> options;
  final String? defaultValue;
  const ParamSpec({this.options = const [], this.defaultValue});
}

/// 模型规格。
class ModelSpec {
  final String id; // 目录 id，如 kling-v3.0-pro
  final String name; // 显示名
  final GenKind kind;
  final String vendorTag; // 小标签，如「可灵」「字节」

  /// 支持的参数与规格；不在 map 里的参数 = 不支持（UI 打角标）。
  final Map<ParamKey, ParamSpec> supports;

  /// 是否支持参考图（生图=图生图；视频=图生视频/首帧）。
  final bool supportsRef;

  const ModelSpec({
    required this.id,
    required this.name,
    required this.kind,
    required this.vendorTag,
    required this.supports,
    this.supportsRef = false,
  });

  bool supportsParam(ParamKey key) => supports.containsKey(key);

  /// 该模型某参数的默认值（不支持则 null）。
  String? defaultOf(ParamKey key) => supports[key]?.defaultValue;
}

/// 目录本体。
class ModelCatalog {
  ModelCatalog._();

  /// 生图通用宽高比选项。提交层把「size 档位 × 宽高比」换算成具体像素。
  static const _imageAspects = ParamSpec(options: [
    ParamOption('1:1', '1:1'),
    ParamOption('4:3', '4:3'),
    ParamOption('3:4', '3:4'),
    ParamOption('16:9', '16:9'),
    ParamOption('9:16', '9:16'),
  ], defaultValue: '1:1');

  static const List<ModelSpec> imageModels = [
    ModelSpec(
      id: 'seedream-5.0-lite',
      name: 'Seedream 5.0 Lite',
      kind: GenKind.image,
      vendorTag: '字节',
      supportsRef: true, // 图生图：image 参数
      supports: {
        ParamKey.size: ParamSpec(options: [
          ParamOption('2048x2048', '2K'),
          ParamOption('3072x3072', '3K'),
        ], defaultValue: '2048x2048'),
        ParamKey.aspectRatio: _imageAspects,
        ParamKey.numOutputs: ParamSpec(options: [
          ParamOption('1', '1 张'),
          ParamOption('2', '2 张'),
          ParamOption('3', '3 张'),
          ParamOption('4', '4 张'),
        ], defaultValue: '1'),
        ParamKey.watermark: ParamSpec(defaultValue: 'false'),
      },
    ),
    ModelSpec(
      id: 'seedream-4.5',
      name: 'Seedream 4.5',
      kind: GenKind.image,
      vendorTag: '字节',
      supportsRef: true,
      supports: {
        ParamKey.size: ParamSpec(options: [
          ParamOption('2048x2048', '2K'),
          ParamOption('4096x4096', '4K'),
        ], defaultValue: '2048x2048'),
        ParamKey.aspectRatio: _imageAspects,
        ParamKey.numOutputs: ParamSpec(options: [
          ParamOption('1', '1 张'),
          ParamOption('2', '2 张'),
          ParamOption('3', '3 张'),
          ParamOption('4', '4 张'),
        ], defaultValue: '1'),
        ParamKey.watermark: ParamSpec(defaultValue: 'false'),
      },
    ),
    ModelSpec(
      id: 'gpt-image-2',
      name: 'GPT Image 2',
      kind: GenKind.image,
      vendorTag: 'OpenAI',
      supportsRef: true, // 走 edit 端点
      supports: {
        // GPT 用经典固定尺寸：1:1/3:2/2:3（提交层映射），不提供 size 档位。
        ParamKey.aspectRatio: ParamSpec(options: [
          ParamOption('1:1', '1:1'),
          ParamOption('3:2', '3:2'),
          ParamOption('2:3', '2:3'),
        ], defaultValue: '1:1'),
        ParamKey.quality: ParamSpec(options: [
          ParamOption('low', '快速'),
          ParamOption('medium', '均衡'),
          ParamOption('high', '高清'),
        ], defaultValue: 'medium'),
        ParamKey.numOutputs: ParamSpec(options: [
          ParamOption('1', '1 张'),
          ParamOption('2', '2 张'),
        ], defaultValue: '1'),
      },
    ),
    ModelSpec(
      id: 'qwen-image',
      name: 'Qwen-Image',
      kind: GenKind.image,
      vendorTag: '通义',
      // qwen-image 文生图不支持参考图（编辑是另一个模型）。
      supports: {
        ParamKey.aspectRatio: _imageAspects,
        ParamKey.watermark: ParamSpec(defaultValue: 'false'),
      },
    ),
  ];

  static const List<ModelSpec> videoModels = [
    ModelSpec(
      id: 'seedance-2.0',
      name: 'Seedance 2.0',
      kind: GenKind.video,
      vendorTag: '字节',
      supportsRef: true, // i2v：content 里加 image_url
      supports: {
        ParamKey.duration: ParamSpec(options: [
          ParamOption('5', '5 秒'),
          ParamOption('8', '8 秒'),
          ParamOption('10', '10 秒'),
          ParamOption('15', '15 秒'),
        ], defaultValue: '5'),
        ParamKey.resolution: ParamSpec(options: [
          ParamOption('480p', '480p'),
          ParamOption('720p', '720p'),
          ParamOption('1080p', '1080p'),
        ], defaultValue: '720p'),
        ParamKey.aspectRatio: ParamSpec(options: [
          ParamOption('16:9', '16:9'),
          ParamOption('9:16', '9:16'),
          ParamOption('1:1', '1:1'),
        ], defaultValue: '16:9'),
        ParamKey.watermark: ParamSpec(defaultValue: 'false'),
      },
    ),
    ModelSpec(
      id: 'seedance-2.0-fast',
      name: 'Seedance 2.0 Fast',
      kind: GenKind.video,
      vendorTag: '字节',
      supportsRef: true,
      supports: {
        ParamKey.duration: ParamSpec(options: [
          ParamOption('5', '5 秒'),
          ParamOption('8', '8 秒'),
          ParamOption('10', '10 秒'),
        ], defaultValue: '5'),
        ParamKey.resolution: ParamSpec(options: [
          ParamOption('480p', '480p'),
          ParamOption('720p', '720p'),
        ], defaultValue: '480p'),
        ParamKey.aspectRatio: ParamSpec(options: [
          ParamOption('16:9', '16:9'),
          ParamOption('9:16', '9:16'),
          ParamOption('1:1', '1:1'),
        ], defaultValue: '16:9'),
        ParamKey.watermark: ParamSpec(defaultValue: 'false'),
      },
    ),
    ModelSpec(
      id: 'kling-v3.0-std',
      name: 'Kling v3.0 标准',
      kind: GenKind.video,
      vendorTag: '可灵',
      supportsRef: true, // i2v：首帧
      supports: {
        ParamKey.duration: ParamSpec(options: [
          ParamOption('3', '3 秒'),
          ParamOption('5', '5 秒'),
          ParamOption('10', '10 秒'),
          ParamOption('15', '15 秒'),
        ], defaultValue: '5'),
        ParamKey.aspectRatio: ParamSpec(options: [
          ParamOption('16:9', '16:9'),
          ParamOption('9:16', '9:16'),
          ParamOption('1:1', '1:1'),
        ], defaultValue: '9:16'),
        ParamKey.audio: ParamSpec(defaultValue: 'true'),
        ParamKey.negativePrompt: ParamSpec(),
      },
    ),
    ModelSpec(
      id: 'kling-v3.0-pro',
      name: 'Kling v3.0 Pro',
      kind: GenKind.video,
      vendorTag: '可灵',
      supportsRef: true,
      supports: {
        ParamKey.duration: ParamSpec(options: [
          ParamOption('3', '3 秒'),
          ParamOption('5', '5 秒'),
          ParamOption('10', '10 秒'),
          ParamOption('15', '15 秒'),
        ], defaultValue: '5'),
        ParamKey.aspectRatio: ParamSpec(options: [
          ParamOption('16:9', '16:9'),
          ParamOption('9:16', '9:16'),
          ParamOption('1:1', '1:1'),
        ], defaultValue: '9:16'),
        ParamKey.audio: ParamSpec(defaultValue: 'true'),
        ParamKey.negativePrompt: ParamSpec(),
      },
    ),
    ModelSpec(
      id: 'minimax-hailuo-2.3',
      name: 'Hailuo 2.3',
      kind: GenKind.video,
      vendorTag: 'MiniMax',
      supportsRef: true,
      supports: {
        ParamKey.duration: ParamSpec(options: [
          ParamOption('6', '6 秒'),
          ParamOption('10', '10 秒'),
        ], defaultValue: '6'),
        // Hailuo 提交时 resolution 必须大写（768P/1080P），提交层转换。
        // 1080P 仅支持 6 秒——提交层校验。
        ParamKey.resolution: ParamSpec(options: [
          ParamOption('768P', '768P'),
          ParamOption('1080P', '1080P'),
        ], defaultValue: '768P'),
        ParamKey.watermark: ParamSpec(defaultValue: 'false'),
      },
    ),
    ModelSpec(
      id: 'veo-3.1',
      name: 'Veo 3.1',
      kind: GenKind.video,
      vendorTag: 'Google',
      supportsRef: true,
      supports: {
        ParamKey.duration: ParamSpec(options: [
          ParamOption('8', '8 秒'),
        ], defaultValue: '8'),
        ParamKey.resolution: ParamSpec(options: [
          ParamOption('720p', '720p'),
          ParamOption('1080p', '1080p'),
        ], defaultValue: '720p'),
        ParamKey.aspectRatio: ParamSpec(options: [
          ParamOption('16:9', '16:9'),
          ParamOption('9:16', '9:16'),
        ], defaultValue: '16:9'),
        ParamKey.audio: ParamSpec(defaultValue: 'true'),
      },
    ),
  ];

  /// 参数面板展示顺序（每类的全集）。
  static const List<ParamKey> imageParamOrder = [
    ParamKey.size,
    ParamKey.aspectRatio,
    ParamKey.quality,
    ParamKey.numOutputs,
    ParamKey.watermark,
  ];
  static const List<ParamKey> videoParamOrder = [
    ParamKey.duration,
    ParamKey.resolution,
    ParamKey.aspectRatio,
    ParamKey.audio,
    ParamKey.negativePrompt,
    ParamKey.watermark,
  ];

  static List<ModelSpec> modelsOf(GenKind kind) =>
      kind == GenKind.image ? imageModels : videoModels;

  static List<ParamKey> paramOrderOf(GenKind kind) =>
      kind == GenKind.image ? imageParamOrder : videoParamOrder;

  static ModelSpec? byId(String id) {
    for (final m in [...imageModels, ...videoModels]) {
      if (m.id == id) return m;
    }
    return null;
  }

  static ModelSpec defaultOf(GenKind kind) => modelsOf(kind).first;

  /// 给定模型，返回其全部参数默认值。
  static Map<ParamKey, String> defaultsFor(ModelSpec model) {
    final out = <ParamKey, String>{};
    for (final e in model.supports.entries) {
      final d = e.value.defaultValue;
      if (d != null) out[e.key] = d;
    }
    return out;
  }
}
