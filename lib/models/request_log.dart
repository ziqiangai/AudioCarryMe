/// 一次大模型请求的统计记录。
class RequestLog {
  final String id;

  /// 发起时间。
  final DateTime startedAt;

  /// 未命中缓存的输入 token。
  final int inputTokens;

  /// 命中缓存读取的 token。
  final int cacheReadTokens;

  /// 写入缓存的 token。
  final int cacheCreationTokens;

  /// 输出 token。
  final int outputTokens;

  /// 响应耗时：发起 → 收到首个内容 token。
  final Duration responseLatency;

  /// 请求耗时：发起 → 整个流结束。
  final Duration totalDuration;

  /// 是否成功。
  final bool ok;

  /// 失败时的错误信息。
  final String? error;

  const RequestLog({
    required this.id,
    required this.startedAt,
    required this.inputTokens,
    required this.cacheReadTokens,
    required this.cacheCreationTokens,
    required this.outputTokens,
    required this.responseLatency,
    required this.totalDuration,
    required this.ok,
    this.error,
  });

  /// 提示词总 token（含缓存部分）。
  int get promptTokens => inputTokens + cacheReadTokens + cacheCreationTokens;

  /// 本次总 token。
  int get totalTokens => promptTokens + outputTokens;

  /// 缓存命中率 = 缓存读取 / 提示词总量。
  double get cacheHitRate =>
      promptTokens == 0 ? 0 : cacheReadTokens / promptTokens;
}
