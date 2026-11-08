import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_app/ink/ink_controller.dart';
import 'package:study_app/ink/ink_model.dart';
import 'package:study_app/ink/shape_snap.dart';
import 'package:study_app/ink/stroke_renderer.dart';

List<ui.Offset> _circle(ui.Offset c, double r, {int n = 48}) =>
    [for (var i = 0; i <= n; i++) c + ui.Offset(math.cos(2 * math.pi * i / n) * r, math.sin(2 * math.pi * i / n) * r)];

/// 펜으로 [path] 를 4ms 간격으로 긋는다 (손을 떼지 않음).
void _draw(InkController c, List<ui.Offset> path, {int t0 = 1000}) {
  c.pointerDown(path.first, 0.5, timeMs: t0);
  for (var i = 1; i < path.length; i++) {
    c.pointerMove(path[i], 0.5, timeMs: t0 + i * 4);
  }
}

Future<ui.Image> _render(InkStroke s, {bool live = false, int w = 400, int h = 400}) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  StrokeRenderer.paint(canvas, s, live: live);
  return rec.endRecording().toImage(w, h);
}

Future<bool> _inked(ui.Image img, ui.Offset p) async {
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = ((p.dy.round() * img.width) + p.dx.round()) * 4;
  return data.getUint8(i) < 128; // 검은 펜
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('필기감', () {
    test('손을 떼면 글씨는 그대로 — 동그라미·직선도 저절로 도형이 되지 않는다', () {
      final c = InkController();
      _draw(c, _circle(const ui.Offset(300, 300), 90));
      c.pointerUp();
      expect(c.strokes.single.points.length, greaterThan(40), reason: '손으로 그린 점이 그대로');
      expect(c.lastSnap.value, isNull);

      _draw(c, [for (var i = 0; i <= 30; i++) ui.Offset(100 + i * 10.0, 600 + (i.isEven ? 1.5 : -1.5))]);
      c.pointerUp();
      expect(c.strokes.last.points.length, greaterThan(20), reason: '그은 선도 손글씨 그대로');
    });

    test('펜을 멈추고 있으면 그때 도형으로 맞춘다 (굿노트처럼)', () {
      fakeAsync((fa) {
        final c = InkController();
        _draw(c, _circle(const ui.Offset(300, 300), 90));
        fa.elapse(const Duration(milliseconds: 800));
        expect(c.active!.points.length, isNot(greaterThan(80)));
        c.pointerUp();
        expect(c.lastSnap.value, ShapeKind.circle);
        c.undoShapeSnap();
        expect(c.strokes.single.points.length, greaterThan(40), reason: '되돌리면 손으로 그린 모양');
        c.dispose();
      });
    });

    test('글씨 크기의 동그라미는 멈춰도 도형이 되지 않는다 (숫자 0, 영어 o)', () {
      fakeAsync((fa) {
        final c = InkController();
        _draw(c, _circle(const ui.Offset(300, 300), 18));
        fa.elapse(const Duration(milliseconds: 800));
        c.pointerUp();
        expect(c.lastSnap.value, isNull);
        expect(c.strokes.single.points.length, greaterThan(20));
        c.dispose();
      });
    });

    test('획 안의 시간은 펜 이벤트 시각을 쓴다 (한 프레임에 몰려 와도)', () {
      final c = InkController(settings: InkSettings(holdToStraighten: false));
      c.pointerDown(const ui.Offset(10, 10), 0.5, timeMs: 5000);
      c.pointerMove(const ui.Offset(20, 10), 0.5, timeMs: 5004);
      c.pointerMove(const ui.Offset(30, 10), 0.5, timeMs: 5008);
      expect([for (final p in c.active!.points) p.t], [0, 4, 8]);
      c.pointerUp();
    });

    test('끝 예측: 펜이 움직이면 앞을 조금 그리고, 멈추면 지운다', () {
      fakeAsync((fa) {
        final c = InkController(settings: InkSettings(holdToStraighten: false));
        c.pointerDown(const ui.Offset(100, 100), 0.5, timeMs: 0);
        for (var i = 1; i <= 10; i++) {
          c.pointerMove(ui.Offset(100 + i * 4.0, 100), 0.5, timeMs: i * 4);
        }
        final p = c.predicted;
        expect(p, isNotNull);
        expect(p!.dx, greaterThan(140), reason: '가던 방향으로');
        expect(p.dx - 140, lessThanOrEqualTo(16.01), reason: '너무 멀리 내다보지 않는다');
        fa.elapse(const Duration(milliseconds: 60));
        expect(c.predicted, isNull, reason: '새 점이 안 오면 꼬리를 지운다');
        c.pointerUp();
        c.dispose();
      });
    });

    test('획 모양: 꺾이는 곳·이음새에 구멍이 없고, 그리는 중과 다 그린 뒤가 같다', () async {
      final pts = <InkPoint>[];
      final zig = [const ui.Offset(40, 40), const ui.Offset(200, 60), const ui.Offset(60, 160), const ui.Offset(330, 200)];
      var t = 0;
      for (var k = 0; k < zig.length - 1; k++) {
        for (var j = 0; j < 12; j++) {
          final o = ui.Offset.lerp(zig[k], zig[k + 1], j / 12)!;
          pts.add(InkPoint(o.dx, o.dy, 0.3 + 0.5 * ((k * 12 + j) % 7) / 7, t += 4));
        }
      }
      pts.add(InkPoint(zig.last.dx, zig.last.dy, 0.5, t + 4));
      final s = InkStroke(id: 'a', tool: InkTool.pen, color: 0xFF000000, width: 6, startedAt: 0, points: pts);
      final done = await _render(s);
      // 라이브: 점을 하나씩 더하며 그린 결과
      final grow = InkStroke(id: 'b', tool: InkTool.pen, color: 0xFF000000, width: 6, startedAt: 0, points: []);
      ui.Image? live;
      for (final p in pts) {
        grow.points.add(p);
        live = await _render(grow, live: true);
      }
      for (final p in pts) {
        expect(await _inked(done, p.offset), isTrue, reason: '점 ${p.offset} 이 칠해져 있어야 한다');
        expect(await _inked(live!, p.offset), isTrue, reason: '그리는 중에도 ${p.offset}');
      }
      expect(await _inked(done, const ui.Offset(380, 380)), isFalse);
      final a = (await done.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final b = (await live!.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var diff = 0;
      for (var i = 0; i < a.lengthInBytes; i += 4) {
        if ((a.getUint8(i) < 128) != (b.getUint8(i) < 128)) diff++;
      }
      expect(diff, lessThan(40), reason: '손을 떼는 순간 모양이 바뀌어 보이지 않게');
    });
  });
}
