// A made-up textbook in the format tools/tex_book.py writes (.pulinote) — for tests and screenshots.
// (Real textbooks are private and never go into this repository.)
import 'dart:convert';
import 'dart:io' show gzip;

const String sampleFigure = '<svg xmlns="http://www.w3.org/2000/svg" width="110.7" height="82.4" viewBox="-55.35 -72.36 110.71 82.36"><path d="M -45.35 0.00 L 45.35 0.00 L 45.35 -62.36 L -45.35 -62.36 Z" fill="none" stroke="#000" stroke-width="0.5"/><circle cx="-28.35" cy="-17.01" r="8.22" fill="#fff" stroke="#000" stroke-width="0.4"/><text x="-28.35" y="-14.21" font-size="8.0" text-anchor="middle" font-family="serif" fill="#000">1</text><circle cx="-5.67" cy="-17.01" r="8.22" fill="#fff" stroke="#000" stroke-width="0.4"/><text x="-5.67" y="-14.21" font-size="8.0" text-anchor="middle" font-family="serif" fill="#000">2</text><circle cx="17.01" cy="-17.01" r="8.22" fill="#fff" stroke="#000" stroke-width="0.4"/><text x="17.01" y="-14.21" font-size="8.0" text-anchor="middle" font-family="serif" fill="#000">3</text><circle cx="-14.17" cy="-39.69" r="8.22" fill="#000" stroke="#000" stroke-width="0.4"/><text x="-14.17" y="-36.89" font-size="8.0" text-anchor="middle" font-family="serif" fill="white">4</text><circle cx="11.34" cy="-41.10" r="8.22" fill="#000" stroke="#000" stroke-width="0.4"/><text x="11.34" y="-38.30" font-size="8.0" text-anchor="middle" font-family="serif" fill="white">5</text></svg>';

Map<String, dynamic> sampleBookJson() => {
      'format': 'pulinote-bundle',
      'version': 1,
      'id': 'sample-type-01',
      'title': 'SAMPLE TYPE 1회차',
      'courses': [
        {
          'subject': '수학',
          'subjectId': 'math',
          'color': '#E0703B',
          'group': 'math',
          'level': 'high',
          'problems': [
            {
              'id': 'sample-type-01-cls-1',
              'unit': '수열',
              'topic': '예제',
              'difficulty': 4,
              'type': 'short',
              'stem': '수열 \$\\{a_n\\}\$이 다음 조건을 만족시킨다.\n[[box]]\n(가) \$a_1=3\$\n(나) 모든 자연수 \$n\$에 대하여\n'
                  '\$\$a_{n+1}=\\begin{cases} a_n+2 & (a_n\\text{이 홀수}) \\\\ \\dfrac{a_n}{2} & (a_n\\text{이 짝수})\\end{cases}\$\$\n'
                  '이다.\n[[/box]]\n\$a_{10}\$의 값을 구하시오.',
              'answer': '21',
              'solution': '\$a_1=3\$이 홀수이므로 \$a_2=5\$이고, 홀수에 \$2\$를 더하면 다시 홀수이다.\n'
                  '\$\$a_n=2n+1\\quad(n\\ge1)\$\$\n따라서 \$a_{10}=21\$이다.',
              'label': '예제',
              'source': '풀이노트 예시 문항',
              'texStyle': true,
              'points': 0,
            },
          ],
        },
        {
          'subject': '수학',
          'subjectId': 'math',
          'color': '#E0703B',
          'group': 'math',
          'level': 'high',
          'problems': [
            {
              'id': 'sample-type-01-cls-2',
              'unit': '확률',
              'topic': '심화',
              'difficulty': 5,
              'type': 'short',
              'stem': '상자에 숫자 1, 2, 3이 하나씩 적힌 흰 공 3개와 숫자 4, 5가 하나씩 적힌 검은 공 2개가 들어 있다. '
                  '이 상자에서 임의로 2개의 공을 동시에 꺼낼 때, 꺼낸 두 공이 서로 같은 색일 확률이 \$\\dfrac{q}{p}\$이다. '
                  '\$p+q\$의 값을 구하시오. (단, \$p\$와 \$q\$는 서로소인 자연수이다.)\n'
                  '[[center]]\n[[svg]]$sampleFigure[[/svg]]\n[[/center]]',
              'answer': '7',
              'solution': '전체 경우의 수는 \${}_5\\mathrm{C}_2=10\$이다.\n'
                  '[[box]]\n흰 공 두 개: \${}_3\\mathrm{C}_2=3\$\n검은 공 두 개: \${}_2\\mathrm{C}_2=1\$\n[[/box]]\n'
                  '\$\$\\frac{3+1}{10}=\\frac{2}{5}\$\$\n따라서 \$p+q=7\$이다.',
              'label': '심화',
              'labelAccent': true,
              'texStyle': true,
              'points': 0,
            },
          ],
        },
      ],
      'workbooks': [
        {
          'id': 'sample-type-01',
          'title': 'SAMPLE TYPE 1회차',
          'course': 'math',
          'stage': 'N제',
          'scope': '수학Ⅰ 수열 · 확률과 통계 확률',
          'level': '심화',
          'publisher': '풀이노트',
          'series': 'SAMPLE TYPE',
          'desc': '교재 파일 예시',
          'problems': ['sample-type-01-cls-1', 'sample-type-01-cls-2'],
        },
      ],
    };

/// The bundle as a `.pulinote` file (gzip JSON).
List<int> sampleBookFile() => gzip.encode(utf8.encode(jsonEncode(sampleBookJson())));
