# 문제 콘텐츠 API (앱 다운로드 · 출제 도구)

선생님 서버(`server/`)는 실시간 필기 중계와 함께 **문제 콘텐츠**를 제공한다.

- 앱은 설정에 입력한 서버 주소(예: `ws://192.168.0.12:8080/ws`)에서 `ws` → `http`, `wss` → `https` 로 바꾸고 `/ws` 를 뗀 주소(예: `http://192.168.0.12:8080`)로 아래 **공개 API** 를 부른다.
- 선생님은 브라우저에서 `http://<서버>:8080/admin` 출제 도구로 문항을 만들고 고친다(아래 **관리 API** 사용).
- 데이터 형식은 [problem-schema.md](problem-schema.md) 와 **완전히 같다**(과목 파일 = `assets/problems/*.json`, 문제집 = `workbooks.json`).

## 저장 위치

| 경로 | 내용 |
|---|---|
| `server/content/<subjectId>.json` | 과목 하나 = 파일 하나 (problem-schema 형식) |
| `server/content/workbooks.json` | `{ "workbooks": [ … ] }` |
| `server/content/_trash/` | 삭제한 과목 파일 보관(시각-파일명) |
| `server/content/.seeded` | 기본 문제를 복사했다는 표시 |

- 서버를 켤 때 과목 파일이 하나도 없고 `.seeded` 도 없으면 `assets/problems/_index.json` 에 적힌 파일과 `assets/problems/workbooks.json` 을 그대로 복사한다. (과목은 있는데 `workbooks.json` 만 없으면 그것만 복사)
- 시작할 때 `server/legacy-samples.json` 의 지문(sha256)과 바이트까지 똑같은 파일(예전에 기본으로 넣었던 샘플 문제)은 지운다. 고치거나 새로 만든 과목·문제집은 그대로 남는다. 지운 뒤에는 `.seeded` 를 남겨 다시 채우지 않는다.
- 모든 쓰기는 한 줄로 세워(직렬화) 처리하고, 임시 파일에 쓴 뒤 이름을 바꾸는(rename) 방식이라 쓰다가 꺼져도 파일이 깨지지 않는다.
- 환경변수: `CONTENT_DIR`(기본 `server/content`), `SEED_DIR`(기본 `assets/problems`), `ADMIN_KEY`.

## 공개 API (앱용 · 키 없음 · CORS `*`)

### `GET /api/content/index`

```json
{
  "packs": [
    { "id": "phy1", "name": "물리학Ⅰ", "group": "sci", "level": "high",
      "version": "906a91e972abde4f", "count": 38,
      "color": "#3B6FE0", "grades": ["고2", "고3", "N수"], "track": "수능", "updatedAt": 1791114829738 }
  ],
  "workbooks": { "version": "1c0e5a3b9d2f4e61", "count": 13 }
}
```

- `id` = `subjectId`, `name` = `subject`, `count` = 문항 수(쌍둥이 포함).
- `version` 은 **파일 내용의 sha1 앞 16자리**. 파일이 바뀌면 반드시 바뀌고, 안 바뀌면 그대로다. 앱은 저장해 둔 버전과 다를 때만 팩을 내려받으면 된다.
- `color` `grades` `track` `updatedAt`(ms) 는 덧붙인 정보(없을 수 있음). `group`/`level` 이 비어 있으면 `""`.
- 순서: 교과군(국어·수학·영어·사회·과학) → 중등·고등 → 과목 이름.

### `GET /api/content/pack/<subjectId>`

과목 JSON 그대로(problem-schema 형식). 응답 헤더 `ETag: "<version>"`, `X-Content-Version: <version>`.
`If-None-Match: "<version>"` 을 보내면 바뀌지 않았을 때 `304` (본문 없음). 없는 과목은 `404`.

### `GET /api/content/workbooks`

`{ "workbooks": [ … ] }` (problem-schema 의 문제집 형식). `ETag`/`304` 동일.

### 앱 쪽 권장 흐름

1. `index` 를 받는다.
2. 팩마다 `version` 이 저장된 값과 다르면 `pack/<id>` 를 받아 저장하고 버전을 기록한다. index 에 없어진 팩은 지운다(또는 숨긴다).
3. `workbooks.version` 이 다르면 `workbooks` 를 받는다.
4. 서버에 연결할 수 없으면 마지막으로 받은 것(없으면 앱에 들어 있는 기본 문제)을 쓴다.

## 관리 API (출제 도구용)

모든 요청에 헤더 **`x-admin-key: <키>`** (또는 주소 끝에 `?key=<키>`).

- 키: 환경변수 `ADMIN_KEY` → 없으면 `server/data/admin-key.txt` → 그것도 없으면 6자리 숫자를 만들어 이 파일에 저장. 서버를 켤 때 콘솔에 `★ 출제 도구 관리자 키: 123456` 으로 표시된다.
- 키가 없거나 틀리면 `401 { "ok": false, "error": "관리자 키가 맞지 않습니다" }`. 같은 IP 에서 1분 안에 10번 틀리면 `429`.
- 본문은 JSON(`Content-Type: application/json`), 최대 10MB.

### 오류 형식

```json
{ "ok": false, "error": "입력 내용에 오류가 2건 있습니다",
  "errors":   [ { "where": "phy1-mech-040", "field": "choices", "message": "선택형은 선택지가 정확히 5개여야 합니다 (지금 4개)" } ],
  "warnings": [ { "where": "phy1-mech-040", "field": "unit", "message": "대단원 \"…\" 가 과목의 대단원 목록(units)에 없습니다" } ] }
```

- `400` 검증 실패(이때 **아무것도 저장되지 않음**), `401` 키, `404` 없음, `413` 너무 큼, `429` 키 너무 많이 틀림.
- `where` = 문항·지문·문제집 id(또는 과목 id), `field` = 필드 이름(`stem`, `choices[2]`, `template.stem`, `boxItems[0]` …).
- 성공 응답에도 `warnings` 가 올 수 있다(저장은 됨).

### 엔드포인트

| 방식 | 주소 | 설명 |
|---|---|---|
| GET | `/api/admin/check` | 키 확인 → `{ ok: true }` |
| GET | `/api/admin/courses` | 과목 목록: `id subject color group level grades track units count originals twins templates passages version updatedAt` |
| GET | `/api/admin/course/:id` | `{ course, version, file, updatedAt }` |
| PUT | `/api/admin/course/:id` | 과목 만들기(`201`)·고치기(`200`). 본문에 `problems`/`passages` 가 **없으면 기존 문항·지문을 그대로 둔다**. `subjectId` 를 다른 값으로 보내면 과목 id 변경(파일 이름·문제집의 `course` 도 바뀜). `track`·`units` 등을 `null` 로 보내면 지움 |
| DELETE | `/api/admin/course/:id` | 과목 삭제 → `{ removedWorkbooks }` (그 과목 문제집 삭제, 다른 문제집에서 그 과목 문항 제거). 파일은 `_trash/` 로 이동 |
| PUT | `/api/admin/course/:id/problem` | 문항 하나 추가(`201`)·수정(`200`), id 로 찾음. `?replace=<옛 id>`: id 바꾸기(쌍둥이의 `twinOf`, 문제집 목록도 함께 바뀜). `?after=<문항 id>`: 새 문항을 그 뒤에 넣음(없으면 맨 끝, 쌍둥이는 원본 가족 바로 뒤). 응답 `{ problem, version, count, created, warnings }` |
| DELETE | `/api/admin/course/:id/problem/:pid` | 문항 삭제. 이 문항을 원본으로 하는 쌍둥이가 있으면 `400 { twins }` → `?cascade=1` 이면 쌍둥이도 함께 삭제. 문제집에서도 빠짐 → `{ deleted, removedFromWorkbooks }` |
| PUT | `/api/admin/course/:id/passage` | 지문 추가·수정. `?replace=<옛 id>` 이면 id 변경(문항의 `passageId` 도 바뀜) |
| DELETE | `/api/admin/course/:id/passage/:pid` | 지문 삭제. 쓰는 문항이 있으면 `400 { problems }` |
| GET | `/api/admin/workbooks` | `{ workbooks, version }` |
| PUT | `/api/admin/workbooks` | **목록 전체**를 바꿈. 본문 `{ "workbooks": [ … ] }` (또는 배열) |
| POST | `/api/admin/import` | 가져오기(아래) |
| GET | `/api/admin/export/:id` | 과목 파일 내려받기(`Content-Disposition: attachment`) |
| GET | `/api/admin/export/workbooks` | `workbooks.json` 내려받기 |
| GET | `/api/admin/export` | 전체 백업 `{ exportedAt, courses: [ … ], workbooks: [ … ] }` |

### 가져오기 `POST /api/admin/import`

본문은 다음 중 하나. **id 기준으로 합친다**(같은 id 는 덮어쓰고, 새 id 는 추가, 가져온 파일에 없는 기존 항목은 그대로).

- 과목 JSON 하나 (`{ subjectId, subject, …, problems }`) — 과목 정보는 보낸 필드만 덮어쓰고, 문항·지문은 id 로 합친다. 없는 과목이면 새로 만든다.
- 과목 배열 `[ {…}, {…} ]`
- 문제집 JSON `{ "workbooks": [ … ] }` — 문제집 id 로 합친다.
- 전체 백업 `{ "courses": [ … ], "workbooks": [ … ] }` (`GET /api/admin/export` 결과)

응답 `{ ok, courses: [ { id, created, added, updated, total } ], workbooks: { added, updated, total } | null, warnings }`.
검증에 실패하면 `400` 이고 아무것도 바뀌지 않는다.

### 서버 검증 규칙 (problem-schema.md · tools/validate_problems.py 와 같음)

검증 코드는 `server/public/admin/schema.js` 하나를 서버와 출제 웹이 함께 쓴다.

- 문항: 필수 `id unit topic difficulty type stem answer solution`, `difficulty` 1~5 정수, id 는 영문·숫자·`- _ .`.
- `choice` → 선택지 정확히 5개(빈 칸·중복 불가), 정답 `"1"`~`"5"`. `short` → 정답은 비어 있지 않은 숫자·분수(`12`, `-3/2`, `2.5`), 선택지 없음, `tolerance` ≥ 0.
- id 는 **모든 과목의 문항·지문 전체에서 유일**.
- `passageId` 는 같은 과목의 지문, `twinOf` 는 같은 과목의 **쌍둥이가 아닌** 문항(자기 자신 불가).
- 본문 표기법: `$` 짝, `**`·`__` 짝(수식 밖), `$…$` 안 한글 금지, `\text{}` 안 영문만, `\begin`·`\\` 금지, 수식 중괄호 짝, 표의 모든 줄 칸 수 같음, 템플릿 밖 `[[…]]` 금지.
- `template`: params 형식, 식 문법, 정의된 이름만 사용, 선택형은 `choiceExprs` 5개이고 첫 번째 = 정답(표본 20개로 확인), `require` 를 만족하는 조합 존재.
- 과목: `subject`, `subjectId`(영문 소문자·숫자·`-`), `color` `#RRGGBB`, `group`·`level` 필수, `grades` 1개 이상, `track` 은 `수능/내신/공통`, `units` 중복 불가.
- 문제집: id(영문 소문자·숫자·`-`) 유일, 제목, 있는 과목, 수준 `기본/실전/심화/모의고사`, 문항 1개 이상·중복 없음·존재·**쌍둥이 아님**.
- 문항 하나를 저장할 때는 그 문항 자체와, 그 저장으로 **새로 생기는** 관계 오류(예: 문제집에 든 문항을 쌍둥이로 바꿈)만 막는다. 원래 있던 다른 문항의 문제 때문에 저장이 막히지는 않는다.

### 예 (curl)

```bash
KEY=123456
curl -s http://localhost:8080/api/content/index
curl -s -H "x-admin-key: $KEY" -X PUT -H 'Content-Type: application/json' \
  --data '{"id":"phy1-mech-099","unit":"역학과 에너지","topic":"운동량","difficulty":3,"type":"short",
           "stem":"질량 $2\\,\\text{kg}$ 인 물체가 $3\\,\\text{m/s}$ 로 움직인다. 운동량의 크기는?",
           "answer":"6","answerUnit":"kg·m/s","solution":"$p=mv=6$"}' \
  http://localhost:8080/api/admin/course/phy1/problem
curl -s -H "x-admin-key: $KEY" -X POST -H 'Content-Type: application/json' --data @my-course.json \
  http://localhost:8080/api/admin/import
```
