import 'package:flutter_test/flutter_test.dart';
import 'package:study_app/ink/ink_model.dart';
import 'package:study_app/core/grader.dart';
import 'package:study_app/core/problem.dart';
import 'package:study_app/services/handwriting.dart';

void main() {
  group('필기 읽기: 정답 모양에 맞게', () {
    test('정답이 어떻게 생겼는지 (값이 아니라 모양만)', () {
      expect(Handwriting.shapeOf('3/2'), AnswerShape.numeric);
      expect(Handwriting.shapeOf('-2√3'), AnswerShape.numeric);
      expect(Handwriting.shapeOf('5π'), AnswerShape.numeric);
      expect(Handwriting.shapeOf('2+i'), AnswerShape.complex);
      expect(Handwriting.shapeOf('-3i'), AnswerShape.complex);
      expect(Handwriting.shapeOf('(1+i)/2'), AnswerShape.complex);
      expect(Handwriting.shapeOf('x>3'), AnswerShape.other);
      expect(Handwriting.shapeOf('[1,2)'), AnswerShape.other);
    });

    test('허수단위 i 가 숫자 1 로 바뀌지 않는다', () {
      expect(Handwriting.cleanAnswer('2+i', shape: AnswerShape.complex), '2+i');
      expect(Handwriting.cleanAnswer('1-2i', shape: AnswerShape.complex), '1-2i');
      expect(Handwriting.cleanAnswer('3i'), '3i', reason: '모양을 모를 때도 i 는 그대로');
      // l / I / | 로 읽혀 와도 복소수 답이면 i 가 앞선 후보
      expect(Handwriting.rank(['2+l'], shape: AnswerShape.complex).first, '2+i');
      expect(Handwriting.rank(['3-I'], shape: AnswerShape.complex).first, '3-i');
      expect(Handwriting.rank(['2+l'], shape: AnswerShape.complex), contains('2+1'));
      expect(Handwriting.rank(['2+i'], shape: AnswerShape.complex).first, '2+i');
    });

    test('복소수 후보를 채점기가 읽는다', () {
      final c = Handwriting.rank(['1+2l'], shape: AnswerShape.complex).first;
      expect(c, '1+2i');
      final p = Problem(id: 'c', subjectId: 'math', subjectName: '수학', stem: 'q', answer: '1+2i');
      expect(Grader.grade(p, c).correct, isTrue);
    });

    test('숫자 답은 글자로 읽힌 것을 숫자로', () {
      expect(Handwriting.cleanAnswer('l2', shape: AnswerShape.numeric), '12');
      expect(Handwriting.cleanAnswer('S', shape: AnswerShape.numeric), '5');
      expect(Handwriting.cleanAnswer('3O', shape: AnswerShape.numeric), '30');
      expect(Handwriting.cleanAnswer('Zl', shape: AnswerShape.numeric), '21');
      expect(Handwriting.cleanAnswer('l2A', shape: AnswerShape.numeric), '124');
      expect(Handwriting.cleanAnswer('3i', shape: AnswerShape.numeric), '31');
      expect(Handwriting.cleanAnswer('V3', shape: AnswerShape.numeric), '√3');
      expect(Handwriting.cleanAnswer('2V3', shape: AnswerShape.numeric), '2√3');
      expect(Handwriting.cleanAnswer('3TT', shape: AnswerShape.numeric), '3π');
    });

    test('후보 순서: 정답 모양에 맞는 후보가 앞', () {
      // 인식기 1순위가 글자 섞인 "S0", 2순위가 "50" 이어도 숫자 답이면 둘 다 "50" 으로 모인다
      expect(Handwriting.rank(['S0', '50'], shape: AnswerShape.numeric), ['50']);
      // 숫자로 안 읽히는 후보는 뒤로
      expect(Handwriting.rank(['x+', '12'], shape: AnswerShape.numeric).first, '12');
    });

    test('글자 답(그 밖)은 건드리지 않는다', () {
      expect(Handwriting.cleanAnswer('sqrt'), 'sqrt');
      expect(Handwriting.cleanAnswer('x>3'), 'x>3');
    });
  
    test('쉼표: 여러 값 답이면 그대로, 아니면 소수점', () {
      expect(Handwriting.cleanAnswer('1,3', shape: AnswerShape.numeric, keepComma: true), '1,3');
      expect(Handwriting.cleanAnswer('0,5', shape: AnswerShape.numeric), '0.5');
      expect(Handwriting.shapeOf('-2,5'), AnswerShape.numeric);
      expect(Handwriting.isListAnswer('-2,5'), isTrue);
      expect(Handwriting.rank(['l,3'], shape: AnswerShape.numeric, list: true).first, '1,3');
    });

    test('군더더기: 끝 마침표·앞의 = 는 뺀다', () {
      expect(Handwriting.cleanAnswer('12.', shape: AnswerShape.numeric), '12');
      expect(Handwriting.cleanAnswer('=12', shape: AnswerShape.numeric), '12');
      expect(Handwriting.cleanAnswer('1.5', shape: AnswerShape.numeric), '1.5');
    });

    InkStroke st(String id, List<List<double>> pts, int at) => InkStroke(
        id: id, tool: InkTool.pen, color: 0xFF000000, width: 3, startedAt: at,
        points: [for (final p in pts) InkPoint(p[0], p[1], 0.5, 0)]);

    test('위아래로 쓴 분수를 나눈다 (− 부호 포함)', () {
      final minus = st('m', [[10, 60], [30, 60]], 0);
      final three = st('3', [[60, 20], [75, 25], [62, 35], [75, 45], [60, 50]], 1);
      final bar = st('bar', [[45, 60], [95, 61]], 2);
      final four = st('4', [[60, 70], [55, 85], [80, 85], [72, 72], [72, 100]], 3);
      final f = Handwriting.splitFraction([minus, three, bar, four])!;
      expect(f.numerator.map((s) => s.id), ['3']);
      expect(f.denominator.map((s) => s.id), ['4']);
      expect(f.before.map((s) => s.id), ['m']);
      expect(Handwriting.combineFraction(['-'], ['3'], ['4'], ['']).first, '-3/4');
      expect(Handwriting.combineFraction([''], ['1+√2'], ['3'], ['']).first, '(1+√2)/3');
      // 한 줄로 쓴 것 · = 는 분수가 아니다
      expect(Handwriting.splitFraction([three, four]), isNull);
      final eq1 = st('e1', [[10, 40], [40, 40]], 0), eq2 = st('e2', [[10, 50], [40, 50]], 1);
      expect(Handwriting.splitFraction([eq1, eq2, three]), isNull);
    });

    test('분수 후보가 한 줄로 읽은 것보다 앞', () {
      final combos = Handwriting.combineFraction([''], ['3', 'B'], ['4'], ['']);
      expect(Handwriting.rank([...combos, '34'], shape: AnswerShape.numeric).first, '3/4');
    });
  });
}
