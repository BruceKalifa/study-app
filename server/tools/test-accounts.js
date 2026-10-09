#!/usr/bin/env node
'use strict';
/**
 * 계정 · 선생님-학생 연결 · 풀이 기록 · 1:1 질문 API 점검 (서버를 직접 띄워서 확인)
 *
 *   npm run test:accounts
 *   node tools/test-accounts.js [--keep]
 */

const fs = require('fs');
const os = require('os');
const net = require('net');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.join(__dirname, '..');
const SEED_DIR = path.join(SERVER_DIR, '..', 'assets', 'problems');
const KEEP = process.argv.includes('--keep');
const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

let passed = 0;
let failed = 0;
function ok(cond, label, extra) {
  if (cond) { passed++; console.log(`  ✔ ${label}`); }
  else { failed++; console.log(`  ✘ ${label}${extra !== undefined ? ' — ' + (typeof extra === 'string' ? extra : JSON.stringify(extra).slice(0, 400)) : ''}`); }
}
function section(t) { console.log(`\n■ ${t}`); }

function freePort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.unref();
    s.on('error', reject);
    s.listen(0, '127.0.0.1', () => { const { port } = s.address(); s.close(() => resolve(port)); });
  });
}

let child = null;
let base = '';
let logBuf = '';
async function startServer(env) {
  const port = await freePort();
  base = `http://127.0.0.1:${port}`;
  child = spawn(process.execPath, [path.join(SERVER_DIR, 'server.js')], {
    env: Object.assign({}, process.env, { PORT: String(port), HOST: '127.0.0.1' }, env),
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout.on('data', (d) => { logBuf += d; });
  child.stderr.on('data', (d) => { logBuf += d; });
  for (let i = 0; i < 100; i++) {
    try { const r = await fetch(base + '/healthz'); if (r.ok) return; } catch (_) { /* 아직 */ }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error('서버가 켜지지 않았습니다\n' + logBuf);
}
async function stopServer() {
  if (!child) return;
  const c = child;
  child = null;
  await new Promise((resolve) => { c.on('exit', resolve); c.kill('SIGTERM'); setTimeout(resolve, 3000); });
}

async function req(method, p, body, token) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(base + p, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined });
  const buf = Buffer.from(await res.arrayBuffer());
  const text = buf.toString('utf8');
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch (_) { /* binary */ }
  return { status: res.status, json, text, buf, headers: res.headers };
}
const get = (p, t) => req('GET', p, undefined, t);
const post = (p, b, t) => req('POST', p, b, t);
const del = (p, t) => req('DELETE', p, undefined, t);
const isKo = (r) => r.json && typeof r.json.error === 'string' && /[가-힣]/.test(r.json.error);

function attempt(id, pid, ok, at, extra) {
  return Object.assign({ id, pid, base: pid.split('~')[0], sub: pid.split('-')[0], unit: '역학', topic: '등가속도', ans: ok ? '3' : '1', exp: '3', ok, ms: 30000, at, mode: 'practice' }, extra || {});
}

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pulinote-accounts-test-'));
  const DATA_DIR = path.join(tmp, 'data');
  const env = { CONTENT_DIR: path.join(tmp, 'content'), DATA_DIR, ADMIN_KEY: 'k-1234', SEED_DIR };
  console.log(`임시 폴더: ${tmp}`);
  await startServer(env);

  // ───────── 가입 ─────────
  section('가입 · 로그인');
  let r = await post('/api/auth/signup', { role: 'admin', loginId: 'abcd', password: '123456', name: '가' });
  ok(r.status === 400 && isKo(r), 'role 이 학생/선생님이 아니면 400');
  r = await post('/api/auth/signup', { role: 'student', loginId: 'ab', password: '123456', name: '가' });
  ok(r.status === 400 && isKo(r), '아이디 너무 짧으면 400');
  r = await post('/api/auth/signup', { role: 'student', loginId: '한글아이디', password: '123456', name: '가' });
  ok(r.status === 400, '아이디에 한글이면 400');
  r = await post('/api/auth/signup', { role: 'student', loginId: 'yejin01', password: '123', name: '가' });
  ok(r.status === 400 && /6자/.test(r.json.error), '비밀번호 6자 미만이면 400');
  r = await post('/api/auth/signup', { role: 'student', loginId: 'yejin01', password: '123456', name: '' });
  ok(r.status === 400, '이름 없으면 400');
  r = await post('/api/auth/signup', { role: 'student', loginId: 'yejin01', password: '123456', name: '오예진', grade: '중3' });
  ok(r.status === 400, '고등 외 학년이면 400');

  r = await post('/api/auth/signup', { role: 'teacher', loginId: 'Teacher.Une', password: 'phys-pass-1', name: '우네 선생님' });
  ok(r.status === 200 && r.json.token && r.json.user.role === 'teacher', '선생님 가입', r.json);
  ok(r.json.user.loginId === 'teacher.une', '아이디는 소문자로 저장');
  ok(/^[A-HJ-NP-Z2-9]{6}$/.test(r.json.inviteCode || ''), '선생님은 6자리 초대 코드를 받는다', r.json.inviteCode);
  ok(!('passHash' in r.json.user) && !('salt' in r.json.user), '응답에 비밀번호 해시 없음');
  const T = { token: r.json.token, id: r.json.user.id, code: r.json.inviteCode };

  r = await post('/api/auth/signup', { role: 'teacher', loginId: 'other.t', password: 'other-pass', name: '김선생' });
  const T2 = { token: r.json.token, id: r.json.user.id, code: r.json.inviteCode };
  ok(T2.code !== T.code, '초대 코드는 선생님마다 다르다');

  r = await post('/api/auth/signup', { role: 'student', loginId: 'yejin01', password: 'secret-77', name: '오예진', grade: '고3' });
  ok(r.status === 200 && r.json.user.grade === '고3' && Array.isArray(r.json.teachers) && r.json.teachers.length === 0, '학생 가입', r.json);
  ok(!('inviteCode' in r.json), '학생에게는 초대 코드가 없다');
  ok(typeof r.json.communityKey === 'string' && r.json.communityKey.length >= 16, '본인에게만 커뮤니티 키를 준다');
  const S = { token: r.json.token, id: r.json.user.id, key: r.json.communityKey };
  r = await post('/api/auth/signup', { role: 'student', loginId: 'YEJIN01', password: 'secret-77', name: '다른 예진' });
  ok(r.status === 409 && isKo(r), '같은 아이디(대소문자만 다름) 409');
  r = await post('/api/auth/signup', { role: 'student', loginId: 'minsu.k', password: 'minsu-pass', name: '김민수', grade: '고2' });
  const S2 = { token: r.json.token, id: r.json.user.id };

  r = await post('/api/auth/login', { loginId: 'yejin01', password: 'wrong-pass' });
  ok(r.status === 401 && isKo(r), '비밀번호 틀리면 401');
  r = await post('/api/auth/login', { loginId: 'nobody', password: 'whatever' });
  ok(r.status === 401, '없는 아이디도 같은 401');
  r = await post('/api/auth/login', { loginId: ' YeJin01 ', password: 'secret-77' });
  ok(r.status === 200 && r.json.user.id === S.id && r.json.token !== S.token, '아이디 대소문자·공백 무시하고 로그인 (새 토큰)');
  const S_dev2 = r.json.token;

  for (let i = 0; i < 8; i++) await post('/api/auth/login', { loginId: 'minsu.k', password: 'bad' });
  r = await post('/api/auth/login', { loginId: 'minsu.k', password: 'minsu-pass' });
  ok(r.status === 429 && isKo(r), '8번 틀리면 잠시 잠금(맞는 비밀번호도 429)');

  r = await get('/api/me');
  ok(r.status === 401 && isKo(r), '토큰 없으면 401');
  r = await get('/api/me', 'not-a-token');
  ok(r.status === 401, '잘못된 토큰 401');
  r = await get('/api/me', S.token);
  ok(r.status === 200 && r.json.user.name === '오예진' && r.json.counts, '내 정보', r.json);
  r = await post('/api/me', { name: '오예진', grade: '고2' }, S.token);
  ok(r.status === 200 && r.json.user.grade === '고2', '학년 바꾸기');
  await post('/api/me', { grade: '고3' }, S.token);

  section('학년·과정 복수 선택');
  r = await post('/api/auth/signup', { role: 'student', loginId: 'hyu.multi', password: 'multi-pass', name: '한양대생', grades: ['한양대', 'N수', '편입', 'N수'] });
  ok(r.status === 200 && r.json.user.grade === '한양대' && JSON.stringify(r.json.user.grades) === '["한양대","N수","편입"]', '여러 개로 가입 (대표 = 첫 번째, 중복 제거)', r.json.user);
  const M = { token: r.json.token };
  r = await post('/api/auth/signup', { role: 'student', loginId: 'hyu.bad', password: 'multi-pass', name: '잘못', grades: ['한양대', '중3'] });
  ok(r.status === 400, '없는 학년이 섞이면 400');
  r = await post('/api/auth/signup', { role: 'student', loginId: 'old.client', password: 'multi-pass', name: '옛앱', grade: '취준' });
  ok(r.status === 200 && r.json.user.grade === '취준' && JSON.stringify(r.json.user.grades) === '["취준"]', '옛 앱(grade 하나)도 가입된다');
  r = await post('/api/me', { grades: ['편입', '한양대'] }, M.token);
  ok(r.status === 200 && r.json.user.grade === '편입' && r.json.user.grades.length === 2, '정보 수정으로 복수 학년 바꾸기', r.json.user);
  r = await post('/api/student/sync', { attempts: [], learner: { grade: '고3', grades: ['고3', '한양대'], goal: '수능' } }, M.token);
  r = await get('/api/me', M.token);
  ok(r.json.user.grade === '고3' && JSON.stringify(r.json.user.grades) === '["고3","한양대"]', '풀이 기록 동기화로도 반영', r.json.user);

  // ───────── 연결 ─────────
  section('선생님 ⇄ 학생 연결');
  r = await post('/api/student/teachers', { code: 'ZZZZZZ' }, S.token);
  ok(r.status === 404 && isKo(r), '틀린 초대 코드 404');
  r = await post('/api/student/teachers', { code: T.code }, T2.token);
  ok(r.status === 403, '선생님은 다른 선생님에게 연결할 수 없다');
  r = await post('/api/student/teachers', { code: ` ${T.code.slice(0, 3).toLowerCase()}-${T.code.slice(3)} ` }, S.token);
  ok(r.status === 200 && r.json.teacher.id === T.id && r.json.teacher.name === '우네 선생님', '초대 코드로 연결 (소문자·하이픈 허용)', r.json);
  r = await post('/api/student/teachers', { code: T.code }, S.token);
  ok(r.status === 200, '같은 선생님 다시 연결해도 괜찮다');
  r = await get('/api/me', S.token);
  ok(r.json.teachers.length === 1 && r.json.teachers[0].id === T.id, '내 선생님 목록');
  await post('/api/student/teachers', { code: T.code }, S2.token);
  await post('/api/student/teachers', { code: T2.code }, S2.token);

  r = await get('/api/teacher/students', S.token);
  ok(r.status === 403 && isKo(r), '학생은 선생님 API 403');
  r = await get('/api/teacher/students', T.token);
  ok(r.status === 200 && r.json.students.length === 2 && r.json.inviteCode === T.code, '선생님: 연결된 학생 2명', r.json);
  ok(!r.text.includes(S.key), '학생의 커뮤니티 키는 선생님에게 보이지 않는다');
  r = await get('/api/teacher/students', T2.token);
  ok(r.json.students.length === 1 && r.json.students[0].name === '김민수', '다른 선생님은 자기 학생만');

  // ───────── 기록 ─────────
  section('풀이 기록 동기화');
  const now = Date.now();
  const atts = [
    attempt('a1', 'phy1-mech-001', false, now - 3 * 86400000),
    attempt('a2', 'phy1-mech-001~v12', true, now - 2 * 86400000),
    attempt('a3', 'phy1-mech-005', false, now - 3000, { ans: '2', exp: '4', topic: '운동량' }),
    attempt('a4', 'phy1-em-002', true, now - 2000, { sub: 'phy1', unit: '전자기' }),
    attempt('a5', 'math-seq-003', false, now - 1000, { sub: 'math', unit: '수열', topic: '귀납적 정의', ans: '12', exp: '14' }),
    { id: '', pid: 'x', at: now }, // 잘못된 것 (무시)
    { id: 'bad2', at: now }, // pid 없음 (무시)
  ];
  r = await post('/api/student/sync', { attempts: atts, learner: { grade: '고3', goal: '수능', workbooks: ['wb-phy1-real1', 'wb-math-real1'], examName: '수능', examDate: now + 40 * 86400000 }, wrongNote: ['phy1-mech-005', 'math-seq-003'] }, S.token);
  ok(r.status === 200 && r.json.stored === 5 && r.json.total === 5, '풀이 5개 저장 (잘못된 2개 무시)', r.json);
  r = await post('/api/student/sync', { attempts: atts.slice(0, 3) }, S.token);
  ok(r.json.stored === 0 && r.json.total === 5, '같은 풀이는 다시 저장하지 않는다', r.json);
  r = await post('/api/student/sync', { attempts: 'nope' }, S.token);
  ok(r.status === 400, 'attempts 가 배열이 아니면 400');
  r = await post('/api/student/sync', { attempts: [] }, T.token);
  ok(r.status === 403, '선생님은 sync 403');
  r = await post('/api/student/sync', { learner: { big: 'x'.repeat(70000) } }, S.token);
  ok(r.status === 413, 'learner 64KB 넘으면 413');

  r = await get('/api/teacher/students', T.token);
  const sum = r.json.students.find((x) => x.id === S.id);
  ok(sum && sum.solved === 5 && sum.correct === 2 && sum.wrongOpen === 2, '요약: 5문제 · 2정답 · 오답노트 2', sum);
  ok(sum.today.solved >= 2 && sum.week.solved === 5, '오늘/이번 주 집계', sum);
  ok(r.json.students[0].id === S.id, '최근에 푼 학생이 위로');

  r = await get(`/api/teacher/students/${S.id}`, T.token);
  ok(r.status === 200, '학생 상세');
  const d = r.json;
  ok(d.wrong.length === 3, '틀린 적 있는 문제 3개', d.wrong);
  ok(d.wrong[0].open && d.wrong[1].open && !d.wrong[2].open, '오답노트에 남은 것 먼저, 해결한 것은 open=false', d.wrong.map((w) => [w.baseId, w.open]));
  const w5 = d.wrong.find((w) => w.baseId === 'phy1-mech-005');
  ok(w5 && w5.answer === '2' && w5.expected === '4' && w5.topic === '운동량', '학생이 쓴 답과 정답', w5);
  const w1 = d.wrong.find((w) => w.baseId === 'phy1-mech-001');
  ok(w1 && w1.tries === 2 && w1.correct === 1 && w1.lastCorrect === true, '변형을 맞힌 것도 원래 문제로 센다', w1);
  ok(d.bySubject.find((x) => x.subjectId === 'phy1').solved === 4, '과목별', d.bySubject);
  ok(d.byDay.length === 14 && d.byDay[13].solved >= 2, '최근 14일', d.byDay.slice(-2));
  ok(d.recent.length === 5 && d.recent[0].id === 'a5', '최근 풀이 (최신이 앞)');
  ok(d.learner.workbooks.join() === 'wb-phy1-real1,wb-math-real1' && d.learner.goal === '수능', '학생의 내 교재');
  r = await get(`/api/teacher/students/${S.id}`, T2.token);
  ok(r.status === 404 && isKo(r), '연결 안 된 선생님은 404');
  r = await get(`/api/teacher/students/${S2.id}`, T2.token);
  ok(r.status === 200 && r.json.wrong.length === 0, '기록 없는 학생도 열린다');

  r = await get('/api/student/records', S_dev2);
  ok(r.status === 200 && r.json.attempts.length === 5 && r.json.learner.workbooks.length === 2 && r.json.wrongNote.length === 2, '새 기기에서 기록 되살리기');

  // ───────── 질문 ─────────
  section('1:1 질문');
  r = await post('/api/questions', { teacherId: T2.id, body: '질문' }, S.token);
  ok(r.status === 403 && isKo(r), '연결 안 된 선생님에게는 질문 403');
  r = await post('/api/questions', { teacherId: T.id }, S.token);
  ok(r.status === 400 && isKo(r), '내용도 그림도 없으면 400');
  r = await post('/api/questions', { teacherId: T.id, body: '질문', image: 'data:image/gif;base64,R0lGODlhAQABAAAAACw=' }, S.token);
  ok(r.status === 400, 'PNG/JPEG 가 아니면 400');
  r = await post('/api/questions', { teacherId: T.id, problemId: 'phy1-mech-005', title: '운동량 보존 질문', body: '충돌 후 속도를 어떻게 구하나요?\n$m_1v_1 = m_2v_2$ 맞나요?', image: 'data:image/png;base64,' + PNG }, S.token);
  ok(r.status === 200 && r.json.question.status === 'open' && r.json.question.messages.length === 1, '질문 + 풀이 사진', r.json);
  const Q = r.json.question;
  ok(Q.messages[0].image && Q.messages[0].image.startsWith(`/api/questions/${Q.id}/images/`), '그림 주소');
  ok(Q.problemId === 'phy1-mech-005' && Q.student.name === '오예진' && Q.teacher.name === '우네 선생님', '문제·학생·선생님');
  r = await post('/api/questions', { teacherId: T.id, body: '시험 범위가 어디까지인가요?' }, S2.token);
  const Q2 = r.json.question;
  ok(Q2.title === '질문', '제목 없으면 "질문"');

  r = await post('/api/questions', { teacherId: T.id, body: 'x' }, T.token);
  ok(r.status === 403, '선생님은 질문을 만들 수 없다');
  r = await get('/api/questions', T.token);
  ok(r.status === 200 && r.json.questions.length === 2 && r.json.questions.every((q) => q.unread), '선생님 질문함: 2개 · 안 읽음', r.json);
  r = await get('/api/me', T.token);
  ok(r.json.counts.openQuestions === 2 && r.json.counts.unreadQuestions === 2, '선생님 알림 수', r.json.counts);
  r = await get(`/api/questions?student=${S.id}`, T.token);
  ok(r.json.questions.length === 1 && r.json.questions[0].id === Q.id, '학생별로 거르기');
  r = await get('/api/questions', T2.token);
  ok(r.json.questions.length === 0, '다른 선생님에게는 안 보인다');
  r = await get(`/api/questions/${Q.id}`, T2.token);
  ok(r.status === 404, '다른 선생님은 읽을 수 없다');
  r = await get(`/api/questions/${Q.id}`, S2.token);
  ok(r.status === 404, '다른 학생은 읽을 수 없다');

  r = await get(Q.messages[0].image, T.token);
  ok(r.status === 200 && r.headers.get('content-type') === 'image/png' && r.buf.equals(Buffer.from(PNG, 'base64')), '선생님이 풀이 사진을 받는다');
  r = await get(Q.messages[0].image);
  ok(r.status === 401, '그림도 로그인 필요');
  r = await get(Q.messages[0].image, T2.token);
  ok(r.status === 404, '다른 선생님은 그림도 못 본다');
  r = await get(`/api/questions/${Q.id}/images/..%2F..%2Faccounts.json`, T.token);
  ok(r.status === 404, '경로 조작 차단');

  r = await get(`/api/questions/${Q.id}`, T.token);
  ok(r.status === 200 && r.json.question.messages[0].body.includes('m_1v_1') && !r.json.question.messages[0].mine, '선생님이 질문을 읽는다');
  r = await get('/api/questions', T.token);
  ok(r.json.questions.find((q) => q.id === Q.id).unread === false, '읽으면 unread=false');

  r = await post(`/api/questions/${Q.id}/messages`, { body: '충돌 전후 운동량의 합이 같아요. 필기로 정리했어요.', image: PNG }, T.token);
  ok(r.status === 200 && r.json.question.status === 'answered' && r.json.question.messages.length === 2, '선생님 답장 (필기 그림 포함)');
  ok(r.json.question.messages[1].from === 'teacher' && r.json.question.messages[1].mine && r.json.question.messages[1].image, '답장 메시지');
  r = await get('/api/me', S.token);
  ok(r.json.counts.unreadQuestions === 1, '학생: 안 읽은 답장 1', r.json.counts);
  r = await get('/api/questions?status=answered', S.token);
  ok(r.json.questions.length === 1 && r.json.questions[0].lastFrom === 'teacher' && r.json.questions[0].unread, '학생: 답변 온 질문');
  r = await get(`/api/questions/${Q.id}`, S.token);
  ok(r.json.question.messages[1].name === '우네 선생님', '학생이 답장을 읽는다');
  r = await get('/api/me', S.token);
  ok(r.json.counts.unreadQuestions === 0, '읽으면 0');
  r = await post(`/api/questions/${Q.id}/messages`, { body: '이해했어요! 그런데 탄성 충돌이면요?' }, S.token);
  ok(r.json.question.status === 'open', '학생이 다시 물으면 open');
  r = await post(`/api/questions/${Q.id}/messages`, {}, S.token);
  ok(r.status === 400, '빈 메시지 400');
  r = await post(`/api/questions/${Q.id}/resolve`, {}, S.token);
  ok(r.status === 200, '해결됨');
  r = await get('/api/questions?status=resolved', T.token);
  ok(r.json.questions.length === 1 && r.json.questions[0].id === Q.id, '선생님: 해결된 질문');
  r = await get('/api/questions?status=nope', T.token);
  ok(r.status === 400, '잘못된 status 400');

  // ───────── 끊기 · 비밀번호 · 로그아웃 ─────────
  section('연결 끊기 · 비밀번호 · 로그아웃');
  r = await del(`/api/teacher/students/${S2.id}`, T.token);
  ok(r.status === 200, '선생님이 학생 연결 끊기');
  r = await get(`/api/teacher/students/${S2.id}`, T.token);
  ok(r.status === 404, '끊으면 기록을 볼 수 없다');
  r = await get(`/api/questions/${Q2.id}`, T.token);
  ok(r.status === 200, '이미 주고받은 질문은 남는다');
  r = await del(`/api/student/teachers/${T2.id}`, S2.token);
  ok(r.status === 200, '학생이 선생님 연결 끊기');
  r = await get('/api/teacher/students', T2.token);
  ok(r.json.students.length === 0, '선생님 목록에서 빠진다');
  r = await del(`/api/student/teachers/${T2.id}`, S2.token);
  ok(r.status === 404, '이미 끊긴 연결 404');

  const oldCode = T.code;
  r = await post('/api/teacher/invite', {}, T.token);
  ok(r.status === 200 && r.json.inviteCode !== oldCode, '초대 코드 새로 만들기');
  r = await post('/api/student/teachers', { code: oldCode }, S2.token);
  ok(r.status === 404, '예전 코드는 더 안 된다');

  r = await post('/api/me/password', { current: 'nope', next: 'new-secret-1' }, S.token);
  ok(r.status === 401, '지금 비밀번호 틀리면 401');
  r = await post('/api/me/password', { current: 'secret-77', next: 'new-secret-1' }, S.token);
  ok(r.status === 200, '비밀번호 바꾸기');
  r = await get('/api/me', S_dev2);
  ok(r.status === 401, '다른 기기의 로그인은 끊긴다');
  r = await get('/api/me', S.token);
  ok(r.status === 200, '지금 기기는 그대로');
  r = await post('/api/auth/login', { loginId: 'yejin01', password: 'new-secret-1' });
  ok(r.status === 200, '새 비밀번호로 로그인');
  const S3 = r.json.token;
  r = await post('/api/auth/logout', {}, S3);
  r = await get('/api/me', S3);
  ok(r.status === 401, '로그아웃한 토큰은 401');

  // ───────── 저장 ─────────
  section('재시작 후 유지 · 저장 내용');
  await stopServer();
  const acc = fs.readFileSync(path.join(DATA_DIR, 'accounts.json'), 'utf8');
  ok(!acc.includes('secret-77') && !acc.includes('new-secret-1') && !acc.includes('phys-pass-1'), '비밀번호 원문은 저장하지 않는다');
  ok(!acc.includes(S.token) && !acc.includes(T.token), '토큰 원문도 저장하지 않는다');
  ok(fs.readdirSync(path.join(DATA_DIR, 'question-images')).length === 2, '그림 파일 2개');
  await startServer(env);
  r = await get('/api/me', S.token);
  ok(r.status === 200 && r.json.teachers.length === 1, '재시작 후에도 로그인 유지');
  r = await get(`/api/teacher/students/${S.id}`, T.token);
  ok(r.status === 200 && r.json.recent.length === 5, '재시작 후에도 기록 유지');
  r = await get(`/api/questions/${Q.id}`, T.token);
  ok(r.status === 200 && r.json.question.messages.length === 3 && r.json.question.status === 'resolved', '재시작 후에도 질문 유지');
  r = await req('OPTIONS', '/api/me');
  ok(r.status === 204 && /Authorization/.test(r.headers.get('access-control-allow-headers') || ''), 'CORS: Authorization 허용');

  await stopServer();
  if (!KEEP) fs.rmSync(tmp, { recursive: true, force: true });
  console.log(`\n결과: ${passed}개 통과, ${failed}개 실패`);
  process.exit(failed ? 1 : 0);
}

main().catch(async (e) => {
  console.error(e);
  console.error(logBuf.slice(-3000));
  await stopServer();
  process.exit(1);
});
