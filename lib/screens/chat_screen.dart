import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import '../models/conversation.dart';
import '../models/gen_ref.dart';
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
import '../config/editor_i18n.dart';
import 'gen_param_sheet.dart';
import 'gen_tasks_screen.dart';
import 'request_log_screen.dart';
import 'video_composer_screen.dart';
import 'video_trim_screen.dart';

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

  /// 多选复制模式（微信式勾选聊天记录）。
  bool _selectMode = false;
  final Set<String> _selectedIds = {};

  /// 引用定位：被高亮的消息 id + 各消息的定位 key。
  String? _highlightedMsgId;
  final Map<String, GlobalKey> _msgKeys = {};

  GlobalKey _keyFor(String id) => _msgKeys.putIfAbsent(id, GlobalKey.new);

  /// 列表项统一包一层：提供定位 key + 引用高亮背景。
  Widget _wrapMsg(String id, Widget child) => Container(
        key: _keyFor(id),
        color: _highlightedMsgId == id ? const Color(0x2242A5F5) : null,
        child: child,
      );

  /// 回到某条消息处：删掉它之后的全部（用户消息则重新生成回复）。
  Future<void> _restartFrom(Message msg) async {
    final regen = msg.isMine;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('回到此处'),
        content: Text(regen
            ? '将删除这条之后的所有消息，并基于这条重新生成回复。确定？'
            : '将删除这条之后的所有消息，从这里继续。确定？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定')),
        ],
      ),
    );
    if (ok == true) await widget.store.restartFrom(widget.conversation, msg);
  }

  /// 编辑我的某条消息并从此重新生成。
  Future<void> _editMessage(Message msg) async {
    final ctl = TextEditingController(text: msg.text);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          minLines: 1,
          maxLines: 6,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctl.text),
              child: const Text('保存并重发')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await widget.store.editAndRegenerate(widget.conversation, msg, result);
      _scrollToBottom();
    }
  }

  /// 点击引用条 → 弹出被引用内容（提示词全文 / 参考图大图），并可「在聊天中定位」。
  void _onRefTap(GenRef ref) {
    Message? target;
    for (final m in widget.conversation.messages) {
      if (ref.targetIsTask ? m.taskId == ref.targetId : m.id == ref.targetId) {
        target = m;
        break;
      }
    }

    Widget content;
    if (ref.kind == GenRefKind.promptCard) {
      content = SelectableText(
        target?.text ?? ref.snapshotText ?? '（内容已不可用）',
        style: const TextStyle(fontSize: 14, height: 1.6),
      );
    } else {
      final task =
          target?.taskId != null ? widget.genStore.byId(target!.taskId!) : null;
      final img = task?.localAt(0) ??
          (task != null && task.resultUrls.isNotEmpty
              ? task.resultUrls.first
              : ref.snapshotImage);
      content = img == null
          ? const Text('图片已不可用')
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: img.startsWith('/')
                  ? Image.file(File(img))
                  : Image.network(img),
            );
    }

    final located = target;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (_, scrollCtl) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
            child: Row(children: [
              Text('引用的${ref.kind.label}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (located != null)
                TextButton.icon(
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text('定位'),
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    _locateMessage(located.id);
                  },
                ),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          Expanded(
            child: ListView(
              controller: scrollCtl,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
              children: [content],
            ),
          ),
        ]),
      ),
    );
  }

  /// 尽力滚动到并高亮某条消息（对已构建的项有效）。
  void _locateMessage(String id) {
    setState(() => _highlightedMsgId = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _msgKeys[id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300),
            alignment: 0.3,
            curve: Curves.easeOut);
      }
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _highlightedMsgId == id) {
        setState(() => _highlightedMsgId = null);
      }
    });
  }

  void _exitSelectMode() => setState(() {
        _selectMode = false;
        _selectedIds.clear();
      });

  /// 把一条消息格式化成可分析的文本行。
  String _formatMessage(Message m) {
    final who = m.isMine ? '我' : '助手';
    String body;
    if (m.isGeneration) {
      final task = widget.genStore.byId(m.taskId!);
      body = task == null
          ? m.text
          : '[${task.kind == GenKind.image ? '图片' : '视频'}生成·${task.modelId}] ${task.prompt}';
    } else if (m.isPromptCard) {
      body = '[提示词卡片] ${m.text}';
    } else if (m.isError) {
      body = '[错误] ${m.text}';
    } else {
      body = m.text;
    }
    if (m.hasQuote) {
      body = '(引用 ${m.quotedAuthor}：${m.quotedText}) $body';
    }
    return '$who: $body';
  }

  Future<void> _copySelected() async {
    final msgs = widget.conversation.messages
        .where((m) => _selectedIds.contains(m.id))
        .toList();
    if (msgs.isEmpty) return;
    final text = msgs.map(_formatMessage).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已复制 ${msgs.length} 条聊天记录'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ));
    }
    _exitSelectMode();
  }

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

  /// Agent 工具调用分发（整批）：同类生成只弹一次参数面板。
  Future<void> _onToolCall(
      Conversation conv, List<AgentToolCall> calls) async {
    if (!mounted || conv != widget.conversation) return;
    widget.store.clearPendingGen(conv); // 进入处理，撤下「准备中」提示

    // 1) 提示词卡片逐个产出（带场景 label，供后续生成解析引用 id）。
    for (final call in calls.where((c) => c.name == 'design_prompt')) {
      final label = (call.input['label'] as String?)?.trim();
      await widget.store.appendLocalMessage(widget.conversation,
          text: (call.input['prompt'] as String?) ?? '',
          sender: Sender.agent,
          isPromptCard: true,
          label: (label?.isEmpty ?? true) ? null : label);
    }
    _scrollToBottom();

    // 2) 生成调用按类型分组，每组一次参数面板。
    for (final kind in [GenKind.image, GenKind.video]) {
      final group = calls
          .where((c) =>
              c.name ==
              (kind == GenKind.image ? 'generate_image' : 'generate_video'))
          .toList();
      if (group.isEmpty) continue;
      if (!mounted) return;
      await _runGenerationGroup(kind, group);
    }
  }

  /// 执行一组同类生成：解析 ref_label 血缘，一次面板参数应用到全部。
  Future<void> _runGenerationGroup(
      GenKind kind, List<AgentToolCall> group) async {
    // 解析每个调用的参考图（引用消息暂存 > ref_label 场景查找）。
    final quoteRef = _pendingRefUrl;
    _pendingRefUrl = null;

    final resolved = group.map((call) {
      final label = (call.input['label'] as String?)?.trim();
      final refLabel = (call.input['ref_label'] as String?)?.trim();
      GenerationTask? parent;
      if (refLabel != null && refLabel.isNotEmpty) {
        parent = widget.genStore
            .findImageByLabel(widget.conversation.id, refLabel);
      }
      return (
        prompt: (call.input['prompt'] as String?) ?? '',
        label: (label?.isEmpty ?? true) ? null : label,
        parent: parent,
      );
    }).toList();

    final isBatch = group.length > 1;
    final hasRefs = resolved.any((r) => r.parent != null) ||
        (quoteRef != null && !isBatch);

    final result = await showGenParamSheet(
      context,
      kind: kind,
      prompt: isBatch ? '' : resolved.first.prompt,
      refImageUrl: isBatch ? null : (quoteRef ??
          resolved.first.parent?.resultUrls.firstOrNull),
      batchCount: group.length,
      batchRef: isBatch && hasRefs,
    );
    if (result == null || !mounted) {
      await widget.store.appendLocalMessage(widget.conversation,
          text: '（已取消本次生成）', sender: Sender.agent);
      return;
    }

    for (var i = 0; i < resolved.length; i++) {
      final r = resolved[i];
      final params = Map<String, String>.of(result.params);
      // 批量时按各自血缘带参考图；单个时面板已注入。
      if (isBatch && r.parent != null) {
        params['imageUrl'] = r.parent!.resultUrls.first;
      }
      final finalPrompt = isBatch ? r.prompt : result.prompt;
      final task = await widget.genStore.start(
        conversationId: widget.conversation.id,
        kind: kind,
        modelId: result.modelId,
        prompt: finalPrompt,
        params: params,
        label: r.label,
        parentTaskId: r.parent?.id,
        references: _buildRefs(
            prompt: finalPrompt, label: r.label, parent: r.parent),
      );
      final tag = r.label != null ? '·${r.label}' : '';
      await widget.store.appendLocalMessage(widget.conversation,
          text: kind == GenKind.image ? '[图片生成$tag]' : '[视频生成$tag]',
          sender: Sender.agent,
          taskId: task.id);
    }
    _scrollToBottom();
  }

  /// 写入时解析引用为稳定 id：卡片（label 优先，prompt 文本兜底）+ 参考图任务。
  List<GenRef> _buildRefs({
    required String prompt,
    String? label,
    GenerationTask? parent,
  }) {
    final refs = <GenRef>[];
    final card = _findPromptCard(label: label, prompt: prompt);
    if (card != null) {
      refs.add(GenRef(
        kind: GenRefKind.promptCard,
        targetId: card.id,
        targetIsTask: false,
        snapshotText: _firstLine(card.text),
      ));
    }
    if (parent != null) {
      refs.add(GenRef(
        kind: GenRefKind.referenceImage,
        targetId: parent.id,
        targetIsTask: true,
        snapshotImage: parent.localAt(0) ??
            (parent.resultUrls.isNotEmpty ? parent.resultUrls.first : null),
      ));
    }
    return refs;
  }

  /// 定位来源提示词卡片消息：优先同 label，否则 prompt 文本精确匹配；取最新一条。
  Message? _findPromptCard({String? label, required String prompt}) {
    Message? byLabel, byText;
    final p = prompt.trim();
    for (final m in widget.conversation.messages) {
      if (!m.isPromptCard) continue;
      if (label != null && label.isNotEmpty && m.label == label) byLabel = m;
      if (m.text.trim() == p) byText = m;
    }
    return byLabel ?? byText;
  }

  static String _firstLine(String text) {
    final line = text.trim().split('\n').first.trim();
    return line.length > 40 ? '${line.substring(0, 40)}…' : line;
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
    final succeeded = task.status == GenTaskStatus.succeeded &&
        task.resultUrls.isNotEmpty;
    final canQuote = task.kind == GenKind.image && succeeded;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy,
          overlay.size.width - pos.dx, overlay.size.height - pos.dy),
      items: [
        if (canQuote)
          const PopupMenuItem(value: 'quote', child: Text('引用')),
        if (task.kind == GenKind.image && succeeded)
          const PopupMenuItem(value: 'edit', child: Text('编辑图片')),
        if (task.kind == GenKind.video && succeeded)
          const PopupMenuItem(value: 'trim', child: Text('剪辑视频')),
        const PopupMenuItem(value: 'regen', child: Text('再生一张')),
        const PopupMenuItem(value: 'prompt', child: Text('复制提示词')),
      ],
    );
    if (!mounted) return;
    if (selected == 'quote') {
      setState(() => _quoting = message);
    } else if (selected == 'edit') {
      await _editImage(task);
    } else if (selected == 'trim') {
      await _trimVideo(task);
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

  /// 确保任务产物已在本地（未下载则先下载）。返回首个本地路径。
  Future<String?> _ensureLocal(GenerationTask task) async {
    if (task.localAt(0) != null) return task.localAt(0);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('正在下载素材…'),
      duration: Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
    ));
    await widget.genStore.downloadMedia(task);
    final local = task.localAt(0);
    if (local == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('下载失败，源链接可能已过期'),
        behavior: SnackBarBehavior.floating,
      ));
    }
    return local;
  }

  /// 派生产物入库并回流为聊天气泡。
  Future<void> _appendDerived({
    required GenerationTask source,
    required GenKind kind,
    required String modelId,
    required String localPath,
    required String messageTag,
  }) async {
    final task = await widget.genStore.addDerived(
      conversationId: widget.conversation.id,
      kind: kind,
      modelId: modelId,
      prompt: source.prompt,
      localPath: localPath,
      label: source.label,
      parentTaskId: source.id,
    );
    final tag = source.label != null ? '·${source.label}' : '';
    await widget.store.appendLocalMessage(widget.conversation,
        text: '[$messageTag$tag]', sender: Sender.agent, taskId: task.id);
    _scrollToBottom();
  }

  /// 图片编辑（pro_image_editor）。
  Future<void> _editImage(GenerationTask task) async {
    final local = await _ensureLocal(task);
    if (local == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProImageEditor.file(
        File(local),
        configs: const ProImageEditorConfigs(
          i18n: kEditorI18nZh,
          cropRotateEditor: CropRotateEditorConfigs(
            aspectRatios: [
              AspectRatioItem(text: '自由', value: -1),
              AspectRatioItem(text: '原图', value: 0),
              AspectRatioItem(text: '1:1', value: 1),
              AspectRatioItem(text: '4:3', value: 4 / 3),
              AspectRatioItem(text: '3:4', value: 3 / 4),
              AspectRatioItem(text: '16:9', value: 16 / 9),
              AspectRatioItem(text: '9:16', value: 9 / 16),
            ],
          ),
        ),
        callbacks: ProImageEditorCallbacks(
          onImageEditingComplete: (bytes) async {
            final path = await widget.genStore.mediaCache!.saveBytes(
                bytes, 'edit-${DateTime.now().millisecondsSinceEpoch}', 'jpg');
            await _appendDerived(
              source: task,
              kind: GenKind.image,
              modelId: 'local-edit',
              localPath: path,
              messageTag: '图片编辑',
            );
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
    ));
  }

  /// 视频修剪（video_trimmer）。
  Future<void> _trimVideo(GenerationTask task) async {
    final local = await _ensureLocal(task);
    if (local == null || !mounted) return;
    final out = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => VideoTrimScreen(path: local),
    ));
    if (out == null || !mounted) return;
    await _appendDerived(
      source: task,
      kind: GenKind.video,
      modelId: 'local-trim',
      localPath: out,
      messageTag: '剪辑片段',
    );
  }

  /// 多选的成功视频任务（按消息时间顺序），用于拼接。
  /// 选中的消息必须全部是成功的视频生成，且 ≥2 段，否则返回空（按钮隐藏）。
  List<GenerationTask> _selectedVideoTasks() {
    final tasks = <GenerationTask>[];
    for (final m in widget.conversation.messages) {
      if (!_selectedIds.contains(m.id)) continue;
      if (!m.isGeneration) return const [];
      final t = m.taskId != null ? widget.genStore.byId(m.taskId!) : null;
      if (t == null ||
          t.kind != GenKind.video ||
          t.status != GenTaskStatus.succeeded ||
          t.resultUrls.isEmpty) {
        return const [];
      }
      tasks.add(t);
    }
    return tasks.length >= 2 ? tasks : const [];
  }

  /// 会话内全部成功的视频任务（合成编辑器的候选池，含派生产物）。
  List<GenerationTask> _allConversationVideos() {
    final seen = <String>{};
    final out = <GenerationTask>[];
    for (final m in widget.conversation.messages) {
      if (!m.isGeneration) continue;
      final t = widget.genStore.byId(m.taskId!);
      if (t != null &&
          t.kind == GenKind.video &&
          t.status == GenTaskStatus.succeeded &&
          t.resultUrls.isNotEmpty &&
          seen.add(t.id)) {
        out.add(t);
      }
    }
    return out;
  }

  /// 打开合成编辑器：多段排序/剪辑/替换/增删 → 导出成片。
  Future<void> _concatSelected() async {
    final tasks = _selectedVideoTasks();
    if (tasks.isEmpty) return;
    _exitSelectMode();

    // 逐段确保本地。
    final segments = <(GenerationTask, String)>[];
    for (final t in tasks) {
      final p = await _ensureLocal(t);
      if (p == null) return;
      segments.add((t, p));
    }
    if (!mounted) return;

    final result =
        await Navigator.of(context).push<ComposeResult>(MaterialPageRoute(
      builder: (_) => VideoComposerScreen(
        initial: segments,
        available: _allConversationVideos(),
        genStore: widget.genStore,
      ),
    ));
    if (result == null || !mounted) return;
    await _appendDerived(
      source: tasks.first,
      kind: GenKind.video,
      modelId: 'local-concat',
      localPath: result.path,
      messageTag: '拼接成片×${result.count}',
    );
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
      appBar: _selectMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectMode,
              ),
              title: Text('已选 ${_selectedIds.length} 条'),
            )
          : AppBar(
              title: Text(conv.name),
              actions: [
                _TopMenu(
                  logStore: widget.logStore,
                  genStore: widget.genStore,
                  conversationId: conv.id,
                  onCopyChat: () => setState(() => _selectMode = true),
                )
              ],
            ),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: widget.store,
              builder: (context, _) {
                final msgs = conv.messages;
                // 底部占位：输入中 或 正在准备生成（工具参数流式传输中）。
                final busy = conv.agentTyping || conv.pendingGenCount > 0;
                final count = msgs.length + (busy ? 1 : 0);
                // reverse 列表：index 0 = 最新（在底部）。
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: count,
                  itemBuilder: (context, i) {
                    if (busy && i == 0) {
                      return conv.agentTyping
                          ? const _TypingBubble()
                          : _PrepareBubble(count: conv.pendingGenCount);
                    }
                    final mi = msgs.length - 1 - (busy ? i - 1 : i);
                    final msg = msgs[mi];
                    // 多选模式：左侧复选圈，点击任意处切换勾选。
                    if (_selectMode) {
                      final checked = _selectedIds.contains(msg.id);
                      return _wrapMsg(
                        msg.id,
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => checked
                              ? _selectedIds.remove(msg.id)
                              : _selectedIds.add(msg.id)),
                          child: Row(children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Icon(
                                checked
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 22,
                                color: checked
                                    ? WeColors.green
                                    : const Color(0xFFBBBBBB),
                              ),
                            ),
                            Expanded(
                                child: AbsorbPointer(
                                    child: _buildMessageItem(conv, msg, mi,
                                        msgs.length))),
                          ]),
                        ),
                      );
                    }
                    return _wrapMsg(
                        msg.id, _buildMessageItem(conv, msg, mi, msgs.length));
                  },
                );
              },
            ),
          ),
          if (_selectMode)
            _SelectionBar(
              count: _selectedIds.length,
              canConcat: _selectedVideoTasks().isNotEmpty,
              onSelectAll: () => setState(() {
                _selectedIds
                  ..clear()
                  ..addAll(conv.messages.map((m) => m.id));
              }),
              onCopy: _copySelected,
              onConcat: _concatSelected,
            )
          else ...[
            if (_quoting != null)
              _QuoteBar(
                message: _quoting!,
                peerName: conv.name,
                onCancel: () => setState(() => _quoting = null),
              ),
            _InputBar(controller: _input, canSend: _canSend, onSend: _send),
          ],
        ],
      ),
    );
  }

  /// 单条消息渲染（原 itemBuilder 主体，供普通/多选两种模式复用）。
  Widget _buildMessageItem(
      Conversation conv, Message msg, int mi, int total) {
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
                    // 错误消息 → 错误气泡（带重试）。
                    if (msg.isError) {
                      return _ErrorMessageBubble(
                        message: msg,
                        onRetry: () =>
                            widget.store.retryAgentReply(conv),
                        onDelete: () =>
                            widget.store.deleteMessage(conv, msg),
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
                              onRefTap: _onRefTap,
                            ),
                          ],
                        ),
                      );
                    }
    final isLast = mi == total - 1;
    final showCursor = conv.streaming && isLast && !msg.isMine;
    return _MessageBubble(
      message: msg,
      peerName: conv.name,
      showCursor: showCursor,
      onQuote: () => setState(() => _quoting = msg),
      onDelete: () => widget.store.deleteMessage(conv, msg),
      onRestart: () => _restartFrom(msg),
      onEdit: msg.isMine ? () => _editMessage(msg) : null,
    );
  }
}

/// 多选模式底部操作栏：全选 / 复制。
class _SelectionBar extends StatelessWidget {
  final int count;
  final bool canConcat;
  final VoidCallback onSelectAll;
  final VoidCallback onCopy;
  final VoidCallback onConcat;
  const _SelectionBar({
    required this.count,
    required this.canConcat,
    required this.onSelectAll,
    required this.onCopy,
    required this.onConcat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: WeColors.barBg,
        border: Border(top: BorderSide(color: WeColors.divider, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      child: Row(children: [
        GestureDetector(
          onTap: onSelectAll,
          child: const Text('全选',
              style: TextStyle(fontSize: 15, color: Color(0xFF2E7CF6))),
        ),
        const Spacer(),
        if (canConcat) ...[
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C4DFF),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.movie_filter_outlined, size: 16),
            label: const Text('拼接', style: TextStyle(fontSize: 14)),
            onPressed: onConcat,
          ),
          const SizedBox(width: 10),
        ],
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: count > 0 ? WeColors.green : const Color(0xFFC8C8C8),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: Text('复制${count > 0 ? '（$count）' : ''}',
              style: const TextStyle(fontSize: 14)),
          onPressed: count > 0 ? onCopy : null,
        ),
      ]),
    );
  }
}

/// 右上角三点菜单（自定义样式，深色圆角，非原生默认外观）。
class _TopMenu extends StatelessWidget {
  final RequestLogStore logStore;
  final GenerationStore genStore;
  final String conversationId;
  final VoidCallback onCopyChat;
  const _TopMenu({
    required this.logStore,
    required this.genStore,
    required this.conversationId,
    required this.onCopyChat,
  });

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
            builder: (_) => RequestLogScreen(
                logStore: logStore, conversationId: conversationId),
          ));
        } else if (v == 'gens') {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GenTasksScreen(
                store: genStore, conversationId: conversationId),
          ));
        } else if (v == 'copy') {
          onCopyChat();
        }
      },
      itemBuilder: (_) => [
        _menuItem('copy', Icons.checklist_rounded, '复制聊天记录'),
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

  /// 编辑（仅我的消息）与「回到此处重来」。
  final VoidCallback? onEdit;
  final VoidCallback onRestart;

  const _MessageBubble({
    required this.message,
    required this.peerName,
    required this.onQuote,
    required this.onDelete,
    required this.onRestart,
    this.onEdit,
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
                    if (onEdit != null)
                      (Icons.edit_outlined, '编辑', () {
                        editableState.hideToolbar();
                        onEdit!();
                      }),
                    (Icons.restart_alt_rounded, '回到此处', () {
                      editableState.hideToolbar();
                      onRestart();
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

/// 错误消息气泡：红色调 + 重试/删除。
class _ErrorMessageBubble extends StatelessWidget {
  final Message message;
  final VoidCallback onRetry;
  final VoidCallback onDelete;
  const _ErrorMessageBubble({
    required this.message,
    required this.onRetry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFF3C9CB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.error_outline, size: 15, color: Color(0xFFE5484D)),
              SizedBox(width: 6),
              Text('回复失败',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE5484D))),
            ]),
            const SizedBox(height: 4),
            // 可选中复制，完整展示不截断。
            SelectableText(
              message.text,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF996666), height: 1.45),
            ),
            const SizedBox(height: 6),
            Row(children: [
              _btn('重试', Icons.refresh, onRetry, primary: true),
              const SizedBox(width: 10),
              _btn('复制', Icons.copy_rounded, () async {
                await Clipboard.setData(ClipboardData(text: message.text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('已复制错误信息'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              }),
              const SizedBox(width: 10),
              _btn('删除', Icons.close, onDelete),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, IconData icon, VoidCallback onTap,
          {bool primary = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: primary ? const Color(0xFFE5484D) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: primary
                ? null
                : Border.all(color: const Color(0xFFDDBBBB)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 13,
                color: primary ? Colors.white : const Color(0xFF996666)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color:
                        primary ? Colors.white : const Color(0xFF996666))),
          ]),
        ),
      );
}

/// 「正在准备生成…」占位（工具参数流式传输期间，避免看起来卡住）。
class _PrepareBubble extends StatelessWidget {
  final int count;
  const _PrepareBubble({required this.count});

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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: WeColors.bubbleOther,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF2E7CF6)),
              ),
              const SizedBox(width: 8),
              Text('正在准备生成 $count 项…',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF666666))),
            ]),
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
