import 'package:flutter/material.dart';

import '../core/problem.dart';
import '../pdf/pdf_view.dart';
import 'math_text.dart';

/// 목록·오답노트·기록에 보이는 문제 본문 — 원본 PDF 문항이면 PDF 영역 그대로 (너무 길면 [maxHeight] 까지).
class ProblemStem extends StatelessWidget {
  const ProblemStem(this.problem, {super.key, required this.style, this.maxLines, this.maxHeight = 420, this.texStyle});
  final Problem problem;
  final TextStyle style;
  final int? maxLines;
  final double maxHeight;
  final bool? texStyle;

  @override
  Widget build(BuildContext context) {
    final r = problem.pdf;
    if (r == null) {
      return MathText(problem.stem, maxLines: maxLines, texStyle: texStyle ?? problem.texStyle, style: style);
    }
    // 원문 글자가 주변 글자와 비슷한 크기가 되게 (원문 약 9.5pt ↔ style.fontSize)
    final perPt = (style.fontSize ?? 16) / 9.5;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth.clamp(0.0, r.rect.width * perPt) : r.rect.width * perPt;
      final h = w * r.rect.height / r.rect.width;
      final cap = maxLines != null ? (style.fontSize ?? 16) * 1.7 * maxLines! : maxHeight;
      return ClipRect(
        child: SizedBox(
          width: w,
          height: h > cap ? cap : h,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: h,
            minHeight: h,
            child: SizedBox(width: w, height: h, child: PdfRegionView.region(r)),
          ),
        ),
      );
    });
  }
}

/// 해설 — 원본 PDF 해설 영역이 있으면 그대로, 아니면 글.
class ProblemSolution extends StatelessWidget {
  const ProblemSolution(this.problem, {super.key, required this.style, this.empty});
  final Problem problem;
  final TextStyle style;

  /// 해설이 없을 때 보일 글 (null 이면 아무것도).
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final r = problem.solutionPdf;
    if (r == null) {
      final t = problem.solution.trim().isEmpty ? (empty ?? '') : problem.solution;
      return MathText(t, texStyle: problem.texStyle, style: style);
    }
    final perPt = (style.fontSize ?? 16) / 9.5;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth.clamp(0.0, r.rect.width * perPt) : r.rect.width * perPt;
      return SizedBox(width: w, child: PdfRegionView.region(r));
    });
  }
}
