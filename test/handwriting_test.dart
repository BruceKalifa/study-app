import 'package:flutter_test/flutter_test.dart';
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
  });
}
