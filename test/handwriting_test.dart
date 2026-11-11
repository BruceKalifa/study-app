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

    // 글자 높이 ≈ 40 으로 "-3i+45" 를 쓴 획들
    List<InkStroke> minus3iPlus45() => [
          st('m', [[0, 40], [18, 41]], 0),
          st('3', [[28, 20], [45, 24], [32, 38], [46, 50], [28, 60]], 1),
          st('i', [[55, 35], [56, 60]], 2),
          st('dot', [[55, 26], [56, 27]], 3),
          st('ph', [[68, 42], [92, 41]], 4),
          st('pv', [[80, 29], [81, 54]], 5),
          st('4a', [[104, 20], [100, 45], [122, 45]], 6),
          st('4b', [[116, 30], [116, 60]], 7),
          st('5a', [[145, 20], [132, 22], [132, 38], [148, 42], [146, 58], [130, 60]], 8),
          st('5b', [[133, 19], [150, 19]], 9),
        ];

    test('+ · − · i 는 획 모양으로 찾고 숫자 덩어리만 따로 읽는다 (-3i+45)', () {
      final t = Handwriting.tokenize(minus3iPlus45())!;
      expect(t.map((e) => e.toString()).toList(), ['-', '[3]', 'i', '+', '[4a,4b,5a,5b]']);
      // 숫자 답이면 i 를 찾지 않는다 (점+세로획은 숫자 덩어리로)
      final n = Handwriting.tokenize(minus3iPlus45(), findI: false)!;
      expect(n.map((e) => e.toString()).toList(), ['-', '[3,i,dot]', '+', '[4a,4b,5a,5b]']);
      expect(Handwriting.combineParts([['-'], ['3', '8'], ['i'], ['+'], ['45', '4S']]).first, '-3i+45');
      expect(Handwriting.combineParts([['-'], ['3', '8'], ['i'], ['+'], ['45', '46']]),
          containsAllInOrder(['-3i+45', '-8i+45']));
      final ranked = Handwriting.rank([
        ...Handwriting.combineParts([['-'], ['3'], ['i'], ['+'], ['45']]),
        '-31+45',
      ], shape: AnswerShape.complex);
      expect(ranked.first, '-3i+45');
      final p = Problem(id: 'z', subjectId: 'math', subjectName: '수학', stem: 'q', answer: '45-3i');
      expect(Grader.grade(p, ranked.first).correct, isTrue);
      expect(Grader.grade(p, '-31+45').correct, isFalse);
    });

    test('− 로 착각하지 않는 수평 획: 5 의 윗줄, 7 의 가로줄, √ 지붕, 밑줄 / = 는 =', () {
      // 5 의 윗줄만 있는 답 "5" → 부호 없음
      final five = minus3iPlus45().where((s) => s.id.startsWith('5')).toList();
      expect(Handwriting.tokenize(five), isNull);
      // 7 + 가로줄
      final seven = [st('7', [[0, 20], [20, 20], [8, 60]], 0), st('bar', [[4, 40], [18, 40]], 1)];
      expect(Handwriting.tokenize(seven), isNull);
      // 답 밑에 그은 밑줄
      final under = [...five, st('u', [[125, 66], [155, 66]], 10)];
      expect(Handwriting.tokenize(under), isNull);
      // = 3
      final eq = [st('e1', [[0, 34], [20, 34]], 0), st('e2', [[0, 46], [20, 46]], 1),
        st('3', [[28, 20], [45, 24], [32, 38], [46, 50], [28, 60]], 2)];
      expect(Handwriting.tokenize(eq)!.map((e) => e.toString()).toList(), ['=', '[3]']);
      expect(Handwriting.cleanAnswer(Handwriting.combineParts([['='], ['3']]).first, shape: AnswerShape.numeric), '3');
      // 1 - 2
      final oneMinusTwo = [st('1', [[5, 20], [5, 60]], 0), st('m', [[15, 40], [30, 40]], 1),
        st('2', [[38, 25], [50, 20], [52, 35], [38, 60], [55, 60]], 2)];
      expect(Handwriting.tokenize(oneMinusTwo)!.map((e) => e.toString()).toList(), ['[1]', '-', '[2]']);
      // -i
      final minusI = [st('m', [[0, 40], [15, 40]], 0), st('i', [[25, 30], [25, 58]], 1), st('d', [[25, 20], [26, 21]], 2)];
      expect(Handwriting.tokenize(minusI)!.map((e) => e.toString()).toList(), ['-', 'i']);
    });

    test('분수 후보가 한 줄로 읽은 것보다 앞', () {
      final combos = Handwriting.combineFraction([''], ['3', 'B'], ['4'], ['']);
      expect(Handwriting.rank([...combos, '34'], shape: AnswerShape.numeric).first, '3/4');
    });
  });
}
