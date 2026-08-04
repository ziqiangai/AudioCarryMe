import '../models/conversation.dart';

/// Agent 输出事件。
sealed class AgentEvent {
  const AgentEvent();
}

/// 文本增量（打字机片段）。
class AgentTextDelta extends AgentEvent {
  final String text;
  const AgentTextDelta(this.text);
}

/// 工具调用开始流式传参（用于在 UI 提示"正在准备生成…"，避免长时间空白）。
class AgentToolStart extends AgentEvent {
  final String name;
  const AgentToolStart(this.name);
}

/// 工具调用（生图/生视频）。App 层弹参数面板处理。
class AgentToolCall extends AgentEvent {
  final String id;
  final String name; // generate_image | generate_video
  final Map<String, dynamic> input; // {prompt: ...}
  const AgentToolCall({required this.id, required this.name, required this.input});
}

/// Agent 服务抽象层。
///
/// 产出事件流：文本增量用于打字机；工具调用交给 UI 弹参数面板。
abstract class AgentService {
  Stream<AgentEvent> respond(Conversation conversation);
}

/// 占位实现：把一句固定话逐字吐出来（模拟流式），不产生工具调用。
class StubAgentService implements AgentService {
  @override
  Stream<AgentEvent> respond(Conversation conversation) async* {
    final lastUser = conversation.messages.lastWhere(
      (m) => m.isMine,
      orElse: () => throw StateError('no user message'),
    );
    final reply = '收到：「${lastUser.text}」（占位流式回复）';
    for (final rune in reply.runes) {
      await Future.delayed(const Duration(milliseconds: 35));
      yield AgentTextDelta(String.fromCharCode(rune));
    }
  }
}
