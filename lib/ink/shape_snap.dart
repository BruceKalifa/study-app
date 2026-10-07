import 'dart:math' as math;
import 'dart:ui';

import 'ink_model.dart';

/// 손으로 그린 획을 알아보는 도형.
enum ShapeKind { line, circle, ellipse, triangle, rectangle, arc }

String shapeName(ShapeKind k) => switch (k) {
      ShapeKind.line => '직선',
      ShapeKind.circle => '원',
      ShapeKind.ellipse => '타원',
      ShapeKind.triangle => '삼각형',
      ShapeKind.rectangle => '사각형',
      ShapeKind.arc => '호',
    };

class SnappedShape {
  final ShapeKind kind;
  final List<InkPoint> points;
  const SnappedShape(this.kind, this.points);
}

/// 손으로 그린 획 [pts] 을 수능 풀이에서 자주 쓰는 도형으로 맞춘다 (아니면 null).
///
/// 직선·원·타원·삼각형·사각형·호를 알아본다. 글씨처럼 작거나 복잡한 획은 그대로 둔다.
SnappedShape? snapShape(List<InkPoint> pts, {double minSize = 26}) {
  if (pts.length < 6) return null;
  final n = pts.length;
  final first = pts.first.offset, last = pts.last.offset;
  final box = _bounds(pts);
  if (box.longestSide < minSize) return null; // 글씨 크기는 건드리지 않는다
  final pathLen = _pathLength(pts);
  if (pathLen < minSize) return null;
  final avgP = pts.fold<double>(0, (a, p) => a + p.p) / n;
  final tEnd = pts.last.t;
  InkPoint at(Offset o, double f) => InkPoint(o.dx, o.dy, avgP, (tEnd * f).round());

  List<InkPoint> poly(List<Offset> os, {bool close = false}) {
    final all = close ? [...os, os.first] : os;
    return [for (var i = 0; i < all.length; i++) at(all[i], all.length == 1 ? 0 : i / (all.length - 1))];
  }

  // ── 직선 ──
  final chord = (last - first).distance;
  if (chord > minSize && pathLen <= chord * 1.12 && _maxDeviation(pts, first, last) <= chord * 0.06) {
    var a = first, b = last;
    final d = b - a;
    final ang = math.atan2(d.dy, d.dx);
    const snap = 7 * math.pi / 180;
    for (final k in [0, 1, 2, 3, -1, -2, -3]) {
      final target = k * math.pi / 4;
      if ((_wrap(ang - target)).abs() < snap) {
        final len = d.distance;
        b = a + Offset(math.cos(target), math.sin(target)) * len;
        break;
      }
    }
    return SnappedShape(ShapeKind.line, poly([a, b]));
  }

  final closed = chord < pathLen * 0.22 || chord < box.longestSide * 0.3;
  final center = Offset(box.center.dx, box.center.dy);

  // ── 원 · 타원 (닫힌 획 중 모서리가 없고 반지름이 고른 것) ──
  if (closed && pathLen > box.longestSide * 2.2) {
    final rs = [for (final p in pts) (p.offset - center).distance];
    final rMean = rs.reduce((a, b) => a + b) / rs.length;
    if (rMean > 1) {
      var dev = 0.0;
      for (final r in rs) {
        dev = math.max(dev, (r - rMean).abs());
      }
      if (dev <= rMean * 0.26) {
        return SnappedShape(ShapeKind.circle, poly(_circle(center, rMean), close: true));
      }
      // 타원: x·y 반지름을 따로 보고 고른지 확인
      final rx = box.width / 2, ry = box.height / 2;
      if (rx > 4 && ry > 4) {
        var edev = 0.0;
        for (final p in pts) {
          final dx = (p.x - center.dx) / rx, dy = (p.y - center.dy) / ry;
          edev = math.max(edev, (math.sqrt(dx * dx + dy * dy) - 1).abs());
        }
        if (edev <= 0.22) {
          return SnappedShape(ShapeKind.ellipse, poly(_ellipse(center, rx, ry), close: true));
        }
      }
    }
  }

  // ── 다각형 (모서리를 찾아서) ──
  final corners = _corners(pts, tol: math.max(4, box.longestSide * 0.055));
  if (closed && corners.length >= 4) {
    // 닫힌 획은 마지막 점이 첫 점과 겹치므로 하나를 뺀다
    final cs = corners.length > 3 && (corners.last - corners.first).distance < box.longestSide * 0.25
        ? corners.sublist(0, corners.length - 1)
        : corners;
    if (cs.length == 3) return SnappedShape(ShapeKind.triangle, poly(cs, close: true));
    if (cs.length == 4) {
      final r = _asRect(cs, box);
      return SnappedShape(ShapeKind.rectangle, poly(r, close: true));
    }
  }
  if (!closed && corners.length == 3) {
    // ㄱ자 꺾은선은 그대로 두고, 직각에 가까우면 모서리만 깎아 준다
    return SnappedShape(ShapeKind.line, poly(corners));
  }

  // ── 호 (열린 원호) ──
  if (!closed && pathLen > chord * 1.25 && pathLen < chord * 2.6) {
    final c = _circleThrough(first, pts[n ~/ 2].offset, last);
    if (c != null && c.$2 < box.longestSide * 4) {
      final (cc, r) = c;
      var dev = 0.0;
      for (final p in pts) {
        dev = math.max(dev, ((p.offset - cc).distance - r).abs());
      }
      if (dev <= r * 0.14) {
        final a0 = math.atan2(first.dy - cc.dy, first.dx - cc.dx);
        final a1 = math.atan2(last.dy - cc.dy, last.dx - cc.dx);
        final mid = math.atan2(pts[n ~/ 2].y - cc.dy, pts[n ~/ 2].x - cc.dx);
        return SnappedShape(ShapeKind.arc, poly(_arc(cc, r, a0, a1, mid)));
      }
    }
  }
  return null;
}

// ───────────────────────── 도우미 ─────────────────────────

Rect _bounds(List<InkPoint> pts) {
  var minX = pts.first.x, maxX = minX, minY = pts.first.y, maxY = minY;
  for (final p in pts) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

double _pathLength(List<InkPoint> pts) {
  var d = 0.0;
  for (var i = 1; i < pts.length; i++) {
    d += (pts[i].offset - pts[i - 1].offset).distance;
  }
  return d;
}

double _wrap(double a) {
  while (a > math.pi) {
    a -= 2 * math.pi;
  }
  while (a < -math.pi) {
    a += 2 * math.pi;
  }
  return a;
}

/// 선분 [a]-[b] 에서 가장 멀리 벗어난 거리.
double _maxDeviation(List<InkPoint> pts, Offset a, Offset b) {
  final d = b - a;
  final len = d.distance;
  if (len < 1e-6) return 0;
  var worst = 0.0;
  for (final p in pts) {
    final v = p.offset - a;
    final cross = (v.dx * d.dy - v.dy * d.dx).abs() / len;
    worst = math.max(worst, cross);
  }
  return worst;
}

/// Ramer–Douglas–Peucker 로 꼭짓점만 남긴다.
List<Offset> _corners(List<InkPoint> pts, {required double tol}) {
  final os = [for (final p in pts) p.offset];
  final keep = List<bool>.filled(os.length, false);
  keep[0] = true;
  keep[os.length - 1] = true;
  void rdp(int i, int j) {
    if (j <= i + 1) return;
    var worst = 0.0;
    var idx = -1;
    final a = os[i], b = os[j];
    final d = b - a;
    final len = d.distance;
    for (var k = i + 1; k < j; k++) {
      final v = os[k] - a;
      final dist = len < 1e-6 ? v.distance : (v.dx * d.dy - v.dy * d.dx).abs() / len;
      if (dist > worst) {
        worst = dist;
        idx = k;
      }
    }
    if (worst > tol && idx > 0) {
      keep[idx] = true;
      rdp(i, idx);
      rdp(idx, j);
    }
  }

  rdp(0, os.length - 1);
  return [for (var i = 0; i < os.length; i++) if (keep[i]) os[i]];
}

List<Offset> _circle(Offset c, double r, {int steps = 48}) =>
    [for (var i = 0; i < steps; i++) c + Offset(math.cos(i / steps * 2 * math.pi) * r, math.sin(i / steps * 2 * math.pi) * r)];

List<Offset> _ellipse(Offset c, double rx, double ry, {int steps = 48}) => [
      for (var i = 0; i < steps; i++)
        c + Offset(math.cos(i / steps * 2 * math.pi) * rx, math.sin(i / steps * 2 * math.pi) * ry)
    ];

List<Offset> _arc(Offset c, double r, double a0, double a1, double mid, {int steps = 32}) {
  // a0 → a1 중 mid 를 지나는 쪽으로 돈다
  var sweep = _wrap(a1 - a0);
  final ccw = _wrap(mid - a0);
  if (sweep.sign != ccw.sign && ccw != 0) sweep += sweep > 0 ? -2 * math.pi : 2 * math.pi;
  return [for (var i = 0; i <= steps; i++) c + Offset(math.cos(a0 + sweep * i / steps) * r, math.sin(a0 + sweep * i / steps) * r)];
}

/// 꼭짓점 네 개 → 직사각형(거의 직각이면 외접 사각형, 아니면 그대로).
List<Offset> _asRect(List<Offset> cs, Rect box) {
  var square = true;
  for (var i = 0; i < 4; i++) {
    final a = cs[(i + 3) % 4], b = cs[i], c = cs[(i + 1) % 4];
    final v1 = a - b, v2 = c - b;
    final ang = (_wrap(math.atan2(v2.dy, v2.dx) - math.atan2(v1.dy, v1.dx))).abs();
    if ((ang - math.pi / 2).abs() > 20 * math.pi / 180) square = false;
  }
  if (!square) return cs;
  return [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft];
}

/// 세 점을 지나는 원 (한 직선 위면 null).
(Offset, double)? _circleThrough(Offset a, Offset b, Offset c) {
  final d = 2 * (a.dx * (b.dy - c.dy) + b.dx * (c.dy - a.dy) + c.dx * (a.dy - b.dy));
  if (d.abs() < 1e-6) return null;
  final ux = ((a.dx * a.dx + a.dy * a.dy) * (b.dy - c.dy) +
          (b.dx * b.dx + b.dy * b.dy) * (c.dy - a.dy) +
          (c.dx * c.dx + c.dy * c.dy) * (a.dy - b.dy)) /
      d;
  final uy = ((a.dx * a.dx + a.dy * a.dy) * (c.dx - b.dx) +
          (b.dx * b.dx + b.dy * b.dy) * (a.dx - c.dx) +
          (c.dx * c.dx + c.dy * c.dy) * (b.dx - a.dx)) /
      d;
  final cc = Offset(ux, uy);
  return (cc, (a - cc).distance);
}
