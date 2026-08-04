import 'package:flutter/material.dart';

import '../models/model_catalog.dart';
import '../theme.dart';

/// 参数面板返回值。
class GenSheetResult {
  final String modelId;
  final String prompt;
  final Map<String, String> params; // ParamKey.name → 值
  const GenSheetResult({
    required this.modelId,
    required this.prompt,
    required this.params,
  });
}

/// 弹出生成参数选择面板。
///
/// [refImageUrl] 非空 = 带参考图（图生图 / 图生视频），
/// 面板顶部显示参考图，不支持参考图的模型被禁用。
Future<GenSheetResult?> showGenParamSheet(
  BuildContext context, {
  required GenKind kind,
  required String prompt,
  String? initialModelId,
  Map<String, String>? initialParams,
  String? refImageUrl,
  int batchCount = 1,
  bool batchRef = false,
}) {
  return showModalBottomSheet<GenSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _GenParamSheet(
      kind: kind,
      prompt: prompt,
      initialModelId: initialModelId,
      initialParams: initialParams,
      refImageUrl: refImageUrl,
      batchCount: batchCount,
      batchRef: batchRef,
    ),
  );
}

class _GenParamSheet extends StatefulWidget {
  final GenKind kind;
  final String prompt;
  final String? initialModelId;
  final Map<String, String>? initialParams;
  final String? refImageUrl;
  final int batchCount;
  final bool batchRef;
  const _GenParamSheet({
    required this.kind,
    required this.prompt,
    this.initialModelId,
    this.initialParams,
    this.refImageUrl,
    this.batchCount = 1,
    this.batchRef = false,
  });

  @override
  State<_GenParamSheet> createState() => _GenParamSheetState();
}

class _GenParamSheetState extends State<_GenParamSheet> {
  late ModelSpec _model;
  late Map<ParamKey, String> _values;
  late final TextEditingController _promptCtl;
  late final TextEditingController _negativeCtl;

  bool get _hasRef => widget.refImageUrl != null || widget.batchRef;
  bool get _isBatch => widget.batchCount > 1;

  @override
  void initState() {
    super.initState();
    var initial = (widget.initialModelId != null
            ? ModelCatalog.byId(widget.initialModelId!)
            : null) ??
        ModelCatalog.defaultOf(widget.kind);
    // 带参考图时默认选一个支持参考图的模型。
    if (_hasRef && !initial.supportsRef) {
      initial = ModelCatalog.modelsOf(widget.kind)
          .firstWhere((m) => m.supportsRef, orElse: () => initial);
    }
    _model = initial;
    _values = ModelCatalog.defaultsFor(_model);
    // 回填初始参数（再生场景）。
    widget.initialParams?.forEach((k, v) {
      final key = ParamKey.values.where((p) => p.name == k).firstOrNull;
      if (key != null && _model.supportsParam(key)) _values[key] = v;
    });
    _promptCtl = TextEditingController(text: widget.prompt);
    _negativeCtl =
        TextEditingController(text: widget.initialParams?['negativePrompt'] ?? '');
  }

  @override
  void dispose() {
    _promptCtl.dispose();
    _negativeCtl.dispose();
    super.dispose();
  }

  void _switchModel(ModelSpec m) {
    setState(() {
      final old = _values;
      _model = m;
      _values = ModelCatalog.defaultsFor(m);
      // 新模型仍支持且取值合法的参数尽量保留。
      for (final e in old.entries) {
        final spec = m.supports[e.key];
        if (spec == null) continue;
        if (spec.options.isEmpty ||
            spec.options.any((o) => o.value == e.value)) {
          _values[e.key] = e.value;
        }
      }
    });
  }

  void _confirm() {
    final params = _values.map((k, v) => MapEntry(k.name, v));
    if (_model.supportsParam(ParamKey.negativePrompt) &&
        _negativeCtl.text.trim().isNotEmpty) {
      params['negativePrompt'] = _negativeCtl.text.trim();
    }
    if (_hasRef) params['imageUrl'] = widget.refImageUrl!;
    Navigator.of(context).pop(GenSheetResult(
      modelId: _model.id,
      prompt: _promptCtl.text.trim(),
      params: params,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isImage = widget.kind == GenKind.image;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: WeColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD0D0D0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Row(
                children: [
                  Icon(isImage ? Icons.image_outlined : Icons.movie_outlined,
                      size: 22, color: const Color(0xFF2E7CF6)),
                  const SizedBox(width: 8),
                  Text(
                      '${isImage ? '生成图片' : '生成视频'}'
                      '${_isBatch ? ' ×${widget.batchCount}' : ''}',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                children: [
                  if (_hasRef) ...[
                    _sectionLabel('参考图'),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: _cardDeco,
                      child: Row(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            widget.refImageUrl!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 56,
                              height: 56,
                              color: const Color(0xFFF0F1F3),
                              child: const Icon(Icons.image_outlined,
                                  color: WeColors.subtitle),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.kind == GenKind.video
                                ? '将以这张图为首帧生成视频（图生视频）'
                                : '将参考这张图进行生成（图生图）',
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF666666),
                                height: 1.4),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _sectionLabel('提示词'),
                  if (_isBatch)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: _cardDeco,
                      child: Row(children: [
                        const Icon(Icons.layers_outlined,
                            size: 18, color: Color(0xFF2E7CF6)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.batchRef
                                ? '将对 ${widget.batchCount} 张参考图分别生成，'
                                    '提示词沿用各自来源'
                                : '将分别使用 ${widget.batchCount} 条提示词生成，'
                                    '以下参数应用到全部',
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF555555),
                                height: 1.4),
                          ),
                        ),
                      ]),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: _cardDeco,
                      child: TextField(
                        controller: _promptCtl,
                        minLines: 2,
                        maxLines: 4,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                        decoration: const InputDecoration(
                            border: InputBorder.none, isCollapsed: false),
                      ),
                    ),
                  const SizedBox(height: 14),
                  _sectionLabel('模型'),
                  SizedBox(
                    height: 64,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: ModelCatalog.modelsOf(widget.kind).length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final m = ModelCatalog.modelsOf(widget.kind)[i];
                        final sel = m.id == _model.id;
                        // 带参考图时，不支持参考图的模型禁用（缺货样式）。
                        final disabled = _hasRef && !m.supportsRef;
                        return GestureDetector(
                          onTap: disabled ? null : () => _switchModel(m),
                          child: Opacity(
                            opacity: disabled ? 0.45 : 1,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color:
                                    sel ? const Color(0xFFEAF2FF) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: sel
                                      ? const Color(0xFF2E7CF6)
                                      : const Color(0xFFE5E5E5),
                                  width: sel ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: sel
                                            ? const Color(0xFF2E7CF6)
                                            : Colors.black87,
                                      )),
                                  const SizedBox(height: 2),
                                  Text(
                                      disabled ? '不支持参考图' : m.vendorTag,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: disabled
                                              ? const Color(0xFFCC8888)
                                              : WeColors.subtitle)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionLabel('参数'),
                  Container(
                    decoration: _cardDeco,
                    child: Column(
                      children: [
                        for (final key
                            in ModelCatalog.paramOrderOf(widget.kind))
                          _paramRow(key),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: WeColors.green,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _confirm,
                  child: const Text('开始生成',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _cardDeco = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: WeColors.subtitle)),
      );

  /// 单个参数行；模型不支持时置灰 + 「不支持」角标（电商缺货样式）。
  Widget _paramRow(ParamKey key) {
    final spec = _model.supports[key];
    final supported = spec != null;

    Widget control;
    if (!supported) {
      control = const SizedBox.shrink();
    } else if (key == ParamKey.negativePrompt) {
      control = TextField(
        controller: _negativeCtl,
        style: const TextStyle(fontSize: 13),
        textAlign: TextAlign.end,
        decoration: const InputDecoration(
          hintText: '不想出现的内容（可选）',
          hintStyle: TextStyle(fontSize: 13, color: Color(0xFFBBBBBB)),
          border: InputBorder.none,
          isCollapsed: true,
        ),
      );
    } else if (spec.options.isEmpty) {
      // 布尔开关（watermark / audio）
      control = Switch.adaptive(
        value: _values[key] == 'true',
        activeTrackColor: WeColors.green,
        onChanged: (v) => setState(() => _values[key] = '$v'),
      );
    } else {
      control = Wrap(
        spacing: 6,
        alignment: WrapAlignment.end,
        children: [
          for (final o in spec.options)
            ChoiceChip(
              label: Text(o.label, style: const TextStyle(fontSize: 12)),
              selected: _values[key] == o.value,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              selectedColor: const Color(0xFFEAF2FF),
              side: BorderSide(
                color: _values[key] == o.value
                    ? const Color(0xFF2E7CF6)
                    : const Color(0xFFE0E0E0),
              ),
              labelStyle: TextStyle(
                color: _values[key] == o.value
                    ? const Color(0xFF2E7CF6)
                    : Colors.black87,
              ),
              onSelected: (_) => setState(() => _values[key] = o.value),
            ),
        ],
      );
    }

    return Opacity(
      opacity: supported ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
              bottom: BorderSide(color: Color(0xFFF2F2F2), width: 0.5)),
        ),
        child: Row(
          children: [
            Text(key.label, style: const TextStyle(fontSize: 14)),
            if (!supported) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFDDDDDD)),
                ),
                child: const Text('该模型不支持',
                    style:
                        TextStyle(fontSize: 10, color: Color(0xFF999999))),
              ),
            ],
            const Spacer(),
            Flexible(flex: 3, child: supported ? control : const SizedBox()),
          ],
        ),
      ),
    );
  }
}
