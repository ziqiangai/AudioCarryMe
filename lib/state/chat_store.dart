import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../services/agent_service.dart';
import '../storage/chat_storage.dart';

/// 全局聊天状态。持有所有会话，驱动 agent 回复，并把会话/消息持久化到 [ChatStorage]。
///
/// 用 [ChangeNotifier]，界面侧用 ListenableBuilder 监听刷新，
/// 不额外引入状态管理依赖。
class ChatStore extends ChangeNotifier {
  ChatStore(this._agent, this._storage);

  final AgentService _agent;
  final ChatStorage _storage;
  final List<Conversation> _conversations = [];

  /// 工具调用回调：由当前打开的聊天页注册。一轮回复里的所有工具调用
  /// 作为一个整体传入——同类批量生成只弹一次参数面板。
  void Function(Conversation conversation, List<AgentToolCall> calls)?
      toolCallHandler;

  /// 追加一条本地消息（生成任务气泡、提示词卡片、系统提示），落库并刷新。
  Future<Message> appendLocalMessage(
    Conversation conversation, {
    required String text,
    required Sender sender,
    String? taskId,
    bool isPromptCard = false,
  }) async {
    if (!_conversations.contains(conversation)) {
      _conversations.add(conversation);
      await _storage.upsertConversation(conversation);
    }
    final msg = Message(
      id: _newId('msg'),
      text: text,
      sender: sender,
      time: DateTime.now(),
      taskId: taskId,
      isPromptCard: isPromptCard,
    );
    conversation.messages.add(msg);
    await _storage.insertMessage(conversation.id, msg);
    notifyListeners();
    return msg;
  }

  /// 聊天列表：按最近活跃时间倒序（最新的在最上面）。
  List<Conversation> get conversations {
    final list = [..._conversations];
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// 启动时从数据库加载历史会话。
  Future<void> load() async {
    final loaded = await _storage.loadConversations();
    _conversations
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  int _seq = 0;
  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  /// 新建一个会话对象。此时还没进列表、也不落库，第一条消息发出后才持久化，
  /// 这样「新建后直接退出、什么都没聊」不会留下空会话（贴近微信行为）。
  Conversation createConversation({String name = '智能助手'}) {
    return Conversation(id: _newId('conv'), name: name);
  }

  /// 删除一个会话（含其消息）。
  Future<void> deleteConversation(Conversation conversation) async {
    _conversations.remove(conversation);
    await _storage.deleteConversation(conversation.id);
    notifyListeners();
  }

  /// 删除单条消息。
  Future<void> deleteMessage(Conversation conversation, Message message) async {
    conversation.messages.remove(message);
    await _storage.deleteMessage(message.id);
    notifyListeners();
  }

  /// 发送一条用户消息，并触发 agent 回复。用户消息与成功的回复都会落库。
  ///
  /// [quoted] 非空时，这条消息会带上对它的引用（快照被引用消息的作者与文本）。
  Future<void> sendMessage(
    Conversation conversation,
    String text, {
    Message? quoted,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // 首次发消息时把会话正式加入列表并落库。
    if (!_conversations.contains(conversation)) {
      _conversations.add(conversation);
      await _storage.upsertConversation(conversation);
    }

    final userMsg = Message(
      id: _newId('msg'),
      text: trimmed,
      sender: Sender.me,
      time: DateTime.now(),
      quotedAuthor: quoted == null
          ? null
          : (quoted.isMine ? '我' : conversation.name),
      quotedText: quoted?.text,
    );
    conversation.messages.add(userMsg);
    await _storage.insertMessage(conversation.id, userMsg);
    await _runAgentTurn(conversation);
  }

  /// 重试上一轮 agent 回复：移除末尾的错误消息后重新请求。
  Future<void> retryAgentReply(Conversation conversation) async {
    while (conversation.messages.isNotEmpty &&
        conversation.messages.last.isError) {
      final err = conversation.messages.removeLast();
      await _storage.deleteMessage(err.id);
    }
    notifyListeners();
    await _runAgentTurn(conversation);
  }

  /// 跑一轮 agent：流式打字机 + 工具调用收集 + 错误落库。
  Future<void> _runAgentTurn(Conversation conversation) async {
    conversation.agentTyping = true; // 首个字符前显示「…」
    notifyListeners();

    // 占位气泡，收到首个字符后才加入列表。
    final agentMsg = Message(
      id: _newId('msg'),
      text: '',
      sender: Sender.agent,
      time: DateTime.now(),
    );

    // 打字机队列：网络来的字符先进 received，由定时器按匀速吐给 UI，
    // 与网络突发解耦，避免「一坨字符一次蹦出」。
    final received = <int>[]; // 已收到的字符（rune 码点）
    final toolCalls = <AgentToolCall>[]; // 本轮收到的工具调用
    var shown = 0; // 已显示到第几个字符
    var started = false;
    var streamDone = false;
    Object? streamError;

    void reveal() {
      if (!started && received.isNotEmpty) {
        conversation.messages.add(agentMsg);
        conversation.agentTyping = false;
        conversation.streaming = true;
        started = true;
      }
      if (shown < received.length) {
        // 落后越多，一次吐越多字符，既能追上突发又保持顺滑。
        final backlog = received.length - shown;
        final take = 1 + backlog ~/ 12;
        shown = (shown + take).clamp(0, received.length);
        agentMsg.text = String.fromCharCodes(received.take(shown));
        notifyListeners();
      }
    }

    final ticker = Timer.periodic(const Duration(milliseconds: 18), (_) => reveal());

    try {
      await for (final ev in _agent.respond(conversation)) {
        switch (ev) {
          case AgentTextDelta(:final text):
            received.addAll(text.runes);
          case AgentToolCall():
            toolCalls.add(ev);
        }
      }
    } catch (e) {
      streamError = e;
    } finally {
      streamDone = true;
    }

    // 等打字机把剩余缓冲吐完。
    while (shown < received.length) {
      await Future.delayed(const Duration(milliseconds: 18));
    }
    ticker.cancel();
    conversation.streaming = false;

    if (streamError != null) {
      // 错误消息持久化（isError 标记：展示但不进模型上下文），支持一键重试。
      if (started) {
        await _storage.insertMessage(conversation.id, agentMsg); // 保留已收到部分
      }
      final errMsg = Message(
        id: _newId('msg'),
        text: '$streamError',
        sender: Sender.agent,
        time: DateTime.now(),
        isError: true,
      );
      conversation.messages.add(errMsg);
      await _storage.insertMessage(conversation.id, errMsg);
    } else if (!started) {
      if (toolCalls.isEmpty) {
        // 一个字符都没返回、也没有工具调用。
        agentMsg.text = '（模型没有返回文本内容）';
        conversation.messages.add(agentMsg);
        await _storage.insertMessage(conversation.id, agentMsg);
      }
    } else {
      // 正常收完，落库（每次只在流结束后写一次盘）。
      await _storage.insertMessage(conversation.id, agentMsg);
    }

    conversation.agentTyping = false;
    // streamDone 仅用于表达语义；如需可在此断言。
    assert(streamDone);
    notifyListeners();

    // 文本吐完后再整批派发工具调用（同类批量只弹一次参数面板）。
    if (toolCalls.isNotEmpty) {
      toolCallHandler?.call(conversation, List.of(toolCalls));
    }
  }
}
