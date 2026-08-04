import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../logging/app_log.dart';

/// 生成产物本地缓存：PPIO 的签名链接会过期（官方口径约 1 小时），
/// 任务成功后立刻把图片/视频下载到 App 文档目录，渲染永远优先本地文件。
class MediaCache {
  MediaCache({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Directory> _mediaDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/media');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 下载 [url] 存为 `<stem>.<ext>`；成功返回本地绝对路径，失败返回 null。
  Future<String?> download(String url, String stem) async {
    try {
      final resp = await _client.get(Uri.parse(url));
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
        AppLog.w('media', '下载失败 ${resp.statusCode}：$stem');
        return null;
      }
      final ext = _extOf(url, resp.headers['content-type']);
      final dir = await _mediaDir();
      final file = File('${dir.path}/$stem.$ext');
      await file.writeAsBytes(resp.bodyBytes, flush: true);
      AppLog.i('media',
          '已缓存 $stem.$ext（${(resp.bodyBytes.length / 1024).round()} KB）');
      return file.path;
    } catch (e) {
      AppLog.w('media', '下载异常 $stem：$e');
      return null;
    }
  }

  /// 把编辑/剪辑产物字节存进媒体目录，返回路径。
  Future<String> saveBytes(Uint8List bytes, String stem, String ext) async {
    final dir = await _mediaDir();
    final file = File('${dir.path}/$stem.$ext');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 生成媒体目录下的输出文件路径（拼接/剪辑导出用）。
  Future<String> outputPath(String stem, String ext) async {
    final dir = await _mediaDir();
    return '${dir.path}/$stem.$ext';
  }

  static String _extOf(String url, String? contentType) {
    final ct = contentType ?? '';
    if (ct.contains('mp4') || url.contains('.mp4')) return 'mp4';
    if (ct.contains('png') || url.contains('.png')) return 'png';
    if (ct.contains('webp')) return 'webp';
    if (ct.contains('gif')) return 'gif';
    return 'jpg';
  }
}
