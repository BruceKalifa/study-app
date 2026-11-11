import 'package:flutter_math_fork/tex.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_app/widgets/math_text.dart';

bool _parses(String tex) {
  try {
    TexParser(tex, const TexParserSettings()).parse();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  group('수식 고치기', () {
    test('^(…) 는 위첨자 묶음으로 (tan^(-1) → \\tan^{-1})', () {
      expect(MathText.fixTex(r'tan^(-1)x'), r'\tan^{-1}x');
      expect(MathText.fixTex(r'\sin^(-1)(x)'), r'\sin^{-1}(x)');
      expect(MathText.fixTex(r'e^(2x+1)'), r'e^{2x+1}');
      expect(MathText.fixTex(r'y^(4)+y=0'), r'y^{(4)}+y=0', reason: 'n계 도함수 표기는 괄호를 살린다');
      expect(MathText.fixTex(r'a_(n+1)'), r'a_{n+1}');
      expect(MathText.fixTex(r'\tan^{-1}x'), r'\tan^{-1}x', reason: '바른 것은 그대로');
      expect(MathText.fixTex(r'\text{using}^2'), r'\text{using}^2');
      expect(MathText.fixTex(r'U_x=V_y \tag{1}'), r'U_x=V_y \qquad(1)');
      expect(MathText.fixTex(r'\left( x'), r'( x');
    });

    test('\$ 밖에 글자로 쓴 첨자 수식도 수식으로', () {
      expect(MathText.asciiMath('역함수 tan^(-1) 의 정의역'), [(false, '역함수 '), (true, r'\tan^{-1}'), (false, ' 의 정의역')]);
      expect(MathText.asciiMath('x^2 + 1'), [(true, 'x^2'), (false, ' + 1')]);
      expect(MathText.asciiMath('no math here'), [(false, 'no math here')]);
    });

    test('목록·미리보기 글자: 함수 이름은 남기고 첨자는 위·아래 글자', () {
      expect(MathText.plain(r'$\tan^{-1}x$'), 'tan⁻¹x');
      expect(MathText.plain(r'$\sin^(-1) x$'), 'sin⁻¹ x');
      expect(MathText.plain(r'$x^2+a_1$'), 'x²+a₁');
      expect(MathText.plain(r'$\operatorname{Arg} z$'), 'Arg z');
    });

    test('고친 수식은 실제로 그려진다', () {
      for (final t in [r'tan^(-1)x', r'U_x=V_y,\qquad U_y=-V_x. \tag{1}', r'y^(4)']) {
        expect(_parses(MathText.fixTex(t)), isTrue, reason: t);
      }
    });
  });
}
