import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/log_entry.dart';
import '../state/log_store.dart';

/// 运行日志页：查看全部日志，一键复制、清空。
class LogsScreen extends StatelessWidget {
  final AppLogStore logStore;
  const LogsScreen({super.key, required this.logStore});

  static const _levelColors = {
    LogLevel.debug: Color(0xFF9AA0A6),
    LogLevel.info: Color(0xFF2E7CF6),
    LogLevel.warn: Color(0xFFE8912A),
    LogLevel.error: Color(0xFFE5484D),
  };

  String _two(int n) => n.toString().padLeft(2, '0');
  String _three(int n) => n.toString().padLeft(3, '0');

  String _fmtTime(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${_three(t.millisecond)}';

  String _plainLine(LogEntry e) =>
      '${_fmtTime(e.time)} [${e.level.label}] ${e.tag}: ${e.message}';

  Future<void> _copyAll(BuildContext context) async {
    final text = logStore.logs.reversed.map(_plainLine).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已复制全部日志'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _clear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空日志'),
        content: const Text('确定清空全部运行日志？此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空', style: TextStyle(color: Color(0xFFE5484D)))),
        ],
      ),
    );
    if (ok == true) await logStore.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () => _copyAll(context),
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () => _clear(context),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: logStore,
        builder: (context, _) {
          final logs = logStore.logs;
          if (logs.isEmpty) {
            return const Center(
              child: Text('暂无日志',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 15)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: logs.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: Color(0xFF2C2C2C)),
            itemBuilder: (context, i) => _LogRow(
              entry: logs[i],
              color: _levelColors[logs[i].level]!,
              time: _fmtTime(logs[i].time),
            ),
          );
        },
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final LogEntry entry;
  final Color color;
  final String time;
  const _LogRow({required this.entry, required this.color, required this.time});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(entry.level.label,
                    style: TextStyle(
                        color: color, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Text(entry.tag,
                  style: const TextStyle(
                      color: Color(0xFFB0B0B0),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(time,
                  style: const TextStyle(
                      color: Color(0xFF6E6E6E),
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            entry.message,
            style: const TextStyle(
                color: Color(0xFFDDDDDD), fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }
}
