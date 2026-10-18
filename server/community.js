'use strict';
/**
 * 커뮤니티 게시판 API (문서: docs/community-api.md)
 *
 *  공개(앱용, CORS *):
 *    GET    /api/community/boards
 *    GET    /api/community/posts?board=&q=&sort=new|hot&before=&limit=&me=
 *    POST   /api/community/posts
 *    GET    /api/community/posts/:id?me=            (조회수 +1)
 *    DELETE /api/community/posts/:id?userId=        (본인만)
 *    POST   /api/community/posts/:id/comments
 *    DELETE /api/community/posts/:id/comments/:cid?userId=   (본인만)
 *    POST   /api/community/posts/:id/like           (토글)
 *    POST   /api/community/posts/:id/report
 *
 *    POST   /api/community/posts/:id/attachments?userId=&name=   (PDF 원본 바이트, 글쓴이만, 자료요청 게시판만)
 *    GET    /api/community/posts/:id/attachments/:aid/file        (글쓴이 ?userId= / 선생님 Bearer / 관리 키)
 *    DELETE /api/community/posts/:id/attachments/:aid?userId=     (글쓴이만)
 *
 *  관리(출제실 "커뮤니티 관리" 탭, 헤더 x-admin-key 또는 ?key=):
 *    GET    /api/admin/community/reports
 *    GET    /api/admin/community/posts?q=&before=&limit=    (추가: 숨김 포함 최근 글 + 댓글)
 *    POST   /api/admin/community/posts/:id/restore
 *    DELETE /api/admin/community/posts/:id
 *    DELETE /api/admin/community/posts/:id/comments/:cid
 *    GET    /api/admin/community/posts/:id/attachments/:aid/file  (첨부 PDF 내려받기)
 *
 * userId 는 저장만 하고 어떤 응답에도 내보내지 않는다 (본인 여부는 mine / liked 로만).
 * 저장: DATA_DIR/community.json
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { JsonStore } = require('./json-store');
const { CORS, HttpError, sendJson, sendError, readJson, pathParts, charLen, charSlice, GRADES, IDENTITIES } = require('./http-util');

// tracks: 이 게시판이 맞는 학년·과정 (앱이 가입 때 고른 과정에 맞는 게시판만 칩으로 보여 준다). 빈 배열 = 모두.
// 앱의 lib/services/community_api.dart 의 Board.defaults 와 id·이름이 같아야 한다.
const HIGH = ['고1', '고2', '고3', 'N수'];
const BOARDS = [
  { id: 'free', name: '자유', desc: '수험생활 이야기', tracks: [] },
  { id: 'qna', name: '질문', desc: '과목·문제 질문', tracks: [] },
  { id: 'request', name: '자료요청', desc: '필요한 문제·교재를 요청해요 (PDF 첨부 가능)', tracks: [], attach: true },
  { id: 'proof', name: '공부인증', desc: '오늘 공부한 것 인증', tracks: [] },
  { id: 'info', name: '입시정보', desc: '입시·모의고사 정보', tracks: HIGH },
  { id: 'mind', name: '고민·멘탈', desc: '털어놓고 응원받기', tracks: [] },
  { id: 'tips', name: '공부법·꿀팁', desc: '시간표·암기·오답 정리 노하우', tracks: [] },
  { id: 'study', name: '스터디 모집', desc: '같이 공부할 사람 찾기', tracks: [] },
  { id: 'naesin', name: '내신', desc: '학교 시험·수행평가·내신 전략', tracks: ['고1', '고2', '고3'] },
  { id: 'suneung', name: '수능·모의고사', desc: '학평·모평·수능 후기와 분석', tracks: ['고2', '고3', 'N수'] },
  { id: 'math', name: '수학', desc: '수학 개념·풀이·킬러 문항', tracks: HIGH },
  { id: 'sci', name: '과학', desc: '물리·화학·생명·지구과학', tracks: HIGH },
  { id: 'lang', name: '국어·영어', desc: '국어·영어 공부법과 질문', tracks: HIGH },
  { id: 'soc', name: '사회탐구', desc: '사탐 과목 공부법과 질문', tracks: HIGH },
  { id: 'sisi', name: '수시·정시', desc: '수시 최저·정시 지원 전략', tracks: ['고3', 'N수'] },
  { id: 'nsu', name: 'N수·재수', desc: '반수·재수 생활과 계획', tracks: ['N수'] },
  { id: 'apt', name: '인적성·NCS', desc: '인적성·NCS 후기와 유형 공유', tracks: ['취준'] },
  { id: 'job', name: '취업정보', desc: '채용 일정·자소서·면접 정보', tracks: ['취준'] },
  { id: 'hyu', name: '한양대 라운지', desc: '학교 생활·수강·시험 이야기', tracks: ['한양대'] },
  { id: 'univmath', name: '공업수학·미분적분학', desc: '공업수학1·2, 미분적분학1·2 질문', tracks: ['한양대'] },
  { id: 'univexam', name: '시험·학점', desc: '중간·기말 대비와 학점 관리', tracks: ['한양대'] },
  { id: 'transfer', name: '편입정보', desc: '대학별 일정·기출·합격 후기', tracks: ['편입'] },
  { id: 'trmath', name: '편입수학', desc: '편입수학 개념과 기출 질문', tracks: ['편입'] },
];
const BOARD_IDS = new Set(BOARDS.map((b) => b.id));
const ATTACH_BOARDS = new Set(BOARDS.filter((b) => b.attach).map((b) => b.id));
const MAX_ATTACH_BYTES = 20 * 1024 * 1024; // PDF 한 개 20MB
const MAX_ATTACH_PER_POST = 3;
const NOTICE_USER = '\u0000notice'; // 공지의 userId (사용자 입력으로는 만들 수 없는 값)
const NOTICE_VERSION = 1; // 공지 문구를 바꾸면 올린다 → 다시 올라온다 (관리자가 지운 공지는 같은 버전에서는 되살리지 않는다)

const RULES_TEXT = [
  '서로 응원하며 공부하는 공간이에요. 아래 이용수칙을 꼭 지켜 주세요.',
  '',
  '1. 서로 존중해요. 욕설·비방·조롱·차별하는 말은 쓰지 않아요.',
  '2. 개인정보(실명, 연락처, SNS 계정, 집 주소 등)를 쓰지 않아요. 내 것도, 남의 것도요.',
  '3. 광고·홍보·도배·낚시성 글은 올리지 않아요.',
  '4. 저작권을 지켜요. 시판 교재나 학원 자료, 기출 해설을 통째로 올리지 않아요.',
  '5. 시험 중 문제를 공유하는 등 부정행위를 부추기는 글은 쓰지 않아요.',
  '6. 게시판 주제에 맞게 써요. 질문은 질문 게시판, 자료는 자료요청 게시판에 올려 주세요.',
  '',
  '수칙을 어긴 글은 신고가 3건 쌓이면 자동으로 숨겨지고, 반복되면 이용이 제한될 수 있어요.',
].join('\n');
const REQUEST_TEXT = [
  '필요한 문제나 자료가 있으면 이 게시판에 요청해 주세요. 선생님이 확인하고 새 문제를 만들어 드려요.',
  '',
  '요청할 때 이렇게 써 주세요.',
  '- 과목·학년·단원 (예: 고2 수학Ⅱ, 미분)',
  '- 원하는 유형·난이도·문항 수',
  '- 시험 범위나 쓰는 교재 이름',
  '',
  '관련 학습 교안(학교 프린트, 수업 필기, 단원 정리 등)을 PDF로 함께 올려 주시면 큰 도움이 돼요! 그 자료를 바탕으로 수업 내용에 딱 맞는 문제를 새로 만들 수 있어요.',
  '',
  '· PDF는 글 쓸 때 첨부해요. 파일 하나당 20MB까지, 최대 3개예요.',
  '· 첨부한 PDF는 글쓴이와 선생님만 열어 볼 수 있어요.',
  '· 시판 교재나 학원 자료 전체를 그대로 올리는 것은 안 돼요. 직접 필기한 노트나 학교 수업 자료 위주로 올려 주세요.',
  '',
  '이용수칙도 함께 지켜 주세요: 서로 존중하기, 개인정보 쓰지 않기, 광고·도배 금지, 저작권 지키기.',
].join('\n');
function noticeFor(board) {
  if (board.id === 'request') return { title: '📌 자료요청 게시판 이용 안내', body: REQUEST_TEXT };
  return { title: '📌 이용수칙을 지켜 주세요', body: RULES_TEXT };
}

const LIMITS = {
  title: 80,
  body: 5000,
  author: 20,
  comment: 1000,
  reason: 200,
  problemId: 120,
  userId: 100,
  preview: 120,
};
const POST_INTERVAL_MS = 20 * 1000; // 같은 userId 글 1개 / 20초
const COMMENT_INTERVAL_MS = 5 * 1000; // 같은 userId 댓글 1개 / 5초
const HIDE_AFTER_REPORTS = 3; // 서로 다른 3명이 신고하면 숨김
const HOT_DAYS = 7;
const MAX_BODY_BYTES = 64 * 1024;

// ───────────────────────── 값 정리 ─────────────────────────
// 제목·이름: 제어 문자 제거 / 본문: 줄바꿈·탭만 남김
const CTRL_ALL = /[\u0000-\u001F\u007F\u200B\u2028\u2029]/g; // eslint-disable-line no-control-regex
const CTRL_BODY = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g; // eslint-disable-line no-control-regex

function lineText(v) {
  return typeof v === 'string' ? v.replace(CTRL_ALL, ' ').replace(/\s+/g, ' ').trim() : '';
}
function bodyText(v) {
  return typeof v === 'string' ? v.replace(/\r\n?/g, '\n').replace(CTRL_BODY, '').trim() : '';
}
function needUserId(v) {
  const id = typeof v === 'string' ? v.trim() : typeof v === 'number' ? String(v) : '';
  if (!id) throw new HttpError(400, 'userId 가 필요합니다');
  if (id.length > LIMITS.userId) throw new HttpError(400, 'userId 가 너무 깁니다');
  return id;
}
function optUserId(v) {
  const id = typeof v === 'string' ? v.trim() : '';
  return id && id.length <= LIMITS.userId ? id : '';
}
/** 받침 있으면 a, 없으면 b (을/를, 은/는) */
function josa(word, a, b) {
  const c = word.charCodeAt(word.length - 1);
  if (c >= 0xAC00 && c <= 0xD7A3) return word + ((c - 0xAC00) % 28 ? a : b);
  return word + a + '(' + b + ')';
}
function needText(value, label, max, isBody) {
  const s = isBody ? bodyText(value) : lineText(value);
  const n = charLen(s);
  if (n < 1) throw new HttpError(400, `${josa(label, '을', '를')} 입력하세요`);
  if (n > max) throw new HttpError(400, `${josa(label, '은', '는')} ${max}자까지 쓸 수 있습니다 (지금 ${n}자)`);
  return s;
}
// 신분 표시: 빈 값 | 학년 하나('고2' '한양대' …) | 신분 라벨('N수생' '한양대생' …)을 " · " 로 이은 것 (최대 3개)
function needGrade(v) {
  const g = typeof v === 'string' ? v.trim() : v == null ? '' : null;
  if (g === '') return '';
  const bad = () => new HttpError(400, '신분은 고1·고2·고3·N수생·취준생·한양대생·편입생 중에서(여러 개는 " · " 로 이어) 보내거나 비워 두어야 합니다');
  if (g == null) throw bad();
  const parts = g.split(/\s*·\s*/);
  if (parts.length > 3) throw bad();
  const seen = [];
  for (const x of parts) {
    if (!GRADES.includes(x) && !IDENTITIES.includes(x)) throw bad();
    if (!seen.includes(x)) seen.push(x);
  }
  return seen.join(' · ');
}
function newId(prefix) {
  return `${prefix}_${Date.now().toString(36)}${crypto.randomBytes(4).toString('hex')}`;
}
function previewOf(body) {
  const flat = body.replace(/\s+/g, ' ').trim();
  return charSlice(flat, LIMITS.preview);
}

// ───────────────────────── API ─────────────────────────
function createCommunityApi({ dataDir, checkKey, log, accounts }) {
  log = log || ((m) => console.warn(m));
  const store = new JsonStore({
    file: path.join(dataDir, 'community.json'),
    empty: () => ({ version: 1, posts: [] }),
    log,
  }).load();
  if (!Array.isArray(store.data.posts)) store.data.posts = [];
  // 손으로 고친 파일 등에 빠진 필드를 채운다
  store.data.posts = store.data.posts.filter((p) => p && typeof p.id === 'string').map((p) => Object.assign(p, {
    title: String(p.title || ''),
    body: String(p.body || ''),
    author: String(p.author || '익명'),
    createdAt: Number(p.createdAt) || 0,
    likes: Array.isArray(p.likes) ? p.likes : [],
    views: Number(p.views) || 0,
    comments: Array.isArray(p.comments) ? p.comments.filter((c) => c && typeof c.id === 'string') : [],
    reports: Array.isArray(p.reports) ? p.reports.filter(Boolean) : [],
    hidden: !!p.hidden,
    attachments: Array.isArray(p.attachments) ? p.attachments.filter((a) => a && typeof a.id === 'string') : [],
  }));
  const posts = () => store.data.posts;
  const filesDir = path.join(dataDir, 'community-files');
  const fileOf = (a) => path.join(filesDir, `${a.id}.pdf`);

  // 게시판마다 고정 공지 (이용수칙 / 자료요청 안내). 문구 버전이 올라가면 다시 올린다.
  function seedNotices() {
    if (!store.data.noticeSeed || typeof store.data.noticeSeed !== 'object') store.data.noticeSeed = {};
    let changed = false;
    const list = store.data.posts;
    for (const b of BOARDS) {
      if ((store.data.noticeSeed[b.id] || 0) >= NOTICE_VERSION) continue;
      const id = `notice_${b.id}`;
      const i = list.findIndex((p) => p.id === id);
      if (i >= 0) list.splice(i, 1);
      const n = noticeFor(b);
      list.push({
        id, board: b.id, title: n.title, body: n.body, author: '솔빗 운영', grade: '', userId: NOTICE_USER,
        createdAt: Date.now(), likes: [], views: 0, comments: [], reports: [], hidden: false, attachments: [], notice: true,
      });
      store.data.noticeSeed[b.id] = NOTICE_VERSION;
      changed = true;
    }
    if (changed) store.save().catch((e) => log(`공지 저장 실패: ${e.message}`));
  }
  seedNotices();

  // 글 id → 글 (빠른 찾기)
  let byId = new Map();
  function reindex() { byId = new Map(posts().map((p) => [p.id, p])); }
  reindex();

  // 간단한 도배 방지 (메모리에만)
  const lastPost = new Map();
  const lastComment = new Map();
  function checkRate(map, userId, interval, what) {
    const now = Date.now();
    const t = map.get(userId);
    if (t && now - t < interval) {
      const sec = Math.ceil((interval - (now - t)) / 1000);
      throw new HttpError(429, `${josa(what, '은', '는')} ${Math.round(interval / 1000)}초에 하나만 쓸 수 있습니다. ${sec}초 뒤에 다시 시도하세요.`);
    }
  }
  function markRate(map, userId, interval) {
    const now = Date.now();
    map.set(userId, now);
    if (map.size > 2000) for (const [k, t] of map) if (now - t >= interval) map.delete(k);
  }

  async function persist() {
    try {
      await store.save();
    } catch (e) {
      throw new HttpError(500, '저장하지 못했습니다. 잠시 뒤 다시 시도하세요.');
    }
  }

  // ── 응답 모양 (userId 는 절대 넣지 않는다) ──
  function postSummary(p, me) {
    return {
      id: p.id,
      board: p.board,
      title: p.title,
      preview: previewOf(p.body),
      author: p.author,
      grade: p.grade || '',
      createdAt: p.createdAt,
      likes: p.likes.length,
      liked: !!me && p.likes.includes(me),
      comments: p.comments.length,
      views: p.views,
      problemId: p.problemId || null,
      mine: !!me && p.userId === me,
      notice: !!p.notice,
      attachments: attachViews(p),
    };
  }
  function attachViews(p) {
    return (p.attachments || []).map((a) => ({ id: a.id, name: a.name, size: a.size }));
  }
  function commentView(c, me) {
    return { id: c.id, author: c.author, grade: c.grade || '', body: c.body, createdAt: c.createdAt, mine: !!me && c.userId === me };
  }
  function postFull(p, me) {
    return Object.assign(postSummary(p, me), { body: p.body, comments: p.comments.map((c) => commentView(c, me)) });
  }
  function adminView(p) {
    return {
      id: p.id,
      board: p.board,
      title: p.title,
      body: p.body,
      author: p.author,
      grade: p.grade || '',
      createdAt: p.createdAt,
      likes: p.likes.length,
      views: p.views,
      problemId: p.problemId || null,
      notice: !!p.notice,
      attachments: (p.attachments || []).map((a) => ({ id: a.id, name: a.name, size: a.size, createdAt: a.createdAt })),
      hidden: !!p.hidden,
      hiddenAt: p.hiddenAt || null,
      reportCount: p.reports.length,
      reports: p.reports.map((r) => ({ reason: r.reason, at: r.at })),
      comments: p.comments.map((c) => ({ id: c.id, author: c.author, grade: c.grade || '', body: c.body, createdAt: c.createdAt })),
    };
  }

  function findPost(id, { allowHidden } = {}) {
    const p = byId.get(id);
    if (!p) throw new HttpError(404, '글이 없거나 삭제되었습니다');
    if (p.hidden && !allowHidden) throw new HttpError(404, '신고가 많아 숨겨진 글입니다');
    return p;
  }
  function removePost(id) {
    const list = posts();
    const i = list.findIndex((p) => p.id === id);
    if (i < 0) return false;
    const [gone] = list.splice(i, 1);
    byId.delete(id);
    for (const a of gone.attachments || []) fs.unlink(fileOf(a), () => {});
    return true;
  }

  function parseLimit(v, def, max) {
    if (v == null || v === '') return def;
    const n = Math.floor(Number(v));
    if (!Number.isFinite(n) || n < 1) return def;
    return Math.min(max, n);
  }
  function parseBefore(v) {
    if (v == null || v === '') return null;
    const n = Number(v);
    if (!Number.isFinite(n)) throw new HttpError(400, 'before 는 시각(ms) 숫자여야 합니다');
    return n;
  }
  function matchQ(p, q) {
    if (!q) return true;
    return p.title.toLowerCase().includes(q) || p.body.toLowerCase().includes(q);
  }

  // ── 공개 ──
  function listPosts(url) {
    const sp = url.searchParams;
    const board = (sp.get('board') || '').trim();
    if (board && !BOARD_IDS.has(board)) throw new HttpError(400, '없는 게시판입니다');
    const q = (sp.get('q') || '').trim().toLowerCase();
    const sort = (sp.get('sort') || 'new').trim();
    if (sort !== 'new' && sort !== 'hot') throw new HttpError(400, 'sort 는 new 또는 hot 이어야 합니다');
    const before = parseBefore(sp.get('before'));
    const limit = parseLimit(sp.get('limit'), 30, 50);
    const me = optUserId(sp.get('me'));
    const since = Date.now() - HOT_DAYS * 86400000;

    let list = posts().filter((p) => !p.hidden
      && !p.notice
      && (!board || p.board === board)
      && (before == null || p.createdAt < before)
      && (sort !== 'hot' || p.createdAt >= since)
      && matchQ(p, q));
    if (sort === 'hot') {
      const score = (p) => p.likes.length * 3 + p.comments.length * 2 + p.views / 10;
      list.sort((a, b) => score(b) - score(a) || b.createdAt - a.createdAt);
    } else {
      list.sort((a, b) => b.createdAt - a.createdAt);
    }
    list = list.slice(0, limit);
    // 고정 공지: 게시판을 골라 첫 쪽을 볼 때, 검색이 아닐 때만 맨 위에
    const pinned = board && before == null && !q && sort === 'new'
      ? posts().filter((p) => p.notice && p.board === board && !p.hidden) : [];
    return { posts: pinned.concat(list).map((p) => postSummary(p, me)) };
  }

  async function createPost(req) {
    const b = await readJson(req, MAX_BODY_BYTES);
    const userId = needUserId(b.userId);
    const board = typeof b.board === 'string' ? b.board.trim() : '';
    if (!BOARD_IDS.has(board)) throw new HttpError(400, '게시판을 골라 주세요 (없는 게시판입니다)');
    const title = needText(b.title, '제목', LIMITS.title, false);
    const body = needText(b.body, '본문', LIMITS.body, true);
    const author = needText(b.author, '닉네임', LIMITS.author, false);
    const grade = needGrade(b.grade);
    let problemId = null;
    if (b.problemId != null && b.problemId !== '') {
      problemId = lineText(String(b.problemId));
      if (charLen(problemId) > LIMITS.problemId) throw new HttpError(400, '문제 id 가 너무 깁니다');
      if (!problemId) problemId = null;
    }
    checkRate(lastPost, userId, POST_INTERVAL_MS, '글');

    const p = {
      id: newId('p'),
      board, title, body, author, grade,
      userId,
      createdAt: Date.now(),
      likes: [],
      views: 0,
      comments: [],
      reports: [],
      hidden: false,
      attachments: [],
    };
    if (problemId) p.problemId = problemId;
    posts().push(p);
    byId.set(p.id, p);
    markRate(lastPost, userId, POST_INTERVAL_MS);
    await persist();
    return { post: postFull(p, userId) };
  }

  function readPost(id, url) {
    const p = findPost(id);
    const me = optUserId(url.searchParams.get('me'));
    p.views = (p.views || 0) + 1;
    store.save().catch(() => {}); // 조회수는 기다리지 않고 저장
    return { post: postFull(p, me) };
  }

  async function bodyOrQueryUserId(req, url) {
    let uid = url.searchParams.get('userId');
    if (!uid) {
      const b = await readJson(req, MAX_BODY_BYTES).catch(() => ({}));
      uid = b.userId;
    }
    return needUserId(uid);
  }

  async function deletePost(req, id, url) {
    const userId = await bodyOrQueryUserId(req, url);
    const p = findPost(id, { allowHidden: true });
    if (p.notice || p.userId !== userId) throw new HttpError(403, '본인이 쓴 글만 삭제할 수 있습니다');
    removePost(id);
    await persist();
    return { ok: true };
  }

  async function addComment(req, id) {
    const b = await readJson(req, MAX_BODY_BYTES);
    const userId = needUserId(b.userId);
    const p = findPost(id);
    if (p.notice) throw new HttpError(403, '공지에는 댓글을 달 수 없어요');
    const body = needText(b.body, '댓글', LIMITS.comment, true);
    const author = needText(b.author, '닉네임', LIMITS.author, false);
    const grade = needGrade(b.grade);
    checkRate(lastComment, userId, COMMENT_INTERVAL_MS, '댓글');
    const c = { id: newId('c'), userId, author, grade, body, createdAt: Date.now() };
    p.comments.push(c);
    markRate(lastComment, userId, COMMENT_INTERVAL_MS);
    await persist();
    return { comment: commentView(c, userId) };
  }

  async function deleteComment(req, id, cid, url) {
    const userId = await bodyOrQueryUserId(req, url);
    const p = findPost(id, { allowHidden: true });
    const i = p.comments.findIndex((c) => c.id === cid);
    if (i < 0) throw new HttpError(404, '댓글이 없거나 삭제되었습니다');
    if (p.comments[i].userId !== userId) throw new HttpError(403, '본인이 쓴 댓글만 삭제할 수 있습니다');
    p.comments.splice(i, 1);
    await persist();
    return { ok: true };
  }

  async function toggleLike(req, id) {
    const b = await readJson(req, MAX_BODY_BYTES);
    const userId = needUserId(b.userId);
    const p = findPost(id);
    if (p.notice) throw new HttpError(403, '공지에는 응원을 누를 수 없어요');
    const i = p.likes.indexOf(userId);
    if (i >= 0) p.likes.splice(i, 1); else p.likes.push(userId);
    await persist();
    return { likes: p.likes.length, liked: i < 0 };
  }

  async function report(req, id) {
    const b = await readJson(req, MAX_BODY_BYTES);
    const userId = needUserId(b.userId);
    const p = findPost(id);
    if (p.notice) throw new HttpError(403, '공지는 신고할 수 없어요');
    const reason = charSlice(lineText(b.reason), LIMITS.reason) || '(사유 없음)';
    if (!p.reports.some((r) => r.userId === userId)) {
      p.reports.push({ userId, reason, at: Date.now() });
      if (!p.hidden && p.reports.length >= HIDE_AFTER_REPORTS) {
        p.hidden = true;
        p.hiddenAt = Date.now();
      }
      await persist();
    }
    return { ok: true };
  }

  // ── 첨부 PDF ──
  function readRaw(req, maxBytes) {
    return new Promise((resolve, reject) => {
      const len = Number(req.headers['content-length']);
      if (Number.isFinite(len) && len > maxBytes) { req.resume(); reject(new HttpError(413, `PDF는 ${Math.round(maxBytes / 1048576)}MB까지 올릴 수 있어요`)); return; }
      const chunks = [];
      let size = 0;
      let done = false;
      req.on('data', (c) => {
        if (done) return;
        size += c.length;
        if (size > maxBytes) { done = true; reject(new HttpError(413, `PDF는 ${Math.round(maxBytes / 1048576)}MB까지 올릴 수 있어요`)); req.resume(); return; }
        chunks.push(c);
      });
      req.on('end', () => { if (!done) { done = true; resolve(Buffer.concat(chunks)); } });
      req.on('error', (e) => { if (!done) { done = true; reject(e); } });
    });
  }
  function attachName(v) {
    let n = lineText(typeof v === 'string' ? v : '').replace(/[\\/:*?"<>|]/g, '_');
    if (!n) n = '자료.pdf';
    if (!/\.pdf$/i.test(n)) n += '.pdf';
    return charLen(n) > 80 ? charSlice(n, 76) + '.pdf' : n;
  }
  async function addAttachment(req, id, url) {
    const userId = needUserId(url.searchParams.get('userId'));
    const p = findPost(id);
    if (p.userId !== userId) { req.resume(); throw new HttpError(403, '본인이 쓴 글에만 파일을 붙일 수 있어요'); }
    if (!ATTACH_BOARDS.has(p.board)) { req.resume(); throw new HttpError(400, '이 게시판에서는 파일을 붙일 수 없어요'); }
    if (p.attachments.length >= MAX_ATTACH_PER_POST) { req.resume(); throw new HttpError(409, `PDF는 글 하나에 ${MAX_ATTACH_PER_POST}개까지 붙일 수 있어요`); }
    const buf = await readRaw(req, MAX_ATTACH_BYTES);
    if (buf.length < 8 || buf.slice(0, 5).toString('latin1') !== '%PDF-') throw new HttpError(400, 'PDF 파일만 올릴 수 있어요');
    const a = { id: newId('f'), name: attachName(url.searchParams.get('name')), size: buf.length, createdAt: Date.now() };
    await fs.promises.mkdir(filesDir, { recursive: true });
    await fs.promises.writeFile(fileOf(a), buf);
    p.attachments.push(a);
    try { await persist(); } catch (e) { p.attachments.pop(); fs.unlink(fileOf(a), () => {}); throw e; }
    return { attachment: { id: a.id, name: a.name, size: a.size } };
  }
  async function deleteAttachment(id, aid, url) {
    const userId = needUserId(url.searchParams.get('userId'));
    const p = findPost(id, { allowHidden: true });
    if (p.userId !== userId) throw new HttpError(403, '본인이 붙인 파일만 지울 수 있어요');
    const i = p.attachments.findIndex((a) => a.id === aid);
    if (i < 0) throw new HttpError(404, '파일이 없어요');
    const [a] = p.attachments.splice(i, 1);
    fs.unlink(fileOf(a), () => {});
    await persist();
    return { ok: true };
  }
  /** 내려받기를 해도 되는 사람: 관리 키 · 선생님 로그인 · 글쓴이 */
  function mayOpen(req, url, p) {
    try { checkKey(req, url); return true; } catch (_) { /* 다음 */ }
    if (accounts) {
      try { if (accounts.auth(req).role === 'teacher') return true; } catch (_) { /* 다음 */ }
    }
    const uid = optUserId(url.searchParams.get('userId'));
    return !!uid && uid === p.userId;
  }
  async function sendAttachment(req, res, p, aid, url, admin) {
    if (!admin && !mayOpen(req, url, p)) throw new HttpError(403, '글쓴이와 선생님만 열 수 있어요');
    const a = p.attachments.find((x) => x.id === aid);
    if (!a) throw new HttpError(404, '파일이 없어요');
    let buf;
    try { buf = await fs.promises.readFile(fileOf(a)); } catch (_) { throw new HttpError(404, '파일을 찾을 수 없어요'); }
    res.writeHead(200, Object.assign({
      'Content-Type': 'application/pdf',
      'Content-Length': buf.length,
      'Cache-Control': 'private, no-store',
      'Content-Disposition': `attachment; filename*=UTF-8''${encodeURIComponent(a.name)}`,
    }, CORS));
    res.end(buf);
  }

  async function handlePublic(req, res, parts, url) {
    const m = req.method;
    const [a, id, sub, cid] = parts; // parts: community 다음 조각들
    if (a === 'boards' && parts.length === 1 && m === 'GET') return sendJson(res, 200, { boards: BOARDS });
    if (a === 'posts') {
      if (parts.length === 1) {
        if (m === 'GET') return sendJson(res, 200, listPosts(url));
        if (m === 'POST') return sendJson(res, 200, await createPost(req));
      }
      if (parts.length === 2) {
        if (m === 'GET') return sendJson(res, 200, readPost(id, url));
        if (m === 'DELETE') return sendJson(res, 200, await deletePost(req, id, url));
      }
      if (parts.length === 3 && m === 'POST') {
        if (sub === 'comments') return sendJson(res, 200, await addComment(req, id));
        if (sub === 'like') return sendJson(res, 200, await toggleLike(req, id));
        if (sub === 'report') return sendJson(res, 200, await report(req, id));
        if (sub === 'attachments') return sendJson(res, 200, await addAttachment(req, id, url));
      }
      if (parts.length === 4 && sub === 'comments' && m === 'DELETE') return sendJson(res, 200, await deleteComment(req, id, cid, url));
      if (parts.length === 4 && sub === 'attachments' && m === 'DELETE') return sendJson(res, 200, await deleteAttachment(id, cid, url));
      if (parts.length === 5 && sub === 'attachments' && parts[4] === 'file' && m === 'GET') {
        return await sendAttachment(req, res, findPost(id, { allowHidden: true }), cid, url, false);
      }
    }
    throw new HttpError(404, '없는 주소이거나 지원하지 않는 방식입니다');
  }

  // ── 관리 ──
  function adminReports() {
    const list = posts().filter((p) => p.hidden || p.reports.length > 0);
    const lastAt = (p) => Math.max(p.hiddenAt || 0, ...p.reports.map((r) => r.at));
    list.sort((a, b) => (b.hidden ? 1 : 0) - (a.hidden ? 1 : 0) || lastAt(b) - lastAt(a));
    return { posts: list.map(adminView) };
  }
  function adminPosts(url) {
    const sp = url.searchParams;
    const q = (sp.get('q') || '').trim().toLowerCase();
    const before = parseBefore(sp.get('before'));
    const limit = parseLimit(sp.get('limit'), 50, 200);
    const list = posts()
      .filter((p) => (before == null || p.createdAt < before) && (matchQ(p, q) || (q && p.author.toLowerCase().includes(q))))
      .sort((a, b) => b.createdAt - a.createdAt)
      .slice(0, limit);
    return { posts: list.map(adminView), total: posts().length };
  }

  async function handleAdmin(req, res, parts, url) {
    const m = req.method;
    const [a, id, sub, cid] = parts; // parts: admin/community 다음 조각들
    if (a === 'reports' && parts.length === 1 && m === 'GET') return sendJson(res, 200, adminReports());
    if (a === 'posts') {
      if (parts.length === 1 && m === 'GET') return sendJson(res, 200, adminPosts(url));
      if (parts.length === 2 && m === 'DELETE') {
        findPost(id, { allowHidden: true });
        removePost(id);
        await persist();
        return sendJson(res, 200, { ok: true });
      }
      if (parts.length === 3 && sub === 'restore' && m === 'POST') {
        const p = findPost(id, { allowHidden: true });
        p.hidden = false;
        delete p.hiddenAt;
        p.reports = []; // 복구하면 신고를 비운다 (다시 3명이 신고하면 다시 숨김)
        p.restoredAt = Date.now();
        await persist();
        return sendJson(res, 200, { ok: true });
      }
      if (parts.length === 5 && sub === 'attachments' && parts[4] === 'file' && m === 'GET') {
        return await sendAttachment(req, res, findPost(id, { allowHidden: true }), cid, url, true);
      }
      if (parts.length === 4 && sub === 'comments' && m === 'DELETE') {
        const p = findPost(id, { allowHidden: true });
        const i = p.comments.findIndex((c) => c.id === cid);
        if (i < 0) throw new HttpError(404, '댓글이 없거나 삭제되었습니다');
        p.comments.splice(i, 1);
        await persist();
        return sendJson(res, 200, { ok: true });
      }
    }
    throw new HttpError(404, '없는 주소이거나 지원하지 않는 방식입니다');
  }

  /** @returns {boolean} 처리했으면 true */
  function handle(req, res, url) {
    const p = url.pathname;
    const isPublic = p === '/api/community' || p.startsWith('/api/community/');
    const isAdmin = p === '/api/admin/community' || p.startsWith('/api/admin/community/');
    if (!isPublic && !isAdmin) return false;
    if (req.method === 'OPTIONS') { res.writeHead(204, CORS).end(); return true; }
    const parts = pathParts(p).slice(isAdmin ? 3 : 2);
    const fail = (e) => sendError(res, e, log);
    try {
      if (isAdmin) checkKey(req, url);
      Promise.resolve(isAdmin ? handleAdmin(req, res, parts, url) : handlePublic(req, res, parts, url)).catch(fail);
    } catch (e) {
      fail(e);
    }
    return true;
  }

  return { handle, store, saveSync: () => store.saveSync() };
}

module.exports = { createCommunityApi, BOARDS };
