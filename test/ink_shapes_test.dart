import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_app/ink/function_plot.dart';
import 'package:study_app/ink/ink_model.dart';
import 'package:study_app/ink/ink_controller.dart';
import 'package:study_app/ink/shape_snap.dart';

/// 손으로 그린 것처럼 흔들리는 획을 만든다.
List<InkPoint> _stroke(List<Offset> path, {double jitter = 0, int seed = 1}) {
  final r = math.Random(seed);
  return [
    for (var i = 0; i < path.length; i++)
      InkPoint(path[i].dx + (r.nextDouble() - 0.5) * jitter, path[i].dy + (r.nextDouble() - 0.5) * jitter, 0.5, i * 8),
  ];
}

List<Offset> _circlePath(Offset c, double r, {int n = 40, double from = 0, double sweep = 2 * math.pi}) =>
    [for (var i = 0; i <= n; i++) c + Offset(math.cos(from + sweep * i / n) * r, math.sin(from + sweep * i / n) * r)];

List<Offset> _linePath(Offset a, Offset b, {int n = 20}) =>
    [for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];

List<Offset> _polyPath(List<Offset> corners, {int per = 12}) {
  final out = <Offset>[];
  for (var i = 0; i < corners.length; i++) {
    final a = corners[i], b = corners[(i + 1) % corners.length];
    for (var k = 0; k < per; k++) {
      out.add(Offset.lerp(a, b, k / per)!);
    }
  }
  out.add(corners.first);
  return out;
}

double _dist(Offset a, Offset b) => (a - b).distance;

void main() {
  group('도형 자동 맞추기', () {
    test('비뚤게 그은 선은 직선이 된다', () {
      final s = snapShape(_stroke(_linePath(const Offset(100, 100), const Offset(300, 160)), jitter: 3));
      expect(s, isNotNull);
      expect(s!.kind, ShapeKind.line);
      expect(s.points, hasLength(2));
      expect(_dist(s.points.first.offset, const Offset(100, 100)), lessThan(6));
    });

    test('거의 수평이면 완전한 수평으로 맞춘다', () {
      final s = snapShape(_stroke(_linePath(const Offset(100, 200), const Offset(400, 205)), jitter: 2));
      expect(s!.kind, ShapeKind.line);
      expect((s.points.first.y - s.points.last.y).abs(), lessThan(0.5));
    });

    test('동그라미는 원이 된다', () {
      final s = snapShape(_stroke(_circlePath(const Offset(200, 200), 80), jitter: 6));
      expect(s, isNotNull);
      expect(s!.kind, ShapeKind.circle);
      // 모든 점이 중심에서 같은 거리
      final c = const Offset(200, 200);
      final rs = [for (final p in s.points) _dist(p.offset, c)];
      expect(rs.reduce(math.max) - rs.reduce(math.min), lessThan(6));
    });

    test('납작한 동그라미는 타원이 된다', () {
      final path = [
        for (var i = 0; i <= 40; i++)
          Offset(200 + math.cos(i / 40 * 2 * math.pi) * 110, 200 + math.sin(i / 40 * 2 * math.pi) * 45)
      ];
      final s = snapShape(_stroke(path, jitter: 4));
      expect(s, isNotNull);
      expect(s!.kind, ShapeKind.ellipse);
    });

    test('세모는 삼각형이 된다', () {
      final s = snapShape(_stroke(_polyPath(const [Offset(100, 240), Offset(220, 60), Offset(330, 240)]), jitter: 4));
      expect(s, isNotNull);
      expect(s!.kind, ShapeKind.triangle);
      expect(s.points, hasLength(4), reason: '닫힌 삼각형 (마지막 점 = 첫 점)');
      expect(s.points.first.offset, s.points.last.offset);
    });

    test('네모는 반듯한 직사각형이 된다', () {
      final s = snapShape(
          _stroke(_polyPath(const [Offset(100, 100), Offset(320, 104), Offset(316, 240), Offset(98, 236)]), jitter: 3));
      expect(s, isNotNull);
      expect(s!.kind, ShapeKind.rectangle);
      final xs = [for (final p in s.points) p.x], ys = [for (final p in s.points) p.y];
      expect(xs.toSet(), hasLength(2), reason: '세로변이 수직');
      expect(ys.toSet(), hasLength(2), reason: '가로변이 수평');
    });

    // 닫힌 획을 [f] 지점(0~1)에서 시작해 그린 것처럼 돌린다. [over] 는 끝을 덧그린 점 수.
    List<Offset> startAt(List<Offset> closedPath, double f, {int over = 0}) {
      final body = closedPath.sublist(0, closedPath.length - 1);
      final s = (body.length * f).floor();
      return [
        ...body.sublist(s),
        ...body.sublist(0, s),
        body[s],
        for (var k = 1; k <= over; k++) body[(s + k) % body.length],
      ];
    }

    bool hasNear(List<InkPoint> pts, Offset o, double r) => pts.any((p) => _dist(p.offset, o) < r);

    test('삼각형은 어디서 그리기 시작해도 삼각형이다', () {
      const tri = [Offset(100, 240), Offset(220, 60), Offset(330, 240)];
      for (final f in [0.0, 0.1, 0.37, 0.6, 0.85]) {
        final s = snapShape(_stroke(startAt(_polyPath(tri), f, over: 3), jitter: 4));
        expect(s, isNotNull, reason: 'f=$f');
        expect(s!.kind, ShapeKind.triangle, reason: 'f=$f');
        expect(s.points, hasLength(4), reason: 'f=$f');
        for (final c in tri) {
          expect(hasNear(s.points, c, 14), isTrue, reason: 'f=$f 꼭짓점 $c');
        }
      }
    });

    test('네모는 어디서 그리기 시작해도 사각형이다 (삼각형이 되지 않는다)', () {
      const sq = [Offset(100, 100), Offset(300, 100), Offset(300, 300), Offset(100, 300)];
      for (final f in [0.0, 0.13, 0.4, 0.7]) {
        final s = snapShape(_stroke(startAt(_polyPath(sq), f, over: 3), jitter: 4));
        expect(s, isNotNull, reason: 'f=$f');
        expect(s!.kind, ShapeKind.rectangle, reason: 'f=$f');
        for (final c in sq) {
          expect(hasNear(s.points, c, 14), isTrue, reason: 'f=$f 꼭짓점 $c');
        }
      }
    });

    test('비슷한 길이의 네모는 정사각형이 된다', () {
      final s = snapShape(_stroke(_polyPath(const [Offset(100, 100), Offset(310, 104), Offset(306, 304), Offset(96, 300)]), jitter: 3));
      expect(s!.kind, ShapeKind.rectangle);
      final w = (s.points[1].offset - s.points[0].offset).distance;
      final h = (s.points[2].offset - s.points[1].offset).distance;
      expect((w - h).abs(), lessThan(0.01));
    });

    test('기울어진 네모는 기울어진 채로 반듯한 직사각형이 된다', () {
      const tilted = [Offset(120, 100), Offset(300, 160), Offset(260, 280), Offset(80, 220)];
      final s = snapShape(_stroke(startAt(_polyPath(tilted), 0.2), jitter: 3));
      expect(s, isNotNull);
      expect(s!.kind, ShapeKind.rectangle);
      final e0 = s.points[1].offset - s.points[0].offset;
      final e1 = s.points[2].offset - s.points[1].offset;
      expect((e0.dx * e1.dx + e0.dy * e1.dy).abs(), lessThan(1.0), reason: '이웃한 변이 수직');
      expect(e0.dy.abs() > 5 || e0.dx.abs() < 5, isTrue, reason: '수평으로 눕히지 않는다');
      for (final c in tilted) {
        expect(hasNear(s.points, c, 16), isTrue, reason: '꼭짓점 $c');
      }
    });

    test('평행사변형·사다리꼴은 손으로 그린 꼭짓점을 따라 사각형이 된다', () {
      for (final quad in const [
        [Offset(100, 250), Offset(330, 250), Offset(400, 100), Offset(170, 100)],
        [Offset(100, 250), Offset(330, 250), Offset(280, 100), Offset(150, 100)],
      ]) {
        final s = snapShape(_stroke(startAt(_polyPath(quad), 0.3), jitter: 3));
        expect(s, isNotNull);
        expect(s!.kind, ShapeKind.quadrilateral);
        expect(s.points, hasLength(5));
        for (final c in quad) {
          expect(hasNear(s.points, c, 18), isTrue, reason: '꼭짓점 $c');
        }
      }
    });

    test('직각삼각형은 직각으로 맞춘다', () {
      final s = snapShape(_stroke(_polyPath(const [Offset(100, 100), Offset(100, 300), Offset(330, 306)]), jitter: 2));
      expect(s!.kind, ShapeKind.triangle);
      // 직각 꼭짓점 찾기: 이웃한 두 변의 내적이 0
      var found = false;
      for (var i = 0; i < 3; i++) {
        final p = s.points[i].offset;
        final a = s.points[(i + 2) % 3].offset - p, b = s.points[(i + 1) % 3].offset - p;
        if ((a.dx * b.dx + a.dy * b.dy).abs() < 1.0) found = true;
      }
      expect(found, isTrue);
    });

    test('반원은 호가 된다', () {
      final s = snapShape(_stroke(_circlePath(const Offset(200, 200), 90, sweep: math.pi), jitter: 4));
      expect(s, isNotNull);
      expect(s!.kind, ShapeKind.arc);
    });

    test('글씨처럼 작거나 복잡한 획은 그대로 둔다', () {
      expect(snapShape(_stroke(_linePath(const Offset(10, 10), const Offset(22, 16)))), isNull, reason: '너무 작음');
      final scribble = <Offset>[];
      for (var i = 0; i < 60; i++) {
        scribble.add(Offset(100 + i * 3.0, 150 + math.sin(i / 2) * 40 + (i % 7) * 5));
      }
      expect(snapShape(_stroke(scribble)), isNull, reason: '지그재그는 도형이 아님');
    });

    test('도형 이름', () {
      expect(shapeName(ShapeKind.circle), '원');
      expect(shapeName(ShapeKind.rectangle), '사각형');
    });
  });

  group('함수 식 읽기', () {
    double at(String src, double x) => Expr.parse(stripFunctionPrefix(src))(x);

    test('사칙연산과 거듭제곱', () {
      expect(at('y = x^2 - 2x', 3), 3.0);
      expect(at('2x + 1', 2), 5.0);
      expect(at('(x+1)(x-1)', 3), 8.0);
      expect(at('x^3', 2), 8.0);
      expect(at('-x^2', 3), -9.0);
      expect(at('1/x', 4), 0.25);
      expect(at('2^3^2', 0), 512.0, reason: '거듭제곱은 오른쪽부터');
    });

    test('함수와 상수', () {
      expect(at('sin x', 0), 0.0);
      expect(at('cos(0)', 0), 1.0);
      expect(at('sqrt x', 9), 3.0);
      expect(at('abs x', -4), 4.0);
      expect(at('ln e', 0), closeTo(1, 1e-12));
      expect(at('log 100', 0), closeTo(2, 1e-12));
      expect(at('f(x) = 2 sin x', math.pi / 2), closeTo(2, 1e-12));
      expect(at('pi', 0), closeTo(math.pi, 1e-12));
    });

    test('기호도 읽는다 (×, ÷, π, √, 유니코드 빼기)', () {
      expect(at('2 × x', 3), 6.0);
      expect(at('x ÷ 2', 8), 4.0);
      expect(at('√x', 16), 4.0);
      expect(at('x − 1', 5), 4.0);
    });

    test('이상한 식은 읽지 않는다', () {
      expect(Expr.tryParse(''), isNull);
      expect(Expr.tryParse('x +'), isNull);
      expect(Expr.tryParse('(x'), isNull);
      expect(Expr.tryParse('zzz(x)'), isNull);
    });

    test('머리말을 떼어 낸다', () {
      expect(stripFunctionPrefix('y = x + 1'), 'x + 1');
      expect(stripFunctionPrefix('f(x)=x'), 'x');
      expect(stripFunctionPrefix('x + 1'), 'x + 1');
    });
  });

  group('함수 그리기', () {
    const frame = PlotFrame(origin: Offset(500, 300), scaleX: 40, scaleY: 40);
    final clip = const Rect.fromLTRB(100, 150, 900, 450);

    test('포물선은 한 획으로 그려진다', () {
      final out = plotFunction(Expr.parse('x^2'), frame: frame, clip: clip, color: 0xFF000000, width: 3);
      expect(out, hasLength(1));
      expect(out.first.points.length, greaterThan(50));
      // 꼭짓점이 원점 근처
      final lowest = out.first.points.reduce((a, b) => a.y > b.y ? a : b);
      expect(lowest.x, closeTo(500, 12));
    });

    test('1/x 는 점근선에서 끊어져 두 획이 된다', () {
      final out = plotFunction(Expr.parse('1/x'), frame: frame, clip: clip, color: 0xFF000000, width: 3);
      expect(out.length, greaterThanOrEqualTo(2));
    });

    test('정의되지 않는 곳은 건너뛴다', () {
      final out = plotFunction(Expr.parse('sqrt x'), frame: frame, clip: clip, color: 0xFF000000, width: 3);
      expect(out, isNotEmpty);
      for (final s in out) {
        for (final p in s.points) {
          expect(p.x, greaterThan(frame.origin.dx - 2), reason: 'x < 0 은 그리지 않는다');
        }
      }
    });

    test('좌표축과 눈금', () {
      final out = plotAxes(frame: frame, clip: clip, color: 0xFF999999, width: 1.5, step: 1);
      expect(out.length, greaterThan(4));
      expect(out.first.points, hasLength(2));
    });
  });

  group('자리 고르기', () {
    test('한 번 누른 자리를 가운데로 놓는다', () {
      final c = InkController(settings: InkSettings());
      Rect? picked;
      c.startPlacing(PlaceRequest(
          hint: '자리', defaultSize: const Size(400, 300), onPick: (r) => picked = r));
      expect(c.placing.value, isNotNull);
      c.finishPlacing(const Offset(500, 600));
      expect(picked!.width, 400);
      expect(picked!.height, 300);
      expect(picked!.center, const Offset(500, 600));
      expect(c.placing.value, isNull, reason: '한 번 누르면 끝난다');
      c.dispose();
    });

    test('종이 밖으로 나가지 않게 안으로 밀어 넣는다', () {
      final c = InkController(settings: InkSettings());
      final r = PlaceRequest(hint: '자리', defaultSize: const Size(400, 300), onPick: (_) {});
      // 왼쪽 위 끝을 눌러도 네모가 종이 안에 들어온다
      final topLeft = c.placeRectAt(const Offset(4, 4), r);
      expect(topLeft.left, greaterThanOrEqualTo(0));
      expect(topLeft.top, greaterThanOrEqualTo(0));
      expect(topLeft.width, 400);
      // 오른쪽 끝도
      final right = c.placeRectAt(const Offset(kPageWidth + 50, 500), r);
      expect(right.right, lessThanOrEqualTo(kPageWidth));
      expect(right.width, 400);
      c.dispose();
    });

    test('취소하면 아무 일도 없다', () {
      final c = InkController(settings: InkSettings());
      var called = false;
      c.startPlacing(PlaceRequest(
          hint: '자리', defaultSize: const Size(400, 300), onPick: (_) => called = true));
      c.cancelPlacing();
      expect(c.placing.value, isNull);
      expect(called, isFalse);
      c.dispose();
    });

    test('만든 획을 그대로 넣는다', () {
      final c = InkController(settings: InkSettings());
      final before = c.strokes.length;
      final strokes = plotFunction(Expr.parse('x'),
          frame: const PlotFrame(origin: Offset(500, 300), scaleX: 40, scaleY: 40),
          clip: const Rect.fromLTRB(100, 150, 900, 450),
          color: 0xFF000000,
          width: 3);
      c.addStrokes(strokes);
      expect(c.strokes.length, before + strokes.length);
      expect(c.canUndo, isTrue, reason: '한 번에 되돌릴 수 있다');
      c.dispose();
    });
  });
}
