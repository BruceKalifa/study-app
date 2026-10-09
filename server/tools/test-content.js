#!/usr/bin/env node
'use strict';
/**
 * 문제 콘텐츠 API 점검 (서버를 직접 띄워서 확인 — 미리 켜 둘 필요 없음)
 *
 *   npm run test:content
 *   node tools/test-content.js [--keep]      (--keep: 임시 폴더를 지우지 않음)
 *
 * 빈 폴더(임시 CONTENT_DIR)로 서버를 띄워 기본 문제 복사(seed), 공개 API(index/pack/workbooks),
 * 관리자 키, 문항 추가·수정·삭제, 검증 오류, 지문, 문제집, 가져오기, 과목 정보 변경, 재시작 후 유지를 확인한다.
 */

const fs = require('fs');
const os = require('os');
const net = require('net');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.join(__dirname, '..');
// 앱에 싣는 assets/problems 는 골격뿐이라 테스트 문제 은행을 쓴다.
// (예전 샘플과 바이트까지 같으면 서버가 시작할 때 지우므로, 다시 직렬화해서 바이트를 다르게 만든다)
const SEED_DIR = (() => {
  const src = path.join(SERVER_DIR, '..', 'test', 'fixtures', 'problems');
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'pulinote-seed-'));
  for (const f of fs.readdirSync(src)) {
    const raw = fs.readFileSync(path.join(src, f), 'utf8');
    fs.writeFileSync(path.join(d, f), f.endsWith('.json') ? JSON.stringify(JSON.parse(raw)) : raw);
  }
  return d;
})();
const KEY = 'test-key-4821';
const KEEP = process.argv.includes('--keep');

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

async function req(method, p, body, opts = {}) {
  const headers = Object.assign({}, opts.headers || {});
  if (opts.key !== false) headers['x-admin-key'] = opts.key || KEY;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(base + p, { method, headers, body: body !== undefined ? (typeof body === 'string' ? body : JSON.stringify(body)) : undefined });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch (_) { /* not json */ }
  return { status: res.status, json, text, headers: res.headers };
}
const get = (p, o) => req('GET', p, undefined, o);
const put = (p, b, o) => req('PUT', p, b, o);
const post = (p, b, o) => req('POST', p, b, o);
const del = (p, o) => req('DELETE', p, undefined, o);
const hasErr = (r, pred) => r.json && Array.isArray(r.json.errors) && r.json.errors.some(pred);

function choiceProblem(id, extra) {
  return Object.assign({
    id, unit: '역학과 에너지', topic: '테스트 유형', difficulty: 3, type: 'choice',
    stem: '속력 $v=3\\,\\text{m/s}$ 로 움직이는 물체의 운동 에너지는? (질량 $2\\,\\text{kg}$)',
    choices: ['3 J', '6 J', '9 J', '12 J', '18 J'], answer: '3',
    solution: '$E_k=\\frac{1}{2}mv^2=\\frac{1}{2}\\times 2\\times 3^2=9\\,\\text{J}$',
  }, extra || {});
}

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pulinote-content-test-'));
  const CONTENT_DIR = path.join(tmp, 'content');
  const DATA_DIR = path.join(tmp, 'data');
  const env = { CONTENT_DIR, DATA_DIR, ADMIN_KEY: KEY, SEED_DIR };
  console.log(`임시 폴더: ${tmp}`);
  await startServer(env);

  // ───────── 1. 기본 문제 복사 ─────────
  section('기본 문제 복사(seed)');
  const idxFiles = JSON.parse(fs.readFileSync(path.join(SEED_DIR, '_index.json'), 'utf8')).files;
  const seedCourses = [];
  for (const f of idxFiles) {
    try { seedCourses.push(JSON.parse(fs.readFileSync(path.join(SEED_DIR, f), 'utf8'))); } catch (_) { /* 깨진 파일은 서버도 건너뜀 */ }
  }
  const copied = fs.readdirSync(CONTENT_DIR).filter((f) => f.endsWith('.json') && f !== 'workbooks.json');
  ok(copied.length === seedCourses.length && seedCourses.length > 0, `과목 파일 ${seedCourses.length}개 복사`, copied.join(','));
  ok(fs.existsSync(path.join(CONTENT_DIR, '.seeded')), '.seeded 표시 파일');
  ok(/문제 저장소/.test(logBuf) && /관리자 키/.test(logBuf), '콘솔에 저장소·관리자 키 안내 출력');

  // ───────── 2. 공개 API ─────────
  section('공개 API');
  let r = await get('/api/content/index', { key: false });
  ok(r.status === 200 && Array.isArray(r.json.packs), 'GET /api/content/index');
  ok(r.headers.get('access-control-allow-origin') === '*', 'CORS 헤더 *');
  const index0 = r.json;
  ok(index0.packs.length === seedCourses.length, '팩 개수 = 과목 수');
  const first = seedCourses[0];
  const pk0 = index0.packs.find((p) => p.id === first.subjectId);
  ok(pk0 && pk0.name === first.subject && pk0.count === first.problems.length && /^[0-9a-f]{16}$/.test(pk0.version), `팩 정보 (${first.subjectId}: ${pk0 && pk0.count}문항, version ${pk0 && pk0.version})`, pk0);
  ok(index0.packs.every((p) => 'group' in p && 'level' in p), '팩마다 group·level 필드');
  ok(index0.workbooks && typeof index0.workbooks.version === 'string' && typeof index0.workbooks.count === 'number', 'workbooks 버전·개수', index0.workbooks);
  r = await get(`/api/content/pack/${first.subjectId}`, { key: false });
  ok(r.status === 200 && JSON.stringify(r.json) === JSON.stringify(first), '팩 내용 = 원본 과목 JSON');
  const etag = r.headers.get('etag');
  ok(etag === `"${pk0.version}"`, 'ETag = version');
  r = await get(`/api/content/pack/${first.subjectId}`, { key: false, headers: { 'If-None-Match': etag } });
  ok(r.status === 304, 'If-None-Match → 304');
  r = await get('/api/content/pack/no-such-course', { key: false });
  ok(r.status === 404 && r.json && r.json.error, '없는 팩 → 404');
  r = await get('/api/content/workbooks', { key: false });
  ok(r.status === 200 && Array.isArray(r.json.workbooks), 'GET /api/content/workbooks');
  r = await req('OPTIONS', '/api/admin/courses', undefined, { key: false });
  ok(r.status === 204 && /x-admin-key/i.test(r.headers.get('access-control-allow-headers') || ''), 'OPTIONS 사전 요청 204');

  // ───────── 3. 관리자 키 ─────────
  section('관리자 키');
  r = await get('/api/admin/courses', { key: false });
  ok(r.status === 401 && /키/.test(r.json.error), '키 없이 → 401', r.json);
  r = await get('/api/admin/courses', { key: 'wrong' });
  ok(r.status === 401, '틀린 키 → 401');
  r = await get(`/api/admin/courses?key=${KEY}`, { key: false });
  ok(r.status === 200 && r.json.courses.length === seedCourses.length, '?key= 로도 통과');
  r = await put(`/api/admin/course/${first.subjectId}/problem`, choiceProblem('x-1'), { key: false });
  ok(r.status === 401, '키 없이 쓰기 → 401');
  r = await get('/api/admin/courses');
  ok(r.status === 200 && r.json.courses[0].count >= 0 && 'twins' in r.json.courses[0], '과목 목록(문항 수·쌍둥이 수)');

  // ───────── 4. 문항 추가·수정 ─────────
  section('문항 추가 · 수정 · 버전');
  const cid = first.subjectId;
  const v0 = pk0.version;
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-new-001'));
  ok(r.status === 201 && r.json.created === true, '새 문항 → 201', r.json);
  let idx = (await get('/api/content/index', { key: false })).json;
  let pk = idx.packs.find((p) => p.id === cid);
  ok(pk.version !== v0, `수정 후 버전 바뀜 (${v0} → ${pk.version})`);
  ok(pk.count === first.problems.length + 1, '문항 수 +1');
  r = await get(`/api/content/pack/${cid}`, { key: false });
  ok(r.json.problems.some((p) => p.id === 'test-new-001' && p.answer === '3'), '팩에 새 문항 포함');
  const v1 = pk.version;
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-new-001', { answer: '4', hint: '  ', tags: ['운동 에너지', ''] }));
  ok(r.status === 200 && r.json.created === false, '같은 id → 수정 200');
  ok(r.json.problem.answer === '4' && !('hint' in r.json.problem) && JSON.stringify(r.json.problem.tags) === '["운동 에너지"]', '빈 값 정리(hint 제거, 빈 태그 제거)', r.json.problem);
  idx = (await get('/api/content/index', { key: false })).json;
  ok(idx.packs.find((p) => p.id === cid).version !== v1, '다시 수정 → 버전 또 바뀜');
  r = await put(`/api/admin/course/${cid}/problem`, { id: 'test-short-001', unit: '역학과 에너지', topic: '테스트 유형', difficulty: '2', type: 'short', stem: '$2+3$ 은?', answer: 5, answerUnit: '', solution: '$5$', choices: ['', '', '', '', ''] });
  ok(r.status === 201 && r.json.problem.answer === '5' && r.json.problem.difficulty === 2 && !('choices' in r.json.problem) && !('answerUnit' in r.json.problem), '단답형: 숫자 정답·난이도 문자열 정리', r.json);

  // ───────── 5. 검증 오류 ─────────
  section('검증 오류 (400 + 한국어 오류 목록)');
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-bad-1', { choices: ['1', '2', '3', '4'] }));
  ok(r.status === 400 && hasErr(r, (e) => e.field === 'choices' && /5개/.test(e.message)), '선택지 4개 → 오류', r.json);
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-bad-2', { answer: '6' }));
  ok(r.status === 400 && hasErr(r, (e) => e.field === 'answer'), '선택형 정답 "6" → 오류');
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-bad-3', { stem: '속력은 $v=3\\,미터$ 이다.' }));
  ok(r.status === 400 && hasErr(r, (e) => e.field === 'stem' && /한글/.test(e.message)), '수식 안 한글 → 오류', r.json);
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-bad-4', { twinOf: 'no-such-original' }));
  ok(r.status === 400 && hasErr(r, (e) => e.field === 'twinOf'), '없는 twinOf → 오류');
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-bad-5', { stem: '$x^2 의 값은?', solution: '**굵게 시작만' }));
  ok(r.status === 400 && hasErr(r, (e) => /\$/.test(e.message) && e.field === 'stem') && hasErr(r, (e) => /\*\*/.test(e.message)), '$·** 짝 안 맞음 → 오류');
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-bad-6', { stem: '표를 보자.\n| 구분 | A | B |\n|---|---|---|\n| 갑 | 1 |\n' }));
  ok(r.status === 400 && hasErr(r, (e) => /표/.test(e.message)), '표 칸 수 다름 → 오류');
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-bad-7', { difficulty: 7, type: 'short', answer: '' }));
  ok(r.status === 400 && hasErr(r, (e) => e.field === 'difficulty') && hasErr(r, (e) => e.field === 'answer'), '난이도 7·단답 빈 정답 → 오류');
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-bad-8', { passageId: 'no-passage' }));
  ok(r.status === 400 && hasErr(r, (e) => e.field === 'passageId'), '없는 지문 → 오류');
  const other = seedCourses[1];
  if (other) {
    r = await put(`/api/admin/course/${cid}/problem`, choiceProblem(other.problems[0].id));
    ok(r.status === 400 && hasErr(r, (e) => e.field === 'id' && /다른 과목/.test(e.message)), '다른 과목 id 중복 → 오류', r.json);
  }
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-bad-9', { template: { params: { a: { min: 1, max: 3 } }, stem: '$[[a]]$', answer: 'a', choiceExprs: ['a', 'a+1'] } }));
  ok(r.status === 400 && hasErr(r, (e) => e.field === 'template' && /choiceExprs/.test(e.message)), 'template choiceExprs 개수 → 오류');
  r = await put(`/api/admin/course/${cid}/problem`, '{ broken json');
  ok(r.status === 400 && /JSON/.test(r.json.error), '깨진 JSON → 400');
  idx = (await get('/api/content/index', { key: false })).json;
  ok(idx.packs.find((p) => p.id === cid).count === first.problems.length + 2, '오류 난 요청은 저장되지 않음');

  // ───────── 6. 쌍둥이 ─────────
  section('쌍둥이 · 삭제');
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-new-001-t1', { twinOf: 'test-new-001', stem: '속력 $v=4\\,\\text{m/s}$ 일 때는?' }));
  ok(r.status === 201, '쌍둥이 추가');
  let pack = (await get(`/api/content/pack/${cid}`, { key: false })).json;
  const io = pack.problems.findIndex((p) => p.id === 'test-new-001');
  ok(pack.problems[io + 1] && pack.problems[io + 1].id === 'test-new-001-t1', '쌍둥이는 원본 바로 뒤에 저장');
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-new-001-t2', { twinOf: 'test-new-001-t1' }));
  ok(r.status === 400 && hasErr(r, (e) => e.field === 'twinOf' && /쌍둥이/.test(e.message)), '쌍둥이의 쌍둥이 → 오류');
  r = await put(`/api/admin/course/${cid}/problem?replace=test-short-001`, { id: 'test-short-renamed', unit: '역학과 에너지', topic: '테스트 유형', difficulty: 2, type: 'short', stem: '$2+3$ 은?', answer: '5', solution: '$5$' });
  pack = (await get(`/api/content/pack/${cid}`, { key: false })).json;
  ok(r.status === 200 && pack.problems.some((p) => p.id === 'test-short-renamed') && !pack.problems.some((p) => p.id === 'test-short-001'), 'id 바꾸기(?replace=)', r.json);
  r = await del(`/api/admin/course/${cid}/problem/test-new-001`);
  ok(r.status === 400 && Array.isArray(r.json.twins) && r.json.twins.includes('test-new-001-t1'), '쌍둥이 있는 원본 삭제 → 400');
  r = await del(`/api/admin/course/${cid}/problem/test-new-001?cascade=1`);
  ok(r.status === 200 && r.json.deleted.length === 2, '?cascade=1 → 쌍둥이와 함께 삭제');
  r = await del(`/api/admin/course/${cid}/problem/test-short-renamed`);
  ok(r.status === 200, '문항 삭제');
  r = await del(`/api/admin/course/${cid}/problem/test-short-renamed`);
  ok(r.status === 404, '없는 문항 삭제 → 404');
  idx = (await get('/api/content/index', { key: false })).json;
  ok(idx.packs.find((p) => p.id === cid).count === first.problems.length, '문항 수 원래대로');

  // ───────── 7. 지문 ─────────
  section('지문');
  r = await put(`/api/admin/course/${cid}/passage`, { id: 'test-psg-01', title: '테스트 지문', body: '첫 문단에 __밑줄__ 이 있다.\n\n둘째 문단 $x^2$.' });
  ok(r.status === 201, '지문 추가');
  r = await put(`/api/admin/course/${cid}/passage`, { id: 'test-psg-02', body: '$한글$' });
  ok(r.status === 400 && hasErr(r, (e) => /한글/.test(e.message)), '지문 검증 오류');
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-psg-q1', { passageId: 'test-psg-01' }));
  ok(r.status === 201, '지문 연결 문항 추가');
  r = await del(`/api/admin/course/${cid}/passage/test-psg-01`);
  ok(r.status === 400 && r.json.problems.includes('test-psg-q1'), '쓰이는 지문 삭제 → 400');
  r = await put(`/api/admin/course/${cid}/passage?replace=test-psg-01`, { id: 'test-psg-01b', title: '테스트 지문', body: '바뀐 본문' });
  pack = (await get(`/api/content/pack/${cid}`, { key: false })).json;
  ok(r.status === 200 && pack.problems.find((p) => p.id === 'test-psg-q1').passageId === 'test-psg-01b', '지문 id 바꾸면 문항 연결도 바뀜');
  await del(`/api/admin/course/${cid}/problem/test-psg-q1`);
  r = await del(`/api/admin/course/${cid}/passage/test-psg-01b`);
  ok(r.status === 200, '지문 삭제');

  // ───────── 8. 문제집 ─────────
  section('문제집');
  const wbBefore = (await get('/api/content/index', { key: false })).json.workbooks;
  const pids = first.problems.filter((p) => !p.twinOf).slice(0, 3).map((p) => p.id);
  const existingWb = (await get('/api/admin/workbooks')).json.workbooks;
  const myWb = { id: 'wb-test-1', title: '테스트 문제집', course: cid, level: '기본', desc: '설명', problems: pids };
  r = await put('/api/admin/workbooks', { workbooks: existingWb.concat([myWb]) });
  ok(r.status === 200 && r.json.count === existingWb.length + 1, '문제집 저장', r.json);
  const wbAfter = (await get('/api/content/index', { key: false })).json.workbooks;
  ok(wbAfter.version !== wbBefore.version && wbAfter.count === wbBefore.count + 1, '문제집 버전·개수 바뀜');
  r = await get('/api/content/workbooks', { key: false });
  ok(r.json.workbooks.some((w) => w.id === 'wb-test-1' && w.problems.length === 3), '공개 API 에 문제집 반영');
  r = await put('/api/admin/workbooks', { workbooks: existingWb.concat([Object.assign({}, myWb, { problems: ['no-such-problem'] })]) });
  ok(r.status === 400 && hasErr(r, (e) => /없습니다/.test(e.message)), '없는 문항 id → 오류');
  r = await put(`/api/admin/course/${cid}/problem`, choiceProblem('test-wb-twin', { twinOf: pids[0] }));
  ok(r.status === 201, '(쌍둥이 준비)');
  r = await put('/api/admin/workbooks', { workbooks: existingWb.concat([Object.assign({}, myWb, { problems: pids.concat(['test-wb-twin']) })]) });
  ok(r.status === 400 && hasErr(r, (e) => /쌍둥이/.test(e.message)), '쌍둥이 문항 넣기 → 오류');
  r = await put(`/api/admin/course/${cid}/problem`, Object.assign({}, first.problems.find((p) => p.id === pids[1]), { twinOf: pids[0] }));
  ok(r.status === 400 && hasErr(r, (e) => /쌍둥이/.test(e.message)), '문제집에 든 문항을 쌍둥이로 바꾸기 → 오류', r.json);
  await del(`/api/admin/course/${cid}/problem/test-wb-twin`);
  r = await del(`/api/admin/course/${cid}/problem/${pids[2]}`);
  const wbNow = (await get('/api/admin/workbooks')).json.workbooks.find((w) => w.id === 'wb-test-1');
  ok(r.status === 200 && r.json.removedFromWorkbooks.includes('wb-test-1') && !wbNow.problems.includes(pids[2]), '문항 삭제 시 문제집에서도 빠짐');

  // ───────── 9. 가져오기 · 과목 ─────────
  section('가져오기 · 과목 정보');
  const impCourse = {
    subject: '테스트 과목', subjectId: 'test-imp', color: '#336699', group: 'math', level: 'mid', grades: ['중2'],
    units: ['수와 연산'],
    problems: [
      { id: 'test-imp-001', unit: '수와 연산', topic: '덧셈', difficulty: 1, type: 'short', stem: '$1+1$ 은?', answer: '2', solution: '$2$' },
      { id: 'test-imp-002', unit: '수와 연산', topic: '덧셈', difficulty: 1, type: 'short', stem: '$2+2$ 는?', answer: '4', solution: '$4$' },
    ],
  };
  r = await post('/api/admin/import', impCourse);
  ok(r.status === 200 && r.json.courses[0].created && r.json.courses[0].added === 2, '새 과목 가져오기', r.json);
  idx = (await get('/api/content/index', { key: false })).json;
  const impPack = idx.packs.find((p) => p.id === 'test-imp');
  ok(impPack && impPack.count === 2 && impPack.group === 'math' && impPack.level === 'mid', 'index 에 새 팩');
  r = await post('/api/admin/import', { subjectId: 'test-imp', subject: '테스트 과목', color: '#336699', problems: [Object.assign({}, impCourse.problems[0], { answer: '2.0' }), { id: 'test-imp-003', unit: '수와 연산', topic: '뺄셈', difficulty: 2, type: 'short', stem: '$3-1$', answer: '2', solution: '$2$' }] });
  ok(r.status === 200 && r.json.courses[0].updated === 1 && r.json.courses[0].added === 1 && r.json.courses[0].total === 3, 'id 로 합치기 (덮어씀 1, 추가 1)', r.json);
  r = await post('/api/admin/import', { subjectId: 'test-imp', problems: [{ id: 'test-imp-004', unit: 'x', topic: 'y', difficulty: 1, type: 'choice', stem: 's', choices: ['a'], answer: '1', solution: 's' }] });
  ok(r.status === 400 && hasErr(r, (e) => e.where === 'test-imp-004'), '가져오기 검증 오류 → 400, 아무것도 안 바뀜');
  r = await post('/api/admin/import', { workbooks: [{ id: 'wb-test-imp', title: '가져온 문제집', course: 'test-imp', level: '실전', problems: ['test-imp-001', 'test-imp-003'] }] });
  ok(r.status === 200 && r.json.workbooks.added === 1, '문제집 JSON 가져오기(합치기)', r.json);
  r = await put('/api/admin/course/test-imp', { subject: '테스트 과목(수정)', color: '#112233', units: ['수와 연산', '도형'], track: '내신' });
  pack = (await get('/api/content/pack/test-imp', { key: false })).json;
  ok(r.status === 200 && pack.subject === '테스트 과목(수정)' && pack.problems.length === 3 && pack.track === '내신', '과목 정보 수정 (문항 유지)', r.json);
  r = await put('/api/admin/course/test-imp', { group: 'xyz' });
  ok(r.status === 400 && hasErr(r, (e) => e.field === 'group'), '잘못된 교과군 → 오류');
  r = await put('/api/admin/course/test-imp', { subjectId: 'test-imp2' });
  idx = (await get('/api/content/index', { key: false })).json;
  const wbs = (await get('/api/admin/workbooks')).json.workbooks;
  ok(r.status === 200 && idx.packs.some((p) => p.id === 'test-imp2') && !idx.packs.some((p) => p.id === 'test-imp') && wbs.find((w) => w.id === 'wb-test-imp').course === 'test-imp2', '과목 id 바꾸기 (문제집 연결도 바뀜)');
  ok(fs.existsSync(path.join(CONTENT_DIR, 'test-imp2.json')) && !fs.existsSync(path.join(CONTENT_DIR, 'test-imp.json')), '파일 이름도 바뀜');
  r = await put('/api/admin/course/test-new', { subject: '빈 과목', color: '#AA5500', group: 'sci', level: 'high', grades: ['고1'] });
  ok(r.status === 201 && r.json.created, '빈 과목 만들기');
  r = await get('/api/admin/export/test-imp2');
  ok(r.status === 200 && r.json.subjectId === 'test-imp2' && /attachment/.test(r.headers.get('content-disposition') || ''), '과목 내보내기');
  r = await get('/api/admin/export');
  ok(r.status === 200 && Array.isArray(r.json.courses) && Array.isArray(r.json.workbooks), '전체 백업 내보내기');
  r = await del('/api/admin/course/test-imp2');
  idx = (await get('/api/content/index', { key: false })).json;
  ok(r.status === 200 && r.json.removedWorkbooks.includes('wb-test-imp') && !idx.packs.some((p) => p.id === 'test-imp2'), '과목 삭제 (그 과목 문제집도 삭제)');
  ok(fs.readdirSync(path.join(CONTENT_DIR, '_trash')).some((f) => f.endsWith('test-imp2.json')), '삭제한 파일은 _trash 에 보관');

  // ───────── 10. 동시 저장 · 원자적 쓰기 ─────────
  section('동시 저장 · 원자적 쓰기');
  const many = await Promise.all(Array.from({ length: 12 }, (_, i) => put('/api/admin/course/test-new/problem', choiceProblem(`test-par-${String(i).padStart(2, '0')}`, { unit: '단원' }))));
  ok(many.every((x) => x.status === 201), '12개 동시 추가 모두 성공');
  pack = (await get('/api/content/pack/test-new', { key: false })).json;
  ok(pack.problems.length === 12, '파일에 12문항 모두 저장');
  const onDisk = JSON.parse(fs.readFileSync(path.join(CONTENT_DIR, 'test-new.json'), 'utf8'));
  ok(onDisk.problems.length === 12, '디스크 파일 내용 일치');
  ok(!fs.readdirSync(CONTENT_DIR).some((f) => f.endsWith('.tmp')), '임시 파일이 남지 않음');

  // ───────── 11. 출제 웹 ─────────
  section('출제 웹 정적 파일');
  r = await fetch(base + '/admin', { redirect: 'manual' });
  ok(r.status === 301 && r.headers.get('location') === '/admin/', '/admin → /admin/');
  for (const f of ['/admin/', '/admin/admin.js', '/admin/admin.css', '/admin/schema.js']) {
    r = await fetch(base + f);
    ok(r.status === 200, `GET ${f}`);
  }
  r = await get('/api/info', { key: false });
  ok(r.status === 200 && Array.isArray(r.json.adminUrls), '/api/info 에 adminUrls');

  // ───────── 12. 재시작 후 유지 ─────────
  section('재시작');
  const before = (await get('/api/content/index', { key: false })).json;
  await stopServer();
  logBuf = '';
  await startServer(env);
  const after = (await get('/api/content/index', { key: false })).json;
  ok(!/기본 문제 .*복사했습니다/.test(logBuf), '다시 켤 때는 복사하지 않음');
  const sig = (x) => x.packs.map((p) => `${p.id}:${p.version}:${p.count}`).join(',') + `|${x.workbooks.version}:${x.workbooks.count}`;
  ok(sig(before) === sig(after), '버전·내용 그대로', `${sig(before)} vs ${sig(after)}`);
  await stopServer();

  // 생성 키 파일 확인 (ADMIN_KEY 없이)
  logBuf = '';
  await startServer({ CONTENT_DIR, DATA_DIR: path.join(tmp, 'data2'), SEED_DIR });
  const keyFile = path.join(tmp, 'data2', 'admin-key.txt');
  const genKey = fs.existsSync(keyFile) ? fs.readFileSync(keyFile, 'utf8').trim() : '';
  ok(/^\d{6}$/.test(genKey) && logBuf.includes(genKey), `ADMIN_KEY 없으면 6자리 키 생성·출력 (${genKey})`);
  r = await get('/api/admin/check', { key: genKey });
  ok(r.status === 200, '생성된 키로 접속');
  await stopServer();

  if (!KEEP) fs.rmSync(tmp, { recursive: true, force: true });
  console.log(`\n결과: 통과 ${passed} · 실패 ${failed}`);
  process.exit(failed ? 1 : 0);
}

main().catch(async (e) => {
  console.error('\n테스트 중 오류:', e);
  if (logBuf) console.error('--- 서버 로그 ---\n' + logBuf.slice(-3000));
  await stopServer();
  process.exit(1);
});
