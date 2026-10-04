import 'dart:convert';
import 'dart:io';

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
import 'package:study_app/widgets/answer_panel.dart';
import 'package:study_app/widgets/math_text.dart';
import 'package:study_app/services/community_api.dart';
import 'package:study_app/services/content_sync.dart';

Future<AppState> _state({bool onboard = true}) async {
  final bank = await ProblemBank.load(rootBundle);
  final s = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false);
  await s.init();
  if (onboard) s.completeOnboarding(name: '학생', grade: '고2', goal: '수능', courses: const [], workbooks: const []);
  return s;
}

class _RealHttp extends HttpOverrides {}

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

/// Palm rejection uses the wall clock: let real time pass after pen strokes before finger taps.
Future<void> _penRest(WidgetTester tester) =>
    tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));

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

    for (final sub in bank.subjects) {
      for (final ps in sub.passages) {
        collect(ps.id, ps.body);
      }
    }
    for (final p in [...bank.all, for (final sub in bank.subjects) ...sub.twins]) {
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
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Math.tex(tex, onErrorFallback: (e) {
                  failures.add('$id: $tex → ${e.message}');
                  return const SizedBox();
                }),
              ),
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
    expect(find.byKey(const Key('daily-start')), findsOneWidget);
    for (final tab in ['문제집', '오답노트', '학습관리', '커뮤니티', '통계', '기록', '연습장', '내 문제', '구독', '설정', '홈']) {
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

    // opens in full screen (no title bar); can be switched off and on again
    expect(find.text('테스트'), findsNothing);
    await tester.tap(find.byKey(const Key('fullscreen-toggle')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('테스트'), findsOneWidget);
    expect(app.settings.fullscreenSolve, isFalse);
    await tester.tap(find.byKey(const Key('fullscreen-toggle')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('테스트'), findsNothing);
    expect(app.settings.fullscreenSolve, isTrue);

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
    await _penRest(tester);

    // 객관식: a quick S Pen tap on a choice marks it (and draws no dot)
    final other = (int.parse(choice.answer) % choice.choices.length) + 1;
    final tapPen = await tester.startGesture(tester.getCenter(find.byKey(Key('choice-$other'))),
        kind: PointerDeviceKind.stylus);
    await tapPen.up();
    await tester.pump();
    expect(find.text('${other}번 선택'), findsOneWidget);
    await _penRest(tester);

    // a finger tap on the right choice changes the mark; then grade
    await tester.tap(find.byKey(Key('choice-${choice.answer}')));
    await tester.pump();
    expect(find.text('${choice.answer}번 선택'), findsOneWidget);
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('정답이에요!'), findsOneWidget);
    expect(app.attempts.length, 1);
    expect(app.attempts.first.correct, isTrue);

    await tester.tap(find.byKey(const Key('next')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // 단답형: no answer yet → cannot grade; fix the answer on the keypad — deliberately wrong
    expect(tester.widget<FilledButton>(find.byKey(const Key('submit'))).onPressed, isNull);
    // a finger tap on the 답 box under the problem opens the keypad
    await tester.tap(find.text('여기에 답을 쓰세요'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('keypad-ok')), findsOneWidget);
    await tester.tap(find.byKey(const Key('key-9')));
    await tester.tap(find.byKey(const Key('key-9')));
    await tester.tap(find.byKey(const Key('key-9')));
    await tester.tap(find.byKey(const Key('key-9')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('keypad-ok')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('recognized-answer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    final wrong = short.answer == '9999';
    expect(find.text(wrong ? '정답이에요!' : '오답 · 정답 ${expectedDisplay(short)}'), findsOneWidget);
    // 해설 sheet opens
    await tester.tap(find.byKey(const Key('solution')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('해설'), findsWidgets);
    await tester.tapAt(const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 600));
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
    await _penRest(tester);
    await tester.tap(find.byKey(Key('choice-${v.answer}')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(app.attempts.single.correct, isTrue);
    expect(app.attempts.single.baseId, base.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exam mode hides answers and grades everything at the end', (tester) async {
    _tabletSize(tester);
    final s = await tester.runAsync(_state);
    final app = s!;
    final ps = app.bank.all.where((p) => p.isChoice).take(3).toList();
    await tester.pumpWidget(_app(app,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () =>
                    SolveScreen.open(context, title: '시험', problems: ps, mode: 'exam', timeLimitMs: 600000),
                child: const Text('go'),
              ),
            ),
          ),
        )));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await _penRest(tester);
    for (var k = 0; k < ps.length; k++) {
      final p = ps[k];
      await tester.tap(find.byKey(Key('choice-${p.answer}')));
      await tester.pump();
      expect(find.text('정답이에요!'), findsNothing);
      if (k < ps.length - 1) {
        await tester.tap(find.byKey(const Key('next')));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(app.attempts, isEmpty);
    expect(find.text('시험 종료 3/3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('exam-finish')).last); // the page-switch animation may still hold the old bar
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('exam-finish-ok')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(app.attempts.length, 3);
    expect(app.attempts.every((a) => a.correct && a.mode == 'exam'), isTrue);
    expect(find.textContaining('결과'), findsWidgets);
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

  testWidgets('onboarding: name, grade, goal, courses, workbooks → home', (tester) async {
    _tabletSize(tester);
    final s = (await tester.runAsync(() => _state(onboard: false)))!;
    await tester.pumpWidget(_app(s));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('반가워요!'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('onb-name')), '예진');
    await tester.tap(find.byKey(const Key('grade-고3')));
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('onb-next')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byKey(const Key('course-phy2')), findsOneWidget);
    expect(find.byKey(const Key('course-integ')), findsNothing, reason: '통합과학 is 고1');
    expect(find.byKey(const Key('grade-중2')), findsNothing, reason: '고등 전용');
    await tester.tap(find.byKey(const Key('onb-next')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('wb-wb-phy2-deep')), findsOneWidget);
    await tester.tap(find.byKey(const Key('onb-start')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('daily-start')), findsOneWidget);
    expect(s.learner.grade, '고3');
    expect(s.learner.goal, '수능');
    expect(s.profile.name, '예진');
    expect(s.myCourseIds, {'phy1', 'phy2', 'earth1', 'math', 'kor-read', 'eng'});
    expect(s.bank.subjects.every((c) => c.level == 'high' || c.id == 'custom'), isTrue);
    expect(s.dailySet.problemIds, isNotEmpty);
    expect(s.dailyProblems.every((p) => s.myCourseIds.contains(p.subjectId)), isTrue);
    expect(s.trialDaysLeft, AppState.trialDays);
    expect(tester.takeException(), isNull);
  });

  test('daily set: a wrong answer comes back as its authored twin; twins count for the original', () async {
    final app = await _state();
    final base = app.bank.byId('phy1-mech-009')!; // has two authored twins
    expect(app.bank.twinsOf(base.id), isNotEmpty);
    expect(app.bank.all.any((p) => p.isTwin), isFalse, reason: 'twins stay out of lists');
    await app.record(base, answer: 'x', expected: base.answer, correct: false, timeMs: 1000, mode: 'practice');
    app.rebuildDailySet();
    final set = app.dailySet;
    final twinId = set.problemIds.firstWhere((id) => app.problem(id)?.twinOf == base.id);
    expect(set.reasons[twinId], 'twin');
    expect(set.problemIds.length, greaterThanOrEqualTo(6));
    final twin = app.problem(twinId)!;
    await app.record(twin, answer: twin.answer, expected: twin.answer, correct: true, timeMs: 1000, mode: 'daily');
    expect(app.dailySet.done, contains(twinId));
    expect(app.stateOf(base.id).attempts, 2);
    expect(app.attempts.last.baseId, base.id);
    // the next variant of this family is the other twin, not the one just solved
    expect(app.makeVariant(base).id, isNot(twinId));
  });

  test('endless feed adapts difficulty and does not repeat a family', () async {
    final app = await _state();
    final feed = EndlessFeed(courseId: 'math');
    final seen = <String>{};
    for (var i = 0; i < 12; i++) {
      final p = app.nextEndless(feed)!;
      expect(p.subjectId, 'math');
      expect(seen.add(p.familyId), isTrue);
      feed.report(true);
    }
    expect(feed.level, 5);
    feed.report(false);
    expect(feed.level, lessThan(5));
  });

  testWidgets('무한 풀기: next keeps drawing new problems', (tester) async {
    _tabletSize(tester);
    final app = (await tester.runAsync(_state))!;
    await tester.pumpWidget(_app(app,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => SolveScreen.endless(context, courseId: 'phy1'),
                child: const Text('go'),
              ),
            ),
          ),
        )));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('1번째'), findsOneWidget);
    await _penRest(tester);
    for (var i = 2; i <= 4; i++) {
      await tester.tap(find.byKey(const Key('next')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('$i번째'), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('endless-stop')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('결과'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('지문형 passages and 표 tables render on the exam sheet', (tester) async {
    _tabletSize(tester);
    final app = (await tester.runAsync(_state))!;
    final kor = app.bank.subject('kor-read')!;
    final pid = kor.passages.first.id;
    final linked = kor.problems.where((p) => p.passageId == pid).take(2).toList();
    final table = app.bank.all.firstWhere((p) => p.stem.contains('\n|'));
    await tester.pumpWidget(_app(app,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => SolveScreen.open(context, title: '지문', problems: [...linked, table]),
                child: const Text('go'),
              ),
            ),
          ),
        )));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('[1~2] 다음 글을 읽고 물음에 답하시오.'), findsOneWidget);
    await _penRest(tester);
    await tester.tap(find.byKey(const Key('next')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('next')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Table), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('학습관리: to-do, 순공 timer, 모의고사 성적', (tester) async {
    _tabletSize(tester);
    final app = (await tester.runAsync(_state))!;
    await tester.pumpWidget(_app(app));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('학습관리').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const Key('todo-input')), '수학Ⅰ 지수함수 20문제');
    await tester.tap(find.byKey(const Key('todo-add')));
    await tester.pump();
    expect(app.todayTodos.single.text, '수학Ⅰ 지수함수 20문제');
    expect(find.text('수학Ⅰ 지수함수 20문제'), findsOneWidget);
    await tester.tap(find.byKey(const Key('planner-study-toggle')));
    await tester.pump();
    expect(app.studying, isTrue);
    await tester.tap(find.byKey(const Key('planner-study-toggle')));
    await tester.pump();
    expect(app.studying, isFalse);
    await tester.ensureVisible(find.byKey(const Key('score-add')));
    await tester.tap(find.byKey(const Key('score-add')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const Key('score-name')), '9월 모의평가');
    await tester.tap(find.byKey(const Key('score-국어-2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('score-수학-3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('score-save')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(app.scores.single.grades, {'국어': 2, '수학': 3});
    expect(tester.takeException(), isNull);
  });

  test('content server: packs are downloaded, cached and reused offline', () async {
    expect(ContentSync.httpBase('ws://192.168.0.12:8080/ws'), 'http://192.168.0.12:8080');
    expect(ContentSync.httpBase('192.168.0.12'), 'http://192.168.0.12:8080');
    await HttpOverrides.runWithHttpOverrides(() async {
      final storage = MemoryStorage();
      final bank = await ProblemBank.load(rootBundle);
      final app = AppState(storage: storage, baseBank: bank, enableLive: false);
      await app.init();
      final pack = {
        'subject': '테스트 과목',
        'subjectId': 'test-course',
        'color': '#123456',
        'group': 'sci',
        'level': 'high',
        'grades': ['고2'],
        'problems': [
          {'id': 'tc-1', 'unit': 'U', 'topic': 'T', 'difficulty': 2, 'type': 'short', 'stem': '1+1?', 'answer': '2'},
          {'id': 'tc-1-t1', 'twinOf': 'tc-1', 'unit': 'U', 'topic': 'T', 'difficulty': 2, 'type': 'short', 'stem': '2+2?', 'answer': '4'},
        ],
      };
      var version = 'v1';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        final path = req.uri.path;
        Object? body;
        if (path == '/api/content/index') {
          body = {
            'packs': [
              {'id': 'test-course', 'version': version}
            ],
            'workbooks': {'version': 'w1'}
          };
        } else if (path == '/api/content/pack/test-course') {
          body = pack;
        } else if (path == '/api/content/workbooks') {
          body = {
            'workbooks': [
              {'id': 'wb-test', 'title': '테스트 문제집', 'course': 'test-course', 'level': '기본', 'problems': ['tc-1']}
            ]
          };
        }
        req.response.statusCode = body == null ? 404 : 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(body == null ? '{}' : jsonEncode(body));
        req.response.close();
      });
      app.updateSettings((x) => x.serverUrl = '127.0.0.1:${server.port}');
      final r = await app.syncContent();
      expect(r.ok, isTrue, reason: r.message);
      expect(r.updated, 2);
      expect(app.bank.byId('tc-1'), isNotNull);
      expect(app.bank.twinsOf('tc-1').single.id, 'tc-1-t1');
      expect(app.bank.workbook('wb-test'), isNotNull);
      expect(app.bank.subject('phy1'), isNotNull, reason: 'bundled courses stay');
      final r2 = await app.syncContent();
      expect(r2.updated, 0);
      version = 'v2';
      expect((await app.syncContent()).updated, 1);
      await server.close(force: true);
      // offline: a fresh start uses the cached copy
      final again = AppState(storage: storage, baseBank: bank, enableLive: false);
      await again.init();
      expect(again.bank.byId('tc-1'), isNotNull);
      expect(again.bank.workbook('wb-test'), isNotNull);
      final failed = await again.syncContent();
      expect(failed.ok, isFalse);
      expect(again.bank.byId('tc-1'), isNotNull);
    }, _RealHttp());
  });

  testWidgets('오답노트 shows only courses the student has solved', (tester) async {
    _tabletSize(tester);
    final app = (await tester.runAsync(_state))!;
    final p = app.bank.subject('phy1')!.problems.first;
    await tester.runAsync(() => app.record(p, answer: 'x', expected: p.answer, correct: false, timeMs: 1000, mode: 'practice'));
    await tester.pumpWidget(_app(app));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('오답노트').first); // the rail tab (the home card has the same label)
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('wn-subject-phy1')), findsOneWidget);
    expect(find.byKey(const Key('wn-subject-eng')), findsNothing);
    expect(find.byKey(const Key('wn-subject-kor-read')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('커뮤니티 without a server explains how to connect', (tester) async {
    _tabletSize(tester);
    final app = (await tester.runAsync(_state))!;
    await tester.pumpWidget(_app(app));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('커뮤니티').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('커뮤니티 서버에 연결되지 않았어요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('names are masked before they leave the tablet', () {
    expect(maskName('오예진'), '오XX');
    expect(maskName('김민'), '김XX');
    expect(maskName(' Kim '), 'KXX');
    expect(maskName(''), '익명');
  });

  // Runs in CI against the real Node server (server/), started on COMMUNITY_SERVER.
  final server = Platform.environment['COMMUNITY_SERVER'];
  test('community + ranking against the real server', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final a = CommunityApi(server!, 'user-a-${DateTime.now().microsecondsSinceEpoch}');
      final b = CommunityApi(server, 'user-b-${DateTime.now().microsecondsSinceEpoch}');
      final post = await a.write(author: '물리왕', grade: '고3', board: 'qna', title: '등가속도 질문', body: r'$v=v_0+at$ 에서 a가 음수면?', problemId: 'phy1-mech-001');
      expect(post.mine, isTrue);
      final listA = await a.posts(board: 'qna');
      expect(listA.any((p) => p.id == post.id && p.mine), isTrue);
      final listB = await b.posts(board: 'qna');
      expect(listB.firstWhere((p) => p.id == post.id).mine, isFalse);
      await b.comment(post.id, author: '지구과학러', grade: '고2', body: '감속 운동이에요');
      final (likes, liked) = await b.like(post.id);
      expect((likes, liked), (1, true));
      final read = await a.post(post.id);
      expect(read.body, contains('v_0'));
      expect(read.comments.single.author, '지구과학러');
      expect(read.comments.single.mine, isFalse);
      expect(read.problemId, 'phy1-mech-001');
      await expectLater(b.deletePost(post.id), throwsA(isA<CommunityError>()));
      await a.deletePost(post.id);
      await expectLater(a.post(post.id), throwsA(isA<CommunityError>()));

      final day = dayKey(DateTime.now());
      await a.reportStudy(name: '오예진', grade: '고3', day: day, studyMs: 3 * 3600000, solved: 40);
      await b.reportStudy(name: '김민수', grade: '고2', day: day, studyMs: 2 * 3600000, solved: 20);
      final r = await a.ranking(period: 'day', day: day);
      expect(r.entries.map((e) => e.name), containsAll(['오XX', '김XX']));
      expect(r.entries.any((e) => e.name.contains('예진') || e.name.contains('민수')), isFalse);
      expect(r.myRank, isNotNull);
      expect(r.entries.firstWhere((e) => e.me).name, '오XX');
      final g2 = await b.ranking(period: 'week', grade: '고2', day: day);
      expect(g2.entries.every((e) => e.grade == '고2'), isTrue);
    }, _RealHttp());
  }, skip: server == null ? 'COMMUNITY_SERVER not set' : false);
}
