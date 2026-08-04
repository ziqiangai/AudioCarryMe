import 'dart:io';

import 'package:flutter/material.dart';

import '../models/generation_task.dart';
import '../models/model_catalog.dart';
import '../state/generation_store.dart';
import '../theme.dart';
import 'gen_task_detail_screen.dart';

/// 生成任务中心：每个任务的类型 / 状态 / 耗时 / 参数 / 发起时间 / 结果缩略图。
class GenTasksScreen extends StatelessWidget {
  final GenerationStore store;

  /// 非空则只显示该会话的任务。
  final String? conversationId;
  const GenTasksScreen(
      {super.key, required this.store, this.conversationId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WeColors.bg,
      appBar: AppBar(title: Text(conversationId == null ? '生成任务' : '生成任务 · 本会话')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final tasks = conversationId == null
              ? store.all
              : store.forConversation(conversationId!);
          if (tasks.isEmpty) {
            return const Center(
              child: Text('还没有生成任务\n在聊天里让我画点什么吧',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: WeColors.subtitle, fontSize: 15, height: 1.6)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: tasks.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) return _Summary(tasks: tasks);
              final task = tasks[i - 1];
              return GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      GenTaskDetailScreen(store: store, taskId: task.id),
                )),
                child: _TaskCard(task: task),
              );
            },
          );
        },
      ),
    );
  }
}

/// 顶部概览：总数 / 成功 / 图片 / 视频。
class _Summary extends StatelessWidget {
  final List<GenerationTask> tasks;
  const _Summary({required this.tasks});

  @override
  Widget build(BuildContext context) {
    final ok = tasks.where((t) => t.status == GenTaskStatus.succeeded).length;
    final img = tasks.where((t) => t.kind == GenKind.image).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        _item('全部', '${tasks.length}'),
        _div(),
        _item('成功', '$ok'),
        _div(),
        _item('图片', '$img'),
        _div(),
        _item('视频', '${tasks.length - img}'),
      ]),
    );
  }

  Widget _item(String label, String value) => Expanded(
        child: Column(children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      );

  Widget _div() => Container(width: 0.5, height: 34, color: Colors.white24);
}

class _TaskCard extends StatelessWidget {
  final GenerationTask task;
  const _TaskCard({required this.task});

  (Color, String) get _statusStyle => switch (task.status) {
        GenTaskStatus.succeeded => (WeColors.green, '成功'),
        GenTaskStatus.failed => (const Color(0xFFE5484D), '失败'),
        GenTaskStatus.draft => (WeColors.subtitle, '草稿'),
        GenTaskStatus.submitting => (const Color(0xFFE8912A), '提交中'),
        GenTaskStatus.queued => (const Color(0xFFE8912A), '排队中'),
        GenTaskStatus.processing => (const Color(0xFF2E7CF6), '生成中'),
      };

  String get _elapsed {
    final d = task.status.isTerminal
        ? task.updatedAt.difference(task.createdAt)
        : DateTime.now().difference(task.createdAt);
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    return '${d.inMinutes}m${d.inSeconds % 60}s';
  }

  String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final hm = '${two(t.hour)}:${two(t.minute)}';
    return sameDay ? hm : '${t.month}/${t.day} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final (color, label) = _statusStyle;
    final model = ModelCatalog.byId(task.modelId);
    final isImage = task.kind == GenKind.image;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDEDED)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumb(task: task, isImage: isImage),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(isImage ? Icons.image_outlined : Icons.movie_outlined,
                      size: 15, color: const Color(0xFF2E7CF6)),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(model?.name ?? task.modelId,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(task.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF555555),
                        height: 1.4)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    for (final e in task.params.entries)
                      _chip('${_paramLabel(e.key)} ${e.value}'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.schedule,
                      size: 12, color: WeColors.subtitle),
                  const SizedBox(width: 3),
                  Text(_fmtTime(task.createdAt),
                      style: const TextStyle(
                          fontSize: 11, color: WeColors.subtitle)),
                  const SizedBox(width: 12),
                  const Icon(Icons.bolt, size: 12, color: WeColors.subtitle),
                  const SizedBox(width: 2),
                  Text('耗时 $_elapsed',
                      style: const TextStyle(
                          fontSize: 11, color: WeColors.subtitle)),
                ]),
                if (task.status == GenTaskStatus.failed &&
                    task.error != null) ...[
                  const SizedBox(height: 6),
                  Text(task.error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFE5484D))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _paramLabel(String name) {
    final key = ParamKey.values.where((p) => p.name == name).firstOrNull;
    return key?.label ?? name;
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 11, color: Color(0xFF666666))),
      );
}

/// 左侧缩略图：图片直出小图；视频深底+播放标；进行中转圈；失败灰块。
class _Thumb extends StatelessWidget {
  final GenerationTask task;
  final bool isImage;
  const _Thumb({required this.task, required this.isImage});

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    Widget inner;
    if (task.status == GenTaskStatus.succeeded && task.resultUrls.isNotEmpty) {
      if (isImage) {
        final local = task.localAt(0);
        inner = local != null
            ? Image.file(File(local),
                fit: BoxFit.cover, width: size, height: size)
            : Image.network(
                task.resultUrls.first,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: WeColors.subtitle),
              );
      } else {
        inner = Container(
          color: const Color(0xFF1A1A1A),
          child: const Center(
              child: Icon(Icons.play_circle_outline,
                  color: Colors.white70, size: 26)),
        );
      }
    } else if (task.status == GenTaskStatus.failed) {
      inner = Container(
        color: const Color(0xFFF5F5F5),
        child: const Center(
            child: Icon(Icons.error_outline,
                color: Color(0xFFE5484D), size: 22)),
      );
    } else {
      inner = Container(
        color: const Color(0xFFF0F1F3),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF2E7CF6)),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(width: size, height: size, child: inner),
    );
  }
}
