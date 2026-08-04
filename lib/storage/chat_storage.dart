import '../models/conversation.dart';
import '../models/generation_task.dart';
import '../models/log_entry.dart';
import '../models/message.dart';
import '../models/request_log.dart';

/// 会话持久化接口。ChatStore 只依赖这一层，方便替换实现 / 测试打桩。
abstract class ChatStorage {
  /// 加载全部会话（含各自的消息，按时间升序）。
  Future<List<Conversation>> loadConversations();

  /// 新增或更新一个会话（首次落库 / 改名时用）。
  Future<void> upsertConversation(Conversation conversation);

  /// 追加一条消息。
  Future<void> insertMessage(String conversationId, Message message);

  /// 删除一个会话及其消息。
  Future<void> deleteConversation(String conversationId);

  /// 删除单条消息。
  Future<void> deleteMessage(String messageId);

  /// 加载全部大模型请求记录（最新在前）。
  Future<List<RequestLog>> loadRequestLogs();

  /// 追加一条请求记录。
  Future<void> insertRequestLog(RequestLog log);

  /// 加载运行日志（最新在前）。
  Future<List<LogEntry>> loadLogs();

  /// 追加一条运行日志。
  Future<void> insertLog(LogEntry entry);

  /// 清空运行日志。
  Future<void> clearLogs();

  /// 加载全部生成任务。
  Future<List<GenerationTask>> loadGenerationTasks();

  /// 新增或整体更新一个生成任务（状态/结果变化时调用）。
  Future<void> upsertGenerationTask(GenerationTask task);
}

/// 空实现：不落任何盘。用于单元/Widget 测试，避免依赖真实数据库。
class NoopChatStorage implements ChatStorage {
  @override
  Future<List<Conversation>> loadConversations() async => [];

  @override
  Future<void> upsertConversation(Conversation conversation) async {}

  @override
  Future<void> insertMessage(String conversationId, Message message) async {}

  @override
  Future<void> deleteConversation(String conversationId) async {}

  @override
  Future<void> deleteMessage(String messageId) async {}

  @override
  Future<List<RequestLog>> loadRequestLogs() async => [];

  @override
  Future<void> insertRequestLog(RequestLog log) async {}

  @override
  Future<List<LogEntry>> loadLogs() async => [];

  @override
  Future<void> insertLog(LogEntry entry) async {}

  @override
  Future<void> clearLogs() async {}

  @override
  Future<List<GenerationTask>> loadGenerationTasks() async => [];

  @override
  Future<void> upsertGenerationTask(GenerationTask task) async {}
}
