import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color = AppColors.inkSoft, this.background, this.icon, this.dense = false});
  final String label;
  final Color color;
  final Color? background;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: dense ? 11.5 : 12.5, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.1)),
        ],
      ),
    );
  }
}

class DifficultyDots extends StatelessWidget {
  const DifficultyDots(this.level, {super.key, this.color = AppColors.ink, this.size = 7});
  final int level;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '난이도 $level / 5',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Container(
              width: size,
              height: size,
              margin: EdgeInsets.only(right: i == 5 ? 0 : size * 0.45),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i <= level ? color : color.withValues(alpha: 0.15),
              ),
            ),
        ],
      ),
    );
  }
}

class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 120,
    this.stroke = 12,
    this.color = AppColors.accent,
    this.track = AppColors.line,
    this.child,
  });
  final double value;
  final double size;
  final double stroke;
  final Color color;
  final Color track;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, stroke, color, track),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.stroke, this.color, this.track);
  final double v, stroke;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (math.min(size.width, size.height) - stroke) / 2;
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawCircle(c, r, p);
    if (v > 0) {
      p.color = color;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * v, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.v != v || old.color != color;
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.sub, this.icon, this.color = AppColors.ink});
  final String label;
  final String value;
  final String? sub;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              if (icon != null) ...[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
                  child: Icon(icon, size: 17, color: color),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(label,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.inkSoft),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 12),
            Text(value,
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1, color: AppColors.ink, height: 1.1)),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub!, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w500)),
            ],
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.ink)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(color: AppColors.paperDeep, borderRadius: BorderRadius.circular(24)),
              child: Icon(icon, size: 36, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.inkMuted)),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class AccuracyBar extends StatelessWidget {
  const AccuracyBar({super.key, required this.value, this.color = AppColors.correct, this.height = 8});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          Positioned.fill(child: ColoredBox(color: color.withValues(alpha: 0.13))),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: ColoredBox(color: color),
          ),
        ]),
      ),
    );
  }
}

class ResultMark extends StatelessWidget {
  const ResultMark({super.key, required this.correct, this.size = 26});
  final bool? correct;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = correct;
    final color = c == null ? AppColors.inkMuted : (c ? AppColors.correct : AppColors.wrong);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), shape: BoxShape.circle),
      child: Icon(c == null ? Icons.remove_rounded : (c ? Icons.circle_outlined : Icons.close_rounded),
          size: size * 0.62, color: color),
    );
  }
}

/// Accent colour for accuracy values.
Color accuracyColor(double v) {
  if (v >= 0.8) return AppColors.correct;
  if (v >= 0.5) return AppColors.review;
  return AppColors.wrong;
}

String pct(double v) => '${(v * 100).round()}%';
