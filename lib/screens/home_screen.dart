import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../state/chat_store.dart';
import '../state/generation_store.dart';
import '../state/log_store.dart';
import '../state/request_log_store.dart';
import '../theme.dart';
import 'chat_screen.dart';
import 'logs_screen.dart';
import 'system_prompt_screen.dart';

/// 首页：微信「聊天」列表。默认空；右上角「+」新建会话直接进聊天界面。
class HomeScreen extends StatelessWidget {
  final ChatStore store;
  final RequestLogStore logStore;
  final AppLogStore appLogStore;
  final GenerationStore genStore;
  const HomeScreen({
    super.key,
    required this.store,
    required this.logStore,
    required this.appLogStore,
    required this.genStore,
  });

  void _newConversation(BuildContext context) {
    final conv = store.createConversation();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
            store: store,
            conversation: conv,
            logStore: logStore,
            genStore: genStore),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('微信'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 26),
            tooltip: '新建会话',
            onPressed: () => _newConversation(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final items = store.conversations;
          if (items.isEmpty) return const _EmptyState();
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Padding(
              padding: EdgeInsets.only(left: 76),
              child: Divider(height: 0.5, thickness: 0.5, color: WeColors.divider),
            ),
            itemBuilder: (context, i) => _ConversationTile(
              conversation: items[i],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                      store: store,
                      conversation: items[i],
                      logStore: logStore,
                      genStore: genStore),
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: _FakeBottomBar(
        onTapContacts: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => LogsScreen(logStore: appLogStore)),
        ),
        onTapDiscover: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SystemPromptScreen()),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '还没有会话\n点右上角「+」新建',
        textAlign: TextAlign.center,
        style: TextStyle(color: WeColors.subtitle, fontSize: 15, height: 1.6),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  const _ConversationTile({required this.conversation, required this.onTap});

  String _timeLabel(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return sameDay ? '$hh:$mm' : '${t.month}/${t.day}';
  }

  @override
  Widget build(BuildContext context) {
    final last = conversation.lastMessage;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _Avatar(name: conversation.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    last?.text ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: WeColors.subtitle, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _timeLabel(last?.time),
              style: const TextStyle(color: WeColors.subtitle, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final ch = name.isNotEmpty ? name[0] : '?';
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: WeColors.green,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(ch, style: const TextStyle(color: Colors.white, fontSize: 20)),
    );
  }
}

/// 底部导航栏：微信/我 只做样子；「通讯录」进运行日志，「发现」看系统提示词。
class _FakeBottomBar extends StatelessWidget {
  final VoidCallback onTapContacts;
  final VoidCallback onTapDiscover;
  const _FakeBottomBar({
    required this.onTapContacts,
    required this.onTapDiscover,
  });

  @override
  Widget build(BuildContext context) {
    // (icon, label, active, onTap)
    final items = <(IconData, String, bool, VoidCallback?)>[
      (Icons.chat_bubble, '微信', true, null),
      (Icons.person_outline, '通讯录', false, onTapContacts),
      (Icons.explore_outlined, '发现', false, onTapDiscover),
      (Icons.account_circle_outlined, '我', false, null),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: WeColors.barBg,
        border: Border(top: BorderSide(color: WeColors.divider, width: 0.5)),
      ),
      padding: EdgeInsets.only(
        top: 6,
        bottom: 6 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final (icon, label, active, onTap) in items)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap, // 为空则不可点
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 24,
                      color: active ? WeColors.green : const Color(0xFF7A7A7A)),
                  const SizedBox(height: 2),
                  Text(label,
                      style: TextStyle(
                        fontSize: 11,
                        color: active ? WeColors.green : const Color(0xFF7A7A7A),
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
