#!/usr/bin/env node
'use strict';
/**
 * 교재 창고 API 점검 — 선생님이 올리고, 공개한 교재는 모든 학생이 · 공개 안 한 교재는 지정된 학생만 받는지 (서버를 직접 띄워서 확인)
 *
 *   npm run test:books
 */

const fs = require('fs');
const os = require('os');
const net = require('net');
const path = require('path');
const zlib = require('zlib');
const { spawn } = require('child_process');

const SERVER_DIR = path.join(__dirname, '..');
const SEED_DIR = path.join(SERVER_DIR, '..', 'assets', 'problems');

/** 테스트 서버의 선생님 가입 승인 코드 */
const TC = 'test-teacher-code';
let passed = 0;
let failed = 0;
function ok(cond, label, extra) {
  if (cond) { passed++; console.log(`  ✔ ${label}`); }
  else { failed++; console.log(`  ✘ ${label}${extra !== undefined ? ' — ' + (typeof extra === 'string' ? extra : JSON.stringify(extra).slice(0, 300)) : ''}`); }
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

async function req(method, p, body, token, raw) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined && !raw) headers['Content-Type'] = 'application/json';
  if (raw) headers['Content-Type'] = 'application/octet-stream';
  const res = await fetch(base + p, {
    method,
    headers,
    body: body === undefined ? undefined : raw ? body : JSON.stringify(body),
  });
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

/** 테스트용 .pulinote (gzip JSON) */
function bundle(id, title, problems = 2) {
  return {
    format: 'pulinote-bundle',
    version: 1,
    id,
    title,
    courses: [{
      id: `course-${id}`,
      name: title,
      problems: Array.from({ length: problems }, (_, i) => ({
        id: `${id}-p${i + 1}`, unit: '단원', topic: '주제', difficulty: 2, type: '객관식',
        stem: `문제 ${i + 1}`, answer: '3',
      })),
      twins: [],
      passages: [],
    }],
    workbooks: [{ id: `wb-${id}`, title, scope: '수학', problemIds: [`${id}-p1`] }],
  };
}
const gz = (obj) => zlib.gzipSync(Buffer.from(JSON.stringify(obj), 'utf8'));

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pulinote-books-test-'));
  const env = { CONTENT_DIR: path.join(tmp, 'content'), DATA_DIR: path.join(tmp, 'data'), ADMIN_KEY: 'k-1234', SEED_DIR, TEACHER_SIGNUP_CODE: TC };
  console.log(`임시 폴더: ${tmp}`);
  await startServer(env);

  // ───────── 계정 ─────────
  section('계정 준비');
  let r = await post('/api/auth/signup', { role: 'teacher', loginId: 'book.teacher', password: 'teach-pass-1', name: '우네 선생님', teacherCode: TC });
  const T = { token: r.json.token, id: r.json.user.id, code: r.json.inviteCode };
  r = await post('/api/auth/signup', { role: 'teacher', loginId: 'other.teacher', password: 'teach-pass-2', name: '김선생', teacherCode: TC });
  const T2 = { token: r.json.token, id: r.json.user.id };
  r = await post('/api/auth/signup', { role: 'student', loginId: 'mine.student', password: 'stu-pass-1', name: '내 학생', grade: '고3' });
  const S = { token: r.json.token, id: r.json.user.id };
  r = await post('/api/auth/signup', { role: 'student', loginId: 'far.student', password: 'stu-pass-2', name: '남의 학생', grade: '고2' });
  const S2 = { token: r.json.token, id: r.json.user.id };
  r = await post('/api/student/teachers', { code: T.code }, S.token);
  ok(r.status === 200, '학생이 선생님과 연결됨', r.json);

  // ───────── 올리기 ─────────
  section('교재 올리기');
  r = await req('POST', '/api/books', gz(bundle('flow01', '수학1 FLOW TYPE 1')), '', true);
  ok(r.status === 401 && isKo(r), '로그인 없이 올리면 401');
  r = await req('POST', '/api/books', gz(bundle('flow01', '수학1 FLOW TYPE 1')), S.token, true);
  ok(r.status === 403 && isKo(r), '학생이 올리면 403');
  r = await req('POST', '/api/books', Buffer.from('안녕하세요 그냥 글'), T.token, true);
  ok(r.status === 400 && isKo(r), '교재 파일이 아니면 400', r.json);
  r = await req('POST', '/api/books', gz({ format: 'pulinote-bundle', id: 'empty', title: '빈 교재', courses: [] }), T.token, true);
  ok(r.status === 400, '문항이 없으면 400', r.json);
  r = await req('POST', '/api/books', gz(bundle('../etc', '나쁜 id')), T.token, true);
  ok(r.status === 400, '교재 id 가 이상하면 400');

  r = await req('POST', '/api/books', gz(bundle('flow01', '수학1 FLOW TYPE 1', 3)), T.token, true);
  ok(r.status === 200 && r.json.book && r.json.book.problems === 3, '선생님이 교재를 올린다', r.json);
  ok(r.json.book.title === '수학1 FLOW TYPE 1', '제목은 파일에서 가져온다', r.json.book);
  ok(Array.isArray(r.json.book.bookIds) && r.json.book.bookIds[0] === 'flow01', '교재 id 를 알려준다');
  ok(r.json.book.mine === true && r.json.book.open === true, '올린 사람에게는 공개 여부가 보인다', r.json.book);
  const B1 = r.json.book.id;

  const collection = { format: 'pulinote-collection', books: [bundle('b1', '책 하나'), bundle('b2', '책 둘')] };
  r = await req('POST', '/api/books?title=' + encodeURIComponent('교재 꾸러미'), gz(collection), T.token, true);
  ok(r.status === 200 && r.json.book.bookIds.length === 2 && r.json.book.problems === 4, '여러 권 묶음도 올라간다', r.json.book);
  ok(r.json.book.title === '교재 꾸러미', 'title= 로 제목을 정한다');
  const B2 = r.json.book.id;

  r = await req('POST', '/api/books', gz(bundle('flow01', '수학1 FLOW TYPE 1 (고침)', 4)), T.token, true);
  ok(r.status === 200 && r.json.replaced === true && r.json.book.id === B1, '같은 교재를 다시 올리면 덮어쓴다', r.json);
  ok(r.json.book.problems === 4, '덮어쓴 내용이 반영된다');

  // 다른 선생님 교재
  r = await req('POST', '/api/books?open=0', gz(bundle('other01', '남의 교재')), T2.token, true);
  const BX = r.json.book.id;

  // ───────── 목록 ─────────
  section('목록');
  r = await get('/api/books');
  ok(r.status === 401, '로그인 없이 목록 401');
  r = await get('/api/books', T.token);
  ok(r.status === 200 && r.json.books.length === 2, '선생님은 자기가 올린 교재만 본다', r.json.books.map((b) => b.title));
  r = await get('/api/books', S.token);
  ok(r.status === 200 && r.json.books.length === 2, '연결된 학생은 선생님 교재를 본다', r.json.books.map((b) => b.title));
  ok(r.json.books.every((b) => b.mine === undefined && b.students === undefined), '학생에게는 공개 설정이 보이지 않는다', r.json.books[0]);
  ok(r.json.books[0].teacher && r.json.books[0].teacher.name === '우네 선생님', '누가 올린 교재인지 보인다');
  r = await get('/api/books', S2.token);
  ok(r.status === 200 && r.json.books.length === 2, '연결 안 된 학생도 공개한 교재는 본다 (공개 안 한 남의 교재는 안 보인다)', r.json.books.map((b) => b.title));

  // ───────── 받기 ─────────
  section('내려받기');
  r = await get(`/api/books/${B1}/file`);
  ok(r.status === 401, '로그인 없이 파일 401');
  r = await get(`/api/books/${B1}/file`, S2.token);
  ok(r.status === 200, '연결 안 된 학생도 공개한 교재 파일은 받는다', r.status);
  r = await get(`/api/books/${B1}/file`, T2.token);
  ok(r.status === 404, '다른 선생님도 받을 수 없다');
  r = await get(`/api/books/${BX}/file`, S.token);
  ok(r.status === 404, '공개하지 않은 남의 교재는 받을 수 없다');

  r = await get(`/api/books/${B1}/file`, S.token);
  ok(r.status === 200, '연결된 학생이 파일을 받는다', r.status);
  let got = null;
  try { got = JSON.parse(zlib.gunzipSync(r.buf).toString('utf8')); } catch (e) { /* 아래에서 실패 */ }
  ok(got && got.format === 'pulinote-bundle' && got.id === 'flow01', '받은 파일은 올린 그대로다', got && got.id);
  ok(got && got.courses[0].problems.length === 4, '덮어쓴 내용을 받는다');
  r = await get(`/api/books/${B2}/file`, S.token);
  got = JSON.parse(zlib.gunzipSync(r.buf).toString('utf8'));
  ok(got.format === 'pulinote-collection' && got.books.length === 2, '묶음 파일도 그대로 받는다');

  // ───────── 공개 설정 ─────────
  section('공개 설정');
  r = await post(`/api/books/${B2}`, { open: false }, T.token);
  ok(r.status === 200 && r.json.book.open === false, '교재를 숨긴다', r.json);
  r = await get('/api/books', S.token);
  ok(r.json.books.length === 1, '숨긴 교재는 학생 목록에서 빠진다', r.json.books.map((b) => b.title));
  r = await get(`/api/books/${B2}/file`, S.token);
  ok(r.status === 404, '숨긴 교재는 받을 수 없다');
  r = await post(`/api/books/${B2}`, { students: [S.id, S2.id] }, T.token);
  ok(r.status === 200 && r.json.book.students.length === 1 && r.json.book.students[0] === S.id, '내 학생에게만 지정된다', r.json.book);
  r = await get(`/api/books/${B2}/file`, S.token);
  ok(r.status === 200, '지정된 학생은 숨긴 교재도 받는다');
  r = await get(`/api/books/${B2}/file`, S2.token);
  ok(r.status === 404, '지정 안 된 학생은 못 받는다');
  r = await post(`/api/books/${B2}`, { title: '이름 바꾼 교재', open: true }, T.token);
  ok(r.json.book.title === '이름 바꾼 교재', '제목을 바꾼다');
  r = await post(`/api/books/${B1}`, { title: '남이 바꾸기' }, T2.token);
  ok(r.status === 403 && isKo(r), '남의 교재는 바꿀 수 없다');

  // ───────── 지우기 ─────────
  section('지우기');
  r = await del(`/api/books/${B1}`, S.token);
  ok(r.status === 403, '학생은 지울 수 없다');
  r = await del(`/api/books/${B1}`, T2.token);
  ok(r.status === 403, '남의 교재는 지울 수 없다');
  r = await del(`/api/books/${B1}`, T.token);
  ok(r.status === 200, '올린 선생님이 지운다');
  r = await get(`/api/books/${B1}/file`, S.token);
  ok(r.status === 404, '지운 교재는 받을 수 없다');
  ok(!fs.existsSync(path.join(env.DATA_DIR, 'books', `${B1}.pulinote`)), '파일도 함께 지워진다');

  // ───────── 다시 켜도 남는지 ─────────
  section('서버를 껐다 켜도');
  await stopServer();
  await startServer(env);
  r = await get('/api/books', S.token);
  ok(r.status === 200 && r.json.books.length === 1 && r.json.books[0].title === '이름 바꾼 교재', '교재가 그대로 남는다', r.json.books);
  r = await get(`/api/books/${B2}/file`, S.token);
  ok(r.status === 200 && r.buf.length > 0, '파일도 그대로 받아진다');

  await stopServer();
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(`\n${failed === 0 ? '✔ 모두 통과' : '✘ 실패 있음'} — 성공 ${passed}, 실패 ${failed}\n`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch(async (e) => {
  console.error(e);
  console.error(logBuf.slice(-3000));
  await stopServer();
  process.exit(1);
});
