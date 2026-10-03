#!/usr/bin/env node
'use strict';
/**
 * 실시간 서버 점검용 테스트 클라이언트 (선생님 + 테스트 학생 역할)
 *
 *   npm test                                  (서버가 localhost:8080 에서 켜져 있어야 함)
 *   node tools/test-live.js ws://localhost:8080/ws [--records path/to/records.json] [--expect-sim]
 *
 * 확인하는 것: snapshot 수신, 실시간 획 중계, 서버 상태 누적, erase/restore/clear 중계,
 * 선생님→학생 메시지, records.json 저장, 같은 학생 재접속 처리, 잘못된 JSON/큰 메시지 처리, 정적 파일.
 */

const fs = require('fs');
const path = require('path');
const http = require('http');
const { WebSocket } = require('ws');

const argv = process.argv.slice(2);
const WS_URL = argv.find((a) => /^wss?:\/\//.test(a)) || 'ws://localhost:8080/ws';
const ri = argv.indexOf('--records');
const RECORDS = ri >= 0 ? path.resolve(argv[ri + 1])
  : path.join(process.env.DATA_DIR ? path.resolve(process.env.DATA_DIR) : path.join(__dirname, '..', 'data'), 'records.json');
const EXPECT_SIM = argv.includes('--expect-sim');
const HTTP_BASE = WS_URL.replace(/^ws/, 'http').replace(/\/ws.*$/, '');

let passed = 0;
let failed = 0;
function ok(cond, label, extra) {
  if (cond) { passed++; console.log(`  ✔ ${label}`); }
  else { failed++; console.log(`  ✘ ${label}${extra ? ' — ' + extra : ''}`); }
}

/** 소켓을 열고 받은 메시지를 모아 둔다 */
function open(role) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${WS_URL}?role=${role}`);
    ws.inbox = [];
    ws.waiters = [];
    ws.on('message', (d) => {
      const m = JSON.parse(d.toString());
      ws.inbox.push(m);
      for (const w of ws.waiters.slice()) if (w.pred(m)) { w.done(m); ws.waiters.splice(ws.waiters.indexOf(w), 1); }
    });
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
    ws.sendJ = (o) => ws.send(JSON.stringify(o));
  });
}
function waitFor(ws, pred, ms = 2000, label = '') {
  const hit = ws.inbox.find(pred);
  if (hit) { ws.inbox.splice(ws.inbox.indexOf(hit), 1); return Promise.resolve(hit); }
  return new Promise((resolve) => {
    const w = {
      pred,
      done: (m) => { clearTimeout(t); ws.inbox.splice(ws.inbox.indexOf(m), 1); resolve(m); },
    };
    const t = setTimeout(() => { ws.waiters.splice(ws.waiters.indexOf(w), 1); resolve(null); }, ms);
    ws.waiters.push(w);
  });
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const closed = (ws) => new Promise((r) => {
  if (ws.readyState === WebSocket.CLOSED) return r({ code: -1 });
  ws.once('close', (code, reason) => r({ code, reason: reason.toString() }));
});
function get(p) {
  return new Promise((resolve) => {
    http.get(HTTP_BASE + p, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => resolve({ status: res.statusCode, body, type: res.headers['content-type'] || '' }));
    }).on('error', (e) => resolve({ status: 0, body: e.message }));
  });
}

async function main() {
  const SID = 'test-bot';
  console.log(`테스트 대상: ${WS_URL}\n`);

  console.log('1) 선생님 접속 → snapshot');
  const teacher = await open('teacher');
  const snap = await waitFor(teacher, (m) => m.type === 'snapshot');
  ok(snap && Array.isArray(snap.students), 'snapshot 수신', snap ? '' : '시간 초과');
  if (snap) {
    console.log(`     학생 ${snap.students.length}명: ${snap.students.map((s) => `${s.name}(${s.history.length}제출)`).join(', ') || '없음'}`);
    if (EXPECT_SIM) {
      const sims = snap.students.filter((s) => s.studentId.startsWith('sim-'));
      ok(sims.length >= 2, '시뮬레이터 학생이 snapshot 에 있음', `${sims.length}명`);
      ok(sims.every((s) => s.history.length > 0 && s.stats && s.stats.total > 0), '시뮬레이터 학생의 history/stats 가 쌓임');
      ok(sims.some((s) => s.page && s.strokes.length > 0), '시뮬레이터 학생의 현재 페이지 획이 snapshot 에 포함');
    }
  }

  console.log('2) 학생 접속 → student_online');
  const student = await open('student');
  student.sendJ({ type: 'page', problemId: 'x' }); // hello 전
  const early = await waitFor(student, (m) => m.type === 'error');
  ok(early && early.reason === 'hello_required', 'hello 전 메시지는 error(hello_required)');
  student.sendJ({ type: 'hello', studentId: SID, name: '테스트봇', device: 'node' });
  const on = await waitFor(teacher, (m) => m.type === 'student_online' && m.studentId === SID);
  ok(on && on.name === '테스트봇', 'student_online 수신 (name 포함)');

  console.log('3) page / 획 실시간 중계');
  student.sendJ({ type: 'page', problemId: 'test-001', title: '테스트 문제', stem: '$x^2=4$ 일 때 양수 $x$는?', choices: null, pageHeight: 1500 });
  const pg = await waitFor(teacher, (m) => m.type === 'page' && m.studentId === SID);
  ok(pg && pg.problemId === 'test-001' && pg.stem.includes('$x^2=4$'), 'page 중계 (+studentId)');
  const pts1 = [[100, 100, 0.5], [110, 104, 0.6]];
  const pts2 = [[120, 110, 0.7], [130, 118, 0.8], [140, 130, 0.9]];
  student.sendJ({ type: 'stroke_begin', id: 's1', tool: 'pen', color: '#112233', width: 3, points: pts1 });
  const sb = await waitFor(teacher, (m) => m.type === 'stroke_begin' && m.studentId === SID);
  ok(sb && sb.id === 's1' && sb.color === '#112233' && JSON.stringify(sb.points) === JSON.stringify(pts1), 'stroke_begin 중계');
  student.sendJ({ type: 'stroke_points', id: 's1', points: pts2 });
  const sp = await waitFor(teacher, (m) => m.type === 'stroke_points' && m.studentId === SID);
  ok(sp && sp.id === 's1' && JSON.stringify(sp.points) === JSON.stringify(pts2), 'stroke_points 중계');
  student.sendJ({ type: 'stroke_end', id: 's1' });
  ok(!!(await waitFor(teacher, (m) => m.type === 'stroke_end' && m.studentId === SID && m.id === 's1')), 'stroke_end 중계');
  student.sendJ({ type: 'stroke_begin', id: 'h1', tool: 'highlighter', color: '#FFD43B', width: 20, points: [[90, 120, 0.5], [300, 122, 0.5]] });
  student.sendJ({ type: 'stroke_end', id: 'h1' });
  await waitFor(teacher, (m) => m.type === 'stroke_end' && m.id === 'h1');

  console.log('4) 잘못된 입력 / ping');
  student.send('{이건 JSON 이 아님');
  const bad = await waitFor(student, (m) => m.type === 'error');
  ok(bad && bad.reason === 'bad_json', '잘못된 JSON → error(bad_json), 연결 유지');
  student.sendJ({ type: 'ping' });
  ok(!!(await waitFor(student, (m) => m.type === 'pong')), 'ping → pong');

  console.log('5) 새 선생님 snapshot 에 현재 페이지 획 누적');
  const teacher2 = await open('teacher');
  const snap2 = await waitFor(teacher2, (m) => m.type === 'snapshot');
  const me = snap2 && snap2.students.find((s) => s.studentId === SID);
  const s1 = me && me.strokes.find((s) => s.id === 's1');
  ok(me && me.online && me.page && me.page.problemId === 'test-001', 'snapshot: 온라인 + 현재 페이지');
  ok(s1 && s1.points.length === 5, 'snapshot: stroke_points 가 획에 이어 붙음', s1 ? `${s1.points.length}점` : '없음');
  ok(me && me.strokes.some((s) => s.id === 'h1' && s.tool === 'highlighter'), 'snapshot: 형광펜 획 포함');

  console.log('6) erase / restore / clear');
  student.sendJ({ type: 'erase', ids: ['h1'] });
  const er = await waitFor(teacher, (m) => m.type === 'erase' && m.studentId === SID);
  ok(er && er.ids[0] === 'h1', 'erase 중계');
  student.sendJ({ type: 'restore', strokes: [{ id: 'r1', tool: 'pen', color: '#000000', width: 2, points: [[1, 1, 0.5], [2, 2, 0.5]] }] });
  const rs = await waitFor(teacher, (m) => m.type === 'restore' && m.studentId === SID);
  ok(rs && rs.strokes.length === 1 && rs.strokes[0].id === 'r1', 'restore 중계 (전체 교체)');
  const teacher3 = await open('teacher');
  const snap3 = await waitFor(teacher3, (m) => m.type === 'snapshot');
  const me3 = snap3 && snap3.students.find((s) => s.studentId === SID);
  ok(me3 && me3.strokes.length === 1 && me3.strokes[0].id === 'r1', 'restore 후 서버 상태도 교체됨');
  teacher3.close();
  student.sendJ({ type: 'clear' });
  ok(!!(await waitFor(teacher, (m) => m.type === 'clear' && m.studentId === SID)), 'clear 중계');

  console.log('7) 선생님 → 학생 메시지');
  teacher.sendJ({ type: 'message', studentId: SID, text: '풀이 과정을 써 보세요', clientId: 'c1' });
  const got = await waitFor(student, (m) => m.type === 'message');
  ok(got && got.text === '풀이 과정을 써 보세요' && got.from, '지정 학생에게 message 전달 (text, from)');
  const ack = await waitFor(teacher, (m) => m.type === 'message_ack' && m.clientId === 'c1');
  ok(ack && ack.ok && ack.delivered === 1, 'message_ack(delivered=1)');
  teacher.sendJ({ type: 'message', text: '전체 공지', clientId: 'c2' });
  const got2 = await waitFor(student, (m) => m.type === 'message');
  ok(got2 && got2.text === '전체 공지', 'studentId 없는 message → 전체 전달');
  teacher.sendJ({ type: 'message', studentId: 'nobody', text: 'hi', clientId: 'c3' });
  const ack3 = await waitFor(teacher, (m) => m.type === 'message_ack' && m.clientId === 'c3');
  ok(ack3 && !ack3.ok && ack3.delivered === 0, '없는 학생에게는 delivered=0');
  teacher.sendJ({ type: 'ping' });
  ok(!!(await waitFor(teacher, (m) => m.type === 'pong')), '선생님 ping → pong');

  console.log('8) answer / stats → records.json');
  student.sendJ({ type: 'answer', problemId: 'test-001', answer: '2', correct: true, timeMs: 42000 });
  const an = await waitFor(teacher, (m) => m.type === 'answer' && m.studentId === SID);
  ok(an && an.answer === '2' && an.correct === true && an.timeMs === 42000 && typeof an.at === 'number', 'answer 중계 (+at)');
  student.sendJ({ type: 'stats', total: 7, correct: 5, streak: 2, todayCount: 3, weakTopics: ['이차함수'] });
  const stt = await waitFor(teacher, (m) => m.type === 'stats' && m.studentId === SID);
  ok(stt && stt.total === 7 && stt.weakTopics[0] === '이차함수', 'stats 중계');
  await sleep(1600); // 저장 지연(1초) 이후
  let rec = null;
  try { rec = JSON.parse(fs.readFileSync(RECORDS, 'utf8')); } catch (e) { /* 아래에서 실패 처리 */ }
  const rme = rec && rec.students && rec.students[SID];
  ok(!!rme, `records.json 저장됨 (${RECORDS})`);
  ok(rme && rme.history[0] && rme.history[0].problemId === 'test-001' && rme.history[0].correct === true, 'records.json: history 최신 제출');
  ok(rme && rme.stats && rme.stats.total === 7, 'records.json: stats');
  ok(rme && rme.strokes === undefined, 'records.json: 획은 저장하지 않음');

  console.log('9) 같은 학생 재접속 → 예전 소켓 대체');
  const student2 = await open('student');
  const oldClosed = closed(student);
  student2.sendJ({ type: 'hello', studentId: SID, name: '테스트봇', device: 'node-2' });
  const oc = await Promise.race([oldClosed, sleep(2500).then(() => null)]);
  ok(oc && oc.code === 4000, '예전 소켓이 4000(replaced) 로 닫힘', oc ? `code ${oc.code}` : '안 닫힘');
  await sleep(200);
  ok(!teacher.inbox.some((m) => m.type === 'student_offline' && m.studentId === SID), '대체될 때는 student_offline 을 보내지 않음');
  teacher.sendJ({ type: 'message', studentId: SID, text: '새 소켓으로', clientId: 'c4' });
  ok(!!(await waitFor(student2, (m) => m.type === 'message' && m.text === '새 소켓으로')), '메시지는 새 소켓으로 전달');

  console.log('10) 큰 메시지 제한 (2MB)');
  const big = await open('student');
  const bigClosed = closed(big);
  big.send(JSON.stringify({ type: 'hello', studentId: 'x', pad: 'a'.repeat(2.2 * 1024 * 1024) }));
  const bc = await Promise.race([bigClosed, sleep(3000).then(() => null)]);
  ok(bc && bc.code === 1009, '2MB 초과 메시지 → 연결 종료(1009)', bc ? `code ${bc.code}` : '안 닫힘');

  console.log('11) 접속 종료 → student_offline');
  student2.close();
  ok(!!(await waitFor(teacher, (m) => m.type === 'student_offline' && m.studentId === SID)), 'student_offline 수신');

  console.log('12) HTTP');
  const idx = await get('/');
  ok(idx.status === 200 && idx.type.includes('text/html') && idx.body.includes('풀이노트'), 'GET / → 선생님 웹');
  ok((await get('/app.js')).status === 200 && (await get('/style.css')).status === 200, 'GET /app.js, /style.css');
  const info = await get('/api/info');
  let infoJ = null; try { infoJ = JSON.parse(info.body); } catch (_) { /* */ }
  ok(info.status === 200 && infoJ && Array.isArray(infoJ.wsUrls), 'GET /api/info', infoJ ? infoJ.wsUrls.join(', ') : '');
  ok((await get('/%2e%2e/server.js')).status !== 200 && (await get('/../package.json')).status !== 200, 'public/ 밖 파일은 열리지 않음');
  const badRole = await new Promise((r) => {
    const w = new WebSocket(`${WS_URL}?role=hacker`);
    w.on('open', () => { w.close(); r(false); });
    w.on('error', () => r(true));
  });
  ok(badRole, 'role 이 없거나 틀리면 WebSocket 거절');

  teacher.close(); teacher2.close();
  console.log(`\n결과: ${passed}개 통과, ${failed}개 실패`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
