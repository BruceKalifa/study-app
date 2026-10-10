import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_app/app/app_state.dart';
import 'package:study_app/app/goals.dart';
import 'package:study_app/app/learner.dart';
import 'package:study_app/app/storage.dart';
import 'package:study_app/app/theme.dart';
import 'package:study_app/core/problem.dart';
import 'package:study_app/core/grader.dart';
import 'package:study_app/core/problem_bank.dart';
import 'fixtures/problem_bundle.dart';
import 'package:study_app/core/variants.dart';
import 'package:study_app/screens/app_root.dart';
import 'package:study_app/screens/home_shell.dart';
import 'package:study_app/screens/library_screen.dart';
import 'package:study_app/screens/workbook_screen.dart';
import 'package:study_app/screens/workbook_store_screen.dart';
import 'package:study_app/screens/answer_key_screen.dart';
import 'package:study_app/screens/concept_screen.dart';
import 'package:study_app/screens/solve_screen.dart';
import 'package:study_app/widgets/answer_panel.dart';
import 'package:study_app/widgets/math_text.dart';
import 'package:study_app/services/account_api.dart';
import 'package:study_app/services/community_api.dart';
import 'package:study_app/services/content_import.dart';
import 'package:study_app/services/content_sync.dart';
import 'package:study_app/widgets/problem_brief.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'fixtures/sample_book.dart';

/// 개념 페이지가 든 교재 (CORE TYPE 처럼 개념·실전개념과 문제가 함께) — 샘플 교재에 개념 셋을 얹는다.
List<int> _conceptBookFile() {
  final j = sampleBookJson();
  final courses = j['courses'] as List;
  (courses.first as Map<String, dynamic>)['concepts'] = [
    {'id': 'sample-type-01-c-intro', 'title': '이 책 보는 법', 'section': '책머리', 'body': '먼저 읽어 보세요.'},
    {
      'id': 'sample-type-01-c-seq',
      'title': '수열의 귀납적 정의',
      'kind': '개념',
      'topic': '예제',
      'section': '수업문항',
      'links': ['예제'],
      'body': '\$a_{n+1}=a_n+d\$ 이면 등차수열이다.\n\n[[box]]\n핵심: 공차 \$d\$\n[[/box]]',
    },
    {
      'id': 'sample-type-01-c-hw',
      'title': '숙제 1 실전 스킬',
      'kind': '실전개념',
      'section': '숙제문항 DAY 1',
      'links': ['숙제 1(중)'],
      'body': '표준화부터 한다.',
    },
  ];
  ((j['workbooks'] as List).first as Map<String, dynamic>)['concepts'] = [
    'sample-type-01-c-intro',
    'sample-type-01-c-seq',
    'sample-type-01-c-hw',
  ];
  return gzip.encode(utf8.encode(jsonEncode(j)));
}

Future<AppState> _state({bool onboard = true}) async {
  final bank = await ProblemBank.load(fixtureBundle);
  final s = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false, autoSyncBooks: false);
  await s.init();
  if (onboard) {
    s.completeOnboarding(
        name: '학생', grade: '고2', goal: '수능', courses: const [], workbooks: [for (final w in s.bank.workbooks) w.id]);
  }
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
  _aptTests();
  _univTests();
  _seriesTests();

  test('problem bank loads every subject (테스트용 문제 은행)', () async {
    final bank = await ProblemBank.load(fixtureBundle);
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
    final bank = (await tester.runAsync(() => ProblemBank.load(fixtureBundle)))!;
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
    for (final tab in ['내 교재', '오답노트', '학습관리', '질문', '커뮤니티', '통계', '기록', '연습장', '내 문제', '설정', '홈']) {
      await tester.ensureVisible(find.text(tab).first); // the rail comes first (and scrolls)
      await tester.pump();
      await tester.tap(find.text(tab).first);
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
    expect(find.text('$other번 선택'), findsOneWidget);
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

  testWidgets('onboarding: 목표 목록이 고른 과정에 따라 다르고 복수 선택된다', (tester) async {
    _tabletSize(tester);
    final s = (await tester.runAsync(() => _state(onboard: false)))!;
    await tester.pumpWidget(_app(s));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byKey(const Key('onb-name')), '취준생');
    await tester.tap(find.byKey(const Key('grade-취준')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('onb-next')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('goal-인적성 실전 대비')), findsOneWidget);
    expect(find.byKey(const Key('goal-NCS 대비')), findsOneWidget);
    expect(find.byKey(const Key('goal-수능')), findsNothing, reason: '취준에는 수능 목표가 없다');
    expect(find.byKey(const Key('goal-내신')), findsNothing);
    // 맨 위 목표는 미리 골라져 있다 → 하나 더 골라 복수 선택
    await tester.ensureVisible(find.byKey(const Key('goal-NCS 대비')));
    await tester.tap(find.byKey(const Key('goal-NCS 대비')));
    await tester.pump();
    // 뒤로 가서 한양대를 더하면 한양대 목표가 과정 이름과 함께 나온다
    await tester.tap(find.text('이전'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('grade-한양대')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('onb-next')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('goal-기말고사 대비')), findsOneWidget);
    expect(find.byKey(const Key('goal-인적성 실전 대비')), findsOneWidget, reason: '취준 목표도 그대로');
    expect(find.text('한양대'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding: name, grade, goal, then pick books from the catalog → 내 교재 → home', (tester) async {
    _tabletSize(tester);
    final s = (await tester.runAsync(() => _state(onboard: false)))!;
    await tester.pumpWidget(_app(s));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('반가워요!'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('onb-name')), '예진');
    await tester.tap(find.byKey(const Key('grade-고3')));
    await tester.pump();
    expect(find.byKey(const Key('grade-중2')), findsNothing, reason: '고등 전용');
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('onb-next')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }
    // 커리큘럼별 카탈로그: 고3 과목만
    expect(find.byKey(const Key('store-course-phy2')), findsOneWidget);
    expect(find.byKey(const Key('store-course-integ')), findsNothing, reason: '통합과학 is 고1');
    await tester.tap(find.byKey(const Key('store-course-phy2')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byKey(const Key('store-add-wb-phy2-deep')));
    await tester.tap(find.byKey(const Key('store-add-wb-phy2-deep')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('store-course-math')));
    await tester.tap(find.byKey(const Key('store-course-math')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('store-scope-수학Ⅰ')), findsOneWidget, reason: '범위로 나눠 보기');
    await tester.ensureVisible(find.byKey(const Key('store-add-wb-math1-concept')));
    await tester.tap(find.byKey(const Key('store-add-wb-math1-concept')));
    await tester.pump();
    expect(find.text('2권 담고 시작하기'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onb-start')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('daily-start')), findsOneWidget);
    expect(s.learner.grade, '고3');
    expect(s.learner.goal, '수능');
    expect(s.profile.name, '예진');
    expect(s.learner.workbooks, ['wb-phy2-deep', 'wb-math1-concept']);
    expect(s.myCourseIds, {'phy2', 'math'});
    final mine = {for (final p in s.myProblems) p.id};
    expect(s.dailySet.problemIds, isNotEmpty);
    expect(s.dailyProblems.every((p) => mine.contains(p.id)), isTrue, reason: '내 교재 문제만');
    expect(tester.takeException(), isNull);
  });

  test('내 교재: problems come only from the books on the shelf', () async {
    final app = await _state(onboard: false);
    app.completeOnboarding(name: '학생', grade: '고2', goal: '수능', courses: const [], workbooks: const ['wb-phy1-concept']);
    final book = {for (final p in app.bank.problemsOf(app.bank.workbook('wb-phy1-concept')!)) p.id};
    expect(app.dailyProblems.every((p) => book.contains(p.id)), isTrue);
    expect(app.dailySet.reasons.values.toSet(), {'new'});
    // 오늘의 진도는 책 순서대로
    expect(app.dailySet.problemIds.first, app.bank.workbook('wb-phy1-concept')!.problemIds.first);
    final feed = EndlessFeed();
    for (var i = 0; i < 8; i++) {
      final p = app.nextEndless(feed);
      expect(p, isNotNull);
      expect(book.contains(p!.familyId), isTrue, reason: '무한 풀기도 내 교재에서만');
    }
    // 빼면 비고, 담으면 다시 생긴다
    app.removeWorkbook('wb-phy1-concept');
    expect(app.myWorkbooks, isEmpty);
    expect(app.dailySet.problemIds, isEmpty);
    expect(app.nextEndless(EndlessFeed()), isNull);
    app.addWorkbook('wb-math1-concept');
    expect(app.dailyProblems.every((p) => p.subjectId == 'math'), isTrue);
    expect(app.dailyProblems, isNotEmpty);
    // 틀린 문제의 변형은 책과 상관없이 오답 세트에 들어온다
    final wrong = app.bank.byId('phy1-mech-009')!;
    await app.record(wrong, answer: 'x', expected: wrong.answer, correct: false, timeMs: 1000, mode: 'practice');
    app.rebuildDailySet();
    expect(app.dailyProblems.any((p) => p.familyId == wrong.id), isTrue);
    // 시험처럼: 내 교재의 책 한 권만으로도 무한 풀기
    final only = EndlessFeed(workbookId: 'wb-math1-concept');
    final ids = app.bank.workbook('wb-math1-concept')!.problemIds.toSet();
    expect(ids.contains(app.nextEndless(only)!.familyId), isTrue);
  });

  testWidgets('empty shelf: home sends the student to the catalog; 담기 fills 내 교재', (tester) async {
    _tabletSize(tester);
    final s = (await tester.runAsync(() => _state(onboard: false)))!;
    s.completeOnboarding(name: '학생', grade: '고2', goal: '수능', courses: const [], workbooks: const []);
    await tester.pumpWidget(_app(s));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('daily-start')), findsNothing);
    await tester.tap(find.byKey(const Key('daily-pick-books')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('문제집 고르기'), findsOneWidget);
    await tester.tap(find.byKey(const Key('store-course-math')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byKey(const Key('store-add-wb-math1-concept')));
    await tester.tap(find.byKey(const Key('store-add-wb-math1-concept')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.learner.workbooks, ['wb-math1-concept']);
    expect(find.text('내 교재 1권'), findsOneWidget);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('daily-start')), findsOneWidget);
    expect(find.byKey(const Key('wbcard-wb-math1-concept')), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('welcome: 학생/선생님 → 로그인 form validates; 로그인 없이 쓰기 → onboarding', (tester) async {
    _tabletSize(tester);
    final s = (await tester.runAsync(() => _state(onboard: false)))!;
    expect(s.needsWelcome, isTrue);
    await tester.pumpWidget(_app(s, home: const AppRoot()));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('welcome-student')), findsOneWidget);
    await tester.tap(find.byKey(const Key('welcome-teacher')));
    await tester.pump(); // AnimatedSize starts resizing on the next frame
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('auth-error')), findsOneWidget);
    await tester.tap(find.text('회원가입'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('auth-name')), findsOneWidget);
    expect(find.byKey(const Key('auth-grade-고3')), findsNothing, reason: '선생님은 학년 없음');
    expect(find.byKey(const Key('auth-teacher-code')), findsOneWidget, reason: '선생님 가입에는 승인 코드');
    await tester.enterText(find.byKey(const Key('auth-name')), '우네');
    await tester.enterText(find.byKey(const Key('auth-id')), 'une.new');
    await tester.enterText(find.byKey(const Key('auth-pw')), 'secret-1');
    await tester.enterText(find.byKey(const Key('auth-pw2')), 'secret-1');
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('승인 코드를 입력하세요'), findsOneWidget);
    await tester.tap(find.byKey(const Key('welcome-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('welcome-offline')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.offlineMode, isTrue);
    expect(find.text('반가워요!'), findsOneWidget);
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

  test('교재 파일: .pulinote import joins the bank, goes on the shelf, survives restart and can be removed', () async {
    final storage = MemoryStorage();
    final bank = await ProblemBank.load(fixtureBundle);
    final app = AppState(storage: storage, baseBank: bank, enableLive: false);
    await app.init();
    app.completeOnboarding(name: '학생', grade: '고3', goal: '수능', courses: const [], workbooks: const ['wb-math1-concept']);
    final before = app.bank.subject('math')!.problems.length;

    expect(() => ContentImport.decode(utf8.encode('hello')), throwsFormatException);
    expect(() => ContentImport.decode(gzip.encode(utf8.encode('{"format":"other"}'))), throwsFormatException);

    final book = await app.importBook(sampleBookFile());
    expect(book.title, 'SAMPLE TYPE 1회차');
    expect(book.problemCount, 3);
    // problems join the existing 수학 course, the 문제집 is in the catalog and on the student's shelf
    expect(app.bank.subject('math')!.problems.length, before + 3);
    final p = app.bank.byId('sample-type-01-cls-2')!;
    expect(p.texStyle, isTrue);
    expect(p.label, '심화');
    expect(p.labelColor, 0xFF00707A);
    expect(p.points, 0);
    expect(app.bank.workbook('sample-type-01'), isNotNull);
    expect(app.hasWorkbook('sample-type-01'), isTrue);
    expect(app.myProblems.map((p) => p.id), containsAll(['sample-type-01-cls-1', 'sample-type-01-cls-2']));
    expect(app.importedBooks.single.id, 'sample-type-01');

    // importing again replaces (no duplicates)
    await app.importBook(sampleBookFile());
    expect(app.bank.subject('math')!.problems.length, before + 3);
    expect(app.importedBooks.length, 1);
    await app.record(p, answer: '7', expected: p.answer, correct: true, timeMs: 1000, mode: 'practice');
    await app.saveNow();

    // a restart keeps the book
    final again = AppState(storage: storage, baseBank: bank, enableLive: false);
    await again.init();
    expect(again.bank.byId('sample-type-01-cls-1')?.stem, contains('[[box]]'));
    expect(again.hasWorkbook('sample-type-01'), isTrue);

    await again.removeImportedBook('sample-type-01');
    expect(again.bank.byId('sample-type-01-cls-1'), isNull);
    expect(again.bank.workbook('sample-type-01'), isNull);
    expect(again.hasWorkbook('sample-type-01'), isFalse);
    expect(again.importedBooks, isEmpty);
    expect(again.bank.subject('math')!.problems.length, before);
    expect(again.attempts.length, 1, reason: '푼 기록은 남는다');

    // one file can carry several books
    final both = await again.importBooks(sampleCollectionFile());
    expect(both.map((b) => b.id), ['sample-type-01', 'sample-type-02']);
    expect(again.importedBooks.length, 2);
    expect(again.bank.byId('sample-type-02-cls-2'), isNotNull);
    expect(again.hasWorkbook('sample-type-02'), isTrue);
  });

  test('MathText.compact / plain flatten block markup for lists', () {
    const src = '조건\n[[box]]\n(가) \$a_1=3\$\n\$\$a_{n+1}=\\dfrac{a_n}{2}\$\$\n[[/box]]\n[[center]]\n[[svg]]<svg width="10" height="10"></svg>[[/svg]]\n[[/center]]';
    final c = MathText.compact(src);
    expect(c.contains('[['), isFalse);
    expect(c.contains(r'$$'), isFalse);
    expect(c, contains('[그림]'));
    expect(MathText.plain(src), isNot(contains('svg')));
    expect(MathText.plain(src), contains('a_n+1=a_n/2'));
  });

  testWidgets('TeX 원문 교재: boxes, display math, figures and the 머리표 render; no 배점', (tester) async {
    _tabletSize(tester);
    final app = (await tester.runAsync(_state))!;
    await tester.runAsync(() => app.importBook(sampleBookFile()));
    final ps = app.bank.problemsOf(app.bank.workbook('sample-type-01')!);
    expect(ps.length, 3);
    await tester.pumpWidget(_app(app,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => SolveScreen.open(context, title: 'SAMPLE', problems: ps),
                child: const Text('go'),
              ),
            ),
          ),
        )));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('예제'), findsNothing, reason: '교재 머리표는 학생 화면에 나오지 않는다 (선생님만)');
    expect(find.text('Solvit 예시 문항'), findsNothing, reason: '출처는 학생 화면에 나오지 않는다 (선생님만)');
    expect(find.byType(Math), findsWidgets);
    bool hasPoints() => tester
        .widgetList<RichText>(find.byType(RichText))
        .any((t) => RegExp(r'\[\d점\]').hasMatch(t.text.toPlainText()));
    expect(hasPoints(), isFalse);
    expect(find.textContaining('[[box]]'), findsNothing);
    await _penRest(tester);
    await tester.tap(find.byKey(const Key('next')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('심화'), findsNothing);
    expect(find.textContaining('<svg'), findsNothing);
    expect(tester.takeException(), isNull);
    // 나란히 (글 | 표) and a list inside the box
    await _penRest(tester);
    await tester.tap(find.byKey(const Key('next')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('[[col'), findsNothing);
    expect(tester.takeException(), isNull);

    // read-only views (선생님 화면 · 오답 상세) use the same markup (fresh navigator: drop the solve route)
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(app,
        home: Scaffold(
            body: SingleChildScrollView(child: ProblemBrief(problem: ps[1], studentAnswer: '5', showSolution: true)))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('문제 보기: 교재별이 기본, 교재 안에서는 단원별', (tester) async {
    _tabletSize(tester);
    final app = (await tester.runAsync(_state))!;
    await tester.runAsync(() => app.importBooks(sampleBookFile()));

    await tester.pumpWidget(_app(app, home: const Scaffold(body: CourseBrowser())));
    await tester.pump(const Duration(milliseconds: 400));
    // 기본은 교재별 — 교재 카드가 늘어서고 단원으로 묶이지 않는다
    expect(find.text('내 교재'), findsOneWidget);
    expect(find.byKey(const Key('book-row-wb-phy1-concept')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('book-row-sample-type-01')), 400,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('book-row-sample-type-01')), findsOneWidget);

    // 단원별로 바꾸면 단원 묶음
    await tester.scrollUntilVisible(find.byKey(const Key('browse-by-unit')), -400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('browse-by-unit')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('book-row-wb-phy1-concept')), findsNothing);
    expect(find.textContaining('문제 풀기'), findsWidgets);

    // 교재를 열면 목차(수업문항 · 숙제문항 DAY 1)로 나뉘고 목차별로 풀 수 있다
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(app, home: const WorkbookScreen(workbookId: 'sample-type-01')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('wb-unit-수업문항')), findsOneWidget);
    expect(find.byKey(const Key('wb-unit-숙제문항 DAY 1')), findsOneWidget);
    expect(find.text('수열 · 예제'), findsOneWidget, reason: '목차로 묶으면 줄에 단원을 붙인다');
    expect(tester.takeException(), isNull);
  });

  test('교재 목차: 수업문항·숙제문항 DAY 로 묶고, 목차가 없으면 단원으로', () {
    Problem p(String id, {String unit = '', String section = '', String topic = ''}) => Problem(
        id: id, subjectId: 's', subjectName: '수학', unit: unit, section: section, topic: topic, stem: '본문', answer: '1');
    // 목차가 적혀 있으면 그대로 (단원은 섞여 있어도 된다)
    final withSection = [
      p('a', unit: '수열', section: '수업문항'),
      p('b', unit: '미분', section: '수업문항'),
      p('c', unit: '수열', section: '숙제문항 DAY 1'),
    ];
    expect(byTableOfContents(withSection).map((e) => e.$1).toList(), ['수업문항', '숙제문항 DAY 1']);
    expect(byTableOfContents(withSection).first.$2, [0, 1]);
    // 목차가 안 적힌 옛 교재도 유형의 DAY 표시로 알아서 묶는다
    final fromTopic = [
      p('a', unit: '수열', topic: '기출 원문'),
      p('b', unit: '미분', topic: '심화'),
      p('c', unit: '수열', topic: 'DAY 1 · 숙제 1(중)'),
      p('d', unit: '확률', topic: 'DAY 2 · 숙제 2(상)'),
    ];
    expect(byTableOfContents(fromTopic).map((e) => e.$1).toList(), ['수업문항', '숙제문항 DAY 1', '숙제문항 DAY 2']);
    expect(byTableOfContents(fromTopic).first.$2, [0, 1]);
    // 줄 이름: 목차로 묶었으면 단원을 앞에 붙이고 DAY 표시는 뗀다
    expect(tocRowLabel(fromTopic[2], withUnit: true), '수열 · 숙제 1(중)');
    expect(tocRowLabel(fromTopic[0], withUnit: false), '기출 원문');
    // 목차가 없으면 단원
    final noSection = [p('a', unit: '수열'), p('b', unit: '미분'), p('c', unit: '수열')];
    expect(byTableOfContents(noSection).map((e) => e.$1).toList(), ['수열', '미분']);
    // 하나뿐이면 묶지 않는다
    final one = byTableOfContents([p('a', unit: '수열'), p('b', unit: '수열')]);
    expect(one, hasLength(1));
    expect(one.single.$1, '');
    expect(one.single.$2, [0, 1]);
  });

  group('개념 교재', () {
    test('개념은 유형이 맞는 문제와 이어지고, 목차 칸에 들어간다', () async {
      final app = await _state();
      await app.importBooks(_conceptBookFile());
      final w = app.bank.workbook('sample-type-01')!;
      final cs = app.bank.conceptsOf(w);
      expect(cs.map((c) => c.id), ['sample-type-01-c-intro', 'sample-type-01-c-seq', 'sample-type-01-c-hw']);
      expect(cs[2].kind, '실전개념');
      final ps = app.bank.problemsOf(w);
      // 연결: 문제 유형 토막이 같을 때만 (DAY 1 · 숙제 1(중) 의 "숙제 1(중)")
      expect(app.bank.conceptsFor(ps[0]).map((c) => c.id), ['sample-type-01-c-seq']);
      expect(app.bank.conceptsFor(ps[1]), isEmpty);
      expect(app.bank.conceptsFor(ps[2]).map((c) => c.id), ['sample-type-01-c-hw']);
      expect(app.bank.problemsExplainedBy(cs[1], within: ps).map((p) => p.id), [ps[0].id]);
      // 목차: 같은 이름의 칸에 들어가고, 어느 칸과도 안 맞는 개념은 맨 앞 칸
      final groups = tocGroups(ps, cs);
      expect(groups.map((g) => g.name).toList(), ['책머리', '수업문항', '숙제문항 DAY 1']);
      expect(groups[0].idx, isEmpty);
      expect(groups[1].concepts.map((c) => c.id), ['sample-type-01-c-seq']);
      expect(groups[2].concepts.map((c) => c.id), ['sample-type-01-c-hw']);
      // 개념이 없는 교재는 예전 그대로
      expect(tocGroups(ps, const []).map((g) => g.name).toList(), ['수업문항', '숙제문항 DAY 1']);
      // 저장 → 다시 읽기에서도 그대로
      expect(Subject.fromJson(app.bank.subject('math')!.toJson()).concepts, hasLength(3));
    });

    testWidgets('PDF 쪽 이미지 개념: 그림이 종이 너비로 펼쳐지고 필기 종이도 그만큼 늘어난다', (tester) async {
      _tabletSize(tester);
      final app = (await tester.runAsync(_state))!;
      // 1×1 흰 PNG (실제로는 pdf_book.py 가 만든 WebP)
      const png =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      final c = Concept.fromJson({'id': 'pdf-1', 'title': '3쪽', 'body': '', 'images': [png, png]});
      expect(c.images, hasLength(2));
      expect(Concept.fromJson(c.toJson()).images, hasLength(2), reason: '저장 → 다시 읽기');
      await tester.pumpWidget(_app(app, home: ConceptScreen(concepts: [c], index: 0)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.text('3쪽'), findsOneWidget, reason: '앱바 제목은 있고, 본문 제목은 그림으로 대신한다');
    });

    testWidgets('교재 화면: 목차마다 개념 카드, 필터, 개념 읽기(읽음 표시) 와 관련 개념', (tester) async {
      _tabletSize(tester);
      final app = (await tester.runAsync(_state))!;
      await tester.runAsync(() => app.importBooks(_conceptBookFile()));
      await tester.pumpWidget(_app(app, home: const WorkbookScreen(workbookId: 'sample-type-01')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('개념 3편'), findsOneWidget);
      expect(find.byKey(const Key('concept-sample-type-01-c-seq')), findsOneWidget);
      expect(find.text('수열의 귀납적 정의'), findsOneWidget);
      expect(find.byKey(const Key('wb-unit-수업문항')), findsOneWidget);

      await tester.tap(find.text('문제만'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('concept-sample-type-01-c-seq')), findsNothing);
      await tester.tap(find.text('개념만'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('concept-sample-type-01-c-seq')), findsOneWidget);
      expect(find.byKey(const Key('wb-unit-수업문항')), findsOneWidget, reason: '문제가 있는 목차는 풀기 버튼이 남는다');
      await tester.tap(find.text('전체'));
      await tester.pump(const Duration(milliseconds: 300));

      // 개념을 열면 읽음, 이 개념의 문제 풀기 버튼
      expect(app.isConceptRead('sample-type-01-c-seq'), isFalse);
      await tester.tap(find.byKey(const Key('concept-sample-type-01-c-seq')));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      expect(find.byType(ConceptScreen), findsOneWidget);
      expect(app.isConceptRead('sample-type-01-c-seq'), isTrue);
      expect(find.byKey(const Key('concept-solve')), findsOneWidget);
      expect(find.textContaining('1문항'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('풀이 시트에 관련 개념이 나오고 누르면 그 개념으로 간다', (tester) async {
      _tabletSize(tester);
      final app = (await tester.runAsync(_state))!;
      await tester.runAsync(() => app.importBooks(_conceptBookFile()));
      final p = app.bank.byId('sample-type-01-hw-1')!;
      await tester.pumpWidget(_app(app,
          home: Scaffold(body: Builder(builder: (ctx) => TextButton(onPressed: () => showSolutionSheet(ctx, p, null), child: const Text('해설'))))));
      await tester.tap(find.text('해설'));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      expect(find.text('관련 개념'), findsOneWidget);
      await tester.tap(find.byKey(const Key('related-concept-sample-type-01-c-hw')));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      expect(find.byType(ConceptScreen), findsOneWidget);
      expect(find.text('숙제 1 실전 스킬'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('내 교재: 시리즈로 묶고 → 회차 고르기 → 교재 목차', (tester) async {
    _tabletSize(tester);
    // 내 교재를 비우고 시작 (담은 교재가 이 시리즈뿐이게)
    final app = (await tester.runAsync(() => _state(onboard: false)))!;
    app.completeOnboarding(name: '학생', grade: '고2', goal: '수능', courses: const [], workbooks: const []);
    await tester.runAsync(() => app.importBooks(sampleCollectionFile()));
    expect(app.myWorkbooks, hasLength(2));
    expect(app.hasWorkbook('sample-type-01'), isTrue);
    expect(app.hasWorkbook('sample-type-02'), isTrue);

    await tester.pumpWidget(_app(app, home: const Scaffold(body: LibraryScreen())));
    await tester.pump(const Duration(milliseconds: 400));
    // 회차가 여럿인 시리즈는 한 칸으로
    expect(find.byKey(const Key('seriescard-SAMPLE TYPE')), findsOneWidget);
    expect(find.byKey(const Key('wbcard-sample-type-01')), findsNothing);
    expect(find.text('2회차'), findsWidgets);

    // 누르면 회차 목록
    await tester.tap(find.byKey(const Key('seriescard-SAMPLE TYPE')));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('round-sample-type-01')), findsOneWidget);
    expect(find.byKey(const Key('round-sample-type-02')), findsOneWidget);
    expect(find.text('1회차'), findsOneWidget, reason: '시리즈 이름은 떼고 회차만');

    // 회차를 누르면 교재 화면 (목차별)
    await tester.tap(find.byKey(const Key('round-sample-type-01')));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('wb-unit-수업문항')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('답안표: 학생이 자기 답을 적고 한 번에 채점한다 (채점된 건 못 고침)', (tester) async {
    _tabletSize(tester);
    final app = (await tester.runAsync(_state))!;
    await tester.runAsync(() => app.importBooks(sampleBookFile()));
    final ids = app.bank.workbook('sample-type-01')!.problemIds;
    final right = app.bank.byId(ids[0])!;
    final wrong = app.bank.byId(ids[1])!;

    await tester.pumpWidget(_app(app, home: const AnswerKeyScreen(workbookId: 'sample-type-01')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('채점하기'), findsOneWidget);
    expect(find.byKey(Key('answer-${right.id}')), findsOneWidget, reason: '안 푼 문항은 입력칸');

    await tester.enterText(find.byKey(Key('answer-${right.id}')), right.answer);
    await tester.enterText(find.byKey(Key('answer-${wrong.id}')), '99999');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('채점하기 (2)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('answers-grade')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(app.stateOf(right.id).lastCorrect, isTrue);
    expect(app.stateOf(wrong.id).lastCorrect, isFalse);
    expect(app.stateOf(wrong.id).inWrongNote, isTrue, reason: '틀린 문항은 오답노트로');
    expect(find.textContaining('맞은 개수 1'), findsOneWidget);

    // 채점된 문항은 입력칸이 사라지고 내 답·O/X 가 보인다
    expect(find.byKey(Key('answer-${right.id}')), findsNothing);
    expect(find.byKey(Key('answer-done-${right.id}')), findsOneWidget);
    expect(find.byKey(Key('answer-done-${wrong.id}')), findsOneWidget);
    // 예약된 기록 보내기 타이머를 흘려보낸다
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('답안표: 선생님이 목차별로 정답을 고치면 교재에 저장된다', (tester) async {
    _tabletSize(tester);
    final app = (await tester.runAsync(_state))!;
    app.profile.account = Account(
        server: 'https://example.test', token: 't', userId: 'u_t', loginId: 'une.teacher', role: 'teacher', name: '선생님');
    await tester.runAsync(() => app.importBooks(sampleBookFile()));
    final pid = app.bank.workbook('sample-type-01')!.problemIds.first;
    expect(app.bank.byId(pid)!.answer, isNot('7'));

    await tester.pumpWidget(_app(app, home: const AnswerKeyScreen(workbookId: 'sample-type-01')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('답안표'), findsWidgets);
    await tester.enterText(find.byKey(Key('answer-$pid')), '7');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('저장 (1)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('answers-save')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(app.bank.byId(pid)!.answer, '7', reason: '문제은행에 바로 반영');
    expect(find.byKey(const Key('answers-msg')), findsOneWidget);

    // 앱을 다시 켜도 고친 정답이 남는다
    final again = (await tester.runAsync(() async {
      final bank = await ProblemBank.load(fixtureBundle);
      final a = AppState(storage: app.storage, baseBank: bank, enableLive: false, autoSyncBooks: false);
      await a.init();
      return a;
    }))!;
    expect(again.bank.byId(pid)!.answer, '7');
    again.dispose();
  });

  testWidgets('TeX 교재에서 쓰는 수식 어휘가 flutter_math 로 그려진다', (tester) async {
    // tools/tex_book.py 로 옮긴 교재들의 명령·환경 (내용 없이 어휘만)
    const snippets = [
      r'\Big( x \Big) + \Bigl( y \Bigr) + \big( z \big) + \bigl( w \bigr)',
      r'\Pi \alpha \beta \gamma \delta \mu \sigma \psi \varphi',
      r'a \ast b \cap c \cup d \cdot e \circ f \div g \pm h \times i',
      r'1, \cdots, n \dots \square \triangle \infty',
      r'\dfrac{a}{b} + \tfrac12 + \frac{1}{2} + \sqrt{2} + \overline{X}',
      r'\displaystyle\sum_{k=1}^{n} a_k \textstyle\int_a^b f(x)\,dx',
      r'a \equiv 1 \pmod 3',
      r'\left\{ t \,\middle|\, t \ge \dfrac32 \right\}',
      r'x \in A, \ a \le b, \ c \ge d, \ e \ne f, \ g \neq h, \ p \mid q, \ X \sim \mathrm{N}(m,\ \sigma^2)',
      r'\lim_{x \to 0} \log_2 x \iff y \leftarrow z',
      r'{\rm A} \quad B \qquad C',
      r'\text{①} + \text{(가)} + \boxed{\,\text{(나)}\,}',
      r'\begin{aligned} f(x) &= x^2 \\ &= x \end{aligned}',
      r'a_{n+1}=\begin{cases} a_n+2 & (a_n\le 0) \\ a_n-2 & (a_n>0) \end{cases}',
      r'\left(\begin{array}{l} n\text{이 홀수} \\ n\text{이 짝수} \end{array}\right)',
    ];
    final failures = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(
        child: Column(children: [
          for (final tex in snippets)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Math.tex(tex, onErrorFallback: (e) {
                failures.add('$tex → ${e.message}');
                return const SizedBox();
              }),
            ),
        ]),
      ),
    ));
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('content server: packs are downloaded, cached and reused offline', () async {
    expect(ContentSync.httpBase('ws://192.168.0.12:8080/ws'), 'http://192.168.0.12:8080');
    expect(ContentSync.httpBase('192.168.0.12'), 'http://192.168.0.12:8080');
    await HttpOverrides.runWithHttpOverrides(() async {
      final storage = MemoryStorage();
      final bank = await ProblemBank.load(fixtureBundle);
      final app = AppState(storage: storage, baseBank: bank, enableLive: false, autoSyncBooks: false);
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
      final port = server.port;
      app.updateSettings((x) => x.serverUrl = '127.0.0.1:$port');
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
      final again = AppState(storage: storage, baseBank: bank, enableLive: false, autoSyncBooks: false);
      await again.init();
      expect(again.bank.byId('tc-1'), isNotNull);
      expect(again.bank.workbook('wb-test'), isNotNull);
      again.updateSettings((x) => x.serverUrl = '127.0.0.1:$port'); // 꺼진 서버 (실제 서버로 나가지 않게)
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

  test('accounts: student syncs records, asks the teacher with a picture, teacher answers; new tablet restores', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final bank = await ProblemBank.load(fixtureBundle);
      final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      // 선생님 (API 로 바로 가입)
      final (tToken, tMe) = await AccountApi(server!)
          .signup(role: 'teacher', loginId: 't$stamp', password: 'teach-pass', name: '우네 선생님', teacherCode: 'ci-teacher-code');
      final teacher = AccountApi(server, tToken);
      expect(tMe.inviteCode, hasLength(6));

      // 학생 앱: 회원가입 → 온보딩 → 선생님 연결
      final st = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false, autoSyncBooks: false);
      await st.init();
      expect(st.needsWelcome, isTrue);
      await st.signup(server: server, role: 'student', loginId: 's$stamp', password: 'stud-pass', name: '오예진', grade: '고3', studentCode: 'CI-HIGH');
      expect(st.signedIn, isTrue);
      expect(st.isTeacher, isFalse);
      expect(st.needsWelcome, isFalse);
      expect(st.needsOnboarding, isTrue);
      expect(st.learner.grade, '고3');
      st.completeOnboarding(name: '오예진', grade: '고3', goal: '수능', courses: const [], workbooks: const ['wb-phy1-concept']);
      final t = await st.joinTeacher(' ${tMe.inviteCode!.toLowerCase()} ');
      expect(t.name, '우네 선생님');
      expect(st.myTeachers.single.id, tMe.userId);
      expect(st.settings.serverUrl, server, reason: '계정 서버가 문항·커뮤니티 서버');

      // 풀이 → 서버로
      final p1 = bank.byId('phy1-mech-001')!;
      final p2 = bank.byId('phy1-mech-002')!;
      await st.record(p1, answer: '9', expected: p1.answer, correct: false, timeMs: 30000, mode: 'practice');
      await st.record(p2, answer: p2.answer, expected: p2.answer, correct: true, timeMs: 20000, mode: 'practice');
      expect(await st.syncRecords(), isTrue);
      expect(st.unsyncedCount, 0);

      final (_, students) = await teacher.students();
      final mine = students.singleWhere((x) => x.name == '오예진');
      expect(mine.solved, 2);
      expect(mine.wrongOpen, 1);
      final detail = await teacher.student(mine.id);
      expect(detail.wrong.single.baseId, 'phy1-mech-001');
      expect(detail.wrong.single.answer, '9');
      expect(detail.workbooks, ['wb-phy1-concept']);
      expect(detail.recent.first.problemId, 'phy1-mech-002');

      // 질문 (풀이 사진) → 선생님 답장 (필기 그림)
      final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
      final q = await st.api!.ask(teacherId: tMe.userId, body: r'왜 $a$ 가 음수예요?', problemId: p1.id, imagePng: png);
      expect(q.status, 'open');
      expect(q.messages.single.image, isNotNull);
      final inbox = await teacher.questions(status: 'open');
      expect(inbox.any((x) => x.id == q.id && x.unread), isTrue);
      final read = await teacher.question(q.id);
      expect(read.student.name, '오예진');
      final answered = await teacher.reply(q.id, body: '감속이라서 그래요', imagePng: png);
      expect(answered.status, 'answered');
      await st.refreshMe();
      expect(st.unreadAnswers, 1);
      final thread = await st.api!.question(q.id);
      expect(thread.messages.last.fromTeacher, isTrue);
      expect(thread.messages.last.name, '우네 선생님');
      expect(await st.api!.imageBytes(thread.messages.last.image!), png, reason: '선생님이 보낸 필기 그림');
      expect(await teacher.imageBytes(thread.messages.first.image!), png, reason: '학생이 보낸 풀이 사진');
      await st.refreshMe();
      expect(st.unreadAnswers, 0);

      // 교재: 웹 교재 창고(/books/)에 올라간 교재를 앱이 받기만 한다
      final tApp = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false, autoSyncBooks: false);
      await tApp.init();
      await tApp.login(server: server, loginId: 't$stamp', password: 'teach-pass');
      expect(tApp.isTeacher, isTrue);
      await tApp.importBooks(sampleBookFile()); // 설정 → 교재 파일 가져오기 (기기에만)
      expect(await tApp.api!.books(), isEmpty, reason: '앱은 교재를 올리지 않는다');
      expect(await tApp.syncBooks(), '', reason: '올릴 것도 받을 것도 없다');

      // 교재 창고가 하는 일 (웹페이지와 같은 요청)
      await tApp.api!.uploadBook(Uint8List.fromList(sampleBookFile()));
      expect((await tApp.api!.books()).single.bookIds, ['sample-type-01']);

      expect(st.importedBooks, isEmpty);
      expect(await st.syncBooks(), '교재 1권을 받았어요');
      expect(st.importedBooks.single.id, 'sample-type-01');
      expect(st.bank.workbook('sample-type-01'), isNotNull, reason: '학생 내 교재에 담긴다');
      expect(await st.syncBooks(), '', reason: '이미 받은 교재는 다시 안 받는다');
      tApp.dispose();

      // 다른 태블릿에서 로그인 → 기록 · 내 교재 되살리기
      final other = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false, autoSyncBooks: false);
      await other.init();
      await other.login(server: server, loginId: 'S$stamp', password: 'stud-pass');
      expect(other.attempts.length, 2);
      expect(other.stateOf('phy1-mech-001').inWrongNote, isTrue);
      expect(other.learner.workbooks, ['wb-phy1-concept']);
      expect(other.needsOnboarding, isFalse);
      expect(other.myTeachers.single.name, '우네 선생님');

      // 로그아웃 → 다시 첫 화면
      await other.logout();
      expect(other.needsWelcome, isTrue);
      st.dispose();
      other.dispose();
    }, _RealHttp());
  }, skip: server == null ? 'COMMUNITY_SERVER not set' : false, timeout: const Timeout(Duration(minutes: 2)));
}

void _aptTests() {
  group('인적성 과정', () {
    testWidgets('취준 학생에게만 보인다', (tester) async {
      final app = (await tester.runAsync(() => _state(onboard: false)))!;
      await tester.runAsync(() => app.importBooks(aptBookFile()));

      // 교과군에 인적성이 있다
      expect(SubjectGroup.byId('apt')?.name, '인적성');
      expect(kGrades, contains('취준'));

      // 고등 학생 화면에는 나오지 않고, 취준 학생에게만 나온다
      String ids(String grade) => app.coursesForGrade(grade).map((s) => s.id).join(',');
      expect(ids('고3').split(','), isNot(contains('apt')));
      expect(ids('취준').split(','), contains('apt'));

      final apt = app.bank.subject('apt')!;
      expect(apt.group, 'apt');
      expect(apt.units, ['언어이해', '자료해석']);
      expect(apt.passages.single.title, '데이터 압축과 정보량');

      // 지문 묶음 객관식 — 채점은 번호로
      final p = app.bank.byId('apt-mock-01-lang-01')!;
      expect(p.type, ProblemType.choice);
      expect(p.choices, hasLength(5));
      expect(p.passageId, 'apt-mock-01-p-p1');
      expect(Grader.grade(p, '3').correct, isTrue);
      expect(Grader.grade(p, '2').correct, isFalse);

      // 자료해석 표는 본문에 그대로 남는다
      expect(app.bank.byId('apt-mock-01-data-01')!.stem, contains('| 갑국 | 30 | 45 |'));
      app.dispose();
    });
  });
}

void _univTests() {
  group('커뮤니티 신분', () {
    test('가입할 때 고른 과정이 글 옆에 보이는 신분이 된다', () {
      expect(identityLabel(['고2']), '고2');
      expect(identityLabel(['한양대']), '한양대생');
      expect(identityLabel(['한양대', 'N수', '편입']), '한양대생 · N수생 · 편입생');
      expect(identityLabel(['취준', '취준']), '취준생');
      expect(identityLabel(['고1', '고2', '고3', 'N수']), '고1 · 고2 · 고3');
      expect(identityLabel(const []), '');
    });
  });

  group('학습 목표', () {
    test('과정마다 목표 목록이 다르고, 여러 과정을 고르면 겹치는 것은 한 번만 나온다', () {
      expect(goalLabels(['취준']), ['인적성 실전 대비', 'NCS 대비', '영역별 약점 보완', '시간 단축 연습']);
      expect(goalLabels(['한양대']), contains('기말고사 대비'));
      expect(goalLabels(['한양대']), isNot(contains('수능')));
      expect(goalLabels(['고3']).first, '수능');
      final both = goalLabels(['고3', 'N수']);
      expect(both.where((g) => g == '수능'), hasLength(1));
      expect(both.where((g) => g == '정시 준비'), hasLength(1));
      expect([for (final s in goalSections(['한양대', '편입'])) s.$1], ['한양대', '편입']);
      for (final g in kGrades) {
        expect(goalsByGrade[g], isNotEmpty, reason: '$g 목표 목록');
      }
    });

    test('Learner 목표: 복수 선택·저장·옛 값', () {
      final l = Learner();
      l.setGoals(['기말고사 대비', '전공 기초 다지기', '기말고사 대비']);
      expect(l.goal, '기말고사 대비 · 전공 기초 다지기');
      expect(l.goals, ['기말고사 대비', '전공 기초 다지기']);
      l.setGoals(const []);
      expect(l.goals, hasLength(2), reason: '빈 목록은 무시');
      expect(Learner.fromJson(l.toJson()).goals, ['기말고사 대비', '전공 기초 다지기']);
      expect(parseGoals('둘 다'), ['수능', '내신']);
      expect(parseGoals('수능'), ['수능']);
      expect(parseGoals('6·9월 모의평가 · 수시 준비'), ['6·9월 모의평가', '수시 준비'], reason: '이름 안의 · 는 쪼개지 않는다');
    });

    test('커뮤니티 게시판은 고른 과정에 맞게 나온다', () {
      List<String> ids(List<String> gs) => [for (final b in Board.forGrades(gs)) b.id];
      expect(Board.defaults.map((b) => b.id).toSet(), hasLength(Board.defaults.length), reason: 'id 중복 없음');
      expect(ids(['취준']), containsAll(['free', 'qna', 'apt', 'job']));
      expect(ids(['취준']), isNot(contains('naesin')));
      expect(ids(['한양대']), containsAll(['univmath', 'univexam', 'hyu']));
      expect(ids(['편입']), containsAll(['transfer', 'trmath']));
      expect(ids(['고1']), containsAll(['naesin', 'math']));
      expect(ids(['고1']), isNot(contains('sisi')));
      expect(ids(['한양대', 'N수']), containsAll(['univmath', 'nsu', 'sisi']), reason: '복수 과정은 합쳐서');
      expect(ids(const []), hasLength(Board.defaults.length), reason: '과정을 모르면 전부');
      expect(Board.nameOf('trmath'), '편입수학');
    });

    test('온보딩을 마치면 D-day 카드에 고른 목표의 시험이 오른다 (날짜는 수능만 미리 채움)', () async {
      final a = (await _state(onboard: false));
      a.completeOnboarding(name: '학생', grade: '취준', goals: const ['NCS 대비'], courses: const [], workbooks: const []);
      expect(a.learner.examName, 'NCS');
      expect(a.learner.examDate, 0, reason: '수능이 아니면 날짜를 직접 정한다');
      final b = (await _state(onboard: false));
      b.completeOnboarding(name: '학생', grade: '고3', goals: const ['수능', '내신 마무리'], courses: const [], workbooks: const []);
      expect(b.learner.examName, '수능');
      expect(b.learner.examDate, greaterThan(0));
      expect(b.learner.goal, '수능 · 내신 마무리');
      final c = (await _state(onboard: false));
      c.completeOnboarding(name: '학생', grade: '고1', goals: const ['선행 학습'], courses: const [], workbooks: const []);
      expect(c.learner.examName, '시험');
      a.dispose();
      b.dispose();
      c.dispose();
    });
  });

  group('한양대 과정', () {
    test('학년·과정은 여러 개를 함께 고를 수 있다 (대표는 첫 번째)', () {
      final l = Learner();
      expect(l.grades, ['고2'], reason: '처음엔 대표 학년 하나');
      l.setGrades(['한양대', 'N수', '편입', 'N수', '']);
      expect(l.grades, ['한양대', 'N수', '편입'], reason: '중복·빈 값 제거');
      expect(l.grade, '한양대');
      expect(l.gradeLabel, '한양대 · N수 · 편입');
      l.setGrades(const []);
      expect(l.grades, ['한양대', 'N수', '편입'], reason: '빈 목록은 무시');

      // 저장했다 읽어도 그대로, 옛 저장본(grade 하나)도 읽힌다
      final back = Learner.fromJson(l.toJson());
      expect(back.grades, ['한양대', 'N수', '편입']);
      expect(back.grade, '한양대');
      final old = Learner.fromJson({'grade': '고3', 'goal': '수능'});
      expect(old.grades, ['고3']);
    });

    testWidgets('여러 학년·과정을 고르면 겹치는 과목이 모두 보인다', (tester) async {
      final app = (await tester.runAsync(() => _state(onboard: false)))!;
      await tester.runAsync(() => app.importBooks(aptBookFile()));
      String ids(List<String> gs) => app.coursesForGrades(gs).map((s) => s.id).toSet().join(',');
      expect(ids(['고3']).split(','), isNot(contains('apt')));
      expect(ids(['취준']), 'apt');
      final both = ids(['고3', '취준']).split(',');
      expect(both, contains('apt'));
      expect(both, contains('phy1'), reason: '고3 과목도 그대로');
      app.dispose();
    });

    testWidgets('회원가입: 학년·과정을 여러 개 고를 수 있고, 하나도 없으면 막는다', (tester) async {
      _tabletSize(tester);
      final s = (await tester.runAsync(() => _state(onboard: false)))!;
      await tester.pumpWidget(_app(s, home: const AppRoot()));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('welcome-student')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('회원가입'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byKey(const Key('auth-id')), 'multi.test');
      await tester.enterText(find.byKey(const Key('auth-pw')), 'secret-1');
      await tester.enterText(find.byKey(const Key('auth-pw2')), 'secret-1');
      await tester.enterText(find.byKey(const Key('auth-name')), '한양대생');

      bool on(String g) => tester.widget<FilterChip>(find.byKey(Key('auth-grade-$g'))).selected;
      expect([for (final g in kGrades) if (on(g)) g], isEmpty, reason: '처음엔 아무것도 고르지 않는다');

      await tester.ensureVisible(find.byKey(const Key('auth-submit')));
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('하나 이상'), findsOneWidget, reason: '학년·과정이 없으면 가입하지 않는다');

      for (final g in ['한양대', 'N수', '편입']) {
        await tester.ensureVisible(find.byKey(Key('auth-grade-$g')));
        await tester.tap(find.byKey(Key('auth-grade-$g')));
        await tester.pump();
      }
      expect([for (final g in kGrades) if (on(g)) g], ['N수', '한양대', '편입'], reason: '세 개 모두 선택');
      await tester.tap(find.byKey(const Key('auth-grade-N수')));
      await tester.pump();
      expect(on('N수'), isFalse, reason: '다시 누르면 해제');
      expect(on('한양대'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('앱에는 과목 이름만 실려 있고 한양대 학생에게만 보인다', (tester) async {
      final bank = (await tester.runAsync(() => ProblemBank.load(rootBundle)))!;
      // 문제는 앱에 싣지 않는다 — 교재는 서버에서 받는다
      expect(bank.all, isEmpty);
      expect(bank.workbooks, isEmpty);
      expect([for (final s in bank.subjects) s.name], ['공업수학1', '공업수학2', '미분적분학1', '미분적분학2']);

      expect(kGrades, contains('한양대'));
      expect(SubjectGroup.byId('univ')?.name, '대학');

      final app = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false, autoSyncBooks: false);
      await tester.runAsync(app.init);
      String ids(String grade) => app.coursesForGrade(grade).map((s) => s.id).join(',');
      expect(ids('한양대'), 'emath1,emath2,calc1,calc2');
      expect(ids('고3'), '');
      expect(ids('취준'), '');
      app.dispose();
    });
  });
}

void _seriesTests() {
  group('시리즈 교재', () {
    testWidgets('교재 고르기: 시리즈는 한 권으로 보이고, 담으면 회차가 전부 담긴다', (tester) async {
      _tabletSize(tester);
      final app = (await tester.runAsync(_state))!;
      await tester.runAsync(() => app.importBooks(sampleCollectionFile()));
      for (final id in ['sample-type-01', 'sample-type-02']) {
        app.removeWorkbook(id);
      }
      await tester.pumpWidget(_app(app, home: const WorkbookStoreScreen(initialCourse: 'math')));
      await tester.pump(const Duration(milliseconds: 400));

      const tile = Key('store-book-series-SAMPLE TYPE');
      await tester.scrollUntilVisible(find.byKey(tile), 300, scrollable: find.byType(Scrollable).first);
      expect(find.byKey(tile), findsOneWidget);
      expect(find.byKey(const Key('store-book-sample-type-01')), findsNothing, reason: '회차마다 따로 보이지 않는다');
      expect(find.byKey(const Key('store-book-sample-type-02')), findsNothing);
      expect(find.textContaining('2회차'), findsWidgets);

      // 한 번 담으면 회차가 모두 내 교재에 들어간다
      const add = Key('store-add-series-SAMPLE TYPE');
      await tester.ensureVisible(find.byKey(add));
      await tester.tap(find.byKey(add));
      await tester.pump(const Duration(milliseconds: 300));
      expect(app.hasWorkbook('sample-type-01'), isTrue);
      expect(app.hasWorkbook('sample-type-02'), isTrue);
      expect(find.text('담김'), findsWidgets);

      // 다시 누르면 모두 빠진다
      await tester.tap(find.byKey(add));
      await tester.pump(const Duration(milliseconds: 300));
      expect(app.hasWorkbook('sample-type-01'), isFalse);
      expect(app.hasWorkbook('sample-type-02'), isFalse);

      // 한 권 칸을 누르면 회차 목록이 열린다
      await tester.tap(find.byKey(tile));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('round-sample-type-01')), findsOneWidget);
      expect(find.byKey(const Key('round-sample-type-02')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
