// Renders every main screen to PNG (real fonts) so the design can be reviewed from CI.
// Runs only when SHOTS=1; output goes to ci-out/shots/.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
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
import 'package:study_app/core/problem_bank.dart';
import 'package:study_app/core/variants.dart';
import 'package:study_app/ink/ink_model.dart';
import 'package:study_app/screens/app_root.dart';
import 'package:study_app/screens/history_screen.dart';
import 'package:study_app/screens/questions_screen.dart';
import 'package:study_app/screens/workbook_store_screen.dart';
import 'package:study_app/services/account_api.dart';
import 'package:study_app/screens/home_shell.dart';
import 'package:study_app/screens/result_screen.dart';
import 'package:study_app/screens/solve_screen.dart';
import 'package:study_app/screens/workbook_screen.dart';
import 'package:study_app/services/community_api.dart';
import 'package:study_app/app/learner.dart';
import 'package:study_app/widgets/answer_panel.dart';

import 'fixtures/sample_book.dart';

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
  s.completeOnboarding(
      name: '선주',
      grade: '고2',
      goal: '수능',
      courses: const [],
      workbooks: const ['wb-phy1-concept', 'wb-phy1-real1', 'wb-math1-concept', 'wb-math-real1', 'wb-earth1-mock1']);
  s.addTodo('수학Ⅰ 지수함수 20문제');
  s.addTodo('영어 단어 Day 12');
  s.toggleTodo(s.todos.first.id);
  for (final (i, (name, g)) in [
    ('3월 학력평가', {'국어': 3, '수학': 4, '영어': 2, '탐구1': 3}),
    ('6월 모의평가', {'국어': 2, '수학': 3, '영어': 2, '탐구1': 3}),
    ('9월 모의평가', {'국어': 2, '수학': 2, '영어': 1, '탐구1': 2}),
  ].indexed) {
    s.saveScore(ExamScore(id: 'e$i', name: name, date: now - (200 - i * 90) * Duration.millisecondsPerDay, grades: g));
  }
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

List<Offset> _digit1() => [for (var y = 0.0; y <= 70; y += 5) Offset(4 - y * 0.06, y - 35)];
List<Offset> _digit2() => [
      for (var a = math.pi; a <= math.pi * 2.2; a += 0.2) Offset(18 + 18 * math.cos(a), -18 + 18 * math.sin(a)),
      for (var t = 0.0; t <= 1; t += 0.1) Offset(34 - 34 * t, -10 + 45 * t),
      for (var x = 0.0; x <= 40; x += 5) Offset(x, 35),
    ];

/// Palm rejection uses the wall clock: let real time pass after pen strokes before finger taps.
Future<void> _rest(WidgetTester tester) =>
    tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));

class _RealHttp extends HttpOverrides {}

Future<void> _waitNet(WidgetTester tester, [int rounds = 4]) async {
  for (var k = 0; k < rounds; k++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Teacher + students with records and questions on the CI server, then the teacher's and a student's screens.
Future<void> _teacherShots(WidgetTester tester, String server) async {
  HttpOverrides.global = _RealHttp();
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final png = (await tester.runAsync(_samplePagePng))!;
  final bank = (await tester.runAsync(() => ProblemBank.load(rootBundle)))!;
  final setup = await tester.runAsync(() async {
    final (tToken, tMe) = await AccountApi(server).signup(role: 'teacher', loginId: 'shot$stamp', password: 'teach-pass', name: '우네');
    final students = <(String, String)>[];
    final rnd = math.Random(7);
    for (final (i, (name, grade)) in [('오예진', '고3'), ('김선주', '고2'), ('박민수', '고3'), ('이서연', 'N수')].indexed) {
      final (sToken, _) = await AccountApi(server)
          .signup(role: 'student', loginId: 'st$i$stamp', password: 'stud-pass', name: name, grade: grade);
      final api = AccountApi(server, sToken);
      await api.joinTeacher(tMe.inviteCode!);
      final now = DateTime.now().millisecondsSinceEpoch;
      final ps = bank.all.where((p) => p.subjectId == 'phy1' || p.subjectId == 'math').toList()..shuffle(rnd);
      final atts = <Attempt>[];
      for (var k = 0; k < 18 + i * 7; k++) {
        final p = ps[k % ps.length];
        final ok = rnd.nextDouble() < 0.68;
        atts.add(Attempt(
          id: 'shot-$i-$k',
          problemId: p.id,
          baseId: p.id,
          subjectId: p.subjectId,
          unit: p.unit,
          topic: p.topic,
          answer: ok ? p.answer : (p.isChoice ? '${(int.parse(p.answer) % 5) + 1}' : '7'),
          expected: p.answer,
          correct: ok,
          timeMs: 40000 + rnd.nextInt(200000),
          at: now - (k % 9) * Duration.millisecondsPerDay - rnd.nextInt(3600000),
          mode: 'practice',
          hasInk: false,
        ));
      }
      await api.sync(
        attempts: atts,
        learner: {'onboarded': true, 'grade': grade, 'goal': '수능', 'workbooks': ['wb-phy1-concept', 'wb-math1-concept'], 'examName': '수능', 'examDate': now + 45 * Duration.millisecondsPerDay},
        wrongNote: [for (final a in atts) if (!a.correct) a.baseId],
      );
      if (i < 3) {
        final wrong = atts.firstWhere((a) => !a.correct);
        await api.ask(
          teacherId: tMe.userId,
          title: ['운동량 보존 질문', '수열 귀납적 정의', '등가속도 그래프'][i],
          body: [r'충돌 후 속도를 $m_1v_1 = m_2v_2$ 로 구하면 왜 틀려요?', '점화식을 어떻게 세우는지 모르겠어요', '기울기가 가속도인 이유가 궁금해요'][i],
          problemId: wrong.problemId,
          imagePng: png,
        );
      }
      students.add((name, sToken));
    }
    final teacher = AccountApi(server, tToken);
    final qs = await teacher.questions();
    await teacher.reply(qs.last.id, body: r'운동량은 $p = mv$ 이고, 충돌 전후 **합**이 같아요. 필기로 정리했어요!', imagePng: png);
    return (tMe.loginId, students.first.$2);
  });
  final (teacherLogin, _) = setup!;

  final tApp = (await tester.runAsync(() async {
    final a = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false);
    await a.init();
    await a.login(server: server, loginId: teacherLogin, password: 'teach-pass');
    return a;
  }))!;
  await tester.pumpWidget(_wrap(tApp, const AppRoot()));
  await _waitNet(tester);
  await _shot(tester, '40_teacher_students');
  final card = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('t-student-'));
  if (card.evaluate().isNotEmpty) {
    await tester.tap(card.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _waitNet(tester);
    await _shot(tester, '41_teacher_student_wrong');
    final row = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('t-wrong-'));
    if (row.evaluate().isNotEmpty) {
      await tester.tap(row.first);
      await tester.pump(const Duration(milliseconds: 400));
      await _shot(tester, '42_teacher_wrong_detail');
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.tap(find.byKey(const Key('t-tab-recent')));
    await tester.pump(const Duration(milliseconds: 500));
    await _shot(tester, '43_teacher_student_recent');
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }
  await tester.tap(find.byKey(const Key('t-tab-1')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await _waitNet(tester);
  await _shot(tester, '44_teacher_inbox');
  final q = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('q-q_'));
  if (q.evaluate().isNotEmpty) {
    await tester.tap(q.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _waitNet(tester);
    await _shot(tester, '45_teacher_thread');
    await tester.tap(find.byKey(const Key('q-reply-ink')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final hc = tester.getCenter(find.byType(HandwriteScreen));
    await _write(tester, hc + const Offset(-200, 40), _parabola());
    await _write(tester, hc + const Offset(60, 120), _wave());
    await _write(tester, hc + const Offset(200, -40), _circle(40));
    await _rest(tester);
    await _shot(tester, '45b_teacher_handwrite_reply');
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  // 학생: 질문 탭 (답변 온 질문 포함)
  final sApp = (await tester.runAsync(() async {
    final a = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false);
    await a.init();
    await a.login(server: server, loginId: 'st0$stamp', password: 'stud-pass');
    return a;
  }))!;
  await tester.pumpWidget(_wrap(sApp, const AppRoot()));
  await _waitNet(tester, 2);
  await _shot(tester, '46_student_home_signed_in');
  await tester.tap(find.text('질문').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await _waitNet(tester);
  await _shot(tester, '47_student_questions');
  final sq = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('q-q_'));
  if (sq.evaluate().isNotEmpty) {
    await tester.tap(sq.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _waitNet(tester);
    await _shot(tester, '48_student_thread');
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pumpWidget(_wrap(sApp, AskTeacherScreen(problem: bank.byId('phy1-mech-005'), snapshot: null)));
  await _shot(tester, '49_ask_teacher');
  // let requests started inside the fake clock (badge refresh) finish or time out
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 90));
}

/// A page-like picture (problem lines + handwriting) to attach to questions in the screenshots.
Future<Uint8List> _samplePagePng() async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  const w = 900.0, h = 520.0;
  c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFFFFDF8));
  final grey = Paint()..color = const Color(0xFFD5CDBF);
  for (var i = 0; i < 4; i++) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(40, 40.0 + i * 26, i == 3 ? 380 : 560, 12), const Radius.circular(6)), grey);
  }
  final ink = Paint()
    ..color = const Color(0xFF1B2A4A)
    ..strokeWidth = 3.2
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final path = Path()..moveTo(80, 420);
  for (var x = 0.0; x <= 300; x += 6) {
    path.lineTo(80 + x, 420 - (x * x) / 260);
  }
  c.drawPath(path, ink);
  c.drawLine(const Offset(70, 430), const Offset(420, 430), ink);
  c.drawLine(const Offset(80, 440), const Offset(80, 200), ink);
  final red = Paint()
    ..color = const Color(0xFFE5484D)
    ..strokeWidth = 3.4
    ..style = PaintingStyle.stroke;
  c.drawCircle(const Offset(640, 300), 70, red);
  final wave = Path()..moveTo(520, 420);
  for (var x = 0.0; x <= 300; x += 5) {
    wave.lineTo(520 + x, 420 + 22 * math.sin(x / 18));
  }
  c.drawPath(wave, ink);
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

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

    // community: seed real posts + ranking on the CI server
    final server = Platform.environment['COMMUNITY_SERVER'];
    if (server != null) {
      HttpOverrides.global = _RealHttp();
      app.updateSettings((x) => x.serverUrl = server);
      await tester.runAsync(() async {
        final day = dayKey(DateTime.now());
        final people = [
          ('오예진', '고3', 9.2, 88), ('김민수', '고3', 8.1, 64), ('이서연', '고2', 7.4, 51), ('박지훈', 'N수', 10.6, 120),
          ('최하은', '고1', 5.2, 30), ('정우진', '고2', 6.8, 47), ('강다은', '고3', 4.1, 22),
        ];
        for (final (i, (name, grade, h, solved)) in people.indexed) {
          final api = CommunityApi(server, 'seed-$i');
          await api.reportStudy(name: name, grade: grade, day: day, studyMs: (h * 3600000).round(), solved: solved);
        }
        await CommunityApi(server, app.profile.id)
            .reportStudy(name: app.profile.name, grade: '고2', day: day, studyMs: 5400000, solved: 35);
        final posts = [
          ('qna', '물리학Ⅰ 운동량 보존 질문이요', r'충돌 전후로 $m_1v_1+m_2v_2$ 가 같다는 건 알겠는데, 탄성 충돌이 아니면 에너지는 어디로 가나요?', '물리왕'),
          ('proof', '오늘 순공 9시간 인증합니다', '수학Ⅰ 지수·로그 40문제 + 오답 변형 세트 완료! 내일도 달린다', '수능가즈아'),
          ('info', '9월 모평 등급컷 정리', '국어 언매 · 수학 미적 등급컷 예상 정리해 봤어요. 틀린 부분 있으면 댓글 주세요', '입시덕후'),
          ('mind', '모의고사 망쳐서 멘탈이 나갔어요', '6월보다 두 등급이나 떨어졌어요… 다들 이럴 때 어떻게 버티나요', '익명고3'),
          ('free', '공부할 때 듣는 노래 추천해 주세요', '가사 없는 걸로요!', '새벽공부'),
        ];
        for (final (i, (board, title, body, author)) in posts.indexed) {
          final api = CommunityApi(server, 'poster-$i');
          final p = await api.write(author: author, grade: i.isEven ? '고3' : '고2', board: board, title: title, body: body);
          for (var k = 0; k < (5 - i); k++) {
            await CommunityApi(server, 'liker-$i-$k').like(p.id);
          }
          if (i < 3) {
            await CommunityApi(server, 'commenter-$i').comment(p.id, author: '응원단', grade: '고2', body: '저도 궁금했어요!');
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
    }

    // 2..11 tabs
    const tabs = ['내 교재', '오답노트', '학습관리', '질문', '커뮤니티', '통계', '기록', '연습장', '내 문제', '구독', '설정'];
    for (var i = 0; i < tabs.length; i++) {
      await tester.ensureVisible(find.text(tabs[i]).first);
      await tester.pump();
      await tester.tap(find.text(tabs[i]).first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      if (tabs[i] == '커뮤니티' || tabs[i] == '학습관리') {
        for (var k = 0; k < 4; k++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      if (tabs[i] == '연습장') {
        final c = tester.getCenter(find.byType(HomeShell));
        await _write(tester, c + const Offset(-200, 50), _axisX());
        await _write(tester, c + const Offset(-200, 50), _axisY());
        await _write(tester, c + const Offset(-50, -60), _parabola());
        await _write(tester, c + const Offset(150, 140), _wave());
      }
      await _shot(tester,
          '${(i + 2).toString().padLeft(2, '0')}_${['shelf', 'wrongnote', 'planner', 'questions_offline', 'community', 'stats', 'history', 'scratch', 'editor', 'subscription', 'settings'][i]}');
    }

    // onboarding (fresh learner)
    final fresh = (await tester.runAsync(() async {
      final bank = await ProblemBank.load(rootBundle);
      final f = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false);
      await f.init();
      return f;
    }))!;
    await tester.pumpWidget(_wrap(fresh, const HomeShell()));
    await _shot(tester, '20_onboarding_grade');
    await tester.tap(find.byKey(const Key('grade-고3')));
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('onb-next')));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await _shot(tester, '21_onboarding_books');
    await tester.tap(find.byKey(const Key('store-course-math')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('store-add-wb-math1-concept')));
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, '21b_onboarding_books_math');

    // welcome (login)
    final fresh2 = (await tester.runAsync(() async {
      final bank = await ProblemBank.load(rootBundle);
      final f = AppState(storage: MemoryStorage(), baseBank: bank, enableLive: false);
      await f.init();
      return f;
    }))!;
    await tester.pumpWidget(_wrap(fresh2, const AppRoot()));
    await _shot(tester, '30_welcome');
    await tester.tap(find.byKey(const Key('welcome-student')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('회원가입'));
    await tester.pump();
    await _shot(tester, '31_welcome_signup');

    // catalog
    await tester.pumpWidget(_wrap(app, const WorkbookStoreScreen(initialCourse: 'math')));
    await _shot(tester, '32_store_math');

    // 선생님 화면 · 질문 (CI 서버)
    if (server != null) await _teacherShots(tester, server);

    // workbook
    await tester.pumpWidget(_wrap(app, const WorkbookScreen(workbookId: 'wb-phy1-concept')));
    await _shot(tester, '22_workbook');

    // 지문형 (국어), 영어, 표 (통합사회), 무한 풀기
    final kor = app.bank.subject('kor-read')!;
    final korPs = kor.problems.where((p) => p.passageId == kor.passages.first.id).toList();
    final eng = app.bank.subject('eng')!;
    final engPs = eng.problems.where((p) => p.passageId != null).take(2).toList();
    final soc = app.bank.all.firstWhere((p) => p.stem.contains('\n|'));
    await tester.pumpWidget(_wrap(
        app,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => SolveScreen.open(context, title: '국어 독서', problems: [...korPs, ...engPs, soc]),
                child: const Text('go'),
              ),
            ),
          ),
        )));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '23_solve_passage_kor');
    for (var i = 0; i < korPs.length; i++) {
      await tester.tap(find.byKey(const Key('next')));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await _shot(tester, '24_solve_passage_eng');
    for (var i = 0; i < engPs.length; i++) {
      await tester.tap(find.byKey(const Key('next')));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await _shot(tester, '25_solve_table_soc');
    tester.view.physicalSize = const Size(1848, 2960);
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, '26_solve_table_portrait');
    tester.view.physicalSize = const Size(2960, 1848);
    await tester.pumpWidget(_wrap(
        app,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => SolveScreen.endless(context, courseId: 'math'),
                child: const Text('go'),
              ),
            ),
          ),
        )));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '27_solve_endless');

    // 교재 파일 (TeX 원문을 옮긴 문항): 조건 상자 · 가운데 수식 · 그림 · 머리표
    await tester.runAsync(() => app.importBook(sampleBookFile()));
    final texPs = app.bank.problemsOf(app.bank.workbook('sample-type-01')!);
    await tester.pumpWidget(_wrap(
        app,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => SolveScreen.open(context, title: 'SAMPLE TYPE 1회차', problems: texPs),
                child: const Text('go'),
              ),
            ),
          ),
        )));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '28_solve_tex_box');
    await tester.tap(find.byKey(const Key('next')));
    await tester.pump(const Duration(milliseconds: 400));
    await _shot(tester, '29_solve_tex_figure');
    unawaited(showSolutionSheet(tester.element(find.byType(SolveScreen)), texPs[1], null));
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '29b_tex_solution');
    await tester.pumpWidget(_wrap(
        app,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => SolveScreen.open(context, title: 'SAMPLE TYPE 1회차', problems: [texPs[2]]),
                child: const Text('go'),
              ),
            ),
          ),
        )));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '29c_solve_tex_table');

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
    // solving work in the free space to the right of the problem column
    await _write(tester, c + const Offset(300, 60), _axisX());
    await _write(tester, c + const Offset(300, 60), _axisY());
    await _write(tester, c + const Offset(470, -40), _parabola());
    await _write(tester, c + const Offset(300, 230), _wave());
    await _write(tester, c + const Offset(560, 120), _circle(26));
    await _rest(tester);
    await _shot(tester, '09_solve_full');

    await tester.tap(find.byKey(Key('choice-${(int.parse(calc.answer) % 5) + 1}')));
    await tester.pump();
    await _shot(tester, '10_solve_choice_marked');
    await tester.tap(find.byKey(const Key('submit')));
    await _shot(tester, '11_solve_wrong');

    await tester.tap(find.byKey(const Key('next')));
    await tester.pump(const Duration(milliseconds: 600));
    await _write(tester, c + const Offset(320, 120), _wave());
    await _rest(tester);
    await tester.tap(find.byKey(Key('choice-${choice.answer}')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit')));
    await _shot(tester, '12_solve_correct');

    await tester.tap(find.byKey(const Key('next')));
    await tester.pump(const Duration(milliseconds: 600));
    // handwriting in the 답 box (recognition needs the device; the keypad fixes it in tests)
    final box = tester.getCenter(find.text('여기에 답을 쓰세요'));
    await _write(tester, box + const Offset(-60, 0), _digit1());
    await _write(tester, box + const Offset(-20, 0), _digit2());
    await _rest(tester);
    await _shot(tester, '13_solve_short_written');
    await tester.tapAt(box + const Offset(120, 30));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    for (final k in short.answer.split('')) {
      final key = find.byKey(Key('key-$k'));
      if (key.evaluate().isNotEmpty) await tester.tap(key);
    }
    await tester.pump(const Duration(milliseconds: 200));
    await _shot(tester, '14_solve_keypad');
    await tester.tap(find.byKey(const Key('keypad-ok')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('submit')));
    await _shot(tester, '15_solve_short_graded');

    // windowed (full screen off)
    await tester.tap(find.byKey(const Key('fullscreen-toggle')));
    await _shot(tester, '16_solve_windowed');
    await tester.tap(find.byKey(const Key('fullscreen-toggle')));

    // portrait tablet
    tester.view.physicalSize = const Size(1848, 2960);
    await tester.tap(find.byKey(const Key('prev')));
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '17_solve_portrait');
    tester.view.physicalSize = const Size(2960, 1848);

    // 18. results
    await tester.pumpWidget(_wrap(
        app,
        ResultScreen(title: '물리학Ⅰ · 역학과 에너지', mode: 'practice', items: [
          SessionItem(problem: calc, graded: GradedAnswer('2', false, expectedDisplay(calc)), timeMs: 84000),
          SessionItem(problem: choice, graded: GradedAnswer(choice.answer, true, expectedDisplay(choice)), timeMs: 62000),
          SessionItem(problem: short, graded: GradedAnswer(short.answer, true, expectedDisplay(short)), timeMs: 120000),
          SessionItem(problem: generateVariant(calc, 5), graded: null, timeMs: 0),
        ])));
    await _shot(tester, '18_results');

    // 19. history detail with replay
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
    await _shot(tester, '19_history_replay');
    // requests started inside the fake clock (ranking report) finish or time out before the test ends
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 90));
  });
}
