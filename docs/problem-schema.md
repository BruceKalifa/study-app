# 문제 데이터 형식 (assets/problems/*.json)

각 파일은 하나의 **과목(코스)** 이다. 예: 물리학Ⅰ, 수학Ⅰ, 중2 수학, 국어(독서), 영어, 통합사회, 인적성.
과목은 교과군(국어·수학·영어·사회·과학·인적성) 하나에 속한다. 고등학교 수학(`subjectId: math`)은 앱에서 항상 **고등수학** 으로 보인다(`수학` 이라고 적어도 바뀜 — 편입수학·대학수학·공업수학과 헷갈리지 않게).

```json
{
  "subject": "물리학Ⅰ",
  "subjectId": "phy1",
  "color": "#3B6FE0",
  "group": "sci",
  "level": "high",
  "grades": ["고2", "고3", "N수"],
  "track": "수능",
  "units": ["역학과 에너지", "물질과 전자기장", "파동과 정보 통신"],
  "passages": [ ...Passage... ],
  "problems": [ ...Problem... ]
}
```

| 필드 | 형식 | 설명 |
|---|---|---|
| `subject` | string | 과목 이름(화면 표시) |
| `subjectId` | string | 과목 id(전체에서 유일, 영문 소문자·숫자·`-`) |
| `color` | `#RRGGBB` | 과목 색 |
| `group` | `kor` `math` `eng` `soc` `sci` `apt` `univ` | 교과군: 국어·수학·영어·사회·과학·인적성·대학 |
| `level` | `mid` `high` | 중등 / 고등 |
| `grades` | string[] | 대상 학년. 값: `중1 중2 중3 고1 고2 고3 N수 취준 한양대 편입`. `취준`·`한양대`·`편입` 과정은 고등 학생 화면에 나오지 않는다. 학생은 여러 학년·과정을 함께 고를 수 있어, 하나라도 겹치면 보인다 |
| `track` | string (선택) | `수능` `내신` `공통` |
| `units` | string[] (선택) | 대단원 순서(문제집·무한 풀기 목록 순서). 없으면 문제에 나온 순서 |
| `passages` | Passage[] (선택) | 지문(국어·영어 지문형 문항용) |

## Passage (지문)

```json
{ "id": "kor-read-p01", "title": "정보 기술과 데이터 압축", "body": "첫 문단...\n\n둘째 문단..." }
```

- `id` 는 전체에서 유일. 문항의 `passageId` 로 연결. 한 지문에 여러 문항을 연결할 수 있다.
- `body` 는 아래 **본문 표기법**을 따른다. 문단은 빈 줄(`\n\n`)로 구분.
- `source`(선택): 출처 표시 한 줄.

## 본문 표기법 (stem · body · boxItems · choices · solution 공통)

- 수식: `$...$` 안에 LaTeX (아래 LaTeX 규칙)
- 굵게: `**굵게**`
- 밑줄: `__밑줄 친 부분__` (국어·영어 "밑줄 친 ㉠" 등)
- 표: `|` 로 시작하는 줄이 이어지면 표가 된다. 둘째 줄이 `|---|---|` 형태면 첫 줄은 머리글.
  ```
  | 구분 | 2020년 | 2025년 |
  |---|---|---|
  | 갑국 | 30 | 45 |
  | 을국 | 50 | 40 |
  ```
  칸 안에서도 수식·굵게·밑줄을 쓸 수 있다.
- 줄바꿈은 `\n`, 문단 구분은 `\n\n`.
- 블록 (한 줄에 하나씩, TeX 원문 교재를 옮길 때 `tools/tex_book.py` 가 쓴다):
  - `$$…$$` — 가운데 수식 줄 (TeX 의 `\[…\]`)
  - `[[box]]` … `[[/box]]` — 조건 상자 (안에 다른 표기 모두 사용 가능, 겹쳐도 됨)
  - `[[center]]` … `[[/center]]` — 가운데 정렬
  - `[[svg]]<svg …>[[/svg]]` — 그림. `width`/`height` 는 pt 단위(본문 9.2pt 기준으로 글자 크기에 맞춰 키움)
  - `[[cols:58:39]]` … `[[col]]` … `[[/cols]]` — 나란히 (비율). 예: 왼쪽 글, 오른쪽 표 (TeX 의 `\TextTable`)
  - 목록 항목은 `• ` 또는 `1. ` 로 시작하는 줄
  목록·미리보기에서는 그림은 `[그림]`, 상자는 그냥 글줄로 보인다.

## 문항 패밀리 (원본 + 쌍둥이 변형)

- 직접 만든 **쌍둥이(변형) 문항**은 `"twinOf": "원본 id"` 를 단다.
- 쌍둥이 문항은 문제집 목록·무한 풀기에는 나오지 않고, 원본을 틀렸을 때 **매일 오답 변형 세트**와 오답 복습에 나온다.
- 쌍둥이도 일반 문항과 같은 필드를 모두 가진다(같은 unit·topic 권장).
- `template` 자동 변형과 함께 쓸 수 있다. 오답 변형 세트는 쌍둥이 → 템플릿 변형 → 같은 유형(topic)의 다른 문항 순서로 고른다.

## 문제집 (assets/problems/workbooks.json)

```json
{
  "workbooks": [
    {
      "id": "wb-phy1-concept",
      "title": "물리학Ⅰ 개념 완성",
      "course": "phy1",
      "level": "기본",
      "desc": "교과 개념을 유형별로 한 바퀴",
      "problems": ["phy1-mech-001", "phy1-mech-002"]
    }
  ]
}
```

- `level`: `기본` `실전` `심화` `모의고사` 중 하나.
- `problems`: 문항 id 순서 그대로 풀게 된다. 쌍둥이 문항 id 는 넣지 않는다.

## Problem

| 필드 | 형식 | 설명 |
|---|---|---|
| `id` | string | 전체에서 유일. 예: `phy1-mech-001` |
| `unit` | string | 대단원. 예: `역학과 에너지` |
| `topic` | string | 유형(소단원). 예: `등가속도 직선 운동`. 약점 분석·오답 변형의 기준이 되므로 같은 유형은 같은 이름으로 |
| `section` | string (선택) | **교재 목차**. 예: `수업`, `DAY 1`. 교재를 목차별로 묶어 보여 주고 목차 단위로 풀게 한다. 없으면 `unit` 으로 묶는다 |
| `difficulty` | 1~5 | 1 쉬움 ~ 5 킬러 |
| `type` | `"choice"` 또는 `"short"` | 5지선다 / 단답형(수치·복소수·구간) |
| `stem` | string | 문제 본문. 수식은 `$...$` 안에만 LaTeX. 줄바꿈은 `\n` |
| `boxItems` | string[] (선택) | `<보기>` 상자 항목. 예: `["ㄱ. ...", "ㄴ. ...", "ㄷ. ..."]` |
| `choices` | string[5] | `choice`형 필수. 선택지 본문(번호 없이) |
| `answer` | string | `choice`형: 정답 번호 `"1"`~`"5"`. `short`형: 정답 값(예: `"12"`, `"-3/2"`, `"2.5"`) |
| `answerUnit` | string (선택) | 단답형 단위 표시(예: `m/s`). 학생은 숫자만 입력 |
| `tolerance` | number (선택) | 단답형 허용 오차(절대값). 기본 0 (정확히 일치, 분수·소수 동치 허용). 정답은 숫자·분수 외에 `3+2i`, `1±√2`, `[1,3)` 같은 꼴도 가능 |
| `solution` | string | 해설. `$...$` 사용 가능 |
| `hint` | string (선택) | 힌트 한 줄 |
| `tags` | string[] (선택) | 검색용 태그 |
| `template` | Template (선택) | 있으면 이 문제의 **변형문제**를 자동 생성 |
| `passageId` | string (선택) | 지문형 문항이면 연결할 지문 id |
| `twinOf` | string (선택) | 쌍둥이(변형) 문항이면 원본 문항 id |
| `label` | string (선택) | 교재 머리표 (예: `기출문제`, `변형`, `심화`, `숙제 1 (중)`) — 검은 상자에 흰 글씨, 옆에 `source` |
| `labelAccent` | bool (선택) | 머리표를 주황 상자로 |
| `labelColor` | `"#RRGGBB"` (선택) | 머리표 상자 색 (교재마다 — 원문 `\definecolor`) |
| `texStyle` | bool (선택) | TeX 원문 문항: 본문 글꼴 Noto Serif KR, 글줄 수식은 text style (원문처럼) |
| `points` | int (선택) | 배점. 없으면 난이도로 2·3·4점, `0` 이면 표시하지 않음 |

### 교재 파일 (.pulinote)

TeX 원문 교재는 `python3 tools/tex_book.py <교재 폴더> <출력 폴더> [--preview]` 로
`<id>.pulinote` (gzip JSON `{format:"pulinote-bundle", version:1, id, title, courses:[과목 파일 형식], workbooks:[문제집]}`) 를 만든다.
TeX 원본이 없는 자료(인적성·NCS, 직접 쓴 교과 문항)는
`python3 tools/text_book.py <교재 폴더> <출력 폴더>` 로 만든다.
교재 폴더는 `정보.txt` (머리말) + `문항.txt` (`#문항`/`#지문` 토막) + `그림/*.svg` 이고,
문항 토막은 `키: 값` 머리말(과목·영역·유형·형식·정답·난이도·배점·지문·목차·머리표·출처·단위·힌트)과
`[문제] [보기] [선택지] [해설]` 구역으로 되어 있다 (`[보기]` 의 `ㄱ. ㄴ. ㄷ.` 줄 → `boxItems`,
`과목`·`영역` 으로 앱 과목을 고른다 — `tools/text_book.py` 의 `COURSES`. 목록에 없는 과목 이름(국어·영어·화학·한국사 …)은 이름으로 교과군을 짐작해 새 과목을 만든다),
`python3 tools/text_book.py check <교재 폴더>` 는 변환하지 않고 빠진 정답·어긋난 선택지만 알려 준다
(`selftest` 는 지어낸 보기 교재로 변환기를 시험한다 — CI 가 돌린다).

앱 설정 → **교재 파일** → 파일 가져오기 (또는 다른 앱에서 "Solvit으로 열기") 로 넣는다.
교재 내용은 저작물이므로 이 저장소·CI 에는 올리지 않는다 (테스트는 `test/fixtures/sample_book.dart` 의 지어낸 예시만 쓴다).

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
