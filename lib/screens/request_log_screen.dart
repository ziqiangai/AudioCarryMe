import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/request_log.dart';
import '../state/request_log_store.dart';
import '../theme.dart';

/// 大模型请求记录页：概览 + 每次请求的 token / 耗时 / 缓存命中。
class RequestLogScreen extends StatelessWidget {
  final RequestLogStore logStore;
  const RequestLogScreen({super.key, required this.logStore});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WeColors.bg,
      appBar: AppBar(title: const Text('大模型请求记录')),
      body: ListenableBuilder(
        listenable: logStore,
        builder: (context, _) {
          final logs = logStore.logs;
          if (logs.isEmpty) {
            return const Center(
              child: Text('还没有请求记录\n发条消息就会出现',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: WeColors.subtitle, fontSize: 15, height: 1.6)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: logs.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) return _SummaryCard(logs: logs);
              final log = logs[i - 1];
              final idx = logs.length - i + 1;
              return GestureDetector(
                onTap: () => _showDetail(context, log, idx),
                child: _LogCard(log: log, index: idx),
              );
            },
          );
        },
      ),
    );
  }
}

/// 请求详情底部弹层：全部字段完整展示（可选中），一键复制。
void _showDetail(BuildContext context, RequestLog log, int index) {
  String two(int n) => n.toString().padLeft(2, '0');
  final t = log.startedAt;
  final fields = <(String, String)>[
    ('序号', '#$index'),
    ('状态', log.ok ? '成功' : '失败'),
    ('发起时间',
        '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}'),
    ('响应耗时(首字)', '${log.responseLatency.inMilliseconds} ms'),
    ('请求耗时', '${log.totalDuration.inMilliseconds} ms'),
    ('输入 tokens', '${log.inputTokens}'),
    ('输出 tokens', '${log.outputTokens}'),
    ('缓存读取', '${log.cacheReadTokens}'),
    ('缓存写入', '${log.cacheCreationTokens}'),
    ('缓存命中率', '${(log.cacheHitRate * 100).toStringAsFixed(1)}%'),
    if (log.error != null) ('错误信息', log.error!),
  ];
  final fullText = fields.map((f) => '${f.$1}: ${f.$2}').join('\n');

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (context, scrollCtl) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 4),
          child: Row(children: [
            const Text('请求详情',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('复制全部'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: fullText));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('已复制'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              },
            ),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFF0F0F0)),
        Expanded(
          child: ListView(
            controller: scrollCtl,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
            children: [
              for (final f in fields)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.$1,
                          style: const TextStyle(
                              fontSize: 12, color: WeColors.subtitle)),
                      const SizedBox(height: 3),
                      SelectableText(
                        f.$2,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.5,
                          color: f.$1 == '错误信息'
                              ? const Color(0xFFE5484D)
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ]),
    ),
  );
}

/// 顶部概览卡：总请求数、累计 token、平均首字延迟。
class _SummaryCard extends StatelessWidget {
  final List<RequestLog> logs;
  const _SummaryCard({required this.logs});

  @override
  Widget build(BuildContext context) {
    final totalTokens = logs.fold<int>(0, (s, l) => s + l.totalTokens);
    final avgLatency = logs.isEmpty
        ? 0
        : logs.fold<int>(0, (s, l) => s + l.responseLatency.inMilliseconds) ~/
            logs.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7CF6), Color(0xFF1348C8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _summaryItem('请求次数', '${logs.length}'),
          _divider(),
          _summaryItem('累计 Tokens', _compact(totalTokens)),
          _divider(),
          _summaryItem('平均首字', '$avgLatency ms'),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );

  Widget _divider() =>
      Container(width: 0.5, height: 34, color: Colors.white24);

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

/// 单条请求卡片。
class _LogCard extends StatelessWidget {
  final RequestLog log;
  final int index;
  const _LogCard({required this.log, required this.index});

  @override
  Widget build(BuildContext context) {
    final hitPct = (log.cacheHitRate * 100);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDEDED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：状态点 + 时间 + 总 token 徽章
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: log.ok ? WeColors.green : Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text('#$index',
                  style: const TextStyle(
                      color: WeColors.subtitle, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text(_fmtTime(log.startedAt),
                  style: const TextStyle(color: Color(0xFF444444), fontSize: 13)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${log.totalTokens} tokens',
                    style: const TextStyle(
                        color: Color(0xFF2E7CF6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 三个核心指标
          Row(
            children: [
              _metric('响应(首字)', _fmtDur(log.responseLatency), Icons.bolt),
              _metric('请求耗时', _fmtDur(log.totalDuration), Icons.timer_outlined),
              _metric('缓存命中', '${hitPct.toStringAsFixed(0)}%', Icons.memory,
                  highlight: hitPct > 0),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 10),
          // token 明细
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip('输入 ${log.inputTokens}'),
              _chip('输出 ${log.outputTokens}'),
              if (log.cacheReadTokens > 0) _chip('缓存读 ${log.cacheReadTokens}'),
              if (log.cacheCreationTokens > 0)
                _chip('缓存写 ${log.cacheCreationTokens}'),
            ],
          ),
          if (!log.ok && log.error != null) ...[
            const SizedBox(height: 8),
            Text(log.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon,
      {bool highlight = false}) {
    final color = highlight ? WeColors.green : const Color(0xFF333333);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: highlight ? WeColors.green : WeColors.subtitle),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: WeColors.subtitle)),
        ],
      ),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
      );

  static String _fmtDur(Duration d) {
    final ms = d.inMilliseconds;
    if (ms < 1000) return '$ms ms';
    return '${(ms / 1000).toStringAsFixed(2)} s';
  }

  static String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    final hms = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    return sameDay ? hms : '${t.month}/${t.day} $hms';
  }
}
