'use strict';
/**
 * 교재 창고 — 선생님이 올린 교재(.pulinote)를 연결된 학생이 앱에서 받아간다 (문서: docs/accounts-api.md — "교재")
 *
 *   POST   /api/books?title=…&open=1   (선생님) 교재 올리기 — 본문은 .pulinote 파일 그대로
 *   GET    /api/books                  내가 받을 수 있는 교재 목록
 *   GET    /api/books/:id              교재 한 권 정보
 *   GET    /api/books/:id/file         교재 파일 받기 (올린 파일 그대로)
 *   POST   /api/books/:id              (올린 선생님) { title?, open?, students?[] }
 *   DELETE /api/books/:id              (올린 선생님) 지우기
 *
 * 교재 내용은 공개 저장소에 두지 않고 여기에만 둔다. 파일은 로그인 없이는 받을 수 없고,
 * 공개(open)한 교재는 로그인한 학생 누구나 받는다 (선생님과 연결돼 있지 않아도).
 * 공개하지 않은 교재는 선생님이 지정한(연결된) 학생만 받는다.
 * 저장: DATA_DIR/books.json (목록) + DATA_DIR/books/<id>.pulinote (파일 그대로)
 */

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const crypto = require('crypto');
const { JsonStore } = require('./json-store');
const { CORS, HttpError, sendJson, sendError, pathParts, charLen, charSlice } = require('./http-util');

const MAX_FILE_BYTES = 40 * 1024 * 1024; // 교재 한 파일 40MB 까지
const MAX_PER_TEACHER_BYTES = 400 * 1024 * 1024; // 선생님 한 명이 올릴 수 있는 전체 크기
const MAX_BOOKS_PER_TEACHER = 200;
const BUNDLE = 'pulinote-bundle';
const COLLECTION = 'pulinote-collection';
const ID_RE = /^[A-Za-z0-9][A-Za-z0-9_-]{0,80}$/;
const CTRL = /[\u0000-\u001F\u007F\u200B\u2028\u2029]/g; // eslint-disable-line no-control-regex

function lineText(v) { return typeof v === 'string' ? v.replace(CTRL, ' ').replace(/\s+/g, ' ').trim() : ''; }
function newId() { return `bk_${Date.now().toString(36)}${crypto.randomBytes(5).toString('hex')}`; }

/** 올린 파일(gzip 또는 그냥 JSON) → { title, bookIds, titles, problems } (잘못된 파일이면 HttpError) */
function readBundle(buf) {
  let raw = buf;
  if (buf.length > 2 && buf[0] === 0x1f && buf[1] === 0x8b) {
    try { raw = zlib.gunzipSync(buf); } catch (_) { throw new HttpError(400, '파일이 손상되었습니다'); }
  }
  let j;
  try { j = JSON.parse(raw.toString('utf8')); } catch (_) { throw new HttpError(400, 'Solvit 교재 파일이 아닙니다'); }
  if (!j || typeof j !== 'object' || Array.isArray(j)) throw new HttpError(400, 'Solvit 교재 파일이 아닙니다');
  const list = j.format === COLLECTION ? j.books : [j];
  if (!Array.isArray(list) || list.length === 0) throw new HttpError(400, '교재가 없습니다');
  const bookIds = [];
  const titles = [];
  let problems = 0;
  for (const b of list) {
    if (!b || typeof b !== 'object' || b.format !== BUNDLE) throw new HttpError(400, 'Solvit 교재 파일이 아닙니다');
    const id = `${b.id ?? ''}`;
    if (!ID_RE.test(id)) throw new HttpError(400, '교재 id 가 잘못되었습니다');
    if (!Array.isArray(b.courses)) throw new HttpError(400, '문항이 없습니다');
    for (const c of b.courses) {
      if (!c || typeof c !== 'object') continue;
      problems += (Array.isArray(c.problems) ? c.problems.length : 0) + (Array.isArray(c.twins) ? c.twins.length : 0);
    }
    bookIds.push(id);
    titles.push(charSlice(lineText(b.title) || id, 80));
  }
  if (problems === 0) throw new HttpError(400, '문항이 없습니다');
  const title = titles.length === 1 ? titles[0] : `${titles[0]} 외 ${titles.length - 1}권`;
  return { title, bookIds, titles, problems };
}

/** 본문 전체를 Buffer 로 (너무 크면 413) */
function readBody(req, maxBytes) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    let done = false;
    req.on('data', (c) => {
      if (done) return;
      size += c.length;
      if (size > maxBytes) {
        done = true;
        reject(new HttpError(413, `교재 파일이 너무 큽니다 (최대 ${Math.round(maxBytes / 1024 / 1024)}MB)`));
        req.resume();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => { if (!done) { done = true; resolve(Buffer.concat(chunks)); } });
    req.on('error', (e) => { if (!done) { done = true; reject(e); } });
  });
}

function createBooksApi({ dataDir, accounts, log }) {
  log = log || ((m) => console.warn(m));
  const fileDir = path.join(dataDir, 'books');
  const store = new JsonStore({
    file: path.join(dataDir, 'books.json'),
    empty: () => ({ version: 1, books: [] }),
    log,
  }).load();
  if (!Array.isArray(store.data.books)) store.data.books = [];
  const list = () => store.data.books;
  const byId = (id) => list().find((b) => b.id === id) || null;

  async function persist() {
    try {
      await store.save();
    } catch (e) {
      throw new HttpError(500, '저장하지 못했습니다. 잠시 뒤 다시 시도하세요.');
    }
  }

  function filePath(id) { return path.join(fileDir, `${id}.pulinote`); }

  /** 이 사람이 받을 수 있는 교재인가 */
  function canRead(u, b) {
    if (!b) return false;
    if (u.id === b.ownerId) return true;
    if (u.role !== 'student') return false;
    if (b.open === true) return true; // 모두에게 열기: 연결 여부와 상관없이 모든 학생
    return accounts.isLinked(u.id, b.ownerId) && Array.isArray(b.students) && b.students.includes(u.id);
  }
  function mine(u, id) {
    const b = byId(id);
    if (!b) throw new HttpError(404, '없는 교재입니다');
    if (b.ownerId !== u.id) throw new HttpError(403, '내가 올린 교재만 바꿀 수 있습니다');
    return b;
  }

  function view(b, u) {
    const owner = accounts.userById(b.ownerId);
    return {
      id: b.id,
      title: b.title,
      titles: b.titles || [b.title],
      bookIds: b.bookIds || [],
      problems: b.problems || 0,
      bytes: b.bytes || 0,
      sha: b.sha || '',
      at: b.at || 0,
      teacher: owner ? { id: owner.id, name: owner.name } : null,
      ...(u && u.id === b.ownerId ? { open: b.open === true, students: b.students || [], mine: true } : {}),
    };
  }

  function books(u) {
    const out = list().filter((b) => canRead(u, b)).sort((a, b) => (b.at || 0) - (a.at || 0));
    return { books: out.map((b) => view(b, u)) };
  }

  async function upload(req, u, url) {
    accounts.need(u, 'teacher');
    const buf = await readBody(req, MAX_FILE_BYTES);
    if (buf.length === 0) throw new HttpError(400, '교재 파일을 보내세요');
    const info = readBundle(buf);
    const ownBooks = list().filter((b) => b.ownerId === u.id);
    if (ownBooks.length >= MAX_BOOKS_PER_TEACHER) throw new HttpError(409, '올린 교재가 너무 많습니다. 쓰지 않는 교재를 지우세요.');
    const used = ownBooks.reduce((n, b) => n + (b.bytes || 0), 0);
    if (used + buf.length > MAX_PER_TEACHER_BYTES) throw new HttpError(409, '올린 교재 전체 크기가 한도를 넘었습니다. 쓰지 않는 교재를 지우세요.');
    const given = lineText(url.searchParams.get('title') || '');
    const title = charLen(given) > 0 ? charSlice(given, 80) : info.title;
    const openParam = url.searchParams.get('open');
    const open = openParam === null ? true : openParam === '1' || openParam === 'true';
    // 같은 내용(같은 교재 id 묶음)을 다시 올리면 새로 만들지 않고 바꾼다
    const key = info.bookIds.join('|');
    const old = ownBooks.find((b) => (b.bookIds || []).join('|') === key);
    const id = old ? old.id : newId();
    fs.mkdirSync(fileDir, { recursive: true });
    const tmp = `${filePath(id)}.tmp`;
    fs.writeFileSync(tmp, buf);
    fs.renameSync(tmp, filePath(id));
    const row = {
      id,
      ownerId: u.id,
      title,
      titles: info.titles,
      bookIds: info.bookIds,
      problems: info.problems,
      bytes: buf.length,
      sha: crypto.createHash('sha256').update(buf).digest('hex').slice(0, 16),
      at: Date.now(),
      open,
      students: old && Array.isArray(old.students) ? old.students : [],
    };
    if (old) list()[list().indexOf(old)] = row;
    else list().push(row);
    await persist();
    log(`교재 ${old ? '바꿈' : '올림'}: ${title} (${info.problems}문항, ${Math.round(buf.length / 1024)}KB)`);
    return { book: view(row, u), replaced: !!old };
  }

  async function update(req, u, id) {
    accounts.need(u, 'teacher');
    const b = mine(u, id);
    const body = await readBody(req, 64 * 1024);
    let j = {};
    if (body.length) {
      try { j = JSON.parse(body.toString('utf8')); } catch (_) { throw new HttpError(400, 'JSON 형식이 잘못되었습니다'); }
    }
    if (typeof j.title === 'string' && lineText(j.title)) b.title = charSlice(lineText(j.title), 80);
    if (typeof j.open === 'boolean') b.open = j.open;
    if (Array.isArray(j.students)) {
      b.students = j.students
        .map((x) => `${x}`)
        .filter((sid) => accounts.isLinked(sid, u.id))
        .slice(0, 500);
    }
    await persist();
    return { book: view(b, u) };
  }

  async function remove(u, id) {
    accounts.need(u, 'teacher');
    const b = mine(u, id);
    store.data.books = list().filter((x) => x.id !== b.id);
    try { fs.unlinkSync(filePath(b.id)); } catch (_) { /* 이미 없으면 그만 */ }
    await persist();
    return { ok: true };
  }

  function sendFile(res, u, id) {
    const b = byId(id);
    if (!canRead(u, b)) throw new HttpError(404, '없는 교재입니다');
    let st;
    try { st = fs.statSync(filePath(b.id)); } catch (_) { throw new HttpError(404, '교재 파일이 없습니다'); }
    res.writeHead(200, Object.assign({
      'Content-Type': 'application/gzip',
      'Content-Length': st.size,
      'Content-Disposition': `attachment; filename="${b.id}.pulinote"`,
      'Cache-Control': 'no-store',
    }, CORS));
    fs.createReadStream(filePath(b.id)).pipe(res);
  }

  async function route(req, res, url) {
    const m = req.method;
    const parts = pathParts(url.pathname).slice(1); // 'api' 다음
    const [, id, sub] = parts;
    const u = accounts.auth(req);
    const ok = (obj) => sendJson(res, 200, obj);
    if (parts.length === 1) {
      if (m === 'GET') return ok(books(u));
      if (m === 'POST') return ok(await upload(req, u, url));
    }
    if (parts.length === 2) {
      if (m === 'GET') {
        const b = byId(id);
        if (!canRead(u, b)) throw new HttpError(404, '없는 교재입니다');
        return ok({ book: view(b, u) });
      }
      if (m === 'POST') return ok(await update(req, u, id));
      if (m === 'DELETE') return ok(await remove(u, id));
    }
    if (parts.length === 3 && sub === 'file' && m === 'GET') return sendFile(res, u, id);
    throw new HttpError(404, '없는 주소이거나 지원하지 않는 방식입니다');
  }

  /** @returns {boolean} 처리했으면 true */
  function handle(req, res, url) {
    if (!/^\/api\/books(\/|$)/.test(url.pathname)) return false;
    if (req.method === 'OPTIONS') { res.writeHead(204, CORS).end(); return true; }
    Promise.resolve().then(() => route(req, res, url)).catch((e) => sendError(res, e, log));
    return true;
  }

  return { handle, count: () => list().length, saveSync: () => store.saveSync() };
}

module.exports = { createBooksApi, readBundle };
