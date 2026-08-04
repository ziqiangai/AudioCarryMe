import 'package:flutter/services.dart';

/// iOS 原生视频能力（AVFoundation，经 carryme/video 通道）。
class VideoNative {
  static const _channel = MethodChannel('carryme/video');

  /// 按顺序拼接多段本地视频为一个 mp4，返回输出路径。
  static Future<String> concat(List<String> paths, String outputPath) async {
    await _channel.invokeMethod<bool>('concat', {
      'paths': paths,
      'output': outputPath,
    });
    return outputPath;
  }
}
