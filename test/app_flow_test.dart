import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:study_app/screens/app_root.dart';
import 'package:study_app/screens/home_shell.dart';
import 'package:study_app/screens/solve_screen.dart';
import 'package:study_app/widgets/answer_panel.dart';
import 'package:study_app/widgets/math_text.dart';
import 'package:study_app/services/account_api.dart';
import 'package:study_app/services/community_api.dart';
import 'package:study_app/services/content_import.dart';
import 'package:study_app/services/content_sync.dart';
import 'package:study_app/widgets/book_files_card.dart';
import 'package:study_app/widgets/problem_brief.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'fixtures/sample_book.dart';

Future<AppState> _state({bool onboard = true}) async {
  final bank = await ProblemBank.load(rootBundle);
  final s = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false);
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
    for (final tab in ['내 교재', '오답노트', '학습관리', '질문', '커뮤니티', '통계', '기록', '연습장', '내 문제', '구독', '설정', '홈']) {
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
    expect(s.trialDaysLeft, AppState.trialDays);
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
    final bank = await ProblemBank.load(rootBundle);
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
    expect(find.text('예제'), findsWidgets);
    expect(find.text('풀이노트 예시 문항'), findsWidgets);
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
    expect(find.text('심화'), findsWidgets);
    expect(find.byType(SvgPicture), findsOneWidget);
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
    expect(find.text('심화'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('설정 → 교재 파일 가져오기 → 목록 → 빼기', (tester) async {
    _tabletSize(tester);
    final app = (await tester.runAsync(_state))!;
    BookFilesCard.picker = () async => Uint8List.fromList(sampleBookFile());
    addTearDown(() => BookFilesCard.picker = BookFiles.pick);
    await tester.pumpWidget(_app(app, home: const Scaffold(body: SingleChildScrollView(child: BookFilesCard()))));
    await tester.tap(find.byKey(const Key('books-import')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('books-msg')), findsOneWidget);
    expect(find.textContaining('3문항'), findsWidgets);
    expect(find.byKey(const Key('book-sample-type-01')), findsOneWidget);
    expect(app.hasWorkbook('sample-type-01'), isTrue);

    BookFilesCard.picker = () async => Uint8List.fromList(utf8.encode('not a book'));
    await tester.tap(find.byKey(const Key('books-import')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('풀이노트 교재 파일이 아니에요'), findsOneWidget);

    await tester.tap(find.byKey(const Key('book-remove-sample-type-01')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('books-remove-ok')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('book-sample-type-01')), findsNothing);
    expect(app.bank.workbook('sample-type-01'), isNull);
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

  test('accounts: student syncs records, asks the teacher with a picture, teacher answers; new tablet restores', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final bank = await ProblemBank.load(rootBundle);
      final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      // 선생님 (API 로 바로 가입)
      final (tToken, tMe) = await AccountApi(server!)
          .signup(role: 'teacher', loginId: 't$stamp', password: 'teach-pass', name: '우네 선생님');
      final teacher = AccountApi(server, tToken);
      expect(tMe.inviteCode, hasLength(6));

      // 학생 앱: 회원가입 → 온보딩 → 선생님 연결
      final st = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false);
      await st.init();
      expect(st.needsWelcome, isTrue);
      await st.signup(server: server, role: 'student', loginId: 's$stamp', password: 'stud-pass', name: '오예진', grade: '고3');
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

      // 다른 태블릿에서 로그인 → 기록 · 내 교재 되살리기
      final other = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false);
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
