import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'function_sheet.dart';
import 'ink_controller.dart';
import 'ink_model.dart';

/// GoodNotes-style tool strip: tools on the left, contextual options in the middle,
/// undo/redo and more on the right.
class InkToolbar extends StatelessWidget {
  const InkToolbar({
    super.key,
    required this.controller,
    required this.onSettingsChanged,
    this.onResetView,
    this.extraMenu = const [],
  });

  final InkController controller;
  final VoidCallback onSettingsChanged;
  final VoidCallback? onResetView;
  final List<PopupMenuEntry<VoidCallback>> extraMenu;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final s = c.settings;
        return Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
            boxShadow: const [BoxShadow(color: Color(0x0F1B2A4A), blurRadius: 18, offset: Offset(0, 6))],
          ),
          child: Row(
            children: [
              _ToolButton(
                icon: Icons.edit_rounded,
                tooltip: '펜',
                active: c.tool == InkTool.pen,
                color: Color(s.penColor),
                onTap: () => c.tool = InkTool.pen,
              ),
              _ToolButton(
                icon: Icons.format_color_fill_rounded,
                glyph: _Glyph.highlighter,
                tooltip: '형광펜',
                active: c.tool == InkTool.highlighter,
                color: Color(s.highlighterColor).withValues(alpha: 1),
                onTap: () => c.tool = InkTool.highlighter,
              ),
              _ToolButton(
                icon: Icons.auto_fix_normal_rounded,
                glyph: _Glyph.eraser,
                tooltip: '지우개 (S펜 버튼을 누른 채 써도 지워져요)',
                active: c.tool == InkTool.eraser,
                onTap: () => c.tool = InkTool.eraser,
              ),
              _ToolButton(
                icon: Icons.gesture_rounded,
                tooltip: '올가미 선택',
                active: c.tool == InkTool.lasso,
                onTap: () => c.tool = InkTool.lasso,
              ),
              _ToolButton(
                icon: Icons.show_chart_rounded,
                tooltip: '함수 그리기',
                onTap: () => showFunctionSheet(context, c),
              ),
              const _Divider(),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _contextual(context, c, s),
                ),
              ),
              const _Divider(),
              _ToolButton(
                icon: Icons.undo_rounded,
                tooltip: '실행 취소 (두 손가락 탭)',
                enabled: c.canUndo,
                onTap: c.undo,
              ),
              _ToolButton(
                icon: Icons.redo_rounded,
                tooltip: '다시 실행 (세 손가락 탭)',
                enabled: c.canRedo,
                onTap: c.redo,
              ),
              PopupMenuButton<VoidCallback>(
                tooltip: '더보기',
                icon: const Icon(Icons.more_horiz_rounded, color: AppColors.ink),
                onSelected: (fn) => fn(),
                itemBuilder: (ctx) => [
                  _menuHeader('종이'),
                  for (final ps in PaperStyle.values)
                    CheckedPopupMenuItem<VoidCallback>(
                      checked: s.paper == ps,
                      value: () {
                        s.paper = ps;
                        onSettingsChanged();
                        c.notifySettingsChanged();
                      },
                      child: Text(_paperName(ps)),
                    ),
                  const PopupMenuDivider(),
                  CheckedPopupMenuItem<VoidCallback>(
                    checked: s.fingerDraws,
                    value: () {
                      s.fingerDraws = !s.fingerDraws;
                      onSettingsChanged();
                      c.notifySettingsChanged();
                    },
                    child: const Text('손가락으로 쓰기'),
                  ),
                  CheckedPopupMenuItem<VoidCallback>(
                    checked: s.holdToStraighten,
                    value: () {
                      s.holdToStraighten = !s.holdToStraighten;
                      onSettingsChanged();
                    },
                    child: const Text('멈추면 직선으로'),
                  ),
                  CheckedPopupMenuItem<VoidCallback>(
                    checked: s.shapeSnap,
                    value: () {
                      s.shapeSnap = !s.shapeSnap;
                      onSettingsChanged();
                    },
                    child: const Text('도형 자동 맞추기'),
                  ),
                  CheckedPopupMenuItem<VoidCallback>(
                    checked: s.pressure,
                    value: () {
                      s.pressure = !s.pressure;
                      onSettingsChanged();
                    },
                    child: const Text('필압 사용'),
                  ),
                  const PopupMenuDivider(),
                  if (onResetView != null)
                    PopupMenuItem<VoidCallback>(
                      value: onResetView,
                      child: const ListTile(
                          dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.fit_screen_rounded), title: Text('화면 맞춤')),
                    ),
                  PopupMenuItem<VoidCallback>(
                    value: c.clearAll,
                    child: const ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_sweep_rounded, color: AppColors.wrong),
                        title: Text('이 페이지 필기 모두 지우기')),
                  ),
                  ...extraMenu,
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static PopupMenuEntry<VoidCallback> _menuHeader(String t) => PopupMenuItem<VoidCallback>(
        enabled: false,
        height: 32,
        child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
      );

  static String _paperName(PaperStyle p) {
    switch (p) {
      case PaperStyle.blank:
        return '무지';
      case PaperStyle.lines:
        return '줄 노트';
      case PaperStyle.grid:
        return '모눈';
      case PaperStyle.dots:
        return '점 격자';
    }
  }

  Widget _contextual(BuildContext context, InkController c, InkSettings s) {
    if (c.selection.isNotEmpty) {
      return Row(children: [
        Text('${c.selection.length}개 선택됨',
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft, fontSize: 14)),
        const SizedBox(width: 10),
        for (final col in s.palette.take(5))
          _Swatch(color: Color(col), selected: false, onTap: () => c.recolorSelection(col)),
        const SizedBox(width: 6),
        _ChipButton(icon: Icons.copy_rounded, label: '복제', onTap: c.duplicateSelection),
        _ChipButton(icon: Icons.delete_outline_rounded, label: '삭제', onTap: c.deleteSelection, danger: true),
        _ChipButton(icon: Icons.close_rounded, label: '해제', onTap: () => c.clearSelection()),
      ]);
    }
    switch (c.tool) {
      case InkTool.pen:
        return Row(children: [
          for (final col in s.palette)
            _Swatch(
              color: Color(col),
              selected: s.penColor == col,
              onTap: () {
                s.penColor = col;
                onSettingsChanged();
                c.notifySettingsChanged();
              },
            ),
          const SizedBox(width: 10),
          for (final w in const [2.0, 3.2, 5.0, 8.0])
            _WidthDot(
              width: w,
              color: Color(s.penColor),
              selected: (s.penWidth - w).abs() < 0.01,
              onTap: () {
                s.penWidth = w;
                onSettingsChanged();
                c.notifySettingsChanged();
              },
            ),
        ]);
      case InkTool.highlighter:
        return Row(children: [
          for (final col in InkSettings.highlighterPalette)
            _Swatch(
              color: Color(col).withValues(alpha: 1),
              selected: s.highlighterColor == col,
              onTap: () {
                s.highlighterColor = col;
                onSettingsChanged();
                c.notifySettingsChanged();
              },
            ),
          const SizedBox(width: 10),
          for (final w in const [14.0, 22.0, 34.0])
            _WidthDot(
              width: w / 4,
              color: Color(s.highlighterColor).withValues(alpha: 1),
              selected: (s.highlighterWidth - w).abs() < 0.01,
              onTap: () {
                s.highlighterWidth = w;
                onSettingsChanged();
                c.notifySettingsChanged();
              },
            ),
        ]);
      case InkTool.eraser:
        return Row(children: [
          _Segment(
            labels: const ['획 지우개', '부분 지우개'],
            index: s.eraserMode == EraserMode.stroke ? 0 : 1,
            onChanged: (i) {
              s.eraserMode = i == 0 ? EraserMode.stroke : EraserMode.area;
              onSettingsChanged();
              c.notifySettingsChanged();
            },
          ),
          const SizedBox(width: 12),
          for (final w in const [12.0, 22.0, 44.0])
            _WidthDot(
              width: w / 4,
              color: AppColors.inkMuted,
              selected: (s.eraserSize - w).abs() < 0.01,
              onTap: () {
                s.eraserSize = w;
                onSettingsChanged();
                c.notifySettingsChanged();
              },
            ),
        ]);
      case InkTool.lasso:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('필기를 둘러 그려서 선택하세요 · 선택한 필기는 끌어서 옮길 수 있어요',
              style: TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600, fontSize: 13.5)),
        );
    }
  }
}

enum _Glyph { highlighter, eraser }

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);
  final _Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    canvas.save();
    canvas.translate(w / 2, size.height / 2);
    canvas.rotate(-0.785);
    if (glyph == _Glyph.eraser) {
      final body = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w * 0.42, height: w * 0.86),
          Radius.circular(w * 0.08));
      canvas.drawRRect(body, stroke);
      canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTRB(-w * 0.21, w * 0.12, w * 0.21, w * 0.43),
              bottomLeft: Radius.circular(w * 0.08), bottomRight: Radius.circular(w * 0.08)),
          fill);
    } else {
      // marker body + chisel tip
      final body = RRect.fromRectAndRadius(Rect.fromLTRB(-w * 0.17, -w * 0.44, w * 0.17, w * 0.12),
          Radius.circular(w * 0.06));
      canvas.drawRRect(body, stroke);
      final tip = Path()
        ..moveTo(-w * 0.17, w * 0.12)
        ..lineTo(w * 0.17, w * 0.12)
        ..lineTo(w * 0.08, w * 0.34)
        ..lineTo(-w * 0.08, w * 0.26)
        ..close();
      canvas.drawPath(tip, fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) => old.color != color || old.glyph != glyph;
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.enabled = true,
    this.color,
    this.glyph,
  });
  final _Glyph? glyph;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool enabled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: active ? AppColors.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (glyph != null)
                  CustomPaint(
                    size: const Size(22, 22),
                    painter: _GlyphPainter(glyph!, active ? Colors.white : AppColors.ink),
                  )
                else
                  Icon(icon,
                      size: 22,
                      color: !enabled
                          ? AppColors.lineStrong
                          : active
                              ? Colors.white
                              : AppColors.ink),
                if (color != null)
                  Positioned(
                    bottom: 5,
                    child: Container(
                      width: 14,
                      height: 3.5,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, margin: const EdgeInsets.symmetric(horizontal: 8), color: AppColors.line);
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 30,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: selected ? AppColors.ink : Colors.transparent, width: 2),
        ),
        child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      ),
    );
  }
}

class _WidthDot extends StatelessWidget {
  const _WidthDot({required this.width, required this.color, required this.selected, required this.onTap});
  final double width;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = (width * 2.2).clamp(4.0, 20.0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.paperDeep : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Container(width: d, height: d, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.paperDeep, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: i == index ? AppColors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: i == index ? const [BoxShadow(color: Color(0x141B2A4A), blurRadius: 6)] : null,
                ),
                child: Text(labels[i],
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: i == index ? AppColors.ink : AppColors.inkMuted)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.wrong : AppColors.ink;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(color: color)),
        style: TextButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.07),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
