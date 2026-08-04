import 'message.dart';

/// 一个会话（对应聊天列表里的一行 = 一个聊天窗口）。
class Conversation {
  final String id;
  String name;
  final List<Message> messages = [];

  /// agent 是否正在「输入中…」（首个 token 到达前）。（不入库，重启即复位）
  bool agentTyping = false;

  /// agent 是否正在流式输出中（用于在末条气泡显示光标）。（不入库）
  bool streaming = false;

  /// 正在流式传输的待生成工具调用数（>0 时底部显示「正在准备生成…」）。（不入库）
  int pendingGenCount = 0;

  /// 创建时间，用于空会话的排序兜底，需持久化。
  final DateTime createdAt;

  Conversation({required this.id, required this.name, DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();

  Message? get lastMessage => messages.isEmpty ? null : messages.last;

  /// 列表里排序用：最近一条消息时间，空会话用创建兜底。
  DateTime get updatedAt => lastMessage?.time ?? createdAt;
}
