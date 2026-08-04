import 'dart:convert';

import 'media_paths.dart';
import 'model_catalog.dart';

/// 生成任务状态机。
/// draft → submitting → queued/processing →(succeeded | failed)
/// App 被杀后重启，对非终态任务用 ppioTaskId 重新查询恢复。
enum GenTaskStatus { draft, submitting, queued, processing, succeeded, failed }

extension GenTaskStatusX on GenTaskStatus {
  bool get isTerminal =>
      this == GenTaskStatus.succeeded || this == GenTaskStatus.failed;

  /// 是否需要在恢复时重新查询（已有远端任务但未终态）。
  bool get needsRecovery =>
      this == GenTaskStatus.submitting ||
      this == GenTaskStatus.queued ||
      this == GenTaskStatus.processing;
}

/// 一次生成任务。完整记录 模型+prompt+参数，支持同参数「再生一张」。
class GenerationTask {
  final String id;
  final String conversationId;
  final GenKind kind;
  final String modelId;
  final String prompt;

  /// 参数快照（ParamKey.name → 值），用于展示与再生。
  final Map<String, String> params;

  GenTaskStatus status;

  /// PPIO 侧任务 id（异步模型才有；seedream 同步无）。
  String? ppioTaskId;

  /// PPIO/Novita 响应头 x-trace-id，反馈问题给供应商时用。
  String? traceId;

  /// 场景标签（批量生成时如「场景 1」），用于聊天里串联同一条创作链。
  final String? label;

  /// 血缘：图生视频时指向来源图片任务 id。
  final String? parentTaskId;

  /// 生成结果 URL 列表（图片或视频）。会过期，仅作下载源与兜底。
  List<String> resultUrls;

  /// 结果的本地缓存路径，与 resultUrls 按下标对齐（下载失败位为空串）。
  List<String> localPaths;

  String? error;
  final DateTime createdAt;
  DateTime updatedAt;

  GenerationTask({
    required this.id,
    required this.conversationId,
    required this.kind,
    required this.modelId,
    required this.prompt,
    required this.params,
    this.status = GenTaskStatus.draft,
    this.ppioTaskId,
    this.traceId,
    this.label,
    this.parentTaskId,
    List<String>? resultUrls,
    List<String>? localPaths,
    this.error,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : resultUrls = resultUrls ?? [],
        localPaths = localPaths ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  String get paramsJson => jsonEncode(params);
  String get resultUrlsJson => jsonEncode(resultUrls);
  String get localPathsJson => jsonEncode(localPaths);

  /// 第 [i] 个产物的本地路径（按文件名在当前容器解析；无缓存/文件丢失返回 null）。
  String? localAt(int i) => (i < localPaths.length)
      ? MediaPaths.resolve(localPaths[i])
      : null;

  static Map<String, String> decodeParams(String json) =>
      (jsonDecode(json) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v.toString()));

  static List<String> decodeUrls(String json) =>
      (jsonDecode(json) as List<dynamic>).cast<String>();

  /// 以同参数复制出一个新草稿任务（「再生一张」）。
  GenerationTask regenerate(String newId) => GenerationTask(
        id: newId,
        conversationId: conversationId,
        kind: kind,
        modelId: modelId,
        prompt: prompt,
        params: Map.of(params),
        label: label,
        parentTaskId: parentTaskId,
      );
}
