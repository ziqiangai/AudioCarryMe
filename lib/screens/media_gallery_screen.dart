import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';

/// 画廊里的一个媒体项（图片或视频）。
class GalleryMedia {
  final bool isVideo;
  final String source; // 本地路径或 URL
  final String? cover; // 视频封面本地路径

  const GalleryMedia({required this.isVideo, required this.source, this.cover});

  ImageProvider? get _coverProvider {
    if (cover != null) return FileImage(File(cover!));
    if (!isVideo) {
      return source.startsWith('/')
          ? FileImage(File(source))
          : NetworkImage(source) as ImageProvider;
    }
    return null;
  }
}

/// 微信式媒体查看器：
/// - 左右滑动切换上一个/下一个
/// - 上下滑动退出
/// - 图片可捏合缩放，视频点击就地播放
class MediaGalleryScreen extends StatefulWidget {
  final List<GalleryMedia> items;
  final int initialIndex;

  const MediaGalleryScreen({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  late final PageController _page =
      PageController(initialPage: widget.initialIndex);
  double _dragDy = 0; // 垂直拖拽位移
  bool _zoomed = false; // 当前图片是否已放大（放大时禁用翻页/下拉退出）

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_dragDy.abs() > 140 || v.abs() > 800) {
      Navigator.of(context).pop();
    } else {
      setState(() => _dragDy = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 下拉越多背景越透（露出下面的聊天），到底就退出。
    final fade = (1 - (_dragDy.abs() / 400)).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onVerticalDragUpdate:
            _zoomed ? null : (d) => setState(() => _dragDy += d.delta.dy),
        onVerticalDragEnd: _zoomed ? null : _onDragEnd,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: Colors.black.withValues(alpha: fade)),
            ),
            Transform.translate(
              offset: Offset(0, _dragDy),
              child: PageView.builder(
                controller: _page,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: widget.items.length,
                itemBuilder: (_, i) {
                  final item = widget.items[i];
                  if (item.isVideo) {
                    return _GalleryVideo(item: item);
                  }
                  return PhotoView(
                    imageProvider: item._coverProvider,
                    backgroundDecoration:
                        const BoxDecoration(color: Colors.transparent),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3,
                    initialScale: PhotoViewComputedScale.contained,
                    scaleStateChangedCallback: (s) {
                      final zoomed = s != PhotoViewScaleState.initial &&
                          s != PhotoViewScaleState.zoomedOut;
                      if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                    },
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.white38, size: 48),
                    ),
                  );
                },
              ),
            ),
            // 顶部关闭按钮
            Positioned(
              top: MediaQuery.of(context).padding.top + 4,
              left: 8,
              child: Opacity(
                opacity: fade,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 画廊内的视频页：先显示封面，点击就地播放/暂停。
class _GalleryVideo extends StatefulWidget {
  final GalleryMedia item;
  const _GalleryVideo({required this.item});

  @override
  State<_GalleryVideo> createState() => _GalleryVideoState();
}

class _GalleryVideoState extends State<_GalleryVideo> {
  VideoPlayerController? _ctl;
  bool _ready = false;

  Future<void> _startPlay() async {
    if (_ctl != null) return;
    final src = widget.item.source;
    final ctl = src.startsWith('/')
        ? VideoPlayerController.file(File(src))
        : VideoPlayerController.networkUrl(Uri.parse(src));
    _ctl = ctl;
    await ctl.initialize();
    if (!mounted) {
      ctl.dispose();
      return;
    }
    setState(() => _ready = true);
    ctl
      ..setLooping(true)
      ..play();
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready && _ctl != null) {
      final v = _ctl!.value;
      return GestureDetector(
        onTap: () =>
            setState(() => v.isPlaying ? _ctl!.pause() : _ctl!.play()),
        child: Center(
          child: AspectRatio(
            aspectRatio: v.aspectRatio > 0 ? v.aspectRatio : 16 / 9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_ctl!),
                if (!v.isPlaying)
                  const _PlayBadge(),
              ],
            ),
          ),
        ),
      );
    }
    // 未播放：封面 + 播放按钮。
    final cover = widget.item.cover;
    return GestureDetector(
      onTap: _startPlay,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (cover != null)
              Image.file(File(cover), fit: BoxFit.contain)
            else
              const SizedBox.expand(),
            const _PlayBadge(),
          ],
        ),
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(
          color: Colors.black45, shape: BoxShape.circle),
      child: const Icon(Icons.play_arrow, color: Colors.white, size: 42),
    );
  }
}
