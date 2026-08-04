import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 提示词卡片：design_prompt 工具的产出。
/// 文案可展开/收起，底部操作：复制 / 引用 / 生图 / 生视频。
class PromptCard extends StatefulWidget {
  final String prompt;
  final VoidCallback onQuote;
  final VoidCallback onGenImage;
  final VoidCallback onGenVideo;

  const PromptCard({
    super.key,
    required this.prompt,
    required this.onQuote,
    required this.onGenImage,
    required this.onGenVideo,
  });

  @override
  State<PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<PromptCard> {
  bool _expanded = false;

  bool get _long => widget.prompt.length > 120;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 292),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E9F5)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F2E7CF6), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部：渐变条 + 标题
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: const Row(children: [
              Icon(Icons.edit_note_rounded, color: Colors.white, size: 17),
              SizedBox(width: 6),
              Text('提示词卡片',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
          // 文案
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: SelectableText(
              _expanded || !_long
                  ? widget.prompt
                  : '${widget.prompt.substring(0, 120)}…',
              style: const TextStyle(
                  fontSize: 13.5, height: 1.55, color: Color(0xFF333333)),
            ),
          ),
          if (_long)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '收起' : '展开全文',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF2E7CF6))),
              ),
            ),
          const SizedBox(height: 6),
          const Divider(height: 1, color: Color(0xFFF0F2F7)),
          // 操作行
          Row(
            children: [
              _action(Icons.copy_rounded, '复制', () async {
                await Clipboard.setData(ClipboardData(text: widget.prompt));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('已复制'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              }),
              _div(),
              _action(Icons.format_quote_rounded, '引用', widget.onQuote),
              _div(),
              _action(Icons.image_outlined, '生图', widget.onGenImage),
              _div(),
              _action(Icons.movie_outlined, '生视频', widget.onGenVideo),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17, color: const Color(0xFF2E7CF6)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      fontSize: 10.5, color: Color(0xFF666666))),
            ]),
          ),
        ),
      );

  Widget _div() => Container(
        width: 0.5,
        height: 26,
        color: const Color(0xFFF0F2F7),
      );
}
