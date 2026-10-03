# 실시간 필기 공유 프로토콜 (앱 ↔ 서버 ↔ 선생님 웹)

전송: WebSocket, 메시지는 모두 JSON 텍스트 한 개 = 객체 한 개.

- 학생 앱: `ws://<서버>:8080/ws?role=student`
- 선생님 웹: `ws://<서버>:8080/ws?role=teacher` (서버가 `http://<서버>:8080/` 에서 선생님 웹을 제공)

## 좌표계

- 필기 좌표는 **논리 페이지 좌표**: 페이지 폭 = **1000**, 높이는 자유(보통 1000~3000).
- 학생 기기 화면 크기·확대 상태와 무관하다. 선생님 화면은 폭 1000 을 자기 캔버스 폭에 맞춰 확대/축소해서 그린다.
- 점 하나 = `[x, y, p]` (p = 필압 0~1, 소수 셋째 자리까지)

## 학생 → 서버

| type | 필드 | 의미 |
|---|---|---|
| `hello` | `studentId`, `name`, `device` | 접속 직후 1회 |
| `page` | `problemId`, `title`, `stem`(LaTeX 포함 원문), `choices`(배열 또는 null), `pageHeight` | 학생이 문제를 열거나 바꿈. 서버는 그 학생의 필기 상태를 비운다 |
| `stroke_begin` | `id`(문자열), `tool`(`pen`/`highlighter`), `color`(`#RRGGBB`), `width`(논리 좌표 기준 굵기), `points`(배열) | 획 시작 |
| `stroke_points` | `id`, `points` | 획 진행 중 추가 점 (약 50ms 마다 묶어서) |
| `stroke_end` | `id` | 획 끝 |
| `erase` | `ids`(문자열 배열) | 획 삭제(지우개, 실행취소) |
| `restore` | `strokes`(전체 획 배열: `{id,tool,color,width,points}`) | 실행취소/다시실행/올가미 이동 후 전체 상태 동기화 |
| `clear` | | 전부 지움 |
| `answer` | `problemId`, `answer`(문자열), `correct`(bool), `timeMs` | 학생이 답을 제출(채점 결과 포함) |
| `stats` | `total`, `correct`, `streak`, `todayCount`, `weakTopics`(문자열 배열) | 학생 누적 기록 요약(제출 때마다) |
| `ping` | | 15초마다 |

## 서버 → 선생님

| type | 필드 | 의미 |
|---|---|---|
| `snapshot` | `students`: `[{studentId,name,device,online,page,strokes,lastAnswer,stats,history}]` | 선생님 접속 직후 전체 상태 |
| `student_online` / `student_offline` | `studentId`, `name` | 접속 변화 |
| 위 학생 메시지 그대로 | + `studentId` 필드 추가 | 실시간 중계 |

## 선생님 → 서버 → 학생

| type | 필드 | 의미 |
|---|---|---|
| `message` | `studentId`(없으면 전체), `text` | 학생 화면에 알림 표시 |

## 서버 → 학생

| type | 필드 |
|---|---|
| `message` | `text`, `from` |
| `pong` | |

서버는 학생별 `history`(최근 제출 200개)를 `server/data/records.json` 에 저장해 재시작 후에도 유지한다.
