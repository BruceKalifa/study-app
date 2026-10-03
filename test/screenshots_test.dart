// Renders every main screen to PNG (real fonts) so the design can be reviewed from CI.
// Runs only when SHOTS=1; output goes to ci-out/shots/.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_app/app/app_state.dart';
import 'package:study_app/app/records.dart';
import 'package:study_app/app/storage.dart';
import 'package:study_app/app/theme.dart';
import 'package:study_app/core/problem.dart';
import 'package:study_app/core/problem_bank.dart';
import 'package:study_app/core/variants.dart';
import 'package:study_app/ink/ink_model.dart';
import 'package:study_app/screens/history_screen.dart';
import 'package:study_app/screens/home_shell.dart';
import 'package:study_app/screens/result_screen.dart';
import 'package:study_app/screens/solve_screen.dart';
import 'package:study_app/widgets/answer_panel.dart';

final bool _enabled = Platform.environment['SHOTS'] == '1';
final GlobalKey _boundary = GlobalKey();

Future<void> _loadFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final f in manifest) {
    final family = (f as Map)['family'] as String;
    final loader = FontLoader(family);
    for (final font in f['fonts'] as List) {
      loader.addFont(rootBundle.load((font as Map)['asset'] as String));
    }
    await loader.load();
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.runAsync(() async {
    final ro = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await ro.toImage(pixelRatio: 1.0);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('ci-out/shots')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget _wrap(AppState s, Widget home) => RepaintBoundary(
      key: _boundary,
      child: AppScope(
        state: s,
        child: MaterialApp(key: UniqueKey(), debugShowCheckedModeBanner: false, theme: AppTheme.light(), home: home),
      ),
    );

Future<AppState> _seeded() async {
  final bank = await ProblemBank.load(rootBundle);
  final s = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false);
  await s.init();
  await s.renameProfile('선주');
  final rnd = math.Random(4);
  final now = DateTime.now().millisecondsSinceEpoch;
  final all = bank.all;
  final list = <Attempt>[];
  var n = 0;
  for (var day = 34; day >= 0; day--) {
    if (rnd.nextDouble() < 0.25 && day > 0) continue;
    final count = day == 0 ? 6 : 2 + rnd.nextInt(9);
    for (var k = 0; k < count; k++) {
      final p = all[rnd.nextInt(all.length)];
      final ok = rnd.nextDouble() < (0.45 + p.subjectId.length * 0.04 + (5 - p.difficulty) * 0.06);
      list.add(Attempt(
        id: 'a${n++}',
        problemId: p.id,
        baseId: p.id,
        subjectId: p.subjectId,
        unit: p.unit,
        topic: p.topic,
        answer: ok ? p.answer : (p.isChoice ? '${(int.parse(p.answer) % 5) + 1}' : '7'),
        expected: expectedDisplay(p),
        correct: ok,
        timeMs: 30000 + rnd.nextInt(240000),
        at: now - day * Duration.millisecondsPerDay - rnd.nextInt(6 * 3600000),
        mode: 'practice',
        hasInk: false,
      ));
    }
  }
  s.seedAttempts(list);
  return s;
}

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(2960, 1848);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Future<void> _write(WidgetTester tester, Offset origin, List<Offset> path, {int buttons = kPrimaryButton}) async {
  final g = await tester.startGesture(origin + path.first, kind: PointerDeviceKind.stylus, buttons: buttons);
  for (final p in path.skip(1)) {
    await g.moveTo(origin + p);
  }
  await g.up();
}

List<Offset> _parabola() => [for (var x = -60.0; x <= 60; x += 3) Offset(x * 2.2, x * x / 30)];
List<Offset> _axisX() => [for (var x = 0.0; x <= 300; x += 10) Offset(x, 0)];
List<Offset> _axisY() => [for (var y = 0.0; y <= 200; y += 10) Offset(0, -y)];
List<Offset> _wave() => [for (var x = 0.0; x <= 260; x += 4) Offset(x, 18 * math.sin(x / 14))];
List<Offset> _circle(double r) =>
    [for (var a = 0.0; a <= math.pi * 2.05; a += 0.15) Offset(r * math.cos(a), r * math.sin(a))];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screenshots', (tester) async {
    if (!_enabled) return;
    _size(tester);
    await tester.runAsync(_loadFonts);
    final app = (await tester.runAsync(_seeded))!;

    // 1. dashboard
    await tester.pumpWidget(_wrap(app, const HomeShell()));
    await _shot(tester, '01_dashboard');

    // 2..7 tabs
    const tabs = ['문제집', '오답노트', '통계', '기록', '연습장', '내 문제', '설정'];
    for (var i = 0; i < tabs.length; i++) {
      await tester.tap(find.text(tabs[i]).last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      if (tabs[i] == '연습장') {
        final c = tester.getCenter(find.byType(HomeShell));
        await _write(tester, c + const Offset(-200, 50), _axisX());
        await _write(tester, c + const Offset(-200, 50), _axisY());
        await _write(tester, c + const Offset(-50, -60), _parabola());
        await _write(tester, c + const Offset(150, 140), _wave());
      }
      await _shot(tester, '0${i + 2}_${['library', 'wrongnote', 'stats', 'history', 'scratch', 'editor', 'settings'][i]}');
    }

    // 9. solve — choice problem with 보기, handwriting on the page
    final choice = app.bank.all.firstWhere((p) => p.isChoice && p.boxItems.isNotEmpty && p.subjectId == 'phy1');
    final calc = app.bank.all.firstWhere((p) => p.hasTemplate && p.isChoice && p.subjectId == 'phy1');
    final short = app.bank.all.firstWhere((p) => !p.isChoice && p.subjectId == 'math' && p.stem.contains(r'$'));
    await tester.pumpWidget(_wrap(
        app,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => SolveScreen.open(context,
                    title: '물리학Ⅰ · 역학과 에너지', problems: [calc, choice, short, generateVariant(calc, 5)]),
                child: const Text('go'),
              ),
            ),
          ),
        )));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));
    debugPrint('SolveScreen found: ${find.byType(SolveScreen).evaluate().length}; '
        'exception: ${tester.takeException()}');
    final c = tester.getCenter(find.byType(SolveScreen));
    await _write(tester, c + const Offset(-380, 160), _axisX());
    await _write(tester, c + const Offset(-380, 160), _axisY());
    await _write(tester, c + const Offset(-200, 60), _parabola());
    await _write(tester, c + const Offset(60, 200), _circle(30));
    await _shot(tester, '09_solve_calc');

    await tester.tap(find.byKey(Key('choice-${(int.parse(calc.answer) % 5) + 1}')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit')));
    await _shot(tester, '10_solve_wrong');

    await tester.tap(find.byKey(const Key('next')));
    await tester.pump(const Duration(milliseconds: 600));
    await _write(tester, c + const Offset(-300, 120), _wave());
    await tester.tap(find.byKey(Key('choice-${choice.answer}')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit')));
    await _shot(tester, '11_solve_correct');

    await tester.tap(find.byKey(const Key('next')));
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '12_solve_short_pad');
    await tester.tap(find.byKey(const Key('mode-keypad')));
    await tester.pump(const Duration(milliseconds: 300));
    for (final k in short.answer.split('')) {
      final key = find.byKey(Key('key-$k'));
      if (key.evaluate().isNotEmpty) await tester.tap(key);
    }
    await _shot(tester, '13_solve_short_keypad');

    // 14. results
    await tester.pumpWidget(_wrap(
        app,
        ResultScreen(title: '물리학Ⅰ · 역학과 에너지', mode: 'practice', items: [
          SessionItem(problem: calc, graded: GradedAnswer('2', false, expectedDisplay(calc)), timeMs: 84000),
          SessionItem(problem: choice, graded: GradedAnswer(choice.answer, true, expectedDisplay(choice)), timeMs: 62000),
          SessionItem(problem: short, graded: GradedAnswer(short.answer, true, expectedDisplay(short)), timeMs: 120000),
          SessionItem(problem: generateVariant(calc, 5), graded: null, timeMs: 0),
        ])));
    await _shot(tester, '14_results');

    // 15. history detail with replay
    final ink = InkDocument(strokes: [
      for (final (i, path) in [_axisX(), _axisY(), _parabola(), _wave()].indexed)
        InkStroke(
          id: 's$i',
          tool: InkTool.pen,
          color: 0xFF1B2A4A,
          width: 3.2,
          startedAt: 1000 * i,
          points: [
            for (final (j, p) in path.indexed) InkPoint(300 + p.dx, 400 + p.dy + i * 40, 0.4 + 0.4 * math.sin(j / 5).abs(), j * 16)
          ],
        ),
    ]);
    final att = app.attempts.last;
    await app.writeProfileFile('ink/${att.id}.json', jsonEncode(ink.toJson()));
    final withInk = Attempt.fromJson({...att.toJson(), 'ink': true});
    await tester.pumpWidget(_wrap(app, AttemptDetailScreen(attempt: withInk)));
    await tester.pump(const Duration(seconds: 3));
    await _shot(tester, '15_history_replay');
  });
}
