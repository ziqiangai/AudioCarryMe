/// 消息发送方。目前只有「我」和「agent」两种。
enum Sender { me, agent }

/// 一条聊天消息。
class Message {
  final String id;

  /// 文本内容。流式回复时会随 token 到达不断追加，故非 final。
  String text;
  final Sender sender;
  final DateTime time;

  /// 被引用消息的作者显示名（如「我」或对方名字）。为空表示这条不是引用。
  /// 冗余存快照而非引用 id：即使原消息被删，引用内容仍在。
  final String? quotedAuthor;

  /// 被引用消息的文本快照。
  final String? quotedText;

  /// 关联的生成任务 id。非空时该消息渲染为图片/视频生成气泡。
  final String? taskId;

  /// 是否为「提示词卡片」：text 即提示词文案，渲染成独立卡片，
  /// 可复制 / 引用（让 AI 重写）/ 直接拿去生图生视频。
  final bool isPromptCard;

  Message({
    required this.id,
    required this.text,
    required this.sender,
    required this.time,
    this.quotedAuthor,
    this.quotedText,
    this.taskId,
    this.isPromptCard = false,
  });

  bool get isMine => sender == Sender.me;

  /// 是否带引用。
  bool get hasQuote => quotedText != null && quotedText!.isNotEmpty;

  /// 是否是生成任务消息（媒体气泡）。
  bool get isGeneration => taskId != null;
}
