# 계정 · 선생님-학생 연결 · 풀이 기록 · 1:1 질문 API

선생님 서버(`server/`)가 제공한다 (`server/accounts.js`, `server/questions.js`). 앱은 콘텐츠·커뮤니티 API와 같은 주소를 쓴다.
모든 응답은 JSON, 오류는 `{ "error": "한국어 메시지" }` + 400/401/403/404/409/413/429.

## 인증

가입·로그인 응답의 `token` 을 이후 요청에 `Authorization: Bearer <token>` 으로 보낸다.
토큰은 180일 동안 쓰이지 않으면 만료된다. 서버에는 토큰의 sha256 해시만, 비밀번호는 scrypt 해시(+salt)만 저장한다.

| 요청 | 본문 | 응답 |
|---|---|---|
| `POST /api/auth/signup` | `{ role: "student"\|"teacher", loginId, password, name, grade? }` | `{ token, user, communityKey, counts, inviteCode? \| teachers? }` |
| `POST /api/auth/login` | `{ loginId, password }` | 위와 같음 |
| `POST /api/auth/logout` | – | `{ ok }` (이 토큰만 끊김) |
| `GET /api/me` | – | `{ user, communityKey, counts, inviteCode?, studentCount? \| teachers? }` |
| `POST /api/me` | `{ name?, grade? }` | `GET /api/me` 와 같음 |
| `POST /api/me/password` | `{ current, next }` | `{ ok }` (다른 기기의 로그인은 모두 끊김) |

- `loginId`: 영문 소문자·숫자로 시작하는 4~20자 (영문·숫자·`.`·`_`·`-`). 대소문자는 구분하지 않는다(소문자로 저장). 이미 있으면 409.
- `password`: 6~100자. `name`: 1~20자. `grades`(학생만): 위 값 중 여러 개를 함께 고를 수 있는 배열 (예: `["한양대","N수","편입"]`, 첫 번째가 대표). 옛 앱은 `grade` 하나만 보내도 된다. 값: `고1 고2 고3 N수 취준 한양대 편입` 또는 빈 값 (`취준` 은 인적성, `한양대` 는 대학 전공 기초, `편입` 은 편입 준비 과정). 응답의 `user.grade` 는 대표 학년, `user.grades` 는 전체다. 선생님 화면에는 `한양대 · N수` 처럼 이어서 보인다.
- 로그인을 8번 틀리면 그 아이디는 10분 잠긴다(429). 가입은 IP 당 1시간 30번까지.
- `user`: `{ id, role, loginId, name, grade?(학생), createdAt }`
- `communityKey`: 커뮤니티·순위 API 의 `userId` 로 쓰는 본인 전용 키 (다른 사람에게는 보이지 않는다).
- `counts`: `{ unreadQuestions, openQuestions }` — 학생은 "선생님이 답한 안 읽은 질문", 선생님은 "답을 기다리는 질문".
- 선생님: `inviteCode`(6자리, 0/O·1/I 없음), `studentCount`. 학생: `teachers: [{ id, name }]`.

## 선생님 ⇄ 학생 연결

학생이 선생님의 **초대 코드**를 입력해 연결한다. 한 학생이 여러 선생님(학원·과외)과 연결될 수 있다(최대 10명).
선생님은 **자기에게 연결된 학생의 기록만** 볼 수 있다.

| 요청 | 누가 | 응답 |
|---|---|---|
| `POST /api/student/teachers` `{ code }` | 학생 | `{ teacher: { id, name } }` (틀린 코드 404, 공백·하이픈·소문자 허용) |
| `DELETE /api/student/teachers/:teacherId` | 학생 | `{ ok }` |
| `POST /api/teacher/invite` | 선생님 | `{ inviteCode }` 새 코드 (예전 코드는 더 이상 안 됨, 이미 연결된 학생은 그대로) |
| `DELETE /api/teacher/students/:id` | 선생님 | `{ ok }` |

## 풀이 기록 (학생 → 서버)

`POST /api/student/sync` (학생) — 셋 다 선택:

```json
{
  "attempts": [ { "id": "앱의 풀이 id", "pid": "phy1-mech-005~v12", "base": "phy1-mech-005", "sub": "phy1",
                  "unit": "역학", "topic": "운동량", "ans": "2", "exp": "4", "ok": false, "ms": 41000,
                  "at": 1791100000000, "mode": "practice" } ],
  "learner": { "grade": "고3", "goal": "수능", "workbooks": ["wb-phy1-real1"], "examName": "수능", "examDate": 0, … },
  "wrongNote": ["phy1-mech-005"]
}
```

→ `{ ok, stored, total, syncedAt }`

- `attempts` 는 앱의 `Attempt.toJson()` 모양 그대로. 같은 `id` 는 한 번만 저장(다시 보내도 됨). 한 번에 2000개, 학생당 최근 30000개 보관.
- `learner`: 앱 학습 설정 전체(64KB 까지) — 새 기기에서 되살릴 때 쓴다. `grade` 가 있으면 계정 학년도 바뀐다.
- `wrongNote`: 지금 오답노트에 남아 있는 원래 문제 id 목록(복습으로 졸업한 것은 빠짐).

`GET /api/student/records` (학생) → `{ attempts, learner, wrongNote, syncedAt }` — 새 기기에서 로그인했을 때 되살리기.

## 선생님 화면

### `GET /api/teacher/students`

```json
{ "inviteCode": "K7Q2MX",
  "students": [ { "id": "u_…", "name": "오예진", "grade": "고3", "joinedAt": 0, "syncedAt": 0, "lastActiveAt": 0,
                  "solved": 120, "correct": 88,
                  "today": { "solved": 12, "correct": 9, "timeMs": 900000 },
                  "week":  { "solved": 60, "correct": 41, "timeMs": 5400000 },
                  "wrongOpen": 7 } ] }
```

최근에 푼 학생이 위. `wrongOpen` = 오답노트에 남은 문제 수. 날짜는 한국 시간(`TZ_OFFSET_MIN`, 기본 540) 기준.

### `GET /api/teacher/students/:id`

```json
{ "student": { …위 요약… },
  "learner": { "grade", "goal", "workbooks": [], "examName", "examDate" },
  "wrong": [ { "baseId", "problemId": "마지막으로 틀린 문제(변형이면 변형 id)", "subjectId", "unit", "topic",
               "answer": "학생이 쓴 답", "expected": "정답", "wrongAt", "lastAt", "lastCorrect",
               "tries", "correct", "wrongs", "open": true } ],
  "bySubject": [ { "subjectId", "solved", "correct", "timeMs" } ],
  "byDay": [ { "day": "2026-10-05", "solved", "correct", "timeMs" } ],   // 최근 14일
  "recent": [ …최근 풀이 150개 (최신이 앞), attempts 와 같은 모양… ] }
```

`wrong` 은 한 번이라도 틀린 문제(변형·쌍둥이는 원래 문제로 묶음). 오답노트에 남은 것(`open`) 먼저, 최근에 틀린 순.
학생이 `wrongNote` 를 보낸 적 없으면 "마지막 풀이가 오답"이면 `open`.

## 1:1 질문

학생이 연결된 선생님에게 문제·풀이 사진과 함께 질문하고, 선생님이 글이나 **필기 그림**으로 답한다.

| 요청 | 누가 | 응답 |
|---|---|---|
| `POST /api/questions` `{ teacherId, problemId?, title?, body, image? }` | 학생 | `{ question }` |
| `GET /api/questions?status=open\|answered\|resolved\|all&student=` | 둘 다 | `{ questions: [요약] }` (최근 바뀐 순, 300개) |
| `GET /api/questions/:id` | 참여자 | `{ question }` + 읽음 표시 |
| `POST /api/questions/:id/messages` `{ body?, image? }` | 참여자 | `{ question }` |
| `POST /api/questions/:id/resolve` | 참여자 | `{ ok }` |
| `GET /api/questions/:id/images/:imageId` | 참여자 | 그림 (PNG/JPEG) |

- `image`: `data:image/png;base64,…` 또는 base64 (PNG·JPEG, 2.5MB 까지). 파일은 `DATA_DIR/question-images/` 에 저장.
- `body` 3000자까지, `title` 80자(없으면 "질문"). 내용과 그림이 둘 다 없으면 400. 연결 안 된 선생님에게 질문하면 403.
- 상태: 학생이 쓰면 `open`, 선생님이 답하면 `answered`, `resolve` 하면 `resolved`. 해결 뒤에도 메시지를 쓰면 다시 열린다.
- 연결을 끊어도 이미 주고받은 질문은 두 사람이 계속 볼 수 있다. 다른 사람에게는 404.
- 요약: `{ id, student: { id, name, grade }, teacher: { id, name }, problemId, title, preview, hasImage, status, createdAt, updatedAt, messageCount, lastFrom, unread }`
- `question` = 요약 + `messages: [ { id, from: "student"|"teacher", name, body, image: "/api/questions/…/images/…"|null, at, mine } ]`

## 교재 창고

선생님이 올린 교재(`.pulinote`, `tools/tex_book.py` 로 만든 파일)를 **연결된 학생만** 앱에서 받아 간다.
교재 내용은 공개 저장소에 두지 않고 서버의 `DATA_DIR/books/` 에만 둔다. 로그인 없이는 목록도 파일도 받을 수 없다.

| 요청 | 누가 | 응답 |
|---|---|---|
| `POST /api/books?title=&open=1` (본문 = 파일 그대로) | 선생님 | `{ book, replaced }` |
| `GET /api/books` | 둘 다 | `{ books: [요약] }` (최근 올린 순) |
| `GET /api/books/:id` | 받을 수 있는 사람 | `{ book }` |
| `GET /api/books/:id/file` | 받을 수 있는 사람 | 올린 파일 그대로 (`application/gzip`) |
| `POST /api/books/:id` `{ title?, open?, students?[] }` | 올린 선생님 | `{ book }` |
| `DELETE /api/books/:id` | 올린 선생님 | `{ ok }` |

- 본문은 `.pulinote` 파일 그대로(`Content-Type: application/octet-stream`). 한 파일 40MB, 선생님 한 명당 400MB·200권까지.
- 올릴 때 서버가 파일을 풀어 `pulinote-bundle`/`pulinote-collection` 인지, 문항이 있는지 확인한다(아니면 400).
  같은 교재(안에 든 교재 id 묶음이 같은 것)를 다시 올리면 새로 만들지 않고 바꿔 끼운다(`replaced: true`).
- 누가 받을 수 있나: 올린 선생님 본인, 그리고 그 선생님과 **연결된 학생** 중 `open: true` 이거나 `students` 에 지정된 학생.
  그 밖에는 목록에서 빠지고 파일도 404(있는지조차 알려주지 않는다).
- 요약: `{ id, title, titles: [묶음 안 교재 제목], bookIds, problems, bytes, sha, at, teacher: { id, name } }`.
  `sha` 는 올린 파일의 지문 — 앱은 받아 둔 지문과 다를 때만 다시 받는다(선생님이 답안표를 고치면 바뀐다).
  올린 선생님에게만 `open`, `students`, `mine: true` 가 함께 온다.
- `students` 는 나와 연결된 학생만 남는다(남의 학생 id 는 조용히 버린다).
- **웹으로 올린다**: 서버의 `/books/` (교재 창고) 에 선생님 아이디로 들어가 `.pulinote` 를 끌어다 놓으면
  올라가고, 권마다 "모두에게 열기"를 끄고 받을 학생을 고를 수 있다. 앱은 올리지 않고 받기만 한다.
  브라우저로 눌러 보는 시험: `node tools/test-books-web.mjs <서버주소> <선생님아이디> <비밀번호> <학생아이디> <학생비밀번호> <교재1> <교재2>`.
- 앱은 **받기만 한다**(`AppState.syncBooks`). 로그인한 뒤·앱을 켤 때 서버에 있는 교재 중 이 기기에 없거나
  지문(`sha`)이 바뀐 것을 받는다. 선생님 태블릿도 똑같이 받기만 한다 — 올리는 곳은 웹 교재 창고(`/books/`)다.
  받은 파일은 `.pulinote` 가져오기와 똑같이 기기에 저장되고, 학생은 내 교재에 자동으로 담긴다.
  앱으로 돌아올 때도 다시 확인한다. 설정에는 교재 카드가 따로 없다 — 받는 건 전부 저절로 된다.
  서버 주소는 묻지 않는다 (`kDefaultServer`, lib/app/theme.dart).
- 하나 있는 예외: 선생님이 **답안표에서 정답을 고치면** 그 교재 한 권만 서버에 다시 올린다
  (`AppState._pushAnswers`). 서버 창고에 없던 교재는 올리지 않는다.

## 저장

`DATA_DIR/accounts.json`(계정·세션), `study.json`(학생별 기록), `questions.json`, `question-images/`.
`books.json` + `books/<id>.pulinote`(올린 교재 파일).
모두 임시 파일에 쓴 뒤 이름 바꾸기(원자적). 점검: `npm run test:accounts`, `npm run test:books`.

## 나중에 (실서비스)

- 클라우드 서버 + HTTPS (Render, `render.yaml`).
- 소셜 로그인(카카오·구글·애플), 비밀번호 찾기(휴대폰·이메일 인증), 선생님 계정 인증.
- 구독 결제 상태를 계정에 저장.
