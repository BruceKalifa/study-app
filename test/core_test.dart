import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_app/core/expr.dart';
import 'package:study_app/core/format.dart';
import 'package:study_app/core/grader.dart';
import 'package:study_app/core/problem.dart';
import 'package:study_app/core/problem_bank.dart';
import 'package:study_app/core/variants.dart';

ProblemTemplate _template({bool choice = false}) => ProblemTemplate(
      params: const <String, ParamSpec>{
        'a': ParamSpec(min: 1, max: 5, step: 1),
        't': ParamSpec(values: <double>[2, 3, 4, 5]),
      },
      require: const <String>['a*t - 3'],
      stem: r'a=[[a]], t=[[t]]. 가속도 $[[a]]\,\text{m/s}^2$ 으로 [[t]]초 동안 운동했다.',
      answer: '0.5*a*t^2',
      round: 1,
      choiceExprs: choice
          ? const <String>[
              '0.5*a*t^2',
              'a*t^2',
              'a*t',
              '0.5*a*t',
              '2*a*t^2',
            ]
          : null,
      choiceFormat: '[[v]] m',
      solution: r'$s=\frac{1}{2}at^2=[[=0.5*a*t^2]]\,\text{m}$',
      hint: 's = (1/2)·[[a]]·[[t]]²',
    );

Problem _shortBase() => Problem(
      id: 'phy1-mech-001',
      subjectId: 'phy1',
      subjectName: '물리학Ⅰ',
      unit: '역학과 에너지',
      topic: '등가속도 직선 운동',
      stem: r'가속도 $2\,\text{m/s}^2$ 으로 3초 동안 운동했다. 이동 거리는?',
      answer: '9',
      answerUnit: 'm',
      solution: r'$s=\frac{1}{2}at^2=9\,\text{m}$',
      difficulty: 2,
      type: ProblemType.short,
      tags: const <String>['등가속도'],
      template: _template(),
    );

Problem _choiceBase() => Problem(
      id: 'phy1-mech-002',
      subjectId: 'phy1',
      subjectName: '물리학Ⅰ',
      unit: '역학과 에너지',
      topic: '등가속도 직선 운동',
      stem: '이동 거리는?',
      answer: '1',
      solution: '해설',
      difficulty: 3,
      type: ProblemType.choice,
      choices: const <String>['9 m', '18 m', '6 m', '3 m', '36 m'],
      boxItems: const <String>['ㄱ. a=[[a]]', 'ㄴ. 고정'],
      template: _template(choice: true),
    );

Problem _short(String answer, {String? unit, double tolerance = 0}) => Problem(
      id: 's-$answer',
      subjectId: 'math',
      subjectName: '수학',
      stem: 'q',
      answer: answer,
      answerUnit: unit,
      tolerance: tolerance,
    );

void main() {
  group('Expr', () {
    test('vectors', () {
      expect(Expr.eval('2+3*4'), 14);
      expect(Expr.eval('-2^2'), -4);
      expect(Expr.eval('2^3^2'), 512);
      expect(Expr.eval('sqrt(16)+abs(-3)'), 7);
      expect(Expr.eval('sin(30)'), closeTo(0.5, 1e-9));
      expect(Expr.eval('cos(60)*2'), closeTo(1, 1e-9));
      expect(Expr.eval('log(1000)'), closeTo(3, 1e-9));
      expect(Expr.eval('ln(e)'), closeTo(1, 1e-9));
      expect(Expr.eval('round(3.14159,2)'), closeTo(3.14, 1e-12));
      expect(Expr.eval('min(3,max(1,2))'), 2);
      expect(Expr.eval('(1+2)*(3-5)/4'), -1.5);
      expect(Expr.eval('0.5*a*t^2', <String, double>{'a': 2, 't': 3}), 9);
      expect(Expr.eval('floor(2.7)+ceil(2.1)'), 5);
    });

    test('numbers and unary', () {
      expect(Expr.eval('.5'), 0.5);
      expect(Expr.eval('1e3'), 1000);
      expect(Expr.eval('2.5E-1'), 0.25);
      expect(Expr.eval('2^-1'), 0.5);
      expect(Expr.eval('--3'), 3);
      expect(Expr.eval('+4'), 4);
      expect(Expr.eval('pi'), closeTo(3.141592653589793, 1e-12));
      expect(Expr.eval('round(2.5)'), 3);
      expect(Expr.eval('round(-2.5)'), -3);
      expect(Expr.eval('round(1.005,2)'), closeTo(1.01, 1e-12));
      expect(Expr.eval('tan(45)'), closeTo(1, 1e-9));
      expect(Expr.eval('exp(0)'), 1);
    });

    test('errors', () {
      expect(() => Expr.eval('2+'), throwsA(isA<ExprError>()));
      expect(() => Expr.eval('(1+2'), throwsA(isA<ExprError>()));
      expect(() => Expr.eval('foo(1)'), throwsA(isA<ExprError>()));
      expect(() => Expr.eval('x+1'), throwsA(isA<ExprError>()));
      expect(() => Expr.eval('2 3'), throwsA(isA<ExprError>()));
      expect(() => Expr.eval(''), throwsA(isA<ExprError>()));
      expect(() => Expr.eval('3 # 4'), throwsA(isA<ExprError>()));
      expect(Expr.isValid('a*t+1'), isTrue);
      expect(Expr.isValid('a*'), isFalse);
      expect(Expr.isValid('sqrt(1,2)'), isFalse);
    });
  });

  group('format', () {
    test('fmtNum', () {
      expect(fmtNum(3.0), '3');
      expect(fmtNum(2.50), '2.5');
      expect(fmtNum(1 / 3), '0.333');
      expect(fmtNum(-0.0), '0');
      expect(fmtNum(-0.0001), '0');
      expect(fmtNum(-1.5), '-1.5');
      expect(fmtNum(2.0005), '2.001');
      expect(fmtNum(1234567.0), '1234567');
      expect(fmtNum(1 / 3, maxDecimals: 1), '0.3');
    });

    test('roundTo', () {
      expect(roundTo(2.5, 0), 3);
      expect(roundTo(-2.5, 0), -3);
      expect(roundTo(1.005, 2), closeTo(1.01, 1e-12));
      expect(roundTo(3.14159, 3), closeTo(3.142, 1e-12));
    });
  });

  group('variants', () {
    test('deterministic for the same seed', () {
      final base = _shortBase();
      final v1 = generateVariant(base, 42);
      final v2 = generateVariant(base, 42);
      expect(v1.toJson(), v2.toJson());
      expect(v1.id, 'phy1-mech-001~v42');
      expect(v1.variantOf, base.id);
      expect(v1.variantSeed, 42);
      expect(v1.isVariant, isTrue);
      expect(v1.hasTemplate, isFalse);
      expect(v1.tolerance, closeTo(0.1, 1e-12));
      expect(v1.stem.contains('[['), isFalse);
      expect(v1.solution.contains('[['), isFalse);
      expect(v1.hint, isNotNull);
      expect(v1.hint!.contains('[['), isFalse);
      expect(v1.answerUnit, 'm');
    });

    test('short answer matches parameters', () {
      final re = RegExp(r'a=(-?[\d.]+), t=(-?[\d.]+)\.');
      for (var seed = 1; seed <= 30; seed++) {
        final v = generateVariant(_shortBase(), seed);
        final m = re.firstMatch(v.stem);
        expect(m, isNotNull, reason: v.stem);
        final a = double.parse(m!.group(1)!);
        final t = double.parse(m.group(2)!);
        expect(a * t - 3, greaterThan(0));
        expect(double.parse(v.answer), closeTo(roundTo(0.5 * a * t * t, 1), 1e-9));
        expect(Grader.grade(v, fmtNum(0.5 * a * t * t)).correct, isTrue);
      }
    });

    test('choice variant: 5 unique choices, answer index points at choiceExprs[0]',
        () {
      final re = RegExp(r'a=(-?[\d.]+), t=(-?[\d.]+)\.');
      for (var seed = 1; seed <= 60; seed++) {
        final v = generateVariant(_choiceBase(), seed);
        expect(v.type, ProblemType.choice);
        expect(v.choices.length, 5);
        expect(v.choices.toSet().length, 5, reason: v.choices.join(' | '));
        final idx = int.parse(v.answer);
        expect(idx, inInclusiveRange(1, 5));
        final m = re.firstMatch(v.stem);
        expect(m, isNotNull);
        final a = double.parse(m!.group(1)!);
        final t = double.parse(m.group(2)!);
        final expected =
            Expr.eval('0.5*a*t^2', <String, double>{'a': a, 't': t});
        expect(v.choices[idx - 1], '${fmtNum(roundTo(expected, 1), maxDecimals: 1)} m');
        expect(v.boxItems.first, 'ㄱ. a=${fmtNum(a)}');
        expect(Grader.grade(v, '$idx').correct, isTrue);
      }
    });

    test('generateVariants gives distinct problems', () {
      final list = generateVariants(_shortBase(), 5, seedBase: 100);
      expect(list.length, 5);
      expect(list.map((p) => p.id).toSet().length, 5);
      expect(list.map((p) => p.stem).toSet().length, 5);
    });

    test('no template throws', () {
      expect(() => generateVariant(_short('1'), 1),
          throwsA(isA<VariantError>()));
    });
  });

  group('grader', () {
    test('choice', () {
      final p = Problem(
        id: 'c1',
        subjectId: 'x',
        subjectName: 'x',
        stem: 'q',
        answer: '3',
        type: ProblemType.choice,
        choices: const <String>['a', 'b', 'c', 'd', 'e'],
      );
      expect(Grader.grade(p, '③').correct, isTrue);
      expect(Grader.grade(p, '3').correct, isTrue);
      expect(Grader.grade(p, ' 3 ').correct, isTrue);
      expect(Grader.grade(p, '3번').correct, isTrue);
      expect(Grader.grade(p, '(3)').correct, isTrue);
      expect(Grader.grade(p, '2').correct, isFalse);
      expect(Grader.grade(p, '②').correct, isFalse);
      expect(Grader.grade(p, 'c').correct, isFalse);
      expect(Grader.grade(p, '').correct, isFalse);
    });

    test('short numeric', () {
      expect(Grader.grade(_short('-1.5'), '-3/2').correct, isTrue);
      expect(Grader.grade(_short('-3/2'), '-1.5').correct, isTrue);
      expect(Grader.grade(_short('sqrt(12)'), '2√3').correct, isTrue);
      expect(Grader.grade(_short('-1.5'), '−1.5').correct, isTrue);
      expect(Grader.grade(_short('-1.5'), '– 1.5').correct, isTrue);
      expect(Grader.grade(_short('12', unit: 'm/s'), '12m/s').correct, isTrue);
      expect(Grader.grade(_short('12', unit: 'm/s'), '12 m/s').correct, isTrue);
      expect(Grader.grade(_short('1200'), '1,200').correct, isTrue);
      expect(Grader.grade(_short('6'), '2×3').correct, isTrue);
      expect(Grader.grade(_short('2*pi'), '2π').correct, isTrue);
      expect(Grader.grade(_short('2.5', tolerance: 0.1), '2.45').correct, isTrue);
      expect(Grader.grade(_short('12'), '13').correct, isFalse);
      expect(Grader.grade(_short('-1.5'), '1.5').correct, isFalse);
      expect(Grader.grade(_short('12'), 'abc').correct, isFalse);
      expect(Grader.grade(_short('12'), '').correct, isFalse);
    });

    test('short non-numeric falls back to string compare', () {
      expect(Grader.grade(_short('ㄱ,ㄴ'), 'ㄱ, ㄴ').correct, isTrue);
      expect(Grader.grade(_short('ㄱ,ㄴ'), 'ㄱ, ㄷ').correct, isFalse);
    });

    test('normalize / parseNumber', () {
      expect(Grader.normalize('   '), isNull);
      expect(Grader.normalize('√3'), 'sqrt(3)');
      expect(Grader.normalize('2√3'), '2*sqrt(3)');
      expect(Grader.normalize('√(12)'), 'sqrt(12)');
      expect(Grader.normalize('2π'), '2*pi');
      expect(Grader.normalize('−3÷2'), '-3/2');
      expect(Grader.parseNumber('2√3'), closeTo(3.4641016151377544, 1e-12));
      expect(Grader.parseNumber('1e3'), 1000);
      expect(Grader.parseNumber('x'), isNull);
    });
  });

  group('model', () {
    test('Problem JSON round-trip', () {
      final p = _choiceBase().copyWith(
        hint: '힌트',
        tags: const <String>['t1', 't2'],
        custom: true,
        variantOf: 'base-1',
        variantSeed: 7,
        tolerance: 0.05,
      );
      final json = p.toJson();
      final decoded =
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
      final p2 =
          Problem.fromJson(decoded, subjectId: 'other', subjectName: 'other');
      expect(p2.toJson(), json);
      expect(p2.subjectId, 'phy1');
      expect(p2.subjectName, '물리학Ⅰ');
      expect(p2.variantOf, 'base-1');
      expect(p2.variantSeed, 7);
      expect(p2.custom, isTrue);
      expect(p2.type, ProblemType.choice);
      expect(p2.template, isNotNull);
      expect(p2.template!.choiceExprs!.length, 5);
      expect(p2.template!.params['t']!.values, <double>[2, 3, 4, 5]);
      expect(p2.template!.round, 1);
    });

    test('Subject.fromJson', () {
      final s = Subject.fromJson(<String, dynamic>{
        'subject': '물리학Ⅰ',
        'subjectId': 'phy1',
        'color': '#3B6FE0',
        'problems': <dynamic>[
          <String, dynamic>{
            'id': 'p1',
            'unit': 'B',
            'topic': 't',
            'difficulty': 2,
            'type': 'short',
            'stem': r'$x$',
            'answer': 3,
            'tolerance': 0,
            'solution': 's',
          },
          <String, dynamic>{
            'id': 'p2',
            'unit': 'A',
            'topic': 't',
            'difficulty': 1,
            'type': 'choice',
            'stem': 'q',
            'choices': <dynamic>['1', '2', '3', '4', '5'],
            'answer': '2',
            'solution': 's',
          },
          <String, dynamic>{
            'id': 'p3',
            'unit': 'B',
            'topic': 't',
            'difficulty': 1,
            'type': 'short',
            'stem': 'q',
            'answer': '2.5',
            'solution': 's',
          },
        ],
      });
      expect(s.id, 'phy1');
      expect(s.name, '물리학Ⅰ');
      expect(s.color, 0xFF3B6FE0);
      expect(s.units, <String>['B', 'A']);
      expect(s.problems.first.answer, '3');
      expect(s.problems.first.subjectId, 'phy1');
      expect(s.problems[1].type, ProblemType.choice);
    });

    test('ProblemBank byId resolves variants and withExtra', () {
      final base = _shortBase();
      final bank = ProblemBank(<Subject>[
        Subject(
            id: 'phy1',
            name: '물리학Ⅰ',
            color: 0xFF3B6FE0,
            problems: <Problem>[base]),
      ]);
      expect(bank.byId(base.id), same(base));
      final v = bank.byId('${base.id}~v9');
      expect(v, isNotNull);
      expect(v!.toJson(), generateVariant(base, 9).toJson());
      expect(bank.byId('nope'), isNull);
      expect(bank.byId('nope~v3'), isNull);

      final mine = _short('1').copyWith(
          id: 'my-1', subjectId: 'custom', subjectName: '', custom: true);
      final more = _short('2').copyWith(id: 'p-extra', subjectId: 'phy1');
      final bank2 = bank.withExtra(<Problem>[mine, more]);
      expect(bank2.subjects.length, 2);
      expect(bank2.subject('phy1')!.problems.length, 2);
      final custom = bank2.subject('custom')!;
      expect(custom.name, '내 문제');
      expect(custom.color, 0xFF5B6475);
      expect(bank2.byId('my-1'), isNotNull);
      expect(bank2.all.length, 3);
      expect(bank.all.length, 1);
    });
  });
}
