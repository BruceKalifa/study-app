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
 *  관리(출제실 "커뮤니티 관리" 탭, 헤더 x-admin-key 또는 ?key=):
 *    GET    /api/admin/community/reports
 *    GET    /api/admin/community/posts?q=&before=&limit=    (추가: 숨김 포함 최근 글 + 댓글)
 *    POST   /api/admin/community/posts/:id/restore
 *    DELETE /api/admin/community/posts/:id
 *    DELETE /api/admin/community/posts/:id/comments/:cid
 *
 * userId 는 저장만 하고 어떤 응답에도 내보내지 않는다 (본인 여부는 mine / liked 로만).
 * 저장: DATA_DIR/community.json
 */

const path = require('path');
const crypto = require('crypto');
const { JsonStore } = require('./json-store');
const { CORS, HttpError, sendJson, sendError, readJson, pathParts, charLen, charSlice, GRADES } = require('./http-util');

const BOARDS = [
  { id: 'free', name: '자유', desc: '수험생활 이야기' },
  { id: 'qna', name: '질문', desc: '과목·문제 질문' },
  { id: 'proof', name: '공부인증', desc: '오늘 공부한 것 인증' },
  { id: 'info', name: '입시정보', desc: '입시·모의고사 정보' },
  { id: 'mind', name: '고민·멘탈', desc: '털어놓고 응원받기' },
];
const BOARD_IDS = new Set(BOARDS.map((b) => b.id));

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
function needGrade(v) {
  const g = typeof v === 'string' ? v.trim() : v == null ? '' : null;
  if (g === '') return '';
  if (g == null || !GRADES.includes(g)) throw new HttpError(400, '학년은 고1·고2·고3·N수 중 하나이거나 비워 두어야 합니다');
  return g;
}
function newId(prefix) {
  return `${prefix}_${Date.now().toString(36)}${crypto.randomBytes(4).toString('hex')}`;
}
function previewOf(body) {
  const flat = body.replace(/\s+/g, ' ').trim();
  return charSlice(flat, LIMITS.preview);
}

// ───────────────────────── API ─────────────────────────
function createCommunityApi({ dataDir, checkKey, log }) {
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
  }));
  const posts = () => store.data.posts;

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
    };
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
    list.splice(i, 1);
    byId.delete(id);
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
    return { posts: list.map((p) => postSummary(p, me)) };
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
    if (p.userId !== userId) throw new HttpError(403, '본인이 쓴 글만 삭제할 수 있습니다');
    removePost(id);
    await persist();
    return { ok: true };
  }

  async function addComment(req, id) {
    const b = await readJson(req, MAX_BODY_BYTES);
    const userId = needUserId(b.userId);
    const p = findPost(id);
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
    const i = p.likes.indexOf(userId);
    if (i >= 0) p.likes.splice(i, 1); else p.likes.push(userId);
    await persist();
    return { likes: p.likes.length, liked: i < 0 };
  }

  async function report(req, id) {
    const b = await readJson(req, MAX_BODY_BYTES);
    const userId = needUserId(b.userId);
    const p = findPost(id);
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
      }
      if (parts.length === 4 && sub === 'comments' && m === 'DELETE') return sendJson(res, 200, await deleteComment(req, id, cid, url));
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
