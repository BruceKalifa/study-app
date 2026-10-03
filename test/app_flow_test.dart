import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_app/app/app_state.dart';
import 'package:study_app/app/storage.dart';
import 'package:study_app/app/theme.dart';
import 'package:study_app/core/problem.dart';
import 'package:study_app/core/problem_bank.dart';
import 'package:study_app/core/variants.dart';
import 'package:study_app/screens/home_shell.dart';
import 'package:study_app/screens/solve_screen.dart';
import 'package:study_app/widgets/math_text.dart';

Future<AppState> _state() async {
  final bank = await ProblemBank.load(rootBundle);
  final s = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false);
  await s.init();
  return s;
}

Widget _app(AppState s, {Widget? home}) => AppScope(
      state: s,
      child: MaterialApp(theme: AppTheme.light(), home: home ?? const HomeShell()),
    );

void _tabletSize(WidgetTester tester) {
  // Galaxy Tab S9 Ultra landscape (2960x1848 px) at ~2x
  tester.view.physicalSize = const Size(2960, 1848);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('problem bank loads every subject from assets', () async {
    final bank = await ProblemBank.load(rootBundle);
    expect(bank.subjects.length, greaterThanOrEqualTo(5));
    expect(bank.all.length, greaterThan(100));
    // every template generates
    for (final p in bank.all.where((p) => p.hasTemplate)) {
      final v = generateVariant(p, 7);
      expect(v.answer, isNotEmpty, reason: p.id);
      if (p.isChoice) expect(v.choices.length, 5, reason: p.id);
    }
  });

  testWidgets('every LaTeX snippet in the bank renders with flutter_math', (tester) async {
    final bank = (await tester.runAsync(() => ProblemBank.load(rootBundle)))!;
    final failures = <String>[];
    final snippets = <(String, String)>[];
    void collect(String id, String s) {
      for (final (isMath, t) in MathText.split(s)) {
        if (isMath) snippets.add((id, t));
      }
    }

    for (final p in bank.all) {
      collect(p.id, p.stem);
      collect(p.id, p.solution);
      if (p.hint != null) collect(p.id, p.hint!);
      for (final c in p.choices) {
        collect(p.id, c);
      }
      for (final b in p.boxItems) {
        collect(p.id, b);
      }
      if (p.hasTemplate) {
        final v = generateVariant(p, 3);
        collect('${p.id}~v', v.stem);
        collect('${p.id}~v', v.solution);
        for (final c in v.choices) {
          collect('${p.id}~v', c);
        }
      }
    }
    for (var i = 0; i < snippets.length; i += 40) {
      final chunk = snippets.sublist(i, i + 40 > snippets.length ? snippets.length : i + 40);
      await tester.pumpWidget(MaterialApp(
        home: SingleChildScrollView(
          child: Column(children: [
            for (final (id, tex) in chunk)
              Math.tex(tex, onErrorFallback: (e) {
                failures.add('$id: $tex → ${e.message}');
                return const SizedBox();
              }),
          ]),
        ),
      ));
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  testWidgets('home renders and every tab opens', (tester) async {
    _tabletSize(tester);
    final s = await tester.runAsync(_state);
    await tester.pumpWidget(_app(s!));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('오늘의 학습'), findsOneWidget);
    for (final tab in ['문제집', '오답노트', '통계', '기록', '연습장', '내 문제', '설정', '홈']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: 'tab $tab');
    }
  });

  testWidgets('solve: write with stylus, answer choice + short, grade, record, results', (tester) async {
    _tabletSize(tester);
    final s = await tester.runAsync(_state);
    final app = s!;
    final choice = app.bank.all.firstWhere((p) => p.isChoice && p.boxItems.isEmpty);
    final short = app.bank.all.firstWhere((p) => !p.isChoice && RegExp(r'^-?\d+(\.\d+)?$').hasMatch(p.answer));

    await tester.pumpWidget(_app(app,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => SolveScreen.open(context, title: '테스트', problems: [choice, short]),
                child: const Text('go'),
              ),
            ),
          ),
        )));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // write on the canvas with the S Pen
    final canvasCenter = tester.getCenter(find.byType(SolveScreen)) - const Offset(200, -100);
    final g = await tester.startGesture(canvasCenter, kind: PointerDeviceKind.stylus);
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(6, 3));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    // S Pen button held → eraser
    final e = await tester.startGesture(canvasCenter + const Offset(0, 260),
        kind: PointerDeviceKind.stylus, buttons: kPrimaryButton | kSecondaryStylusButton);
    await e.moveBy(const Offset(4, 4));
    await e.up();
    // fingers: pan + two-finger tap undo
    final f1 = await tester.startGesture(canvasCenter, kind: PointerDeviceKind.touch);
    await f1.moveBy(const Offset(0, -40));
    await f1.up();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);

    // answer the choice problem correctly
    await tester.tap(find.byKey(Key('choice-${choice.answer}')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('정답이에요!'), findsOneWidget);
    expect(app.attempts.length, 1);
    expect(app.attempts.first.correct, isTrue);

    await tester.tap(find.byKey(const Key('next')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // short answer via keypad — deliberately wrong first
    await tester.tap(find.byKey(const Key('mode-keypad')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('key-9')));
    await tester.tap(find.byKey(const Key('key-9')));
    await tester.tap(find.byKey(const Key('key-9')));
    await tester.tap(find.byKey(const Key('key-9')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    final wrong = short.answer == '9999';
    expect(find.text(wrong ? '정답이에요!' : '아쉬워요, 오답이에요'), findsOneWidget);
    expect(app.attempts.length, 2);
    expect(app.wrongNote.length, wrong ? 0 : 1);
    expect(app.stateOf(short.id).inWrongNote, !wrong);

    await tester.tap(find.byKey(const Key('next')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('결과'), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(app.todayCount, 2);
    expect(app.attempts.first.hasInk, isTrue);
  });

  testWidgets('variant problems render and grade', (tester) async {
    _tabletSize(tester);
    final s = await tester.runAsync(_state);
    final app = s!;
    final base = app.bank.all.firstWhere((p) => p.hasTemplate && p.isChoice);
    final v = generateVariant(base, 11);
    expect(v.isVariant, isTrue);
    await tester.pumpWidget(_app(app,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => SolveScreen.open(context, title: '변형', problems: [v]),
                child: const Text('go'),
              ),
            ),
          ),
        )));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(Key('choice-${v.answer}')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(app.attempts.single.correct, isTrue);
    expect(app.attempts.single.baseId, base.id);
    expect(tester.takeException(), isNull);
  });

  test('wrong answers schedule spaced review and graduate after 3 correct reviews', () async {
    final app = AppState(storage: MemoryStorage(), baseBank: ProblemBank(const <Subject>[]), enableLive: false);
    await app.init();
    const p = Problem(id: 'x1', subjectId: 'math', subjectName: '수학', stem: '1+1?', answer: '2');
    await app.record(p, answer: '3', expected: '2', correct: false, timeMs: 1000, mode: 'practice');
    expect(app.stateOf('x1').inWrongNote, isTrue);
    for (var i = 0; i < 3; i++) {
      await app.record(p, answer: '2', expected: '2', correct: true, timeMs: 1000, mode: 'review');
    }
    expect(app.stateOf('x1').inWrongNote, isFalse);
    expect(app.resolvedWrong.length, 1);
    expect(app.totalSolved, 4);
    expect(app.streak, 1);
  });
}
