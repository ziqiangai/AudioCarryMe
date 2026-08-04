import 'dart:convert';

/// 引用类型。
enum GenRefKind { promptCard, referenceImage, firstFrame, lastFrame }

extension GenRefKindX on GenRefKind {
  String get label => switch (this) {
        GenRefKind.promptCard => '提示词',
        GenRefKind.referenceImage => '参考图',
        GenRefKind.firstFrame => '首帧',
        GenRefKind.lastFrame => '尾帧',
      };
}

/// 生成任务的一条引用（血缘）。
///
/// 底层用稳定 id 关联（[targetId] 指向 Message 或 GenerationTask），
/// 由创建任务时在 App 端解析确定；label/prompt 仅用于解析，不存进这里。
/// [snapshotText]/[snapshotImage] 冗余一份展示快照，原消息删除后仍可显示。
class GenRef {
  final GenRefKind kind;

  /// 目标 id：卡片=消息 id；参考图/首尾帧=生成任务 id。
  final String targetId;

  /// 目标是否为生成任务（true=GenerationTask，false=Message）。
  final bool targetIsTask;

  /// 展示快照：卡片文本首行（提示词类）。
  final String? snapshotText;

  /// 展示快照：缩略图路径或 URL（图片类）。
  final String? snapshotImage;

  const GenRef({
    required this.kind,
    required this.targetId,
    required this.targetIsTask,
    this.snapshotText,
    this.snapshotImage,
  });

  Map<String, dynamic> toMap() => {
        'kind': kind.index,
        'targetId': targetId,
        'targetIsTask': targetIsTask,
        if (snapshotText != null) 'snapshotText': snapshotText,
        if (snapshotImage != null) 'snapshotImage': snapshotImage,
      };

  static GenRef fromMap(Map<String, dynamic> m) => GenRef(
        kind: GenRefKind.values[m['kind'] as int],
        targetId: m['targetId'] as String,
        targetIsTask: m['targetIsTask'] as bool,
        snapshotText: m['snapshotText'] as String?,
        snapshotImage: m['snapshotImage'] as String?,
      );

  static String encode(List<GenRef> refs) =>
      jsonEncode(refs.map((r) => r.toMap()).toList());

  static List<GenRef> decode(String json) => (jsonDecode(json) as List)
      .map((e) => GenRef.fromMap(e as Map<String, dynamic>))
      .toList();
}
