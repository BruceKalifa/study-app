# 커뮤니티 · 공부시간 순위 API

선생님 서버(`server/`)가 제공한다. 앱은 콘텐츠 API와 같은 주소(`http://<서버>:8080`)를 쓴다. 모든 응답은 JSON, CORS `*`.
실서비스에서는 클라우드 서버 + 로그인으로 옮길 예정이고, 지금은 `userId`(앱 프로필마다 무작위로 만든 id)로 사람을 구분한다.
**userId 는 어떤 응답에도 그대로 내보내지 않는다** (본인 여부는 `mine` 으로만 알려 준다).

## 게시판

`GET /api/community/boards`

```json
{ "boards": [
  { "id": "free",  "name": "자유", "desc": "수험생활 이야기", "tracks": [] },
  { "id": "math",  "name": "수학", "desc": "수학 개념·풀이·킬러 문항", "tracks": ["고1", "고2", "고3", "N수"] },
  { "id": "apt",   "name": "인적성·NCS", "desc": "인적성·NCS 후기와 유형 공유", "tracks": ["취준"] }
] }
```

게시판은 22개다 (공통: 자유·질문·공부인증·고민·멘탈·공부법·꿀팁·스터디 모집 / 고등: 입시정보·내신·수능·모의고사·수학·과학·국어·영어·사회탐구·수시·정시·N수·재수 /
취준: 인적성·NCS·취업정보 / 한양대: 한양대 라운지·공업수학·미적분학·시험·학점 / 편입: 편입정보·편입수학). `tracks` 는 그 게시판이 맞는 학년·과정이고, 빈 배열이면 모두에게 맞다.
앱은 가입 때 고른 과정에 맞는 게시판만 칩으로 보여 주고(전체 보기는 모든 글), 서버는 어느 게시판에든 글을 받는다. 위 예시는 일부만 적은 것이다 — 전체 목록은 `server/community.js` 의 `BOARDS`.


## 글

### 목록 `GET /api/community/posts?board=&q=&sort=new|hot&before=&limit=&me=`

- `board` 없으면 전체(신고로 숨겨진 글 제외). `q` 는 제목·본문 검색. `sort=hot` 은 최근 7일 글을 (좋아요×3 + 댓글×2 + 조회/10) 순.
- `before`: 이 `createdAt`(ms)보다 오래된 글만 (더 보기). `limit` 기본 30, 최대 50.
- `me`: 내 userId — 응답의 `mine`, `liked` 계산용.

```json
{ "posts": [ {
  "id": "p_lx2…", "board": "qna", "title": "…", "preview": "본문 앞 120자",
  "author": "닉네임", "grade": "고3", "createdAt": 1791100000000,
  "likes": 3, "liked": false, "comments": 2, "views": 41,
  "problemId": "phy1-mech-005", "mine": false
} ] }
```

### 읽기 `GET /api/community/posts/:id?me=` (조회수 +1)

`{ "post": { …위 필드…, "body": "본문 전체", "comments": [ { "id": "c_…", "author": "닉", "grade": "고2", "body": "…", "createdAt": 0, "mine": false } ] } }`

### 쓰기 `POST /api/community/posts`

`{ "userId": "…", "author": "닉네임", "grade": "고3", "board": "qna", "title": "…", "body": "…", "problemId": "선택" }` → `{ "post": {…} }`

- 검증: board 존재, title 1~80자, body 1~5000자, author 1~20자, grade(신분)는 빈 값, 또는 `고1 고2 고3 N수생 취준생 한양대생 편입생 선생님` (옛 값 `N수 취준 한양대 편입` 도 받음) 중 최대 3개를 " · " 로 이은 글자 (예: `한양대생 · N수생`). 앱은 가입할 때 고른 과정으로 만들어 보낸다. 그 밖의 값은 400. 같은 userId 는 20초에 글 1개(429).
- 400 `{ "error": "한국어 메시지" }`

### 댓글 `POST /api/community/posts/:id/comments`

`{ "userId", "author", "grade", "body"(1~1000자) }` → `{ "comment": {…} }` (같은 userId 5초에 1개)

### 좋아요 `POST /api/community/posts/:id/like` `{ "userId" }` → `{ "likes": 4, "liked": true }` (토글)

### 삭제 (본인만) `DELETE /api/community/posts/:id?userId=` · `DELETE /api/community/posts/:id/comments/:cid?userId=` → `{ "ok": true }` (남의 글이면 403)

### 신고 `POST /api/community/posts/:id/report` `{ "userId", "reason" }` → `{ "ok": true }`
같은 사람의 중복 신고는 한 번만 센다. 서로 다른 3명이 신고하면 글이 숨겨진다(`hidden`).

### 관리 (x-admin-key)

- `GET /api/admin/community/reports` → 신고된 글 목록(숨김 포함, 신고 사유)
- `POST /api/admin/community/posts/:id/restore` → 숨김 해제
- `DELETE /api/admin/community/posts/:id` · `DELETE /api/admin/community/posts/:id/comments/:cid`

## 공부시간 순위 (개인정보 보호)

### 보고 `POST /api/ranking/report`

`{ "userId": "…", "name": "오예진", "grade": "고3", "day": "2026-10-04", "studyMs": 7200000, "solved": 35 }`

- 같은 userId·day 는 덮어쓴다. `studyMs` 는 0 ~ 24시간 안으로 자른다.
- **이름은 저장할 때 가린다**: 첫 글자 + `XX` (예: `오예진` → `오XX`, `Kim` → `KXX`). 전체 이름은 저장하지 않는다.

### 조회 `GET /api/ranking?period=day|week&day=YYYY-MM-DD&grade=&me=`

- `day`: 기준 날짜(기본 서버 오늘). `week` 는 그 날짜까지 7일 합.
- `grade` 를 주면 그 학년만.

```json
{ "period": "day", "day": "2026-10-04", "total": 128,
  "entries": [ { "rank": 1, "name": "오XX", "grade": "고3", "studyMs": 36000000, "solved": 120, "me": false } ],
  "me": { "rank": 17, "studyMs": 7200000, "solved": 35 } }
```

- `entries` 는 상위 50명. `me` 는 내 순위(보고한 적 없으면 `null`).

## 저장

`DATA_DIR`(기본 `server/data`) 아래 `community.json`, `ranking.json`. 임시 파일에 쓴 뒤 이름 바꾸기(원자적), 쓰기는 직렬화. 90일 지난 순위 기록은 정리한다.

## 구현 메모 (서버 `community.js` · `ranking.js` 기준, 위 계약에 덧붙인 것)

- 성공 응답은 모두 **200** (글·댓글 작성 포함). 오류는 `{ "error": "한국어 메시지" }` 와 400(검증) · 403(남의 글/댓글) · 404(없음·삭제됨·숨김) · 413(본문 64KB 초과) · 429(도배 제한).
- 숨겨진 글은 **어떤 목록에도** 나오지 않고(board 를 줘도), 읽기·좋아요·댓글·신고는 404 `"신고가 많아 숨겨진 글입니다"`.
- 글쓰기 응답 `post` 는 읽기와 같은 모양(`body`, `comments: []` 포함). `problemId` 가 없으면 `null`. `grade` 가 없으면 `""`.
- 글자 수는 코드 포인트 기준(한글 한 글자 = 1). 제목·닉네임은 앞뒤 공백을 지우고 줄바꿈을 공백으로 바꾼 뒤 센다.
- `before` 는 `sort=hot` 에도 같은 뜻(그 createdAt 보다 오래된 글)으로 적용된다. 인기순 "더 보기"가 필요하면 `limit` 을 늘려 쓰는 편이 낫다.
- 삭제의 `userId` 는 쿼리(`?userId=`)로 보낸다(JSON 본문 `{ "userId" }` 도 받는다).
- 관리자가 `restore` 하면 숨김이 풀리고 신고 기록도 비워진다(다시 3명이 신고하면 다시 숨김).
- 관리 응답: `GET /api/admin/community/reports` → `{ "posts": [ { id, board, title, body, author, grade, createdAt, likes, views, problemId, hidden, hiddenAt, reportCount, reports: [ { reason, at } ], comments: [ { id, author, grade, body, createdAt } ] } ] }` (숨김 글 먼저, 최근 신고 순). userId 는 관리 응답에도 없다.
- 추가 관리 API: `GET /api/admin/community/posts?q=&before=&limit=` (숨김 포함 최근 글, 위와 같은 모양, `total` = 전체 글 수) — 출제실 "커뮤니티 관리" 탭이 쓴다.
- 순위 보고 응답: `{ "ok": true, "day", "name": "오XX", "grade", "studyMs": 자른 값, "solved" }`. `day` 를 빼면 서버 오늘. 내일보다 미래이거나 90일보다 오래된 날짜, 잘못된 학년은 400. `solved` 는 0 이상 정수로 정리.
- 이름 가리기의 "첫 글자"는 자소 결합(NFD 한글)·이모지까지 한 글자로 본다. 제어 문자는 지운다.
- 순위 정렬: studyMs 많은 순 → solved 많은 순 → 먼저 보고한 순. `rank` 는 이 순서의 번호(동점이어도 번호가 다르다).
- `period=week` 응답에는 시작 날짜 `from` 이 더 있다. 이름·학년은 그 기간 중 가장 최근 날의 값. `grade` 를 주면 `total`·`me` 도 그 학년 안에서 센다(내가 그 학년이 아니면 `me: null`).
