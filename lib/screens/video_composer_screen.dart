import 'package:flutter/material.dart';

import '../models/generation_task.dart';
import '../models/model_catalog.dart';
import '../services/video_native.dart';
import '../state/generation_store.dart';
import '../theme.dart';
import 'video_player_screen.dart';
import 'video_trim_screen.dart';

/// 合成结果。
class ComposeResult {
  final String path;
  final int count;
  const ComposeResult(this.path, this.count);
}

/// 一个待合成片段。
class _Segment {
  GenerationTask task;
  String path;
  bool trimmed = false;
  _Segment(this.task, this.path);
}

/// 视频合成编辑器：多段拖拽排序 / 单段剪辑 / 替换 / 增删 → 导出成片。
class VideoComposerScreen extends StatefulWidget {
  /// 初始片段（任务 + 本地路径），按期望顺序。
  final List<(GenerationTask, String)> initial;

  /// 会话内全部可用的成功视频任务（替换/添加的候选池）。
  final List<GenerationTask> available;

  final GenerationStore genStore;

  const VideoComposerScreen({
    super.key,
    required this.initial,
    required this.available,
    required this.genStore,
  });

  @override
  State<VideoComposerScreen> createState() => _VideoComposerScreenState();
}

class _VideoComposerScreenState extends State<VideoComposerScreen> {
  late final List<_Segment> _segments = [
    for (final (t, p) in widget.initial) _Segment(t, p),
  ];
  bool _exporting = false;

  Future<void> _export() async {
    if (_segments.length < 2 || _exporting) return;
    setState(() => _exporting = true);
    try {
      final out = await widget.genStore.mediaCache!.outputPath(
          'concat-${DateTime.now().millisecondsSinceEpoch}', 'mp4');
      await VideoNative.concat(
          _segments.map((s) => s.path).toList(), out);
      if (mounted) {
        Navigator.of(context).pop(ComposeResult(out, _segments.length));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _exporting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('导出失败：$e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _trim(int index) async {
    final seg = _segments[index];
    final out = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => VideoTrimScreen(path: seg.path),
    ));
    if (out != null && mounted) {
      setState(() {
        seg.path = out;
        seg.trimmed = true;
      });
    }
  }

  /// 从候选池选一个视频（替换某段 / 追加新段）。
  Future<void> _pickFrom({int? replaceIndex}) async {
    final picked = await showModalBottomSheet<GenerationTask>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _VideoPicker(available: widget.available),
    );
    if (picked == null || !mounted) return;

    // 确保本地。
    var local = picked.localAt(0);
    if (local == null) {
      await widget.genStore.downloadMedia(picked);
      local = picked.localAt(0);
    }
    if (local == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('该视频下载失败，源链接可能已过期'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    setState(() {
      if (replaceIndex != null) {
        _segments[replaceIndex] = _Segment(picked, local!);
      } else {
        _segments.add(_Segment(picked, local!));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WeColors.bg,
      appBar: AppBar(
        title: Text('合成成片（${_segments.length} 段）'),
        actions: [
          _exporting
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _segments.length >= 2 ? _export : null,
                  child: Text('导出',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _segments.length >= 2
                              ? WeColors.green
                              : const Color(0xFFBBBBBB))),
                ),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: const Color(0xFFFFF8E8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: const Text(
            '长按拖拽排序 · 点击片段可预览 · 每段可单独剪辑或替换',
            style: TextStyle(fontSize: 12, color: Color(0xFF8A6D3B)),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            itemCount: _segments.length,
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                final s = _segments.removeAt(oldIndex);
                _segments.insert(newIndex, s);
              });
            },
            itemBuilder: (context, i) {
              final seg = _segments[i];
              return Container(
                key: ValueKey('${seg.task.id}-$i-${seg.path}'),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEDEDED)),
                ),
                child: Row(children: [
                  // 序号
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF7C4DFF))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => VideoPlayerScreen(url: seg.path),
                      )),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            if (seg.task.label != null) ...[
                              Text(seg.task.label!,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF7C4DFF))),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                ModelCatalog.displayNameOf(seg.task.modelId),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                            if (seg.trimmed) ...[
                              const SizedBox(width: 6),
                              const Text('已剪辑',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: WeColors.green)),
                            ],
                          ]),
                          const SizedBox(height: 3),
                          Text(
                            seg.task.prompt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: WeColors.subtitle),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '剪辑',
                    icon: const Icon(Icons.content_cut,
                        size: 18, color: Color(0xFF2E7CF6)),
                    onPressed: () => _trim(i),
                  ),
                  IconButton(
                    tooltip: '替换',
                    icon: const Icon(Icons.swap_horiz,
                        size: 20, color: Color(0xFF2E7CF6)),
                    onPressed: () => _pickFrom(replaceIndex: i),
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.close,
                        size: 18, color: Color(0xFF999999)),
                    onPressed: _segments.length > 1
                        ? () => setState(() => _segments.removeAt(i))
                        : null,
                  ),
                ]),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF7C4DFF)),
                  foregroundColor: const Color(0xFF7C4DFF),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加片段'),
                onPressed: () => _pickFrom(),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// 候选视频选择器（会话内全部成功视频）。
class _VideoPicker extends StatelessWidget {
  final List<GenerationTask> available;
  const _VideoPicker({required this.available});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('选择视频',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const Divider(height: 1, color: Color(0xFFF0F0F0)),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: available.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: Color(0xFFF5F5F5)),
            itemBuilder: (context, i) {
              final t = available[i];
              return ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white70, size: 22),
                ),
                title: Text(
                  '${t.label != null ? '${t.label} · ' : ''}'
                  '${ModelCatalog.displayNameOf(t.modelId)}',
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(t.prompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
                onTap: () => Navigator.of(context).pop(t),
              );
            },
          ),
        ),
      ]),
    );
  }
}
