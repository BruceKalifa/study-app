'use strict';
/**
 * 선생님께 질문하기 (1:1) API (문서: docs/accounts-api.md — "질문")
 *
 *    POST /api/questions                          (학생) { teacherId, problemId?, title?, body, image? }
 *    GET  /api/questions?status=open|answered|resolved|all
 *    GET  /api/questions/:id                      (읽음 표시)
 *    POST /api/questions/:id/messages             { body?, image? }   (학생·선생님 모두)
 *    POST /api/questions/:id/resolve              해결됨으로
 *    GET  /api/questions/:id/images/:imageId      질문·답장에 붙은 그림 (참여자만)
 *
 * image: "data:image/png;base64,…" 또는 base64 문자열 (PNG/JPEG, 2.5MB 까지) — 앱이 찍은 풀이 화면이나
 * 선생님이 필기로 쓴 풀이. 파일은 DATA_DIR/question-images/ 에 저장한다.
 * 상태: open(선생님 답을 기다림) → answered(선생님이 답함) → resolved(해결). 새 메시지가 오면 다시 open/answered.
 * 저장: DATA_DIR/questions.json
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { JsonStore } = require('./json-store');
const { HttpError, sendJson, sendError, readJson, pathParts, charLen, charSlice } = require('./http-util');

const MAX_BODY_BYTES = 4 * 1024 * 1024;
const MAX_IMAGE_BYTES = Math.floor(2.5 * 1024 * 1024);
const LIMITS = { title: 80, body: 3000, problemId: 160 };
const CTRL_LINE = /[\u0000-\u001F\u007F\u200B\u2028\u2029]/g; // eslint-disable-line no-control-regex
const CTRL_BODY = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g; // eslint-disable-line no-control-regex
const STATUSES = ['open', 'answered', 'resolved'];
const ID_RE = /^[A-Za-z0-9_-]{1,80}$/;

function lineText(v) { return typeof v === 'string' ? v.replace(CTRL_LINE, ' ').replace(/\s+/g, ' ').trim() : ''; }
function bodyText(v) { return typeof v === 'string' ? v.replace(/\r\n?/g, '\n').replace(CTRL_BODY, '').trim() : ''; }
function newId(prefix) { return `${prefix}_${Date.now().toString(36)}${crypto.randomBytes(4).toString('hex')}`; }

/** data URL / base64 → { buf, ext } (PNG·JPEG 만) */
function decodeImage(v) {
  if (v == null || v === '') return null;
  if (typeof v !== 'string') throw new HttpError(400, '그림 형식이 잘못되었습니다');
  const m = /^data:image\/(png|jpe?g);base64,/i.exec(v);
  const b64 = m ? v.slice(m[0].length) : v;
  const buf = Buffer.from(b64, 'base64');
  if (buf.length === 0) throw new HttpError(400, '그림 형식이 잘못되었습니다');
  if (buf.length > MAX_IMAGE_BYTES) throw new HttpError(413, `그림이 너무 큽니다 (최대 ${Math.round(MAX_IMAGE_BYTES / 1024 / 1024 * 10) / 10}MB)`);
  const png = buf.length > 8 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47;
  const jpg = buf.length > 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff;
  if (!png && !jpg) throw new HttpError(400, 'PNG 또는 JPEG 그림만 보낼 수 있습니다');
  return { buf, ext: png ? 'png' : 'jpg' };
}

function createQuestionsApi({ dataDir, accounts, log }) {
  log = log || ((m) => console.warn(m));
  const imageDir = path.join(dataDir, 'question-images');
  const store = new JsonStore({
    file: path.join(dataDir, 'questions.json'),
    empty: () => ({ version: 1, questions: [] }),
    log,
  }).load();
  if (!Array.isArray(store.data.questions)) store.data.questions = [];
  const list = () => store.data.questions;
  let byId = new Map(list().map((q) => [q.id, q]));

  async function persist() {
    try { await store.save(); } catch (e) { throw new HttpError(500, '저장하지 못했습니다. 잠시 뒤 다시 시도하세요.'); }
  }

  async function saveImage(img) {
    if (!img) return null;
    const id = `${newId('img')}.${img.ext}`;
    await fs.promises.mkdir(imageDir, { recursive: true });
    await fs.promises.writeFile(path.join(imageDir, id), img.buf);
    return id;
  }

  function sideOf(q, u) {
    if (u.id === q.studentId) return 'student';
    if (u.id === q.teacherId) return 'teacher';
    return null;
  }
  function find(id, u) {
    const q = byId.get(id);
    if (!q || !sideOf(q, u)) throw new HttpError(404, '질문이 없거나 볼 수 없습니다');
    return q;
  }
  function unreadFor(q, side) {
    const last = q.messages[q.messages.length - 1];
    if (!last || last.from === side) return false;
    return (q.readAt && q.readAt[side] ? q.readAt[side] : 0) < last.at;
  }
  function imageUrl(q, imageId) { return imageId ? `/api/questions/${q.id}/images/${imageId}` : null; }

  function summary(q, u) {
    const side = sideOf(q, u);
    const first = q.messages[0];
    const last = q.messages[q.messages.length - 1];
    return {
      id: q.id,
      student: accounts.brief(accounts.userById(q.studentId)) || { id: q.studentId, name: '(탈퇴)', grade: '' },
      teacher: accounts.brief(accounts.userById(q.teacherId)) || { id: q.teacherId, name: '(탈퇴)' },
      problemId: q.problemId || null,
      title: q.title,
      preview: charSlice((first && first.body ? first.body : '').replace(/\s+/g, ' ').trim(), 100),
      hasImage: q.messages.some((m) => m.image),
      status: q.status,
      createdAt: q.createdAt,
      updatedAt: q.updatedAt,
      messageCount: q.messages.length,
      lastFrom: last ? last.from : 'student',
      unread: unreadFor(q, side),
    };
  }
  function full(q, u) {
    return Object.assign(summary(q, u), {
      messages: q.messages.map((m) => ({
        id: m.id,
        from: m.from,
        name: m.name,
        body: m.body,
        image: imageUrl(q, m.image),
        at: m.at,
        mine: m.userId === u.id,
      })),
    });
  }

  function readMessage(b, needSomething) {
    const body = bodyText(b.body);
    if (charLen(body) > LIMITS.body) throw new HttpError(400, `내용은 ${LIMITS.body}자까지 쓸 수 있습니다 (지금 ${charLen(body)}자)`);
    const img = decodeImage(b.image);
    if (needSomething && !body && !img) throw new HttpError(400, '내용을 쓰거나 그림을 붙여 주세요');
    return { body, img };
  }

  async function create(req, u) {
    accounts.need(u, 'student');
    const b = await readJson(req, MAX_BODY_BYTES);
    const teacherId = typeof b.teacherId === 'string' ? b.teacherId.trim() : '';
    if (!teacherId) throw new HttpError(400, '질문할 선생님을 골라 주세요');
    if (!accounts.isLinked(u.id, teacherId)) throw new HttpError(403, '연결된 선생님에게만 질문할 수 있습니다');
    const title = charSlice(lineText(b.title), LIMITS.title) || '질문';
    let problemId = null;
    if (b.problemId != null && b.problemId !== '') {
      problemId = lineText(String(b.problemId));
      if (charLen(problemId) > LIMITS.problemId) throw new HttpError(400, '문제 id 가 너무 깁니다');
    }
    const { body, img } = readMessage(b, true);
    const now = Date.now();
    const q = {
      id: newId('q'),
      studentId: u.id,
      teacherId,
      problemId: problemId || null,
      title,
      status: 'open',
      createdAt: now,
      updatedAt: now,
      readAt: { student: now },
      messages: [{ id: newId('m'), from: 'student', userId: u.id, name: u.name, body, image: await saveImage(img), at: now }],
    };
    list().push(q);
    byId.set(q.id, q);
    await persist();
    return { question: full(q, u) };
  }

  function listFor(u, url) {
    const status = (url.searchParams.get('status') || 'all').trim();
    if (status !== 'all' && !STATUSES.includes(status)) throw new HttpError(400, 'status 는 open·answered·resolved·all 중 하나입니다');
    const studentId = (url.searchParams.get('student') || '').trim();
    const out = list().filter((q) => sideOf(q, u)
      && (status === 'all' || q.status === status)
      && (!studentId || q.studentId === studentId));
    out.sort((a, b) => b.updatedAt - a.updatedAt);
    return { questions: out.slice(0, 300).map((q) => summary(q, u)) };
  }

  async function read(id, u) {
    const q = find(id, u);
    const side = sideOf(q, u);
    (q.readAt ||= {})[side] = Date.now();
    store.save().catch(() => {});
    return { question: full(q, u) };
  }

  async function addMessage(req, id, u) {
    const q = find(id, u);
    const side = sideOf(q, u);
    const b = await readJson(req, MAX_BODY_BYTES);
    const { body, img } = readMessage(b, true);
    const now = Date.now();
    if (q.messages.length >= 200) throw new HttpError(400, '한 질문에는 메시지를 200개까지 쓸 수 있습니다');
    const m = { id: newId('m'), from: side, userId: u.id, name: u.name, body, image: await saveImage(img), at: now };
    q.messages.push(m);
    q.status = side === 'teacher' ? 'answered' : 'open';
    q.updatedAt = now;
    (q.readAt ||= {})[side] = now;
    await persist();
    return { question: full(q, u) };
  }

  async function resolve(id, u) {
    const q = find(id, u);
    q.status = 'resolved';
    q.resolvedAt = Date.now();
    q.updatedAt = q.updatedAt || q.resolvedAt;
    await persist();
    return { ok: true };
  }

  function sendImage(res, id, imageId, u) {
    const q = find(id, u);
    if (!ID_RE.test(imageId.replace(/\.(png|jpg)$/, '')) || !q.messages.some((m) => m.image === imageId)) {
      throw new HttpError(404, '그림이 없습니다');
    }
    const file = path.join(imageDir, imageId);
    fs.readFile(file, (err, buf) => {
      if (err) { sendJson(res, 404, { error: '그림이 없습니다' }); return; }
      res.writeHead(200, {
        'Content-Type': imageId.endsWith('.png') ? 'image/png' : 'image/jpeg',
        'Content-Length': buf.length,
        'Cache-Control': 'private, max-age=86400',
        'Access-Control-Allow-Origin': '*',
      });
      res.end(buf);
    });
  }

  /** /api/me 의 counts: 학생 = 선생님이 답한 안 읽은 질문 수, 선생님 = 답을 기다리는 질문 수 */
  accounts.setCounts((u) => {
    let unread = 0, open = 0;
    for (const q of list()) {
      const side = sideOf(q, u);
      if (!side) continue;
      if (unreadFor(q, side)) unread++;
      if (q.status === 'open') open++;
    }
    return { unreadQuestions: unread, openQuestions: open };
  });

  async function route(req, res, url) {
    const u = accounts.auth(req);
    const m = req.method;
    const parts = pathParts(url.pathname).slice(2); // api/questions 다음
    const [id, sub, x] = parts;
    const ok = (obj) => sendJson(res, 200, obj);
    if (parts.length === 0) {
      if (m === 'GET') return ok(listFor(u, url));
      if (m === 'POST') return ok(await create(req, u));
    }
    if (parts.length === 1 && m === 'GET') return ok(await read(id, u));
    if (parts.length === 2 && m === 'POST') {
      if (sub === 'messages') return ok(await addMessage(req, id, u));
      if (sub === 'resolve') return ok(await resolve(id, u));
    }
    if (parts.length === 3 && sub === 'images' && m === 'GET') return sendImage(res, id, x, u);
    throw new HttpError(404, '없는 주소이거나 지원하지 않는 방식입니다');
  }

  function handle(req, res, url) {
    const p = url.pathname;
    if (p !== '/api/questions' && !p.startsWith('/api/questions/')) return false;
    if (req.method === 'OPTIONS') {
      res.writeHead(204, {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Max-Age': '600',
      }).end();
      return true;
    }
    Promise.resolve().then(() => route(req, res, url)).catch((e) => sendError(res, e, log));
    return true;
  }

  return { handle, saveSync: () => store.saveSync() };
}

module.exports = { createQuestionsApi, decodeImage };
