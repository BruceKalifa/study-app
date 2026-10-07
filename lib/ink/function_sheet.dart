import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'function_plot.dart';
import 'ink_controller.dart';
import 'ink_model.dart';

/// 함수 그리기 — 식을 적으면 연습장에 그래프를 그려 준다 (좌표축도 같이).
Future<void> showFunctionSheet(BuildContext context, InkController c, {Offset? at}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _FunctionSheet(controller: c, at: at),
    ),
  );
}

class _FunctionSheet extends StatefulWidget {
  const _FunctionSheet({required this.controller, this.at});
  final InkController controller;
  final Offset? at;

  @override
  State<_FunctionSheet> createState() => _FunctionSheetState();
}

class _FunctionSheetState extends State<_FunctionSheet> {
  final _text = TextEditingController(text: 'y = x^2 - 2x');
  final _from = TextEditingController(text: '-5');
  final _to = TextEditingController(text: '5');
  bool _axes = true;
  double _scale = 36; // 한 칸 픽셀
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Expr? get _expr => Expr.tryParse(stripFunctionPrefix(_text.text));

  void _draw() {
    final src = stripFunctionPrefix(_text.text);
    final Expr f;
    try {
      f = Expr.parse(src);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    final x0 = double.tryParse(_from.text.trim()) ?? -5;
    final x1 = double.tryParse(_to.text.trim()) ?? 5;
    if (!(x1 > x0)) {
      setState(() => _error = 'x 범위를 확인하세요');
      return;
    }
    final c = widget.controller;
    final w = kPageWidth;
    final left = w * 0.08, right = w * 0.92;
    final span = (x1 - x0);
    final scaleX = (right - left) / span;
    final scaleY = _scale;
    final top = (widget.at?.dy ?? 120) - 150;
    final clip = Rect.fromLTRB(left, math.max(8, top), right, math.max(8, top) + 300);
    final origin = Offset(left + (0 - x0) * scaleX, clip.center.dy);
    final frame = PlotFrame(origin: origin, scaleX: scaleX, scaleY: scaleY);
    final now = DateTime.now().millisecondsSinceEpoch;
    final strokes = <InkStroke>[
      if (_axes)
        ...plotAxes(
            frame: frame,
            clip: clip,
            color: 0xFF9AA4B2,
            width: 1.6,
            step: _niceStep(span),
            startedAt: now),
      ...plotFunction(f, frame: frame, clip: clip, color: c.settings.penColor, width: c.settings.penWidth, startedAt: now + 100),
    ];
    if (strokes.isEmpty) {
      setState(() => _error = '이 범위에서는 그릴 값이 없어요');
      return;
    }
    c.addStrokes(strokes);
    Navigator.pop(context);
  }

  /// 눈금 간격 — 한 화면에 5~10칸쯤 되게.
  static double _niceStep(double span) {
    final raw = span / 8;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in [1, 2, 5, 10]) {
      if (raw <= mag * m) return mag * m;
    }
    return mag * 10;
  }

  @override
  Widget build(BuildContext context) {
    final ok = _expr != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 14),
          const Text('함수 그리기', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          const SizedBox(height: 4),
          const Text('식을 적으면 연습장에 그래프를 그려요. 그린 뒤에는 펜으로 고치거나 지울 수 있어요.',
              style: TextStyle(color: AppColors.inkSoft, fontSize: 13.5)),
          const SizedBox(height: 16),
          TextField(
            key: const Key('fn-input'),
            controller: _text,
            autofocus: true,
            autocorrect: false,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _draw(),
            decoration: InputDecoration(
              labelText: '함수',
              hintText: 'y = x^2 - 2x',
              prefixIcon: const Icon(Icons.functions_rounded),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in const ['x^2', 'x^3-3x', 'sin x', 'cos x', '1/x', 'sqrt x', 'ln x', 'e^x', '|x|'])
              ActionChip(
                label: Text(e),
                onPressed: () => setState(() {
                  _text.text = 'y = ${e.replaceAll('|x|', 'abs x')}';
                  _error = null;
                }),
              ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('fn-from'),
                controller: _from,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: const InputDecoration(labelText: 'x 처음'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('fn-to'),
                controller: _to,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: const InputDecoration(labelText: 'x 끝'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Text('세로 크기', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
            Expanded(
              child: Slider(
                value: _scale,
                min: 10,
                max: 90,
                onChanged: (v) => setState(() => _scale = v),
              ),
            ),
            Switch(value: _axes, onChanged: (v) => setState(() => _axes = v)),
            const SizedBox(width: 6),
            const Text('좌표축', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text(
                ok ? '쓸 수 있는 것: + - * / ^ ( ), sin cos tan, sqrt, ln, log, abs, e, pi' : '식을 읽지 못했어요',
                style: TextStyle(fontSize: 12.5, color: ok ? AppColors.inkMuted : AppColors.wrong),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              key: const Key('fn-draw'),
              onPressed: _draw,
              icon: const Icon(Icons.show_chart_rounded),
              label: const Text('그리기'),
            ),
          ]),
        ]),
      ),
    );
  }
}
