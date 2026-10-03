# 문제 데이터 형식 (assets/problems/*.json)

각 파일은 하나의 과목이며 다음 구조를 가진다.

```json
{
  "subject": "물리학Ⅰ",
  "subjectId": "phy1",
  "color": "#3B6FE0",
  "problems": [ ...Problem... ]
}
```

## Problem

| 필드 | 형식 | 설명 |
|---|---|---|
| `id` | string | 전체에서 유일. 예: `phy1-mech-001` |
| `unit` | string | 대단원. 예: `역학과 에너지` |
| `topic` | string | 소단원/유형. 예: `등가속도 직선 운동` |
| `difficulty` | 1~5 | 1 쉬움 ~ 5 킬러 |
| `type` | `"choice"` 또는 `"short"` | 5지선다 / 단답형(수치) |
| `stem` | string | 문제 본문. 수식은 `$...$` 안에만 LaTeX. 줄바꿈은 `\n` |
| `boxItems` | string[] (선택) | `<보기>` 상자 항목. 예: `["ㄱ. ...", "ㄴ. ...", "ㄷ. ..."]` |
| `choices` | string[5] | `choice`형 필수. 선택지 본문(번호 없이) |
| `answer` | string | `choice`형: 정답 번호 `"1"`~`"5"`. `short`형: 정답 값(예: `"12"`, `"-3/2"`, `"2.5"`) |
| `answerUnit` | string (선택) | 단답형 단위 표시(예: `m/s`). 학생은 숫자만 입력 |
| `tolerance` | number (선택) | 단답형 허용 오차(절대값). 기본 0 (정확히 일치, 분수·소수 동치 허용) |
| `solution` | string | 해설. `$...$` 사용 가능 |
| `hint` | string (선택) | 힌트 한 줄 |
| `tags` | string[] (선택) | 검색용 태그 |
| `template` | Template (선택) | 있으면 이 문제의 **변형문제**를 자동 생성 |

## Template (변형문제)

```json
"template": {
  "params": {
    "a": { "min": 1, "max": 5, "step": 1 },
    "t": { "values": [2, 3, 4, 5] }
  },
  "require": ["a*t - 3"],
  "stem": "정지해 있던 물체가 가속도 $[[a]]\\,\\text{m/s}^2$ 으로 [[t]]초 동안 운동했다. 이동 거리는?",
  "answer": "0.5*a*t^2",
  "round": 1,
  "choiceExprs": ["0.5*a*t^2", "a*t^2", "a*t", "0.5*a*t", "2*a*t^2"],
  "choiceFormat": "[[v]] m",
  "solution": "$s=\\frac{1}{2}at^2=\\frac{1}{2}\\times [[a]]\\times [[t]]^2=[[=0.5*a*t^2]]\\,\\text{m}$"
}
```

- `params`: 이름 → `{min,max,step}` 또는 `{values:[...]}`. 이름은 영문 소문자/숫자.
- `require`(선택): 식 목록. **모든 식이 0보다 커야** 그 매개변수 조합을 채택(최대 200회 재시도).
- `stem`, `solution`, `hint`: `[[이름]]` 은 매개변수 값, `[[=식]]` 은 계산 결과(소수 셋째 자리까지, 불필요한 0 제거)로 치환된다. `$...$` 안에서도 치환된다. 치환 값이 음수일 수 있으면 괄호를 직접 써라.
- `answer`: 정답 식.
- `round`(선택): 정답을 소수 몇째 자리까지 반올림해 표시할지. 채점 허용오차는 `10^-round`.
- `choiceExprs`(선택): 원본이 `choice`형이면 필수. 5개 식, **첫 번째가 정답 식과 같은 값**이어야 한다(나머지는 오답 유도용). 앱이 섞어서 배치하고 값이 겹치면 자동 보정한다.
- `choiceFormat`(선택): 선택지 표시 형식. `[[v]]` 자리에 계산된 숫자(round 적용). 예: `"[[v]] m/s"`. 기본 `"[[v]]"`.

### 식 문법 (앱의 계산기와 tools/validate_problems.py 가 동일하게 해석)

- 숫자, 매개변수 이름, `+ - * / ^`, 괄호, 단항 `-`
- 함수: `sqrt(x)`, `abs(x)`, `sin(x)`, `cos(x)`, `tan(x)` (**각도는 도(degree) 단위**), `log(x)` (상용로그), `ln(x)`, `exp(x)`, `min(a,b)`, `max(a,b)`, `round(x,n)`, `floor(x)`, `ceil(x)`
- 상수: `pi`, `e`
- `^` 는 오른쪽 결합, 단항 `-` 보다 우선 (`-2^2 = -4`)

## LaTeX 사용 규칙 (flutter_math_fork 로 렌더링)

- 한글은 `$...$` **밖에** 쓴다. `\text{}` 안에는 영문/숫자/단위만.
- 사용 가능: `\frac \sqrt ^ _ \times \cdot \div \pm \le \ge \ne \approx \theta \alpha \beta \lambda \omega \Delta \pi \mu \rho \sigma \circ \vec \overline \text \left( \right) \infty \sum \int \lim \log \sin \cos \tan`
- 사용 금지: `\begin{...}` 환경, `\\` 줄바꿈, 그림.
- JSON 이므로 역슬래시는 두 번 (`\\frac`).
