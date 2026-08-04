import 'dart:io';

/// 本地媒体路径解析。
///
/// iOS 每次安装/更新会更换沙盒容器路径，数据库里存的绝对路径会失效
/// （文件本身随 Documents 迁移仍在）。因此统一按「文件名」在当前
/// media 目录下解析，旧的绝对路径记录也能自动恢复。
class MediaPaths {
  MediaPaths._();

  /// 当前容器的媒体目录，启动时由 main 设置。
  static String? mediaDir;

  /// 当前容器的封面目录，启动时由 main 设置。
  static String? coversDir;

  /// 把存储的路径（绝对或文件名）解析为当前可用的本地路径；找不到返回 null。
  /// 依次在 media、covers 目录里按文件名查找，兼容安装后容器路径变更。
  static String? resolve(String stored) {
    if (stored.isEmpty) return null;
    final name = stored.split('/').last;
    for (final dir in [mediaDir, coversDir]) {
      if (dir != null) {
        final p = '$dir/$name';
        if (File(p).existsSync()) return p;
      }
    }
    // 兜底：原始绝对路径仍有效（同一次安装内）。
    if (stored.startsWith('/') && File(stored).existsSync()) return stored;
    return null;
  }
}
