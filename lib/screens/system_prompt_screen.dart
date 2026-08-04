import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/agent_config.dart';
import '../services/deepseek_agent_service.dart';
import '../theme.dart';

/// 「发现」页：查看创作 Agent 的系统提示词与工具集定义。
class SystemPromptScreen extends StatelessWidget {
  const SystemPromptScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WeColors.bg,
      appBar: AppBar(
        title: const Text('系统提示词'),
        actions: [
          IconButton(
            tooltip: '复制',
            icon: const Icon(Icons.copy_rounded, size: 21),
            onPressed: () async {
              await Clipboard.setData(
                  const ClipboardData(text: AgentConfig.systemPrompt));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('已复制'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _card(
            title: '模型',
            child: Text(
              '${AgentConfig.model}\n${AgentConfig.baseUrl}',
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF666666), height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          _card(
            title: 'System Prompt',
            child: SelectableText(
              AgentConfig.systemPrompt.trim(),
              style: const TextStyle(fontSize: 14, height: 1.6),
            ),
          ),
          const SizedBox(height: 12),
          _card(
            title: '工具集（${kCreationTools.length}）',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final tool in kCreationTools) ...[
                  Row(children: [
                    Icon(
                      switch (tool['name']) {
                        'design_prompt' => Icons.edit_note_rounded,
                        'generate_image' => Icons.image_outlined,
                        _ => Icons.movie_outlined,
                      },
                      size: 18,
                      color: const Color(0xFF2E7CF6),
                    ),
                    const SizedBox(width: 8),
                    Text(tool['name'] as String,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                  ]),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 26, bottom: 10),
                    child: Text(tool['description'] as String,
                        style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF666666),
                            height: 1.5)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: WeColors.subtitle)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}
