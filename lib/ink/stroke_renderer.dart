import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'ink_model.dart';

/// Pre-computed geometry for one finished stroke.
class _Geometry {
  final Path fill; // pen: segment polygons + round joints (one path, one draw call)
  final Path? line; // highlighter centre-line
  _Geometry(this.fill, this.line);
}

/// 그리고 있는 획: 끝난 구간은 한 번만 만들어 쌓아 두고, 마지막 구간만 매 프레임 다시 만든다
/// (긴 획에서도 펜이 느려지지 않게).
class _Live {
  final Path frozen = Path();

  /// frozen 에 들어간 구간 수 (구간 i = 점 i → i+1).
  int segments = 0;
  int pointCount = 0;
  double firstX = 0, firstY = 0;
}

/// Pressure → radius curve shared by pen rendering everywhere (app + replay).
double penRadius(double width, double pressure) {
  final p = pressure.clamp(0.0, 1.0);
  return width / 2 * (0.28 + 0.72 * math.pow(p, 0.8));
}

class StrokeRenderer {
  StrokeRenderer._();

  static final Paint _fill = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  static final Paint _hl = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  static final Expando<_Live> _live = Expando<_Live>('liveInk');

  /// 그리는 중인 획의 점을 통째로 바꿨을 때 (도형 맞추기) 쌓아 둔 모양을 버린다.
  static void resetLive(InkStroke s) => _live[s] = null;

  /// Paint every stroke: highlighters first (under), then pens.
  static void paintAll(Canvas canvas, Iterable<InkStroke> strokes, {Rect? cull, Set<String>? dimmed}) {
    for (final s in strokes) {
      if (s.tool != InkTool.highlighter) continue;
      if (cull != null && !cull.overlaps(s.bounds)) continue;
      paint(canvas, s, dim: dimmed?.contains(s.id) ?? false);
    }
    for (final s in strokes) {
      if (s.tool == InkTool.highlighter) continue;
      if (cull != null && !cull.overlaps(s.bounds)) continue;
      paint(canvas, s, dim: dimmed?.contains(s.id) ?? false);
    }
  }

  /// [live]: the stroke is still growing (its geometry is not cached as final).
  /// [predicted]: where the pen will probably be a moment from now — drawn as a short tail
  /// so the line keeps up with the pen tip (replaced by the real points as they arrive).
  static void paint(Canvas canvas, InkStroke s, {bool dim = false, bool live = false, Offset? predicted}) {
    if (s.points.isEmpty) return;
    var color = Color(s.color);
    if (dim) color = color.withValues(alpha: color.a * 0.35);

    if (s.tool == InkTool.highlighter) {
      var g = live ? null : s.renderCache as _Geometry?;
      if (g == null) {
        g = _Geometry(Path(), _centreLine(s));
        if (!live) s.renderCache = g;
      }
      _hl
        ..color = color
        ..strokeWidth = s.width;
      if (s.points.length == 1) {
        _fill.color = color;
        canvas.drawCircle(s.points.first.offset, s.width / 2, _fill);
      } else {
        canvas.drawPath(g.line!, _hl);
      }
      return;
    }

    _fill.color = color;
    if (!live) {
      var g = s.renderCache as _Geometry?;
      if (g == null) {
        final p = Path();
        _segments(s, 0, s.points.length - 1, p, closeEnd: true);
        g = _Geometry(p, null);
        s.renderCache = g;
      }
      canvas.drawPath(g.fill, _fill);
      return;
    }

    // ── live ──
    final pts = s.points;
    final n = pts.length;
    var c = _live[s];
    if (c == null || n < c.pointCount || pts.first.x != c.firstX || pts.first.y != c.firstY) {
      c = _Live()
        ..firstX = pts.first.x
        ..firstY = pts.first.y;
      _live[s] = c;
    }
    // 구간 i 는 점 i+2 가 생기면 더 바뀌지 않는다 (곡선·필압 다듬기가 앞뒤 점을 쓴다)
    final frozenUpTo = math.max(0, n - 3); // [0, frozenUpTo) 구간은 끝났다
    if (frozenUpTo > c.segments) {
      _segments(s, c.segments, frozenUpTo, c.frozen, closeEnd: false);
      c.segments = frozenUpTo;
    }
    c.pointCount = n;
    canvas.drawPath(c.frozen, _fill);
    final tail = Path();
    _segments(s, c.segments, n - 1, tail, closeEnd: true);
    if (predicted != null && n >= 2) {
      final last = pts.last;
      final r = penRadius(s.width, last.p);
      final d = predicted - last.offset;
      if (d.distance > 0.5) {
        final nx = -d.dy / d.distance * r, ny = d.dx / d.distance * r;
        _addPolygon(tail, [
          Offset(last.x + nx, last.y + ny),
          Offset(predicted.dx + nx, predicted.dy + ny),
          Offset(predicted.dx - nx, predicted.dy - ny),
          Offset(last.x - nx, last.y - ny),
        ]);
        _addDisc(tail, predicted, r);
      }
    }
    canvas.drawPath(tail, _fill);
  }

  /// Pressure, lightly smoothed with the neighbours (same everywhere so live = final).
  static double _pr(List<InkPoint> pts, int i) {
    final n = pts.length;
    final a = pts[math.max(0, i - 1)].p, b = pts[i].p, c = pts[math.min(n - 1, i + 1)].p;
    return (a + 2 * b + c) / 4;
  }

  /// Adds segments [from, to) (segment i = point i → i+1, a Catmull-Rom curve) to [out]:
  /// one polygon per segment plus a round joint at each segment start. With [closeEnd] the last
  /// point gets a round cap too. A single point becomes a dot.
  static void _segments(InkStroke s, int from, int to, Path out, {required bool closeEnd}) {
    final pts = s.points;
    final n = pts.length;
    final w = s.width;
    if (n == 1) {
      if (closeEnd) _addDisc(out, pts.first.offset, penRadius(w, _pr(pts, 0)));
      return;
    }
    for (var i = from; i < to; i++) {
      final p0 = pts[math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[math.min(n - 1, i + 2)];
      final r1 = penRadius(w, _pr(pts, i)), r2 = penRadius(w, _pr(pts, i + 1));
      final dx = p2.x - p1.x, dy = p2.y - p1.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      final step = math.max(0.6, math.min(r1, r2) * 0.5);
      final k = (dist / step).ceil().clamp(1, 24);
      // samples j = 0..k along the curve
      final xs = Float64List(k + 1), ys = Float64List(k + 1), rs = Float64List(k + 1);
      for (var j = 0; j <= k; j++) {
        final t = j / k;
        final t2 = t * t, t3 = t2 * t;
        xs[j] = 0.5 *
            ((2 * p1.x) +
                (-p0.x + p2.x) * t +
                (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
                (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3);
        ys[j] = 0.5 *
            ((2 * p1.y) +
                (-p0.y + p2.y) * t +
                (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
                (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);
        rs[j] = r1 + (r2 - r1) * t;
      }
      _addDisc(out, Offset(xs[0], ys[0]), r1);
      if (dist < 1e-6) continue;
      final left = <Offset>[], right = <Offset>[];
      for (var j = 0; j <= k; j++) {
        final a = math.max(0, j - 1), b = math.min(k, j + 1);
        var tx = xs[b] - xs[a], ty = ys[b] - ys[a];
        var len = math.sqrt(tx * tx + ty * ty);
        if (len < 1e-6) {
          tx = dx;
          ty = dy;
          len = dist;
        }
        final nx = -ty / len * rs[j], ny = tx / len * rs[j];
        left.add(Offset(xs[j] + nx, ys[j] + ny));
        right.add(Offset(xs[j] - nx, ys[j] - ny));
      }
      _addPolygon(out, [...left, ...right.reversed]);
    }
    if (closeEnd) {
      final last = pts[n - 1];
      _addDisc(out, last.offset, penRadius(w, _pr(pts, n - 1)));
    }
  }

  /// A round joint/cap as a polygon (same winding as every other piece — see [_addPolygon]).
  static void _addDisc(Path out, Offset c, double r) {
    final m = (r * 4).clamp(10, 28).round();
    final poly = <Offset>[
      for (var i = 0; i < m; i++) c + Offset(math.cos(i * 2 * math.pi / m) * r, math.sin(i * 2 * math.pi / m) * r)
    ];
    out.addPolygon(poly, true);
  }

  /// Every piece goes in with the same winding (that of [_addDisc]: increasing angle), so
  /// overlapping pieces add up under the non-zero fill rule instead of cancelling into holes.
  static void _addPolygon(Path out, List<Offset> poly) {
    var area = 0.0;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    out.addPolygon(area < 0 ? poly.reversed.toList() : poly, true);
  }

  static Path _centreLine(InkStroke s) {
    final pts = s.points;
    final line = Path()..moveTo(pts.first.x, pts.first.y);
    if (pts.length == 2) {
      line.lineTo(pts[1].x, pts[1].y);
      return line;
    }
    // smooth through the points (quadratic through midpoints)
    for (var i = 1; i < pts.length - 1; i++) {
      final m = Offset((pts[i].x + pts[i + 1].x) / 2, (pts[i].y + pts[i + 1].y) / 2);
      line.quadraticBezierTo(pts[i].x, pts[i].y, m.dx, m.dy);
    }
    line.lineTo(pts.last.x, pts.last.y);
    return line;
  }
}
