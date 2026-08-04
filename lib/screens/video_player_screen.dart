import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 全屏视频播放：进度条 + 播放/暂停 + 关闭。
class VideoPlayerScreen extends StatefulWidget {
  final String url;
  const VideoPlayerScreen({super.key, required this.url});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _ctl;
  bool _ready = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _ctl = (widget.url.startsWith('/')
        ? VideoPlayerController.file(File(widget.url))
        : VideoPlayerController.networkUrl(Uri.parse(widget.url)))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _ctl
          ..setLooping(true)
          ..play();
      });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            Center(
              child: _ready
                  ? AspectRatio(
                      // aspectRatio<=0（元数据未就绪）会导致 NaN 布局，兜底 16:9。
                      aspectRatio: _ctl.value.aspectRatio > 0
                          ? _ctl.value.aspectRatio
                          : 16 / 9,
                      child: VideoPlayer(_ctl),
                    )
                  : const CircularProgressIndicator(color: Colors.white54),
            ),
            // 顶部关闭
            if (_showControls)
              Positioned(
                top: MediaQuery.of(context).padding.top + 4,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.close,
                      color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            // 底部控制条（Positioned 钉死屏幕底部，避免对齐歧义）
            if (_showControls && _ready)
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).padding.bottom,
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _ctl,
                      builder: (context, v, _) {
                        // duration 未就绪时避免 0/0=NaN 导致渲染出异常灰块。
                        final durMs = v.duration.inMilliseconds;
                        final hasDur = durMs > 0;
                        return Row(
                          children: [
                            GestureDetector(
                              onTap: () =>
                                  v.isPlaying ? _ctl.pause() : _ctl.play(),
                              child: Icon(
                                v.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(_fmt(v.position),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6),
                                ),
                                child: Slider(
                                  value: hasDur
                                      ? v.position.inMilliseconds
                                          .clamp(0, durMs)
                                          .toDouble()
                                      : 0,
                                  max: hasDur ? durMs.toDouble() : 1,
                                  activeColor: Colors.white,
                                  inactiveColor: Colors.white24,
                                  onChanged: hasDur
                                      ? (ms) => _ctl.seekTo(Duration(
                                          milliseconds: ms.round()))
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(_fmt(v.duration),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
