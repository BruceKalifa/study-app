import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_app/app/app_state.dart';
import 'package:study_app/app/storage.dart';
import 'package:study_app/app/theme.dart';
import 'package:study_app/core/problem.dart';
import 'package:study_app/core/problem_bank.dart';
import 'package:study_app/screens/solve_screen.dart';

Problem _essay({List<Object> rubric = const []}) => Problem.fromJson({
      'id': 'gs1-essay-1',
      'type': '서술형',
      'stem': r"미분방정식 $y'+y=0$ 의 일반해를 구하는 과정을 서술하시오.",
      'answer': r'$y=Ce^{-x}$',
      'solution': r'변수분리하면 $\frac{dy}{y}=-dx$, 적분하면 $\ln|y|=-x+C$ 이므로 $y=Ce^{-x}$.',
      'rubric': rubric,
    }, subjectId: 'gs1', subjectName: '공업수학1');

void main() {
  test('서술형: 형식·채점 기준을 읽고 쓴다, 만점은 기준의 합', () {
    final p = _essay(rubric: [
      {'text': '변수분리', 'points': 2},
      '적분 (2점)',
      '일반해 | 1',
    ]);
    expect(p.isEssay, isTrue);
    expect(p.isShort, isFalse);
    expect([for (final r in p.rubric) (r.text, r.points)], [('변수분리', 2), ('적분', 2), ('일반해', 1)]);
    expect(p.essayMax, 5);
    final back = Problem.fromJson(p.toJson(), subjectId: 'gs1', subjectName: '공업수학1');
    expect(back.type, ProblemType.essay);
    expect(back.rubric.length, 3);
    expect(_essay().essayMax, 10, reason: '기준이 없으면 10점 만점');
  });

  testWidgets('서술형: 답칸 없이, 스스로 채점 → 점수 기록, 만점이 아니면 오답노트', (tester) async {
    tester.view.physicalSize = const Size(2960, 1848);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(() async {
      final a = AppState(storage: MemoryStorage(), baseBank: ProblemBank(const []), enableLive: false, autoSyncBooks: false);
      await a.init();
      return a;
    }))!;
    final p = _essay(rubric: [
      {'text': '변수분리', 'points': 2},
      {'text': '적분', 'points': 2},
      {'text': '일반해', 'points': 1},
    ]);
    await tester.pumpWidget(AppScope(
      state: app,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => SolveScreen.open(context, title: '서술형', problems: [p]),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('여기에 답을 쓰세요'), findsNothing, reason: '답칸이 없다');
    expect(find.text('서술형'), findsWidgets);
    expect(find.byKey(const Key('submit')), findsNothing);

    await tester.tap(find.byKey(const Key('self-grade')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('스스로 채점'), findsWidgets);
    expect(find.text('- / 5점'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rubric-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('rubric-2')));
    await tester.pump();
    expect(find.text('3 / 5점'), findsOneWidget);
    await tester.tap(find.byKey(const Key('essay-confirm')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));

    final a = app.attempts.last;
    expect(a.answer, '3/5점');
    expect(a.correct, isFalse);
    expect(app.stateOf(p.id).inWrongNote, isTrue, reason: '만점이 아니면 오답노트로');
    expect(find.byKey(const Key('grade-result')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
