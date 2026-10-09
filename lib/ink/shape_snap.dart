import 'dart:math' as math;
import 'dart:ui';

import 'ink_model.dart';

/// 손으로 그린 획을 알아보는 도형.
enum ShapeKind { line, circle, ellipse, triangle, rectangle, quadrilateral, arc }

String shapeName(ShapeKind k) => switch (k) {
      ShapeKind.line => '직선',
      ShapeKind.circle => '원',
      ShapeKind.ellipse => '타원',
      ShapeKind.triangle => '삼각형',
      ShapeKind.rectangle => '사각형',
      ShapeKind.quadrilateral => '사각형',
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

  // ── 다각형 (삼각형·사각형) ──
  // 어디서 그리기 시작했든(꼭짓점이든 변 한가운데든) 같은 도형이 나와야 한다.
  final tol = math.max(4.0, box.longestSide * 0.055);
  if (closed) {
    final cs = _polygonCorners(pts, tol: tol, perimeter: pathLen);
    if (cs != null && cs.length == 3) {
      return SnappedShape(ShapeKind.triangle, poly(_levelPolygon(_rightAngleTriangle(cs)), close: true));
    }
    if (cs != null && cs.length == 4) {
      final (quad, kind) = _tidyQuad(cs);
      return SnappedShape(kind, poly(quad, close: true));
    }
  }
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

  final corners = _corners(pts, tol: tol);
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

/// 닫힌 획에서 꼭짓점만 골라 낸다 (3개 또는 4개, 아니면 null).
///
/// 획의 시작점은 변 한가운데일 수도 있으므로, 시작점에서 가장 먼 점을 기준으로 획을
/// 둘로 나누어 각각 꼭짓점을 찾은 뒤, 일직선 위의 점·너무 짧은 변을 정리한다.
List<Offset>? _polygonCorners(List<InkPoint> pts, {required double tol, required double perimeter}) {
  final os = <Offset>[];
  for (final p in pts) {
    if (os.isEmpty || (p.offset - os.last).distance > 0.5) os.add(p.offset);
  }
  if (os.length < 6) return null;

  var far = 0;
  var best = 0.0;
  for (var i = 0; i < os.length; i++) {
    final d = (os[i] - os[0]).distance;
    if (d > best) {
      best = d;
      far = i;
    }
  }
  if (far == 0 || far == os.length - 1) return null;

  final keep = List<bool>.filled(os.length, false);
  keep[0] = true;
  keep[far] = true;
  keep[os.length - 1] = true;
  _rdpKeep(os, keep, 0, far, tol);
  _rdpKeep(os, keep, far, os.length - 1, tol);
  final v = [for (var i = 0; i < os.length; i++) if (keep[i]) os[i]];
  // 마지막 점은 첫 점과 같은 자리 (덧그린 끝도 여기서 정리된다)
  if (v.length > 3 && (v.last - v.first).distance < tol * 4) v.removeLast();

  // 1) 너무 짧은 변은 한 점으로 합친다
  final minEdge = math.max(tol * 2, perimeter * 0.04);
  var merged = true;
  while (merged && v.length > 3) {
    merged = false;
    for (var i = 0; i < v.length; i++) {
      final j = (i + 1) % v.length;
      if ((v[i] - v[j]).distance < minEdge) {
        final mid = (v[i] + v[j]) / 2;
        if (j == 0) {
          v[0] = mid;
          v.removeAt(i);
        } else {
          v[i] = mid;
          v.removeAt(j);
        }
        merged = true;
        break;
      }
    }
  }

  // 2) 거의 일직선 위에 있는 점(변 한가운데서 시작한 자리, 흔들린 자리)을 뺀다
  while (v.length > 3) {
    var wi = 0;
    var wd = double.infinity;
    for (var i = 0; i < v.length; i++) {
      final d = _lineDeviation(v, i);
      if (d < wd) {
        wd = d;
        wi = i;
      }
    }
    final limit = v.length > 4 ? tol * 3 : tol * 1.3;
    if (wd < limit) {
      v.removeAt(wi);
    } else {
      break;
    }
  }
  if (v.length < 3 || v.length > 4) return null;

  // 꼬인 사각형(나비넥타이)은 사각형이 아니다
  if (v.length == 4 && (_segmentsCross(v[0], v[1], v[2], v[3]) || _segmentsCross(v[1], v[2], v[3], v[0]))) {
    return null;
  }
  // 고른 꼭짓점을 이은 도형이 손으로 그린 획과 많이 다르면 도형으로 보지 않는다
  for (final p in os) {
    if (_distToPolygon(p, v) > tol * 2) return null;
  }
  return v;
}

void _rdpKeep(List<Offset> os, List<bool> keep, int i, int j, double tol) {
  if (j <= i + 1) return;
  var worst = 0.0;
  var idx = -1;
  final a = os[i], b = os[j];
  final d = b - a;
  final len = d.distance;
  for (var k = i + 1; k < j; k++) {
    final w = os[k] - a;
    final dist = len < 1e-6 ? w.distance : (w.dx * d.dy - w.dy * d.dx).abs() / len;
    if (dist > worst) {
      worst = dist;
      idx = k;
    }
  }
  if (worst > tol && idx > 0) {
    keep[idx] = true;
    _rdpKeep(os, keep, i, idx, tol);
    _rdpKeep(os, keep, idx, j, tol);
  }
}

/// 꼭짓점 [i] 가 이웃 두 꼭짓점을 잇는 직선에서 떨어진 거리.
double _lineDeviation(List<Offset> v, int i) {
  final n = v.length;
  final a = v[(i + n - 1) % n], b = v[(i + 1) % n], p = v[i];
  final d = b - a;
  final len = d.distance;
  final w = p - a;
  return len < 1e-6 ? w.distance : (w.dx * d.dy - w.dy * d.dx).abs() / len;
}

double _distToSegment(Offset p, Offset a, Offset b) {
  final d = b - a;
  final l2 = d.dx * d.dx + d.dy * d.dy;
  if (l2 < 1e-9) return (p - a).distance;
  final t = (((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / l2).clamp(0.0, 1.0);
  return (p - (a + d * t)).distance;
}

double _distToPolygon(Offset p, List<Offset> v) {
  var best = double.infinity;
  for (var i = 0; i < v.length; i++) {
    best = math.min(best, _distToSegment(p, v[i], v[(i + 1) % v.length]));
  }
  return best;
}

bool _segmentsCross(Offset a, Offset b, Offset c, Offset d) {
  double cross(Offset o, Offset p, Offset q) => (p.dx - o.dx) * (q.dy - o.dy) - (p.dy - o.dy) * (q.dx - o.dx);
  final d1 = cross(c, d, a), d2 = cross(c, d, b), d3 = cross(a, b, c), d4 = cross(a, b, d);
  return d1 * d2 < 0 && d3 * d4 < 0;
}

Offset _centroid(List<Offset> v) => v.fold<Offset>(Offset.zero, (a, b) => a + b) / v.length.toDouble();

/// 가장 긴 변이 수평·수직에서 6° 안쪽이면 도형 전체를 살짝 돌려 반듯하게 맞춘다.
List<Offset> _levelPolygon(List<Offset> v) {
  var k = 0;
  var longest = 0.0;
  for (var i = 0; i < v.length; i++) {
    final len = (v[(i + 1) % v.length] - v[i]).distance;
    if (len > longest) {
      longest = len;
      k = i;
    }
  }
  final e = v[(k + 1) % v.length] - v[k];
  final ang = math.atan2(e.dy, e.dx);
  final quarter = math.pi / 2;
  final r = ang - (ang / quarter).round() * quarter;
  if (r.abs() > 6 * math.pi / 180 || r == 0) return v;
  final c = _centroid(v);
  final cs = math.cos(-r), sn = math.sin(-r);
  return [
    for (final p in v)
      c + Offset((p.dx - c.dx) * cs - (p.dy - c.dy) * sn, (p.dx - c.dx) * sn + (p.dy - c.dy) * cs),
  ];
}

/// 한 각이 직각에서 7° 안쪽이면 정확한 직각으로 맞춘다 (직각삼각형).
List<Offset> _rightAngleTriangle(List<Offset> t) {
  for (var i = 0; i < 3; i++) {
    final p = t[i], a = t[(i + 2) % 3], b = t[(i + 1) % 3];
    final u = a - p, w = b - p;
    if (u.distance < 1e-6 || w.distance < 1e-6) continue;
    final ang = _wrap(math.atan2(w.dy, w.dx) - math.atan2(u.dy, u.dx)).abs();
    if ((ang - math.pi / 2).abs() > 7 * math.pi / 180) continue;
    final un = u / u.distance;
    var perp = Offset(-un.dy, un.dx);
    if (perp.dx * w.dx + perp.dy * w.dy < 0) perp = -perp;
    final out = [...t];
    out[(i + 1) % 3] = p + perp * w.distance;
    return out;
  }
  return t;
}

/// 꼭짓점 네 개를 정리한다: 네 각이 모두 직각에 가까우면 (기울어졌더라도) 반듯한 직사각형·정사각형,
/// 아니면 손으로 그린 꼭짓점을 그대로 두되 수평·수직에 가까우면 바로잡는다.
(List<Offset>, ShapeKind) _tidyQuad(List<Offset> cs) {
  var rectLike = true;
  for (var i = 0; i < 4; i++) {
    final a = cs[(i + 3) % 4], b = cs[i], c = cs[(i + 1) % 4];
    final v1 = a - b, v2 = c - b;
    final ang = _wrap(math.atan2(v2.dy, v2.dx) - math.atan2(v1.dy, v1.dx)).abs();
    if ((ang - math.pi / 2).abs() > 18 * math.pi / 180) rectLike = false;
  }
  if (!rectLike) return (_levelPolygon(cs), ShapeKind.quadrilateral);

  // 변 방향의 평균 (직각이라 90° 단위로 겹쳐 놓고 평균)
  var s = 0.0, c4 = 0.0;
  for (var i = 0; i < 4; i++) {
    final e = cs[(i + 1) % 4] - cs[i];
    final a = math.atan2(e.dy, e.dx), len = e.distance;
    s += math.sin(4 * a) * len;
    c4 += math.cos(4 * a) * len;
  }
  var theta = math.atan2(s, c4) / 4;
  final quarter = math.pi / 2;
  final off = theta - (theta / quarter).round() * quarter;
  if (off.abs() < 6 * math.pi / 180) theta -= off; // 거의 반듯하면 완전히 반듯하게

  final u = Offset(math.cos(theta), math.sin(theta));
  final w = Offset(-math.sin(theta), math.cos(theta));
  final pu = [for (final p in cs) p.dx * u.dx + p.dy * u.dy]..sort();
  final pv = [for (final p in cs) p.dx * w.dx + p.dy * w.dy]..sort();
  var uLo = (pu[0] + pu[1]) / 2, uHi = (pu[2] + pu[3]) / 2;
  var vLo = (pv[0] + pv[1]) / 2, vHi = (pv[2] + pv[3]) / 2;
  final width = uHi - uLo, height = vHi - vLo;
  if (width > 0 && height > 0 && (width - height).abs() <= math.max(width, height) * 0.08) {
    final side = (width + height) / 2; // 정사각형
    final cu = (uLo + uHi) / 2, cv = (vLo + vHi) / 2;
    uLo = cu - side / 2;
    uHi = cu + side / 2;
    vLo = cv - side / 2;
    vHi = cv + side / 2;
  }
  Offset at(double a, double b) => u * a + w * b;
  return ([at(uLo, vLo), at(uHi, vLo), at(uHi, vHi), at(uLo, vHi)], ShapeKind.rectangle);
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
