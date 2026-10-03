import 'dart:math' as math;
import 'dart:ui';

import 'ink_model.dart';

/// Pre-computed geometry for one stroke.
class _Geometry {
  final Path ribbon;
  final List<Offset> dotCenters;
  final List<double> dotRadii;
  final Path? line; // highlighter centre-line
  _Geometry(this.ribbon, this.dotCenters, this.dotRadii, this.line);
}

class _Sample {
  final double x, y, r;
  const _Sample(this.x, this.y, this.r);
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

  static void paint(Canvas canvas, InkStroke s, {bool dim = false, bool live = false}) {
    if (s.points.isEmpty) return;
    var g = live ? null : s.renderCache as _Geometry?;
    if (g == null) {
      g = _build(s);
      if (!live) s.renderCache = g;
    }
    var color = Color(s.color);
    if (dim) color = color.withValues(alpha: color.a * 0.35);
    if (s.tool == InkTool.highlighter) {
      _hl
        ..color = color
        ..strokeWidth = s.width;
      final line = g.line;
      if (line != null) canvas.drawPath(line, _hl);
      if (s.points.length == 1) {
        _fill.color = color;
        canvas.drawCircle(s.points.first.offset, s.width / 2, _fill);
      }
      return;
    }
    _fill.color = color;
    canvas.drawPath(g.ribbon, _fill);
    for (var i = 0; i < g.dotCenters.length; i++) {
      canvas.drawCircle(g.dotCenters[i], g.dotRadii[i], _fill);
    }
  }

  /// Smoothed, densified samples along a Catmull-Rom spline through the points.
  static List<_Sample> _samples(InkStroke s) {
    final pts = s.points;
    final n = pts.length;
    // light pressure smoothing
    final pr = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final a = pts[math.max(0, i - 1)].p, b = pts[i].p, c = pts[math.min(n - 1, i + 1)].p;
      pr[i] = (a + 2 * b + c) / 4;
    }
    // taper the very first/last points a little so starts look natural
    final out = <_Sample>[];
    final w = s.width;
    for (var i = 0; i < n - 1; i++) {
      final p0 = pts[math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[math.min(n - 1, i + 2)];
      final dx = p2.x - p1.x, dy = p2.y - p1.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      final r1 = penRadius(w, pr[i]), r2 = penRadius(w, pr[i + 1]);
      final step = math.max(0.6, math.min(r1, r2) * 0.5);
      final k = (dist / step).ceil().clamp(1, 24);
      for (var j = 0; j < k; j++) {
        final t = j / k;
        final t2 = t * t, t3 = t2 * t;
        final x = 0.5 *
            ((2 * p1.x) +
                (-p0.x + p2.x) * t +
                (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
                (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3);
        final y = 0.5 *
            ((2 * p1.y) +
                (-p0.y + p2.y) * t +
                (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
                (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);
        out.add(_Sample(x, y, r1 + (r2 - r1) * t));
      }
    }
    final last = pts[n - 1];
    out.add(_Sample(last.x, last.y, penRadius(w, pr[n - 1])));
    return out;
  }

  static _Geometry _build(InkStroke s) {
    final samples = s.points.length == 1
        ? [_Sample(s.points.first.x, s.points.first.y, penRadius(s.width, s.points.first.p))]
        : _samples(s);

    if (s.tool == InkTool.highlighter) {
      final line = Path()..moveTo(samples.first.x, samples.first.y);
      for (var i = 1; i < samples.length; i++) {
        line.lineTo(samples[i].x, samples[i].y);
      }
      return _Geometry(Path(), const [], const [], line);
    }

    final centers = <Offset>[];
    final radii = <double>[];
    void dot(_Sample a) {
      centers.add(Offset(a.x, a.y));
      radii.add(a.r);
    }

    if (samples.length == 1) {
      dot(samples.first);
      return _Geometry(Path(), centers, radii, null);
    }

    // Build left/right offset polylines.
    final left = <Offset>[];
    final right = <Offset>[];
    double? prevDx, prevDy;
    for (var i = 0; i < samples.length; i++) {
      final a = samples[i];
      final b = samples[math.min(samples.length - 1, i + 1)];
      final c = samples[math.max(0, i - 1)];
      var dx = b.x - c.x, dy = b.y - c.y;
      var len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-6) {
        if (prevDx == null) {
          dx = 1;
          dy = 0;
        } else {
          dx = prevDx;
          dy = prevDy!;
        }
        len = 1;
      } else {
        dx /= len;
        dy /= len;
      }
      // sharp turn → round joint
      if (prevDx != null && (dx * prevDx + dy * prevDy!) < 0.35) dot(a);
      prevDx = dx;
      prevDy = dy;
      final nx = -dy * a.r, ny = dx * a.r;
      left.add(Offset(a.x + nx, a.y + ny));
      right.add(Offset(a.x - nx, a.y - ny));
    }
    final ribbon = Path()..moveTo(left.first.dx, left.first.dy);
    for (var i = 1; i < left.length; i++) {
      ribbon.lineTo(left[i].dx, left[i].dy);
    }
    for (var i = right.length - 1; i >= 0; i--) {
      ribbon.lineTo(right[i].dx, right[i].dy);
    }
    ribbon.close();
    dot(samples.first);
    dot(samples.last);
    return _Geometry(ribbon, centers, radii, null);
  }
}
