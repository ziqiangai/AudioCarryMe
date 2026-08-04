import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';
import '../models/generation_task.dart';
import '../models/message.dart';
import '../models/model_catalog.dart';
import '../services/agent_service.dart';
import '../state/chat_store.dart';
import '../state/generation_store.dart';
import '../state/request_log_store.dart';
import '../theme.dart';
import '../widgets/generation_bubble.dart';
import '../widgets/prompt_card.dart';
import 'gen_param_sheet.dart';
import 'gen_tasks_screen.dart';
import 'request_log_screen.dart';

/// 聊天界面：消息气泡列表 + 底部输入栏。
class ChatScreen extends StatefulWidget {
  final ChatStore store;
  final Conversation conversation;
  final RequestLogStore logStore;
  final GenerationStore genStore;
  const ChatScreen({
    super.key,
    required this.store,
    required this.conversation,
    required this.logStore,
    required this.genStore,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _canSend = false;

  /// 当前正在引用的消息（非空时输入框上方显示引用条）。
  Message? _quoting;

  /// 引用图片消息后暂存的参考图 URL：下一次工具调用会作为参考图（图生图/图生视频）。
  String? _pendingRefUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input.addListener(() {
      final can = _input.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
    // 注册 agent 工具调用回调：弹参数面板。
    widget.store.toolCallHandler = _onToolCall;
  }

  @override
  void dispose() {
    if (widget.store.toolCallHandler == _onToolCall) {
      widget.store.toolCallHandler = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Agent 工具调用分发。
  Future<void> _onToolCall(Conversation conv, AgentToolCall call) async {
    if (!mounted || conv != widget.conversation) return;
    final prompt = (call.input['prompt'] as String?) ?? '';

    // design_prompt → 直接产出提示词卡片消息，不弹面板。
    if (call.name == 'design_prompt') {
      await widget.store.appendLocalMessage(widget.conversation,
          text: prompt, sender: Sender.agent, isPromptCard: true);
      _scrollToBottom();
      return;
    }

    final kind =
        call.name == 'generate_video' ? GenKind.video : GenKind.image;
    final refUrl = _pendingRefUrl;
    _pendingRefUrl = null;

    final result = await showGenParamSheet(context,
        kind: kind, prompt: prompt, refImageUrl: refUrl);
    if (result == null || !mounted) {
      // 用户取消：留一句话保持上下文完整。
      await widget.store.appendLocalMessage(widget.conversation,
          text: '（已取消本次生成）', sender: Sender.agent);
      return;
    }
    await _startGeneration(kind, result);
  }

  /// 提示词卡片一键生成：直接弹参数面板（prompt=卡片全文，不经 Agent）。
  Future<void> _genFromCard(String prompt, GenKind kind) async {
    final result =
        await showGenParamSheet(context, kind: kind, prompt: prompt);
    if (result == null || !mounted) return;
    await _startGeneration(kind, result);
  }

  Future<void> _startGeneration(GenKind kind, GenSheetResult r) async {
    final task = await widget.genStore.start(
      conversationId: widget.conversation.id,
      kind: kind,
      modelId: r.modelId,
      prompt: r.prompt,
      params: r.params,
    );
    await widget.store.appendLocalMessage(widget.conversation,
        text: kind == GenKind.image ? '[图片生成]' : '[视频生成]',
        sender: Sender.agent,
        taskId: task.id);
    _scrollToBottom();
  }

  /// 长按媒体气泡：引用（做参考图）/ 再生一张 / 复制提示词。
  Future<void> _onBubbleLongPress(
      Message message, GenerationTask task, Offset pos) async {
    final canQuote = task.kind == GenKind.image &&
        task.status == GenTaskStatus.succeeded &&
        task.resultUrls.isNotEmpty;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy,
          overlay.size.width - pos.dx, overlay.size.height - pos.dy),
      items: [
        if (canQuote)
          const PopupMenuItem(value: 'quote', child: Text('引用')),
        const PopupMenuItem(value: 'regen', child: Text('再生一张')),
        const PopupMenuItem(value: 'prompt', child: Text('复制提示词')),
      ],
    );
    if (!mounted) return;
    if (selected == 'quote') {
      setState(() => _quoting = message);
    } else if (selected == 'regen') {
      final newTask = await widget.genStore.regenerate(task);
      await widget.store.appendLocalMessage(widget.conversation,
          text: task.kind == GenKind.image ? '[图片生成]' : '[视频生成]',
          sender: Sender.agent,
          taskId: newTask.id);
      _scrollToBottom();
    } else if (selected == 'prompt') {
      await Clipboard.setData(ClipboardData(text: task.prompt));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已复制提示词'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  /// 列表用 reverse:true 倒挂：偏移 0 即底部，新消息天然贴底，
  /// 用户上翻历史时不会被自动拉回。只有明确动作（发送）才主动回底。
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        0, // reverse 列表的底部
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// 键盘弹出时，若本就贴近底部则保持贴底（倒挂列表大多数情况自动保持）。
  @override
  void didChangeMetrics() {
    if (_scroll.hasClients && _scroll.position.pixels < 120) {
      _scrollToBottom();
    }
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    final quoted = _quoting;
    _input.clear();
    setState(() => _quoting = null);

    // 引用了成功的图片生成消息 → 暂存参考图，供本轮工具调用做图生图/图生视频。
    _pendingRefUrl = null;
    if (quoted != null && quoted.isGeneration) {
      final task = widget.genStore.byId(quoted.taskId!);
      if (task != null &&
          task.kind == GenKind.image &&
          task.status == GenTaskStatus.succeeded &&
          task.resultUrls.isNotEmpty) {
        _pendingRefUrl = task.resultUrls.first;
      }
    }

    await widget.store.sendMessage(widget.conversation, text, quoted: quoted);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final conv = widget.conversation;
    return Scaffold(
      backgroundColor: WeColors.bg,
      appBar: AppBar(
        title: Text(conv.name),
        actions: [
          _TopMenu(logStore: widget.logStore, genStore: widget.genStore)
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: widget.store,
              builder: (context, _) {
                final msgs = conv.messages;
                final count = msgs.length + (conv.agentTyping ? 1 : 0);
                // reverse 列表：index 0 = 最新（在底部）。
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: count,
                  itemBuilder: (context, i) {
                    // 「输入中…」占位挂在最底部。
                    if (conv.agentTyping && i == 0) {
                      return const _TypingBubble();
                    }
                    final mi =
                        msgs.length - 1 - (conv.agentTyping ? i - 1 : i);
                    final msg = msgs[mi];
                    // 提示词卡片。
                    if (msg.isPromptCard) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SquareAvatar(
                              label: conv.name.isNotEmpty ? conv.name[0] : '?',
                              color: WeColors.avatar,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: PromptCard(
                                prompt: msg.text,
                                onQuote: () =>
                                    setState(() => _quoting = msg),
                                onGenImage: () =>
                                    _genFromCard(msg.text, GenKind.image),
                                onGenVideo: () =>
                                    _genFromCard(msg.text, GenKind.video),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    // 生成任务消息 → 媒体气泡（骨架屏/图片/视频）。
                    if (msg.isGeneration) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SquareAvatar(
                              label: conv.name.isNotEmpty ? conv.name[0] : '?',
                              color: WeColors.avatar,
                            ),
                            const SizedBox(width: 8),
                            GenerationBubble(
                              store: widget.genStore,
                              taskId: msg.taskId!,
                              onLongPress: (t, pos) =>
                                  _onBubbleLongPress(msg, t, pos),
                            ),
                          ],
                        ),
                      );
                    }
                    final isLast = mi == msgs.length - 1;
                    final showCursor =
                        conv.streaming && isLast && !msg.isMine;
                    return _MessageBubble(
                      message: msg,
                      peerName: conv.name,
                      showCursor: showCursor,
                      onQuote: () => setState(() => _quoting = msg),
                      onDelete: () => widget.store.deleteMessage(conv, msg),
                    );
                  },
                );
              },
            ),
          ),
          if (_quoting != null)
            _QuoteBar(
              message: _quoting!,
              peerName: conv.name,
              onCancel: () => setState(() => _quoting = null),
            ),
          _InputBar(controller: _input, canSend: _canSend, onSend: _send),
        ],
      ),
    );
  }
}

/// 右上角三点菜单（自定义样式，深色圆角，非原生默认外观）。
class _TopMenu extends StatelessWidget {
  final RequestLogStore logStore;
  final GenerationStore genStore;
  const _TopMenu({required this.logStore, required this.genStore});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz, size: 24),
      color: const Color(0xFF3D3D3D),
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: PopupMenuPosition.under, // 紧贴按钮下方（去掉额外 offset 修偏移）
      onSelected: (v) {
        if (v == 'logs') {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RequestLogScreen(logStore: logStore),
          ));
        } else if (v == 'gens') {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GenTasksScreen(store: genStore),
          ));
        }
      },
      itemBuilder: (_) => [
        _menuItem('gens', Icons.auto_awesome, '生成任务'),
        _menuItem('logs', Icons.query_stats, '大模型请求记录'),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 19, color: Colors.white),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 14.5)),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final String peerName;

  /// 是否在文末显示打字机光标（流式输出中的末条 agent 气泡）。
  final bool showCursor;

  /// 长按/选中后的操作。
  final VoidCallback onQuote;
  final VoidCallback onDelete;

  const _MessageBubble({
    required this.message,
    required this.peerName,
    required this.onQuote,
    required this.onDelete,
    this.showCursor = false,
  });

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final avatar = _SquareAvatar(
      label: mine ? '我' : (peerName.isNotEmpty ? peerName[0] : '?'),
      color: mine ? WeColors.green : WeColors.avatar,
    );

    final bubble = Flexible(
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: mine ? WeColors.bubbleMine : WeColors.bubbleOther,
              borderRadius: BorderRadius.circular(6),
            ),
            // 可自由拖选文字；长按/选中弹出自定义 action bar。
            child: SelectableText.rich(
              TextSpan(children: [
                TextSpan(text: message.text),
                if (showCursor)
                  const TextSpan(
                    text: ' ▍',
                    style: TextStyle(
                        color: WeColors.green, fontWeight: FontWeight.bold),
                  ),
              ]),
              style: const TextStyle(
                  fontSize: 16, height: 1.35, color: Colors.black),
              contextMenuBuilder: (context, editableState) {
                final value = editableState.textEditingValue;
                final sel = value.selection;
                final selected = sel.isValid && !sel.isCollapsed
                    ? sel.textInside(value.text)
                    : message.text;
                return _MessageActionBar(
                  anchor: editableState.contextMenuAnchors.primaryAnchor,
                  actions: [
                    (Icons.copy_rounded, '复制', () {
                      Clipboard.setData(ClipboardData(text: selected));
                      editableState.hideToolbar();
                      _toast(context, '已复制');
                    }),
                    (Icons.format_quote_rounded, '引用', () {
                      editableState.hideToolbar();
                      onQuote();
                    }),
                    (Icons.delete_outline_rounded, '删除', () {
                      editableState.hideToolbar();
                      onDelete();
                    }),
                  ],
                );
              },
            ),
          ),
          if (message.hasQuote)
            Container(
              margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              constraints: const BoxConstraints(maxWidth: 260),
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${message.quotedAuthor}：${message.quotedText}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: mine ? [bubble, avatar] : [avatar, bubble],
      ),
    );
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    duration: const Duration(seconds: 1),
    behavior: SnackBarBehavior.floating,
    width: 140,
  ));
}

/// 微信风格消息操作条：深色圆角、图标+文字，定位在选中处上方。
class _MessageActionBar extends StatelessWidget {
  final Offset anchor;
  final List<(IconData, String, VoidCallback)> actions;
  const _MessageActionBar({required this.anchor, required this.actions});

  @override
  Widget build(BuildContext context) {
    const itemW = 56.0;
    final barW = actions.length * itemW;
    final media = MediaQuery.of(context);
    final size = media.size;

    double left = (anchor.dx - barW / 2).clamp(8.0, size.width - barW - 8.0);
    double top = anchor.dy - 58; // 默认放选中处上方
    if (top < media.padding.top + 8) top = anchor.dy + 14; // 上方没地方就放下方

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF4C4C4C),
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (icon, label, cb) in actions)
                    InkWell(
                      onTap: cb,
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: itemW,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, color: Colors.white, size: 21),
                              const SizedBox(height: 4),
                              Text(label,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11.5)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 输入框上方的「正在引用」条。
class _QuoteBar extends StatelessWidget {
  final Message message;
  final String peerName;
  final VoidCallback onCancel;
  const _QuoteBar({
    required this.message,
    required this.peerName,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final author = message.isMine ? '我' : peerName;
    return Container(
      color: const Color(0xFFE9E9E9),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Container(width: 3, height: 32, color: WeColors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$author：${message.text}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Color(0xFF888888)),
            onPressed: onCancel,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SquareAvatar(label: 'A', color: WeColors.avatar),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: WeColors.bubbleOther,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const SizedBox(
              width: 20,
              height: 10,
              child: Text('…', style: TextStyle(fontSize: 16, height: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SquareAvatar extends StatelessWidget {
  final String label;
  final Color color;
  const _SquareAvatar({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
      alignment: Alignment.center,
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool canSend;
  final VoidCallback onSend;
  const _InputBar({required this.controller, required this.canSend, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: WeColors.barBg,
        border: Border(top: BorderSide(color: WeColors.divider, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
        10, 8, 10, 8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 11),
                ),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: canSend ? onSend : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: canSend ? WeColors.green : const Color(0xFFC8C8C8),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('发送',
                  style: TextStyle(color: Colors.white, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
