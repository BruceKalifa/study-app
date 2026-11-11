import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_app/app/app_state.dart';
import 'package:study_app/app/storage.dart';
import 'package:study_app/app/theme.dart';
import 'package:study_app/core/problem_bank.dart';
import 'package:study_app/core/problem.dart';
import 'package:study_app/pdf/pdf_store.dart';
import 'package:study_app/pdf/pdf_view.dart';
import 'package:study_app/screens/concept_book_screen.dart';
import 'package:study_app/screens/solve_screen.dart';
import 'package:study_app/services/content_import.dart';
import 'package:study_app/widgets/problem_card.dart';

/// 그리는 대신 회색 그림을 돌려주고, 부른 내용을 적어 둔다.
class _FakeRaster implements PdfRasterizer {
  final calls = <(String, int, PdfBox, double)>[];

  @override
  Future<ui.Image?> render(String doc, int page, PdfBox rect, double pxPerPt) async {
    calls.add((doc, page, rect, pxPerPt));
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 8, 8), ui.Paint()..color = const ui.Color(0xFFCCCCCC));
    return rec.endRecording().toImageSync(8, 8);
  }
}

const _region = {
  'doc': 'flow1-abc123',
  'page': 4,
  'rect': [40, 44, 292, 256],
  'choices': [
    [44, 240, 52, 248],
    [94, 240, 102, 248],
    [144, 240, 152, 248],
    [194, 240, 202, 248],
    [244, 240, 252, 248],
  ],
};

Map<String, dynamic> _bundle() => {
      'format': 'pulinote-bundle',
      'version': 1,
      'id': 'pdf-book',
      'title': 'PDF 교재',
      'pdfs': {'flow1-abc123': base64Encode(utf8.encode('%PDF-1.4 fake'))},
      'courses': [
        {
          'subject': '수학Ⅱ',
          'subjectId': 'math2pdf',
          'grades': ['대학생'],
          'problems': [
            {'id': 'q1', 'type': 'choice', 'stem': '정수 a 에 대하여 …', 'answer': '3', 'pdf': _region},
          ],
          'concepts': [
            {
              'id': 'c1',
              'title': 'I-1 물체의 운동',
              'body': '',
              'pdf': {
                'doc': 'flow1-abc123',
                'pages': [3, 4],
                'sizes': [
                  [595.28, 841.89],
                  [595.28, 841.89]
                ],
                'examples': [
                  {'page': 3, 'rect': [34, 224, 290, 450], 'problem': 'q1'}
                ],
              },
            }
          ],
        }
      ],
      'workbooks': [
        {'id': 'pdf-book', 'title': 'PDF 교재', 'course': 'math2pdf', 'problems': ['q1'], 'concepts': ['c1']}
      ],
    };

void main() {
  group('원본 PDF 교재', () {
    test('문항의 PDF 영역·개념의 쪽이 JSON 으로 오가고, 선지 수는 PDF 선지 자리 수', () {
      final p = Problem.fromJson({'id': 'q1', 'type': 'choice', 'stem': 's', 'answer': '3', 'pdf': _region},
          subjectId: 'm', subjectName: '수학');
      expect(p.pdf!.page, 4);
      expect(p.pdf!.rect, const PdfBox(40, 44, 292, 256));
      expect(p.choiceCount, 5);
      final back = Problem.fromJson(p.toJson(), subjectId: 'm', subjectName: '수학');
      expect(back.pdf!.toJson(), p.pdf!.toJson());
      expect(Problem.fromJson({'id': 'x', 'stem': 's', 'answer': '1', 'pdf': {'doc': '', 'page': 1, 'rect': [0, 0, 1, 1]}},
              subjectId: 'm', subjectName: '수학')
          .pdf, isNull, reason: '잘못된 영역은 무시');

      final c = Concept.fromJson((_bundle()['courses'] as List).first['concepts'][0] as Map<String, dynamic>);
      expect(c.pdf!.pages, [3, 4]);
      expect(c.pdf!.sizeOf(1).$2, closeTo(841.89, 0.01));
      expect(c.pdf!.examples.single.problem, 'q1');
      expect(Concept.fromJson(c.toJson()).pdf!.toJson(), c.pdf!.toJson());
    });

    test('교재를 넣으면 원본 PDF 를 따로 두고, 다시 묶을 때도 함께 간다', () async {
      final st = MemoryStorage();
      PdfStore.instance = PdfStore(st);
      final imp = ContentImport(st);
      await imp.add(gzip.encode(utf8.encode(jsonEncode(_bundle()))));
      expect(utf8.decode((await PdfStore.instance!.bytes('flow1-abc123'))!), '%PDF-1.4 fake');
      expect(await PdfStore.instance!.bytes('없음'), isNull);
      final again = ContentImport.decode((await imp.fileFor(['pdf-book']))!);
      expect((again['pdfs'] as Map).containsKey('flow1-abc123'), isTrue);
    });

    testWidgets('문제지: PDF 영역을 그리고, PDF 에 찍힌 선지 자리를 누르면 그 번호', (tester) async {
      final fake = _FakeRaster();
      PdfRasterizer.current = fake;
      addTearDown(() => PdfRasterizer.current = PdfiumRasterizer());
      final p = Problem.fromJson({'id': 'q1', 'type': 'choice', 'stem': 's', 'answer': '3', 'pdf': _region},
          subjectId: 'm', subjectName: '수학');
      final keys = ExamSheetKeys();
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProblemSheet(problem: p, number: 1, color: Colors.blue, keys: keys, selectedChoice: 2),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PdfRegionView), findsOneWidget);
      expect(fake.calls, isNotEmpty, reason: 'PDF 를 그렸다');
      final c = fake.calls.last;
      expect((c.$1, c.$2, c.$3), ('flow1-abc123', 4, const PdfBox(40, 44, 292, 256)));
      expect(c.$4, greaterThan(1), reason: '화면 크기에 맞춰 1pt 보다 크게');
      // 선지 자리 → 번호
      final r3 = keys.rectOf(keys.choices[2])!;
      expect(keys.choiceAt(r3.center, p.choiceCount), 3);
      final r1 = keys.rectOf(keys.choices[0])!;
      expect(keys.choiceAt(r1.center, p.choiceCount), 1);
      expect(r1.left, lessThan(r3.left), reason: 'PDF 에서처럼 왼쪽부터');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('개념책: 태블릿 가로는 두 쪽 펼침, 다시 볼래·이해했어요, 예제는 일반 풀이 화면으로', (tester) async {
      PdfRasterizer.current = _FakeRaster();
      addTearDown(() => PdfRasterizer.current = PdfiumRasterizer());
      tester.view.physicalSize = const Size(2960, 1848);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final s = (await tester.runAsync(() async {
        final st = AppState(
            storage: MemoryStorage(), baseBank: ProblemBank(const []), enableLive: false, autoSyncBooks: false);
        await st.init();
        await st.importBooks(gzip.encode(utf8.encode(jsonEncode(_bundle()))));
        return st;
      }))!;
      final concepts = s.bank.conceptsOf(s.bank.workbook('pdf-book')!);
      expect(concepts.single.pdf, isNotNull);
      await tester.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(theme: AppTheme.light(), home: ConceptBookScreen(concepts: concepts)),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(PdfRegionView), findsNWidgets(2), reason: '3·4쪽 펼침');
      expect(find.text('3–4쪽'), findsOneWidget);
      expect(find.text('풀어 보기'), findsOneWidget, reason: '3쪽 예제에 단추');
      await tester.tap(find.byKey(const Key('book-review')));
      await tester.pump();
      expect(s.isConceptReview('c1'), isTrue);
      await tester.tap(find.byKey(const Key('book-understood')));
      await tester.pump();
      expect(s.isConceptRead('c1'), isTrue);
      expect(s.isConceptReview('c1'), isFalse, reason: '이해했으면 다시 볼래는 내린다');
      // 목차 → 예제만 모아 풀기 = 일반 풀이 화면
      await tester.tap(find.byKey(const Key('book-toc')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('toc-c1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('book-all-examples')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.byType(SolveScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
