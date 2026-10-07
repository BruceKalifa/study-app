import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'ink_controller.dart';
import 'shape_snap.dart';

/// 도형을 맞췄을 때 잠깐 뜨는 알림 — "원으로 맞췄어요 · 되돌리기".
class ShapeSnapHint extends StatefulWidget {
  const ShapeSnapHint({super.key, required this.controller});
  final InkController controller;

  @override
  State<ShapeSnapHint> createState() => _ShapeSnapHintState();
}

class _ShapeSnapHintState extends State<ShapeSnapHint> {
  ShapeKind? _kind;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.controller.lastSnap.addListener(_onSnap);
  }

  @override
  void dispose() {
    _hide?.cancel();
    widget.controller.lastSnap.removeListener(_onSnap);
    super.dispose();
  }

  void _onSnap() {
    final k = widget.controller.lastSnap.value;
    if (!mounted) return;
    setState(() => _kind = k);
    _hide?.cancel();
    if (k != null) _hide = Timer(const Duration(seconds: 4), () => mounted ? setState(() => _kind = null) : null);
  }

  @override
  Widget build(BuildContext context) {
    final k = _kind;
    return AnimatedOpacity(
      opacity: k == null ? 0 : 1,
      duration: const Duration(milliseconds: 160),
      child: IgnorePointer(
        ignoring: k == null,
        child: Container(
          key: const Key('shape-hint'),
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: AppColors.ink.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${k == null ? '' : shapeName(k)}으로 맞췄어요',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
            TextButton(
              key: const Key('shape-undo'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                widget.controller.undoShapeSnap();
                _hide?.cancel();
                setState(() => _kind = null);
              },
              child: const Text('되돌리기'),
            ),
          ]),
        ),
      ),
    );
  }
}
