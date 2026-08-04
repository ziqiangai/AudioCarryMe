import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/generation_task.dart';
import '../models/model_catalog.dart';
import '../screens/video_player_screen.dart';
import '../state/generation_store.dart';
import '../theme.dart';

/// 生成任务气泡：骨架屏（生成中）→ 图片/视频（成功）→ 错误卡（失败）。
class GenerationBubble extends StatelessWidget {
  final GenerationStore store;
  final String taskId;

  /// 长按回调（弹「再生一张」等菜单），由聊天页注入。
  final void Function(GenerationTask task, Offset globalPos)? onLongPress;

  const GenerationBubble({
    super.key,
    required this.store,
    required this.taskId,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final task = store.byId(taskId);
        if (task == null) {
          return const _Card(child: Text('（任务记录缺失）'));
        }
        return GestureDetector(
          onLongPressStart: (d) => onLongPress?.call(task, d.globalPosition),
          child: switch (task.status) {
            GenTaskStatus.succeeded => _ResultView(task: task, store: store),
            GenTaskStatus.failed => _ErrorView(task: task, store: store),
            _ => _SkeletonView(task: task),
          },
        );
      },
    );
  }
}

// ---------- 通用外壳 ----------

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

double _aspectOf(GenerationTask task) {
  final ar = task.params['aspectRatio'];
  return switch (ar) {
    '16:9' => 16 / 9,
    '9:16' => 9 / 16,
    '1:1' => 1,
    _ => task.kind == GenKind.video ? 16 / 9 : 1,
  };
}

// ---------- 骨架屏 ----------

class _SkeletonView extends StatefulWidget {
  final GenerationTask task;
  const _SkeletonView({required this.task});

  @override
  State<_SkeletonView> createState() => _SkeletonViewState();
}

class _SkeletonViewState extends State<_SkeletonView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  String get _statusText => switch (widget.task.status) {
        GenTaskStatus.submitting => '提交中…',
        GenTaskStatus.queued => '排队中…',
        _ => widget.task.kind == GenKind.image ? '正在绘制…' : '正在生成视频…',
      };

  @override
  Widget build(BuildContext context) {
    final model = ModelCatalog.byId(widget.task.modelId);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: _aspectOf(widget.task),
              child: AnimatedBuilder(
                animation: _ctl,
                builder: (context, _) {
                  // 流动的高光渐变 = shimmer。
                  final t = _ctl.value;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-1.5 + 3 * t, -0.3),
                        end: Alignment(-0.5 + 3 * t, 0.3),
                        colors: const [
                          Color(0xFFEDEFF2),
                          Color(0xFFF8F9FB),
                          Color(0xFFEDEFF2),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        widget.task.kind == GenKind.image
                            ? Icons.image_outlined
                            : Icons.movie_outlined,
                        size: 36,
                        color: const Color(0xFFC9CDD4),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF2E7CF6)),
              ),
              const SizedBox(width: 8),
              Text(_statusText,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF666666))),
              const Spacer(),
              Text(model?.name ?? widget.task.modelId,
                  style: const TextStyle(
                      fontSize: 11, color: WeColors.subtitle)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------- 成功结果 ----------

/// 未下载媒体的过期提示（PPIO 官方口径：源链接保留约 48 小时）。
String _expiryHint(GenerationTask task) {
  final deadline = task.updatedAt.add(const Duration(hours: 48));
  final left = deadline.difference(DateTime.now());
  if (left.isNegative) return '源链接可能已过期，请尽快尝试下载';
  if (left.inHours >= 1) return '源链接约 ${left.inHours} 小时后过期，建议下载保存';
  return '源链接约 ${left.inMinutes + 1} 分钟后过期，尽快下载！';
}

class _ResultView extends StatelessWidget {
  final GenerationTask task;
  final GenerationStore store;
  const _ResultView({required this.task, required this.store});

  @override
  Widget build(BuildContext context) {
    final model = ModelCatalog.byId(task.modelId);
    final cached = GenerationStore.isFullyCached(task);
    final downloading = store.isDownloading(task.id);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.kind == GenKind.image)
            ..._imageViews(context)
          else
            _InlineVideo(
                source: task.localAt(0) ?? task.resultUrls.first,
                aspect: _aspectOf(task)),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                task.kind == GenKind.image
                    ? Icons.auto_awesome
                    : Icons.movie_outlined,
                size: 12,
                color: WeColors.subtitle,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  model?.name ?? task.modelId,
                  style:
                      const TextStyle(fontSize: 11, color: WeColors.subtitle),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (cached)
                const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle, size: 12, color: WeColors.green),
                  SizedBox(width: 3),
                  Text('已保存',
                      style:
                          TextStyle(fontSize: 11, color: WeColors.green)),
                ]),
            ],
          ),
          if (!cached) ...[
            const SizedBox(height: 6),
            Row(children: [
              SizedBox(
                height: 26,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    side: const BorderSide(color: Color(0xFF2E7CF6)),
                    foregroundColor: const Color(0xFF2E7CF6),
                  ),
                  icon: downloading
                      ? const SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_rounded, size: 14),
                  label: Text(downloading ? '下载中…' : '下载',
                      style: const TextStyle(fontSize: 11.5)),
                  onPressed:
                      downloading ? null : () => store.downloadMedia(task),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _expiryHint(task),
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFFE8912A), height: 1.3),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  List<Widget> _imageViews(BuildContext context) {
    return [
      for (var i = 0; i < task.resultUrls.length; i++) ...[
        if (i > 0) const SizedBox(height: 6),
        GestureDetector(
          onTap: () =>
              _openViewer(context, task.localAt(i) ?? task.resultUrls[i]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _taskImage(
              task,
              i,
              fit: BoxFit.cover,
              width: double.infinity,
            ),
          ),
        ),
      ],
    ];
  }

  /// 本地缓存优先的图片组件；网络兜底并带加载/破图占位。
  Widget _taskImage(GenerationTask task, int i,
      {BoxFit? fit, double? width}) {
    final local = task.localAt(i);
    if (local != null) {
      return Image.file(File(local), fit: fit, width: width);
    }
    return Image.network(
      task.resultUrls[i],
      fit: fit,
      width: width,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return AspectRatio(
          aspectRatio: _aspectOf(task),
          child: Container(
            color: const Color(0xFFF0F1F3),
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        );
      },
      errorBuilder: (_, _, _) => AspectRatio(
        aspectRatio: _aspectOf(task),
        child: Container(
          color: const Color(0xFFF0F1F3),
          child: const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: WeColors.subtitle)),
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, String source) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, _, _) => _ImageViewer(source: source),
    ));
  }
}

/// 全屏图片查看（捏合缩放，点按关闭）。
class _ImageViewer extends StatelessWidget {
  final String source; // 本地路径或 URL
  const _ImageViewer({required this.source});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: source.startsWith('/')
                ? Image.file(File(source))
                : Image.network(source),
          ),
        ),
      ),
    );
  }
}

/// 聊天内联视频：首帧 + 播放按钮，点击播放/暂停。
class _InlineVideo extends StatefulWidget {
  final String source; // 本地路径或 URL
  final double aspect;
  const _InlineVideo({required this.source, required this.aspect});

  @override
  State<_InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<_InlineVideo> {
  VideoPlayerController? _ctl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final ctl = widget.source.startsWith('/')
        ? VideoPlayerController.file(File(widget.source))
        : VideoPlayerController.networkUrl(Uri.parse(widget.source));
    _ctl = ctl;
    ctl.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
      ctl.setLooping(true);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctl = _ctl;
    if (ctl == null || !_ready) {
      return AspectRatio(
        aspectRatio: widget.aspect,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white54),
            ),
          ),
        ),
      );
    }
    // 点击 → 全屏播放（内联只做首帧预览）。
    return GestureDetector(
      onTap: () {
        ctl.pause();
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(url: widget.source),
        ));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: ctl.value.aspectRatio > 0
                  ? ctl.value.aspectRatio
                  : widget.aspect,
              child: VideoPlayer(ctl),
            ),
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 30),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- 失败 ----------

class _ErrorView extends StatelessWidget {
  final GenerationTask task;
  final GenerationStore store;
  const _ErrorView({required this.task, required this.store});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.error_outline, size: 16, color: Color(0xFFE5484D)),
            const SizedBox(width: 6),
            Text(task.kind == GenKind.image ? '图片生成失败' : '视频生成失败',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE5484D))),
          ]),
          const SizedBox(height: 4),
          SelectableText(
            task.error ?? '未知错误',
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF888888), height: 1.45),
          ),
          if (task.traceId != null) ...[
            const SizedBox(height: 4),
            Text('trace: ${task.traceId}',
                style:
                    const TextStyle(fontSize: 10.5, color: Color(0xFFAAAAAA))),
          ],
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(
              height: 30,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: const BorderSide(color: Color(0xFF2E7CF6)),
                  foregroundColor: const Color(0xFF2E7CF6),
                ),
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('重试', style: TextStyle(fontSize: 12)),
                onPressed: () => store.retry(task),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 30,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: const BorderSide(color: Color(0xFFCCCCCC)),
                  foregroundColor: const Color(0xFF888888),
                ),
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('复制', style: TextStyle(fontSize: 12)),
                onPressed: () async {
                  final text = [
                    task.error ?? '未知错误',
                    if (task.traceId != null) 'trace: ${task.traceId}',
                    if (task.ppioTaskId != null) 'task: ${task.ppioTaskId}',
                  ].join('\n');
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('已复制'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                },
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
