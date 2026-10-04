#!/usr/bin/env node
'use strict';
/**
 * 커뮤니티 게시판 · 공부시간 순위 API 점검 (서버를 직접 띄워서 확인 — 미리 켜 둘 필요 없음)
 *
 *   npm run test:community
 *   node tools/test-community.js [--keep]      (--keep: 임시 폴더를 지우지 않음)
 *
 * 임시 DATA_DIR/CONTENT_DIR 로 서버를 띄워 게시판, 글 검증·도배 방지, 목록(mine/liked·검색·정렬·더 보기),
 * 읽기(조회수·댓글), 좋아요, 댓글, 삭제 권한, 신고·숨김, 관리자 API, userId 비노출,
 * 순위 보고(이름 가리기·덮어쓰기·자르기)·조회(일/주·학년·내 순위·상위 50명), 재시작 후 유지·90일 정리를 확인한다.
 */

const fs = require('fs');
const os = require('os');
const net = require('net');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.join(__dirname, '..');
const SEED_DIR = path.join(SERVER_DIR, '..', 'assets', 'problems');
const KEY = 'test-key-7713';
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

// 모든 응답 본문을 모아 두고 마지막에 userId 가 들어 있지 않은지 확인한다
const bodies = [];
async function req(method, p, body, opts = {}) {
  const headers = Object.assign({}, opts.headers || {});
  if (opts.key) headers['x-admin-key'] = opts.key;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(base + p, { method, headers, body: body !== undefined ? (typeof body === 'string' ? body : JSON.stringify(body)) : undefined });
  const text = await res.text();
  bodies.push({ p, text });
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch (_) { /* not json */ }
  return { status: res.status, json, text, headers: res.headers };
}
const get = (p, o) => req('GET', p, undefined, o);
const post = (p, b, o) => req('POST', p, b, o);
const del = (p, o) => req('DELETE', p, undefined, o);
const admin = { key: KEY };
const enc = encodeURIComponent;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const isKo = (r) => r.json && typeof r.json.error === 'string' && /[가-힣]/.test(r.json.error);

function pad(n) { return String(n).padStart(2, '0'); }
function dayOffset(n) { const d = new Date(); d.setHours(12, 0, 0, 0); d.setDate(d.getDate() + n); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; }

// 사용한 userId (응답에 절대 나오면 안 됨)
const U = {
  a: 'uid-ALPHA-q9x1z', b: 'uid-BRAVO-w4k2y', c: 'uid-CHARLIE-e7m3x', d: 'uid-DELTA-r2p8w', e: 'uid-ECHO-t5n6v',
  f: 'uid-FOXTROT-y3j4u', g: 'uid-GOLF-u8h1t', h: 'uid-HOTEL-i6g9s', v: 'uid-VALID-o1f2r',
};
const usedIds = new Set(Object.values(U));
function postBody(user, extra) {
  return Object.assign({ userId: user, author: '테스트닉', grade: '고3', board: 'qna', title: '운동량 보존 질문', body: '충돌 전후 운동량이 같은 이유가 궁금합니다.' }, extra || {});
}

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pulinote-community-test-'));
  const DATA_DIR = path.join(tmp, 'data');
  const env = { CONTENT_DIR: path.join(tmp, 'content'), DATA_DIR, ADMIN_KEY: KEY, SEED_DIR };
  console.log(`임시 폴더: ${tmp}`);
  await startServer(env);

  // ───────── 게시판 ─────────
  section('게시판');
  let r = await get('/api/community/boards');
  ok(r.status === 200 && Array.isArray(r.json.boards) && r.json.boards.length === 5, 'GET /api/community/boards → 5개', r.json);
  ok(JSON.stringify(r.json.boards.map((b) => b.id)) === '["free","qna","proof","info","mind"]' && r.json.boards.every((b) => b.name && b.desc), '게시판 id·이름·설명');
  ok(r.headers.get('access-control-allow-origin') === '*', 'CORS 헤더 *');
  r = await req('OPTIONS', '/api/community/posts');
  ok(r.status === 204 && /DELETE/.test(r.headers.get('access-control-allow-methods') || ''), 'OPTIONS 사전 요청 204');

  // ───────── 글쓰기 검증 ─────────
  section('글쓰기 검증');
  r = await post('/api/community/posts', postBody(U.v, { board: 'nope' }));
  ok(r.status === 400 && isKo(r), '없는 게시판 → 400 (한국어)', r.json);
  r = await post('/api/community/posts', postBody(U.v, { title: '   ' }));
  ok(r.status === 400 && /제목/.test(r.json.error), '빈 제목 → 400', r.json);
  r = await post('/api/community/posts', postBody(U.v, { title: '가'.repeat(81) }));
  ok(r.status === 400 && /80자/.test(r.json.error), '제목 81자 → 400', r.json);
  r = await post('/api/community/posts', postBody(U.v, { body: '가'.repeat(5001) }));
  ok(r.status === 400 && /본문/.test(r.json.error) && /5000자/.test(r.json.error), '본문 5001자 → 400', r.json);
  r = await post('/api/community/posts', postBody(U.v, { body: '' }));
  ok(r.status === 400 && /본문/.test(r.json.error), '빈 본문 → 400');
  r = await post('/api/community/posts', postBody(U.v, { author: '가'.repeat(21) }));
  ok(r.status === 400 && /닉네임/.test(r.json.error), '닉네임 21자 → 400', r.json);
  r = await post('/api/community/posts', postBody(U.v, { author: '' }));
  ok(r.status === 400 && /닉네임/.test(r.json.error), '빈 닉네임 → 400');
  r = await post('/api/community/posts', postBody(U.v, { grade: '중3' }));
  ok(r.status === 400 && /학년/.test(r.json.error), '학년 "중3" → 400', r.json);
  r = await post('/api/community/posts', postBody(''));
  ok(r.status === 400 && /userId/.test(r.json.error), 'userId 없음 → 400');
  r = await post('/api/community/posts', '{ broken');
  ok(r.status === 400 && /JSON/.test(r.json.error), '깨진 JSON → 400');
  // 검증 실패는 도배 제한에 걸리지 않는다
  r = await post('/api/community/posts', postBody(U.v, { title: '가'.repeat(80), body: '나'.repeat(5000), author: '다'.repeat(20), grade: '', problemId: 'phy1-mech-005' }));
  ok(r.status === 200 && r.json.post && r.json.post.title.length === 80 && r.json.post.body.length === 5000, '경계값(제목 80자·본문 5000자·닉 20자·빈 학년) → 200', r.json && r.json.error);
  const pV = r.json.post;
  ok(pV.mine === true && pV.liked === false && pV.likes === 0 && pV.comments.length === 0 && pV.views === 0 && pV.problemId === 'phy1-mech-005' && pV.grade === '', '새 글 응답 필드 (mine, problemId …)', pV);
  ok(/^p_/.test(pV.id) && pV.preview.length === 120 && typeof pV.createdAt === 'number', 'id p_… · preview 120자 · createdAt');

  // ───────── 도배 방지 ─────────
  section('도배 방지 (같은 userId 20초에 글 1개)');
  r = await post('/api/community/posts', postBody(U.a, { title: '첫 글', board: 'free' }));
  ok(r.status === 200, 'A 첫 글 → 200');
  const pA1 = r.json.post;
  r = await post('/api/community/posts', postBody(U.a, { title: '둘째 글' }));
  ok(r.status === 429 && isKo(r) && /초/.test(r.json.error), 'A 바로 또 쓰기 → 429', r.json);
  r = await post('/api/community/posts', postBody(U.b, { title: '포물선 운동 공식', body: '수평 방향 속도는 일정합니다.', board: 'qna', grade: '고2', author: '비닉' }));
  ok(r.status === 200, '다른 사용자 B 는 바로 쓸 수 있음');
  const pB1 = r.json.post;
  r = await post('/api/community/posts', postBody(U.c, { title: '오늘 6시간 인증', body: '물리 30문제 풀었습니다', board: 'proof', author: '씨닉' }));
  const pC1 = r.json.post;
  ok(r.status === 200, 'C 글 (공부인증)');

  // ───────── 목록 ─────────
  section('목록 (mine / liked · 게시판 · 검색 · 더 보기)');
  r = await get(`/api/community/posts?me=${enc(U.a)}`);
  ok(r.status === 200 && r.json.posts.length === 4, '전체 목록 4개', r.json.posts && r.json.posts.length);
  const listed = r.json.posts;
  ok(listed[0].createdAt >= listed[listed.length - 1].createdAt, '최신 순');
  ok(listed.find((p) => p.id === pA1.id).mine === true && listed.filter((p) => p.mine).length === 1, 'me=A → A 글만 mine');
  ok(listed.every((p) => !('body' in p) && typeof p.comments === 'number' && 'preview' in p && 'liked' in p && 'problemId' in p), '목록 필드 (preview, comments=개수, body 없음)');
  r = await get('/api/community/posts');
  ok(r.json.posts.every((p) => p.mine === false && p.liked === false), 'me 없으면 mine/liked 모두 false');
  r = await get('/api/community/posts?board=proof');
  ok(r.json.posts.length === 1 && r.json.posts[0].id === pC1.id, 'board=proof 필터');
  r = await get('/api/community/posts?board=zzz');
  ok(r.status === 400 && isKo(r), '없는 게시판 목록 → 400');
  r = await get(`/api/community/posts?q=${enc('포물선')}`);
  ok(r.json.posts.length === 1 && r.json.posts[0].id === pB1.id, 'q=포물선 (제목 검색)');
  r = await get(`/api/community/posts?q=${enc('30문제')}`);
  ok(r.json.posts.length === 1 && r.json.posts[0].id === pC1.id, 'q=30문제 (본문 검색)');
  r = await get('/api/community/posts?limit=2');
  ok(r.json.posts.length === 2, 'limit=2');
  const page1 = r.json.posts;
  r = await get(`/api/community/posts?limit=2&before=${page1[1].createdAt}`);
  ok(r.json.posts.length >= 1 && r.json.posts.every((p) => p.createdAt < page1[1].createdAt && !page1.some((q) => q.id === p.id)), 'before= 로 더 보기 (겹치지 않음)');
  r = await get('/api/community/posts?limit=999');
  ok(r.status === 200 && r.json.posts.length <= 50, 'limit 최대 50');
  r = await get('/api/community/posts?sort=zzz');
  ok(r.status === 400, 'sort 잘못 → 400');

  // ───────── 읽기 · 좋아요 · 댓글 ─────────
  section('읽기 (조회수 +1, 댓글 포함)');
  r = await get(`/api/community/posts/${pA1.id}?me=${enc(U.b)}`);
  ok(r.status === 200 && r.json.post.views === 1 && r.json.post.body === '충돌 전후 운동량이 같은 이유가 궁금합니다.' && Array.isArray(r.json.post.comments), '읽기 → views 1, body, comments[]', r.json);
  ok(r.json.post.mine === false, '남의 글은 mine false');
  r = await get(`/api/community/posts/${pA1.id}?me=${enc(U.a)}`);
  ok(r.json.post.views === 2 && r.json.post.mine === true, '다시 읽기 → views 2, 본인 mine true');
  r = await get('/api/community/posts/p_nope');
  ok(r.status === 404 && isKo(r), '없는 글 → 404');

  section('좋아요 토글');
  r = await post(`/api/community/posts/${pA1.id}/like`, { userId: U.b });
  ok(r.status === 200 && r.json.likes === 1 && r.json.liked === true, 'B 좋아요 → {likes:1, liked:true}', r.json);
  r = await post(`/api/community/posts/${pA1.id}/like`, { userId: U.c });
  ok(r.json.likes === 2 && r.json.liked === true, 'C 좋아요 → 2');
  r = await get(`/api/community/posts?me=${enc(U.b)}`);
  ok(r.json.posts.find((p) => p.id === pA1.id).liked === true && r.json.posts.find((p) => p.id === pB1.id).liked === false, '목록 me=B → liked');
  r = await post(`/api/community/posts/${pA1.id}/like`, { userId: U.b });
  ok(r.json.likes === 1 && r.json.liked === false, 'B 다시 누르면 취소 → {likes:1, liked:false}');
  r = await post(`/api/community/posts/${pA1.id}/like`, {});
  ok(r.status === 400, 'userId 없는 좋아요 → 400');

  section('댓글');
  r = await post(`/api/community/posts/${pA1.id}/comments`, { userId: U.b, author: '비닉', grade: '고2', body: '작용 반작용 때문이에요' });
  ok(r.status === 200 && r.json.comment && /^c_/.test(r.json.comment.id) && r.json.comment.mine === true && r.json.comment.body === '작용 반작용 때문이에요', 'B 댓글 → 200', r.json);
  const cB = r.json.comment;
  r = await post(`/api/community/posts/${pA1.id}/comments`, { userId: U.b, author: '비닉', grade: '고2', body: '또 씀' });
  ok(r.status === 429 && isKo(r), 'B 5초 안에 또 댓글 → 429', r.json);
  r = await post(`/api/community/posts/${pA1.id}/comments`, { userId: U.c, author: '씨닉', body: '' });
  ok(r.status === 400 && /댓글/.test(r.json.error), '빈 댓글 → 400');
  r = await post(`/api/community/posts/${pA1.id}/comments`, { userId: U.c, author: '씨닉', body: '가'.repeat(1001) });
  ok(r.status === 400 && /1000자/.test(r.json.error), '댓글 1001자 → 400');
  r = await post(`/api/community/posts/${pA1.id}/comments`, { userId: U.c, author: '씨닉', grade: '', body: '좋은 질문!' });
  ok(r.status === 200, 'C 댓글');
  const cC = r.json.comment;
  r = await get(`/api/community/posts/${pA1.id}?me=${enc(U.b)}`);
  ok(r.json.post.comments.length === 2 && r.json.post.comments[0].mine === true && r.json.post.comments[1].mine === false, '읽기에 댓글 2개 (B 기준 mine)');
  r = await get('/api/community/posts');
  ok(r.json.posts.find((p) => p.id === pA1.id).comments === 2, '목록 comments = 2');
  r = await del(`/api/community/posts/${pA1.id}/comments/${cB.id}?userId=${enc(U.c)}`);
  ok(r.status === 403 && isKo(r), '남의 댓글 삭제 → 403', r.json);
  r = await del(`/api/community/posts/${pA1.id}/comments/${cB.id}?userId=${enc(U.a)}`);
  ok(r.status === 403, '글쓴이도 남의 댓글은 삭제 불가 → 403');
  r = await del(`/api/community/posts/${pA1.id}/comments/${cB.id}?userId=${enc(U.b)}`);
  ok(r.status === 200 && r.json.ok === true, '본인 댓글 삭제 → {ok:true}');
  r = await del(`/api/community/posts/${pA1.id}/comments/${cB.id}?userId=${enc(U.b)}`);
  ok(r.status === 404, '이미 지운 댓글 → 404');
  r = await get(`/api/community/posts/${pA1.id}`);
  ok(r.json.post.comments.length === 1 && r.json.post.comments[0].id === cC.id, '댓글 1개 남음');

  section('인기순 (sort=hot)');
  r = await get('/api/community/posts?sort=hot');
  ok(r.status === 200 && r.json.posts[0].id === pA1.id, '좋아요·댓글·조회 많은 글이 맨 앞', r.json.posts.map((p) => p.title));

  section('글 삭제 (본인만)');
  r = await del(`/api/community/posts/${pB1.id}?userId=${enc(U.a)}`);
  ok(r.status === 403 && isKo(r), '남의 글 삭제 → 403');
  r = await del(`/api/community/posts/${pB1.id}`);
  ok(r.status === 400, 'userId 없이 삭제 → 400');
  r = await del(`/api/community/posts/${pB1.id}?userId=${enc(U.b)}`);
  ok(r.status === 200 && r.json.ok === true, '본인 글 삭제 → {ok:true}');
  r = await get(`/api/community/posts/${pB1.id}`);
  ok(r.status === 404, '삭제한 글 읽기 → 404');

  // ───────── 신고 · 숨김 ─────────
  section('신고 → 서로 다른 3명이면 숨김');
  r = await post(`/api/community/posts/${pC1.id}/report`, { userId: U.d, reason: '광고' });
  ok(r.status === 200 && r.json.ok === true, '신고 1 (D) → {ok:true}');
  r = await post(`/api/community/posts/${pC1.id}/report`, { userId: U.d, reason: '광고 또' });
  ok(r.status === 200, '같은 사람 D 다시 신고 → ok (한 번만 셈)');
  r = await post(`/api/community/posts/${pC1.id}/report`, { userId: U.e, reason: '욕설' });
  r = await get('/api/community/posts');
  ok(r.json.posts.some((p) => p.id === pC1.id), '서로 다른 2명 신고 → 아직 보임');
  r = await get(`/api/admin/community/reports`, admin);
  let rp = r.json.posts.find((p) => p.id === pC1.id);
  ok(r.status === 200 && rp && rp.reportCount === 2 && rp.hidden === false, '관리: 신고 2건, 숨김 아님 (중복 신고 1번으로)', rp);
  r = await post(`/api/community/posts/${pC1.id}/report`, { userId: U.f, reason: '도배' });
  ok(r.status === 200, '신고 3 (F)');
  r = await get('/api/community/posts');
  ok(!r.json.posts.some((p) => p.id === pC1.id), '3명 신고 → 목록에서 숨김');
  r = await get('/api/community/posts?board=proof');
  ok(r.json.posts.length === 0, '게시판 목록에서도 숨김');
  r = await get(`/api/community/posts/${pC1.id}`);
  ok(r.status === 404 && /숨겨/.test(r.json.error), '숨긴 글 읽기 → 404 (숨겨진 글)', r.json);
  r = await post(`/api/community/posts/${pC1.id}/like`, { userId: U.g });
  ok(r.status === 404, '숨긴 글 좋아요 → 404');

  // ───────── 관리 ─────────
  section('관리 API (x-admin-key)');
  r = await get('/api/admin/community/reports');
  ok(r.status === 401 || r.status === 403, `키 없이 신고 목록 → ${r.status}`, r.json);
  ok(isKo(r), '오류 메시지 한국어');
  r = await get('/api/admin/community/reports', { key: 'wrong-key' });
  ok(r.status === 401 || r.status === 403, '틀린 키 → 401/403');
  r = await post(`/api/admin/community/posts/${pC1.id}/restore`, {});
  ok(r.status === 401 || r.status === 403, '키 없이 복구 → 401/403');
  r = await del(`/api/admin/community/posts/${pA1.id}`);
  ok(r.status === 401 || r.status === 403, '키 없이 삭제 → 401/403');
  r = await get('/api/community/posts');
  ok(r.json.posts.some((p) => p.id === pA1.id), '(키 없는 삭제는 반영 안 됨)');
  r = await get('/api/admin/community/reports', admin);
  rp = r.json.posts.find((p) => p.id === pC1.id);
  ok(r.status === 200 && rp && rp.hidden === true && rp.reportCount === 3 && typeof rp.hiddenAt === 'number', '신고 목록: 숨김 글, 신고 3건', rp);
  ok(rp && JSON.stringify(rp.reports.map((x) => x.reason).sort()) === JSON.stringify(['광고', '도배', '욕설']) && rp.reports.every((x) => typeof x.at === 'number'), '신고 사유·시각', rp && rp.reports);
  ok(rp && rp.body === '물리 30문제 풀었습니다' && rp.title === '오늘 6시간 인증', '신고 목록에 본문 포함');
  r = await get(`/api/admin/community/reports?key=${KEY}`);
  ok(r.status === 200, '?key= 로도 통과');
  r = await get('/api/admin/community/posts', admin);
  ok(r.status === 200 && r.json.posts.some((p) => p.id === pC1.id && p.hidden) && r.json.posts.some((p) => p.id === pA1.id && p.comments.length === 1), '관리 최근 글 목록(숨김 포함, 댓글 포함)');
  r = await post(`/api/admin/community/posts/${pC1.id}/restore`, {}, admin);
  ok(r.status === 200 && r.json.ok === true, '복구 → {ok:true}');
  r = await get('/api/community/posts');
  ok(r.json.posts.some((p) => p.id === pC1.id), '복구한 글이 다시 보임');
  r = await get('/api/admin/community/reports', admin);
  ok(!r.json.posts.some((p) => p.id === pC1.id), '복구하면 신고 목록에서 빠짐');
  r = await del(`/api/admin/community/posts/${pA1.id}/comments/${cC.id}`, admin);
  ok(r.status === 200 && r.json.ok === true, '관리자 댓글 삭제');
  r = await get(`/api/community/posts/${pA1.id}`);
  ok(r.json.post.comments.length === 0, '댓글 0개');
  r = await del(`/api/admin/community/posts/${pC1.id}`, admin);
  ok(r.status === 200 && r.json.ok === true, '관리자 글 삭제');
  r = await get(`/api/community/posts/${pC1.id}`);
  ok(r.status === 404, '관리자가 지운 글 → 404');
  r = await del(`/api/admin/community/posts/${pC1.id}`, admin);
  ok(r.status === 404, '없는 글 관리자 삭제 → 404');
  r = await get('/api/admin/community/nope', admin);
  ok(r.status === 404 && isKo(r), '관리: 없는 주소 → 404 (콘텐츠 API 로 새지 않음)');
  r = await get('/api/admin/courses', admin);
  ok(r.status === 200 && Array.isArray(r.json.courses), '기존 콘텐츠 관리 API 그대로 동작');

  // ───────── 순위 ─────────
  section('공부시간 순위 — 보고 · 이름 가리기');
  const T = dayOffset(0);
  const Y = dayOffset(-1);
  const D3 = dayOffset(-3);
  const D8 = dayOffset(-8);
  const R = {
    oh: 'rk-OH-z81k', kim1: 'rk-KIM1-x72j', kimEn: 'rk-KIMEN-c63h', anon: 'rk-ANON-v54g', nfd: 'rk-NFD-b45f', emo: 'rk-EMOJI-n36d', g2: 'rk-G2-m27s',
  };
  for (const v of Object.values(R)) usedIds.add(v);
  r = await post('/api/ranking/report', { userId: R.oh, name: '오예진', grade: '고3', day: T, studyMs: 7200000, solved: 35 });
  ok(r.status === 200 && r.json.ok === true && r.json.name === '오XX', '오예진 → 오XX', r.json);
  r = await post('/api/ranking/report', { userId: R.kim1, name: '김', grade: '고3', day: T, studyMs: 3600000, solved: 10 });
  ok(r.json.name === '김XX', '한 글자 이름 김 → 김XX', r.json);
  r = await post('/api/ranking/report', { userId: R.kimEn, name: 'Kim', grade: '고3', day: T, studyMs: 1800000, solved: 5 });
  ok(r.json.name === 'KXX', 'Kim → KXX', r.json);
  r = await post('/api/ranking/report', { userId: R.anon, name: '   ', grade: '', day: T, studyMs: 600000, solved: 1 });
  ok(r.json.name === '익명', '빈 이름 → 익명', r.json);
  r = await post('/api/ranking/report', { userId: R.nfd, name: '한지민'.normalize('NFD'), grade: '고1', day: T, studyMs: 60000, solved: 0 });
  ok(r.json.name === '한'.normalize('NFD') + 'XX', '자모 분리(NFD) 한글도 첫 글자 통째로 → 한XX', r.json);
  r = await post('/api/ranking/report', { userId: R.emo, name: '👍🏽철수', grade: '고1', day: T, studyMs: 30000, solved: 0 });
  ok(r.json.name === '👍🏽XX', '이모지(피부색 결합)도 한 글자', r.json);
  const rankFile = fs.readFileSync(path.join(DATA_DIR, 'ranking.json'), 'utf8');
  ok(!rankFile.includes('예진') && !rankFile.includes('Kim') && !rankFile.includes('철수') && rankFile.includes('오XX'), 'ranking.json 에 전체 이름이 저장되지 않음');
  r = await post('/api/ranking/report', { name: '누구', day: T, studyMs: 1 });
  ok(r.status === 400 && isKo(r), 'userId 없음 → 400');
  r = await post('/api/ranking/report', { userId: R.oh, name: '오예진', day: '2026-13-45', studyMs: 1 });
  ok(r.status === 400 && /날짜/.test(r.json.error), '잘못된 날짜 → 400');
  r = await post('/api/ranking/report', { userId: R.oh, name: '오예진', day: dayOffset(5), studyMs: 1 });
  ok(r.status === 400, '미래 날짜 → 400');
  r = await post('/api/ranking/report', { userId: R.oh, name: '오예진', grade: '중1', day: T, studyMs: 1 });
  ok(r.status === 400 && /학년/.test(r.json.error), '잘못된 학년 → 400');

  section('순위 조회 — 오늘');
  r = await get(`/api/ranking?period=day&day=${T}&me=${enc(R.oh)}`);
  ok(r.status === 200 && r.json.period === 'day' && r.json.day === T && r.json.total === 6, `오늘 total 6`, r.json);
  ok(r.json.entries[0].rank === 1 && r.json.entries[0].name === '오XX' && r.json.entries[0].studyMs === 7200000 && r.json.entries[0].solved === 35 && r.json.entries[0].me === true, '1위 오XX (me true)', r.json.entries[0]);
  ok(r.json.entries.map((e) => e.rank).join(',') === '1,2,3,4,5,6' && r.json.entries.filter((e) => e.me).length === 1, '순위 번호 · me 는 한 명');
  ok(r.json.me && r.json.me.rank === 1 && r.json.me.studyMs === 7200000 && r.json.me.solved === 35, 'me = {rank 1, studyMs, solved}', r.json.me);
  ok(r.json.entries.every((e) => Object.keys(e).sort().join(',') === 'grade,me,name,rank,solved,studyMs'), '항목 필드 (userId 없음)');
  r = await get(`/api/ranking?me=rk-NOBODY`);
  ok(r.status === 200 && r.json.day === T && r.json.me === null, '기본값: period=day, day=서버 오늘, 보고 안 한 me → null', r.json);

  section('덮어쓰기 · 자르기');
  r = await post('/api/ranking/report', { userId: R.kim1, name: '김', grade: '고3', day: T, studyMs: 9000000, solved: 40 });
  r = await get(`/api/ranking?day=${T}&me=${enc(R.kim1)}`);
  ok(r.json.total === 6 && r.json.me.rank === 1 && r.json.me.studyMs === 9000000 && r.json.entries[0].name === '김XX', '같은 userId·day 다시 보고 → 덮어씀 (1위로)', r.json.me);
  r = await post('/api/ranking/report', { userId: R.kimEn, name: 'Kim', grade: '고3', day: T, studyMs: 30 * 3600000, solved: 5 });
  ok(r.json.studyMs === 86400000, '30시간 → 24시간으로 자름', r.json);
  r = await post('/api/ranking/report', { userId: R.anon, name: '', grade: '', day: T, studyMs: -500, solved: -3 });
  ok(r.json.studyMs === 0 && r.json.solved === 0, '음수 → 0', r.json);
  r = await post('/api/ranking/report', { userId: R.emo, name: 'x', grade: '고1', day: T, studyMs: 'abc' });
  ok(r.status === 200 && r.json.studyMs === 0, '숫자 아님 → 0');
  r = await get(`/api/ranking?day=${T}&me=${enc(R.kimEn)}`);
  ok(r.json.me.rank === 1 && r.json.me.studyMs === 86400000, '자른 값으로 순위 계산');

  section('주간 합계 · 학년 필터');
  await post('/api/ranking/report', { userId: R.oh, name: '오예진', grade: '고3', day: Y, studyMs: 3600000, solved: 5 });
  await post('/api/ranking/report', { userId: R.oh, name: '오예진', grade: '고3', day: D3, studyMs: 1000000, solved: 2 });
  await post('/api/ranking/report', { userId: R.oh, name: '오예진', grade: '고3', day: D8, studyMs: 50000000, solved: 99 });
  await post('/api/ranking/report', { userId: R.g2, name: '박서준', grade: '고2', day: Y, studyMs: 5000000, solved: 12 });
  r = await get(`/api/ranking?period=week&day=${T}&me=${enc(R.oh)}`);
  ok(r.status === 200 && r.json.period === 'week' && r.json.me.studyMs === 7200000 + 3600000 + 1000000 && r.json.me.solved === 35 + 5 + 2, '주간 = 7일 합 (8일 전 기록은 빠짐)', r.json.me);
  ok(r.json.from === dayOffset(-6), 'week 응답에 from(시작 날짜)', r.json.from);
  ok(r.json.total === 7, '주간 total 7 (어제만 보고한 사람 포함)', r.json.total);
  r = await get(`/api/ranking?period=day&day=${Y}&me=${enc(R.oh)}`);
  ok(r.json.total === 2 && r.json.me.studyMs === 3600000 && r.json.entries[0].name === '박XX' && r.json.me.rank === 2, 'day=어제 → 그날 기록만', r.json);
  r = await get(`/api/ranking?period=week&day=${T}&grade=${enc('고2')}`);
  ok(r.json.total === 1 && r.json.entries.length === 1 && r.json.entries[0].grade === '고2' && r.json.entries[0].name === '박XX', 'grade=고2 필터', r.json);
  r = await get(`/api/ranking?period=day&day=${T}&grade=${enc('고3')}&me=${enc(R.oh)}`);
  ok(r.json.total === 3 && r.json.entries.every((e) => e.grade === '고3') && r.json.me && r.json.me.rank === 3, 'grade=고3 필터 + 그 안에서 내 순위', r.json);
  r = await get(`/api/ranking?period=day&day=${T}&grade=${enc('고1')}&me=${enc(R.oh)}`);
  ok(r.json.me === null, '필터에 내가 없으면 me null');
  r = await get('/api/ranking?period=month');
  ok(r.status === 400 && isKo(r), 'period 잘못 → 400');
  r = await get('/api/ranking?day=2026-02-30');
  ok(r.status === 400, '없는 날짜 → 400');

  section('상위 50명');
  const many = [];
  for (let i = 0; i < 55; i++) {
    const uid = `rk-MANY-${String(i).padStart(2, '0')}-q7`;
    usedIds.add(uid);
    many.push(post('/api/ranking/report', { userId: uid, name: `학생${i}`, grade: 'N수', day: D3, studyMs: (i + 1) * 60000, solved: i }));
  }
  const res55 = await Promise.all(many);
  ok(res55.every((x) => x.status === 200), '55명 동시 보고 성공');
  r = await get(`/api/ranking?day=${D3}&grade=N${enc('수')}&me=rk-MANY-00-q7`);
  ok(r.json.total === 55 && r.json.entries.length === 50, 'entries 상위 50명, total 55', { total: r.json.total, n: r.json.entries.length });
  ok(r.json.entries[0].studyMs === 55 * 60000 && r.json.entries[49].rank === 50, '1위 = 가장 많이 공부한 사람');
  ok(r.json.me && r.json.me.rank === 55 && !r.json.entries.some((e) => e.me), '50위 밖의 me → rank 55 (entries 엔 없음)', r.json.me);
  const disk = JSON.parse(fs.readFileSync(path.join(DATA_DIR, 'ranking.json'), 'utf8'));
  ok(Object.keys(disk.days[D3]).length === 56, '디스크에 55명 + 1 모두 저장 (직렬화된 쓰기)');

  // ───────── userId 비노출 ─────────
  section('userId 비노출');
  const leaks = [];
  for (const b of bodies) for (const id of usedIds) if (b.text.includes(id)) leaks.push(`${b.p} ← ${id}`);
  ok(leaks.length === 0, `응답 ${bodies.length}개 어디에도 userId 없음`, leaks.slice(0, 5));

  // ───────── 저장 · 재시작 ─────────
  section('저장 · 재시작 · 90일 정리');
  ok(fs.existsSync(path.join(DATA_DIR, 'community.json')) && fs.existsSync(path.join(DATA_DIR, 'ranking.json')), 'DATA_DIR 에 community.json, ranking.json');
  ok(!fs.readdirSync(DATA_DIR).some((f) => f.endsWith('.tmp')), '임시 파일이 남지 않음');
  const listBefore = (await get('/api/community/posts')).json.posts.map((p) => `${p.id}:${p.views}:${p.likes}:${p.comments}`).join(',');
  await sleep(150); // 조회수 저장(기다리지 않는 쓰기)이 끝나도록
  await stopServer();
  const rk = JSON.parse(fs.readFileSync(path.join(DATA_DIR, 'ranking.json'), 'utf8'));
  rk.days['2000-01-01'] = { 'rk-OLD': { name: '옛XX', grade: '고3', studyMs: 1, solved: 1, at: 1 } };
  rk.days[dayOffset(-91)] = { 'rk-OLD': { name: '옛XX', grade: '고3', studyMs: 1, solved: 1, at: 1 } };
  fs.writeFileSync(path.join(DATA_DIR, 'ranking.json'), JSON.stringify(rk));
  logBuf = '';
  await startServer(env);
  const listAfter = (await get('/api/community/posts')).json.posts.map((p) => `${p.id}:${p.views}:${p.likes}:${p.comments}`).join(',');
  ok(listBefore === listAfter && listAfter.length > 0, '재시작 후 글·조회수·좋아요·댓글 수 그대로', `${listBefore} vs ${listAfter}`);
  r = await get(`/api/ranking?day=${T}&me=${enc(R.kim1)}`);
  ok(r.json.total === 6 && r.json.me && r.json.me.studyMs === 9000000, '재시작 후 순위 그대로');
  await sleep(200);
  const rk2 = JSON.parse(fs.readFileSync(path.join(DATA_DIR, 'ranking.json'), 'utf8'));
  ok(!rk2.days['2000-01-01'] && !rk2.days[dayOffset(-91)] && !!rk2.days[D8], '90일 지난 기록은 정리 (8일 전 기록은 유지)', Object.keys(rk2.days));
  ok(!/community\.json|ranking\.json|커뮤니티|순위/.test(logBuf), '시작할 때 커뮤니티·순위 관련 잡음 출력 없음', logBuf);
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
