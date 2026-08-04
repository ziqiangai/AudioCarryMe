import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/generation_task.dart';
import '../models/model_catalog.dart';
import '../state/generation_store.dart';
import '../theme.dart';
import 'video_player_screen.dart';

/// 生成任务详情：大图预览 / 全部参数 / 时间线 / 错误信息。
class GenTaskDetailScreen extends StatelessWidget {
  final GenerationStore store;
  final String taskId;
  const GenTaskDetailScreen(
      {super.key, required this.store, required this.taskId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WeColors.bg,
      appBar: AppBar(title: const Text('任务详情')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final task = store.byId(taskId);
          if (task == null) {
            return const Center(child: Text('任务不存在'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
            children: [
              _Preview(task: task),
              const SizedBox(height: 12),
              _StatusCard(task: task),
              if (task.status == GenTaskStatus.succeeded) ...[
                const SizedBox(height: 12),
                _DownloadCard(task: task, store: store),
              ],
              const SizedBox(height: 12),
              _PromptCard(task: task),
              const SizedBox(height: 12),
              _ParamsCard(task: task),
              const SizedBox(height: 12),
              _TimelineCard(task: task),
            ],
          );
        },
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final GenerationTask task;
  const _Preview({required this.task});

  @override
  Widget build(BuildContext context) {
    if (task.status != GenTaskStatus.succeeded || task.resultUrls.isEmpty) {
      return const SizedBox.shrink();
    }
    if (task.kind == GenKind.video) {
      return GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
              url: task.localAt(0) ?? task.resultUrls.first),
        )),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 200,
            color: const Color(0xFF1A1A1A),
            child: const Center(
              child: Icon(Icons.play_circle_outline,
                  color: Colors.white70, size: 52),
            ),
          ),
        ),
      );
    }
    return Column(children: [
      for (var i = 0; i < task.resultUrls.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        GestureDetector(
          onTap: () => Navigator.of(context).push(PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.black87,
            pageBuilder: (_, _, _) => GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(
                  child: InteractiveViewer(
                      maxScale: 5,
                      child: task.localAt(i) != null
                          ? Image.file(File(task.localAt(i)!))
                          : Image.network(task.resultUrls[i])),
                ),
              ),
            ),
          )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: task.localAt(i) != null
                ? Image.file(File(task.localAt(i)!), fit: BoxFit.cover)
                : Image.network(task.resultUrls[i], fit: BoxFit.cover),
          ),
        ),
      ],
    ]);
  }
}

class _StatusCard extends StatelessWidget {
  final GenerationTask task;
  const _StatusCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final model = ModelCatalog.byId(task.modelId);
    final (color, label) = switch (task.status) {
      GenTaskStatus.succeeded => (WeColors.green, '生成成功'),
      GenTaskStatus.failed => (const Color(0xFFE5484D), '生成失败'),
      GenTaskStatus.processing => (const Color(0xFF2E7CF6), '生成中'),
      GenTaskStatus.queued => (const Color(0xFFE8912A), '排队中'),
      GenTaskStatus.submitting => (const Color(0xFFE8912A), '提交中'),
      GenTaskStatus.draft => (WeColors.subtitle, '草稿'),
    };
    return _card(
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            task.kind == GenKind.image
                ? Icons.image_outlined
                : Icons.movie_outlined,
            color: color,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 2),
          Text(
            '${task.kind == GenKind.image ? '图片' : '视频'} · ${model?.name ?? task.modelId}',
            style: const TextStyle(fontSize: 12, color: WeColors.subtitle),
          ),
        ]),
        const Spacer(),
        if (!task.status.isTerminal)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ]),
    );
  }
}

/// 下载与产物链接：本地保存状态 + 每个 URL 可复制。
class _DownloadCard extends StatelessWidget {
  final GenerationTask task;
  final GenerationStore store;
  const _DownloadCard({required this.task, required this.store});

  @override
  Widget build(BuildContext context) {
    final cached = GenerationStore.isFullyCached(task);
    final downloading = store.isDownloading(task.id);
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('产物', style: _titleStyle),
          const Spacer(),
          if (cached)
            const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle, size: 14, color: Color(0xFF07C160)),
              SizedBox(width: 4),
              Text('已保存到本地',
                  style: TextStyle(fontSize: 12, color: Color(0xFF07C160))),
            ])
          else
            SizedBox(
              height: 28,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  side: const BorderSide(color: Color(0xFF2E7CF6)),
                  foregroundColor: const Color(0xFF2E7CF6),
                ),
                icon: downloading
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_rounded, size: 15),
                label: Text(downloading ? '下载中…' : '下载到本地',
                    style: const TextStyle(fontSize: 12)),
                onPressed:
                    downloading ? null : () => store.downloadMedia(task),
              ),
            ),
        ]),
        if (!cached) ...[
          const SizedBox(height: 4),
          Text(
            '供应商源链接有效期约 48 小时，过期后未下载的内容将无法查看',
            style: const TextStyle(fontSize: 11, color: Color(0xFFE8912A)),
          ),
        ],
        const SizedBox(height: 8),
        for (var i = 0; i < task.resultUrls.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('#${i + 1}',
                  style: const TextStyle(
                      fontSize: 12, color: WeColors.subtitle)),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  task.resultUrls[i],
                  maxLines: 3,
                  style: const TextStyle(
                      fontSize: 11.5, color: Color(0xFF555555), height: 1.4),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  await Clipboard.setData(
                      ClipboardData(text: task.resultUrls[i]));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('已复制链接'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                },
                child: const Padding(
                  padding: EdgeInsets.only(left: 6, top: 1),
                  child: Icon(Icons.copy_rounded,
                      size: 15, color: WeColors.subtitle),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _PromptCard extends StatelessWidget {
  final GenerationTask task;
  const _PromptCard({required this.task});

  @override
  Widget build(BuildContext context) {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('提示词', style: _titleStyle),
          const Spacer(),
          GestureDetector(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: task.prompt));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('已复制'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
            child:
                const Icon(Icons.copy_rounded, size: 16, color: WeColors.subtitle),
          ),
        ]),
        const SizedBox(height: 8),
        SelectableText(task.prompt,
            style: const TextStyle(fontSize: 14, height: 1.55)),
        if (task.params['imageUrl'] != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(task.params['imageUrl']!,
                  width: 44, height: 44, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.image_outlined, size: 30)),
            ),
            const SizedBox(width: 8),
            const Text('参考图',
                style: TextStyle(fontSize: 12, color: WeColors.subtitle)),
          ]),
        ],
      ]),
    );
  }
}

class _ParamsCard extends StatelessWidget {
  final GenerationTask task;
  const _ParamsCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final entries =
        task.params.entries.where((e) => e.key != 'imageUrl').toList();
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('参数', style: _titleStyle),
        const SizedBox(height: 6),
        if (entries.isEmpty)
          const Text('（无）',
              style: TextStyle(fontSize: 13, color: WeColors.subtitle)),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Text(_paramLabel(e.key),
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF888888))),
              const Spacer(),
              Text(e.value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
          ),
      ]),
    );
  }

  static String _paramLabel(String name) {
    final key = ParamKey.values.where((p) => p.name == name).firstOrNull;
    return key?.label ?? name;
  }
}

class _TimelineCard extends StatelessWidget {
  final GenerationTask task;
  const _TimelineCard({required this.task});

  String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = task.status.isTerminal
        ? task.updatedAt.difference(task.createdAt)
        : DateTime.now().difference(task.createdAt);
    // (标签, 值, 是否提供复制按钮)
    final rows = <(String, String, bool)>[
      ('发起时间', _fmt(task.createdAt), false),
      ('更新时间', _fmt(task.updatedAt), false),
      ('耗时',
          elapsed.inSeconds < 60
              ? '${elapsed.inSeconds} 秒'
              : '${elapsed.inMinutes} 分 ${elapsed.inSeconds % 60} 秒',
          false),
      ('PPIO 任务', task.ppioTaskId ?? '—（本版本前的任务未记录）',
          task.ppioTaskId != null),
      ('Trace ID', task.traceId ?? '—（本版本前的任务未记录）',
          task.traceId != null),
      if (task.error != null) ('错误', task.error!, true),
    ];
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('时间线', style: _titleStyle),
        const SizedBox(height: 6),
        for (final (k, v, copyable) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 76,
                child: Text(k,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF888888))),
              ),
              Expanded(
                child: SelectableText(v,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: k == '错误'
                            ? const Color(0xFFE5484D)
                            : Colors.black87)),
              ),
              if (copyable)
                Builder(
                  builder: (context) => GestureDetector(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: v));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(
                          content: Text('已复制'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ));
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(left: 6, top: 1),
                      child: Icon(Icons.copy_rounded,
                          size: 15, color: WeColors.subtitle),
                    ),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}

const _titleStyle = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w600, color: WeColors.subtitle);

Widget _card({required Widget child}) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
