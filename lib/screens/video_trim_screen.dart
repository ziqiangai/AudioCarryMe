import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_trimmer/video_trimmer.dart';

/// 简单视频修剪：时间轴选区 + 预览 + 导出。
/// pop 返回修剪后的文件路径（取消返回 null）。
class VideoTrimScreen extends StatefulWidget {
  final String path;
  const VideoTrimScreen({super.key, required this.path});

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  final Trimmer _trimmer = Trimmer();
  double _start = 0;
  double _end = 0;
  bool _playing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _trimmer.loadVideo(videoFile: File(widget.path));
  }

  @override
  void dispose() {
    _trimmer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _trimmer.saveTrimmedVideo(
      startValue: _start,
      endValue: _end,
      onSave: (outputPath) {
        if (!mounted) return;
        setState(() => _saving = false);
        Navigator.of(context).pop(outputPath);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('剪辑视频', style: TextStyle(color: Colors.white)),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text('完成',
                      style: TextStyle(
                          color: Color(0xFF07C160),
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: VideoViewer(trimmer: _trimmer)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: TrimViewer(
                trimmer: _trimmer,
                viewerHeight: 56,
                viewerWidth: MediaQuery.of(context).size.width - 32,
                maxVideoLength: const Duration(minutes: 5),
                durationStyle: DurationStyle.FORMAT_MM_SS,
                editorProperties: const TrimEditorProperties(
                  borderPaintColor: Color(0xFF07C160),
                  circlePaintColor: Color(0xFF07C160),
                ),
                onChangeStart: (v) => _start = v,
                onChangeEnd: (v) => _end = v,
                onChangePlaybackState: (playing) {
                  if (mounted) setState(() => _playing = playing);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 30),
            child: IconButton(
              icon: Icon(
                _playing
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
                color: Colors.white,
                size: 48,
              ),
              onPressed: () async {
                final playing = await _trimmer.videoPlaybackControl(
                  startValue: _start,
                  endValue: _end,
                );
                if (mounted) setState(() => _playing = playing);
              },
            ),
          ),
        ],
      ),
    );
  }
}
