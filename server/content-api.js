'use strict';
/**
 * 콘텐츠 API (문서: docs/content-api.md)
 *
 *  공개(앱용, CORS *):
 *    GET  /api/content/index
 *    GET  /api/content/pack/:subjectId
 *    GET  /api/content/workbooks
 *
 *  관리(출제 웹용, 헤더 x-admin-key 또는 ?key=):
 *    GET    /api/admin/check
 *    GET    /api/admin/courses
 *    GET    /api/admin/course/:id            PUT (만들기/고치기)   DELETE
 *    PUT    /api/admin/course/:id/problem    (?replace=옛id&after=문항id)
 *    DELETE /api/admin/course/:id/problem/:pid   (?cascade=1 이면 쌍둥이도 삭제)
 *    PUT    /api/admin/course/:id/passage    (?replace=옛id)
 *    DELETE /api/admin/course/:id/passage/:pid
 *    GET/PUT /api/admin/workbooks
 *    POST   /api/admin/import
 *    GET    /api/admin/export[/:id | /workbooks]
 */

const crypto = require('crypto');
const Schema = require('./public/admin/schema.js');

const MAX_BODY = 10 * 1024 * 1024;
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, PUT, POST, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, X-Admin-Key, If-None-Match',
  'Access-Control-Expose-Headers': 'ETag, X-Content-Version',
  'Access-Control-Max-Age': '600',
};

class HttpError extends Error {
  constructor(status, message, extra) {
    super(message);
    this.status = status;
    this.extra = extra || {};
  }
}

/** 검증 실패 → 400 (errors: [{where, field, message}]) */
function validationError(errors, warnings) {
  return new HttpError(400, `입력 내용에 오류가 ${errors.length}건 있습니다`, { errors, warnings: warnings || [] });
}

// ───────────────────────── 정리(필드 순서·빈 값) ─────────────────────────
const PROBLEM_ORDER = ['id', 'unit', 'topic', 'difficulty', 'type', 'passageId', 'twinOf', 'stem', 'boxItems', 'choices',
  'answer', 'answerUnit', 'tolerance', 'solution', 'hint', 'tags', 'template'];
const COURSE_ORDER = ['subject', 'subjectId', 'color', 'group', 'level', 'grades', 'track', 'units', 'passages', 'problems'];
const PASSAGE_ORDER = ['id', 'title', 'source', 'body'];
const WB_ORDER = ['id', 'title', 'course', 'level', 'desc', 'problems'];

function ordered(obj, order) {
  const out = {};
  for (const k of order) if (obj[k] !== undefined) out[k] = obj[k];
  for (const k of Object.keys(obj)) if (!(k in out) && obj[k] !== undefined && !k.startsWith('_')) out[k] = obj[k];
  return out;
}
const trimStr = (v) => (typeof v === 'string' ? v.trim() : v);
const emptyToUndef = (v) => (v == null || (typeof v === 'string' && v.trim() === '') ? undefined : v);

function normalizeProblem(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return raw;
  const p = Object.assign({}, raw);
  for (const k of ['id', 'unit', 'topic', 'type']) p[k] = trimStr(p[k]);
  if (typeof p.difficulty === 'string' && /^\d+$/.test(p.difficulty.trim())) p.difficulty = Number(p.difficulty);
  if (typeof p.answer === 'number') p.answer = String(p.answer);
  if (typeof p.answer === 'string') p.answer = p.answer.trim();
  for (const k of ['answerUnit', 'hint', 'passageId', 'twinOf']) p[k] = emptyToUndef(trimStr(p[k]));
  if (Array.isArray(p.boxItems)) { p.boxItems = p.boxItems.filter((x) => !(typeof x === 'string' && !x.trim())); if (!p.boxItems.length) delete p.boxItems; }
  if (Array.isArray(p.tags)) {
    p.tags = Array.from(new Set(p.tags.map(trimStr).filter((x) => typeof x !== 'string' || x)));
    if (!p.tags.length) delete p.tags;
  }
  if (p.type === 'short') {
    if (Array.isArray(p.choices) && p.choices.every((c) => typeof c !== 'string' || !c.trim())) delete p.choices;
    if (typeof p.tolerance === 'string' && p.tolerance.trim() !== '' && Number.isFinite(Number(p.tolerance))) p.tolerance = Number(p.tolerance);
    if (p.tolerance === 0 || p.tolerance === '' || p.tolerance == null) delete p.tolerance;
  } else if (p.type === 'choice') {
    delete p.tolerance;
    delete p.answerUnit;
  }
  if (p.template === null) delete p.template;
  return ordered(p, PROBLEM_ORDER);
}

function normalizePassage(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return raw;
  const p = Object.assign({}, raw);
  p.id = trimStr(p.id);
  p.title = emptyToUndef(p.title);
  p.source = emptyToUndef(p.source);
  return ordered(p, PASSAGE_ORDER);
}

/** deep=false 이면 문항·지문은 건드리지 않고 과목 정보만 정리 */
function normalizeCourse(raw, deep = true) {
  const c = Object.assign({}, raw);
  c.subjectId = trimStr(c.subjectId);
  c.subject = trimStr(c.subject);
  if (typeof c.color === 'string') c.color = c.color.trim().toUpperCase();
  c.track = emptyToUndef(c.track);
  c.group = emptyToUndef(c.group);
  c.level = emptyToUndef(c.level);
  for (const k of ['units', 'grades', 'passages', 'problems']) if (c[k] === null) delete c[k];
  if (Array.isArray(c.grades)) c.grades = Schema.GRADES.filter((g) => c.grades.includes(g)).concat(c.grades.filter((g) => !Schema.GRADES.includes(g)));
  if (Array.isArray(c.units)) { c.units = c.units.map(trimStr).filter((u) => u !== ''); if (!c.units.length) delete c.units; }
  if (Array.isArray(c.passages)) { if (deep) c.passages = c.passages.map(normalizePassage); if (!c.passages.length) delete c.passages; }
  if (Array.isArray(c.problems) && deep) c.problems = c.problems.map(normalizeProblem);
  return ordered(c, COURSE_ORDER);
}

function normalizeWorkbook(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return raw;
  const w = Object.assign({}, raw);
  w.id = trimStr(w.id);
  w.title = trimStr(w.title);
  w.course = trimStr(w.course);
  w.level = emptyToUndef(w.level);
  w.desc = emptyToUndef(w.desc);
  if (Array.isArray(w.problems)) w.problems = w.problems.map(trimStr);
  return ordered(w, WB_ORDER);
}

// ───────────────────────── 도우미 ─────────────────────────
function issueKey(e) { return Schema.formatIssue(e); }
/** after 에서 before 에 없던 것만 */
function newIssues(before, after) {
  const seen = new Set(before.map(issueKey));
  return after.filter((e) => !seen.has(issueKey(e)));
}

function courseSummary(id, entry) {
  const c = entry.data;
  const problems = c.problems || [];
  const twins = problems.filter((p) => p && p.twinOf).length;
  return {
    id,
    subject: c.subject || id,
    color: c.color || null,
    group: c.group || null,
    level: c.level || null,
    grades: Array.isArray(c.grades) ? c.grades : [],
    track: c.track || null,
    units: Array.isArray(c.units) ? c.units : [],
    count: problems.length,
    originals: problems.length - twins,
    twins,
    templates: problems.filter((p) => p && p.template).length,
    passages: (c.passages || []).length,
    version: entry.version,
    updatedAt: Math.round(entry.updatedAt),
  };
}

function sortCourseIds(store) {
  const order = (g) => { const i = Schema.GROUP_ORDER.indexOf(g); return i < 0 ? 99 : i; };
  const lv = (l) => (l === 'mid' ? 0 : l === 'high' ? 1 : 2);
  return store.courseIds().sort((a, b) => {
    const A = store.getCourse(a).data;
    const B = store.getCourse(b).data;
    return order(A.group) - order(B.group) || lv(A.level) - lv(B.level) || String(A.subject || a).localeCompare(String(B.subject || b), 'ko');
  });
}

function wbIssues(store, courses, workbooks) {
  return Schema.validateWorkbooks(workbooks, store.problemIndex(courses), new Set(courses.keys()));
}

// ───────────────────────── API ─────────────────────────
function createContentApi({ store, adminKey, log }) {
  log = log || ((m) => console.log(m));
  const keyBuf = Buffer.from(String(adminKey));
  const failures = new Map(); // ip → { n, until }

  function checkKey(req, url) {
    const ip = req.socket.remoteAddress || '';
    const f = failures.get(ip);
    if (f && f.n >= 10 && Date.now() < f.until) throw new HttpError(429, '관리자 키를 너무 많이 틀렸습니다. 1분 뒤에 다시 시도하세요.');
    const given = String(req.headers['x-admin-key'] || url.searchParams.get('key') || '');
    if (!given) throw new HttpError(401, '관리자 키가 필요합니다 (서버 화면에 표시된 6자리 키)');
    const g = Buffer.from(given);
    const ok = g.length === keyBuf.length && crypto.timingSafeEqual(g, keyBuf);
    if (!ok) {
      const n = f && Date.now() < f.until ? f.n + 1 : 1;
      failures.set(ip, { n, until: Date.now() + 60000 });
      throw new HttpError(401, '관리자 키가 맞지 않습니다');
    }
    failures.delete(ip);
  }

  function readBody(req) {
    return new Promise((resolve, reject) => {
      const chunks = [];
      let size = 0;
      req.on('data', (c) => {
        size += c.length;
        if (size > MAX_BODY) { reject(new HttpError(413, '보낸 내용이 너무 큽니다 (최대 10MB)')); req.destroy(); return; }
        chunks.push(c);
      });
      req.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8').replace(/^﻿/, '');
        if (!text.trim()) { resolve(null); return; }
        try { resolve(JSON.parse(text)); } catch (e) { reject(new HttpError(400, `JSON 형식이 잘못되었습니다: ${e.message}`)); }
      });
      req.on('error', reject);
    });
  }

  function sendJson(res, status, obj, headers) {
    const body = JSON.stringify(obj);
    res.writeHead(status, Object.assign({
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-cache',
      'Content-Length': Buffer.byteLength(body),
    }, CORS, headers || {}));
    res.end(body);
  }

  /** 미리 직렬화된 파일 내용을 ETag 와 함께 (If-None-Match 이면 304) */
  function sendFile(req, res, canon, version, extra) {
    const etag = `"${version}"`;
    const headers = Object.assign({ ETag: etag, 'X-Content-Version': version, 'Cache-Control': 'no-cache' }, CORS, extra || {});
    if (req.headers['if-none-match'] === etag) { res.writeHead(304, headers).end(); return; }
    const buf = Buffer.from(canon, 'utf8');
    res.writeHead(200, Object.assign({ 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': buf.length }, headers));
    res.end(req.method === 'HEAD' ? undefined : buf);
  }

  function mustCourse(id) {
    const e = store.getCourse(id);
    if (!e) throw new HttpError(404, `과목 "${id}" 가 없습니다`);
    return e;
  }
  function draftCourse(draft, id) {
    const c = draft.courses.get(id);
    if (!c) throw new HttpError(404, `과목 "${id}" 가 없습니다`);
    if (!Array.isArray(c.problems)) c.problems = [];
    return c;
  }
  function index() {
    const packs = sortCourseIds(store).map((id) => {
      const e = store.getCourse(id);
      const c = e.data;
      return {
        id,
        name: c.subject || id,
        group: c.group || '',
        level: c.level || '',
        version: e.version,
        count: (c.problems || []).length,
        color: c.color || null,
        grades: Array.isArray(c.grades) ? c.grades : [],
        track: c.track || null,
        updatedAt: Math.round(e.updatedAt),
      };
    });
    const wb = store.workbooks();
    return { packs, workbooks: { version: wb.version, count: wb.data.workbooks.length } };
  }

  // ── 공개 ──
  function handlePublic(req, res, parts) {
    if (req.method !== 'GET' && req.method !== 'HEAD') throw new HttpError(405, 'GET 만 지원합니다');
    if (parts[0] === 'index' && parts.length === 1) return sendJson(res, 200, index());
    if (parts[0] === 'pack' && parts.length === 2) {
      const id = parts[1].replace(/\.json$/, '');
      const e = mustCourse(id);
      return sendFile(req, res, e.canon, e.version);
    }
    if (parts[0] === 'workbooks' && parts.length === 1) {
      const wb = store.workbooks();
      return sendFile(req, res, wb.canon, wb.version);
    }
    throw new HttpError(404, '없는 주소입니다');
  }

  // ── 관리 ──
  async function handleAdmin(req, res, parts, url) {
    const m = req.method;
    const q = (k) => url.searchParams.get(k);
    const [a, id, sub, pid] = parts;

    if (a === 'check' && m === 'GET') return sendJson(res, 200, { ok: true });

    if (a === 'courses' && parts.length === 1 && m === 'GET') {
      return sendJson(res, 200, { courses: sortCourseIds(store).map((cid) => courseSummary(cid, store.getCourse(cid))) });
    }

    if (a === 'course' && id && parts.length === 2) {
      if (m === 'GET') {
        const e = mustCourse(id);
        return sendJson(res, 200, { course: e.data, version: e.version, file: e.file, updatedAt: Math.round(e.updatedAt) });
      }
      if (m === 'PUT') return putCourse(req, res, id);
      if (m === 'DELETE') return deleteCourse(res, id);
    }
    if (a === 'course' && id && sub === 'problem') {
      if (m === 'PUT' && parts.length === 3) return putProblem(req, res, id, q('replace'), q('after'));
      if (m === 'DELETE' && parts.length === 4) return deleteProblem(res, id, pid, q('cascade') === '1');
    }
    if (a === 'course' && id && sub === 'passage') {
      if (m === 'PUT' && parts.length === 3) return putPassage(req, res, id, q('replace'));
      if (m === 'DELETE' && parts.length === 4) return deletePassage(res, id, pid);
    }
    if (a === 'workbooks' && parts.length === 1) {
      if (m === 'GET') { const wb = store.workbooks(); return sendJson(res, 200, { workbooks: wb.data.workbooks, version: wb.version }); }
      if (m === 'PUT') return putWorkbooks(req, res);
    }
    if (a === 'import' && parts.length === 1 && m === 'POST') return importContent(req, res);
    if (a === 'export' && m === 'GET') {
      if (parts.length === 1) {
        const bundle = {
          exportedAt: new Date().toISOString(),
          courses: sortCourseIds(store).map((cid) => store.getCourse(cid).data),
          workbooks: store.workbooks().data.workbooks,
        };
        const stamp = new Date().toISOString().slice(0, 10);
        return sendJson(res, 200, bundle, { 'Content-Disposition': `attachment; filename="pulinote-content-${stamp}.json"` });
      }
      if (parts.length === 2 && id === 'workbooks') {
        const wb = store.workbooks();
        return sendFile(req, res, wb.canon, wb.version, { 'Content-Disposition': 'attachment; filename="workbooks.json"' });
      }
      if (parts.length === 2) {
        const e = mustCourse(id.replace(/\.json$/, ''));
        return sendFile(req, res, e.canon, e.version, { 'Content-Disposition': `attachment; filename="${encodeURIComponent(e.data.subjectId || id)}.json"` });
      }
    }
    throw new HttpError(404, '없는 주소이거나 지원하지 않는 방식입니다');
  }

  // PUT /api/admin/course/:id
  async function putCourse(req, res, id) {
    const body = await readBody(req);
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new HttpError(400, '과목 정보({ … })를 보내세요');
    const result = await store.mutate((draft) => {
      const existing = draft.courses.get(id);
      const newId = body.subjectId ? String(body.subjectId).trim() : id;
      let c;
      if (existing) {
        c = Object.assign({}, existing);
        for (const k of Object.keys(body)) if (k !== 'problems' && k !== 'passages') c[k] = body[k];
        if (Array.isArray(body.problems)) c.problems = body.problems;
        if (Array.isArray(body.passages)) c.passages = body.passages;
        // 비우려고 보낸 선택 필드
        for (const k of ['track', 'units', 'grades', 'group', 'level']) if (k in body && (body[k] === null || body[k] === '')) delete c[k];
      } else {
        c = Object.assign({ problems: [] }, body);
        if (!Array.isArray(c.problems)) c.problems = [];
      }
      c.subjectId = newId;
      const replacedItems = !existing || Array.isArray(body.problems) || Array.isArray(body.passages);
      c = normalizeCourse(c, replacedItems);
      if (newId !== id && draft.courses.has(newId)) throw validationError([{ where: newId, field: 'subjectId', message: `과목 id "${newId}" 는 이미 있습니다` }]);
      draft.courses.delete(id);
      draft.courses.set(newId, c);
      let rep;
      if (replacedItems) {
        rep = Schema.validateCourse(c, { foreignIds: store.foreignIds(newId, draft.courses) });
      } else {
        rep = new Schema.Report();
        Schema.validateCourseMeta(c, rep);
      }
      let wbErrors = [];
      if (existing && newId !== id) {
        draft.renames.set(newId, id);
        for (const w of draft.workbooks) if (w && w.course === id) w.course = newId;
      }
      if (replacedItems) {
        const before = wbIssues(store, new Map(Array.from(store.courses, ([k, v]) => [k, v.data])), store.workbooks().data.workbooks).errors;
        wbErrors = newIssues(before, wbIssues(store, draft.courses, draft.workbooks).errors);
      }
      const errors = rep.errors.concat(wbErrors);
      if (errors.length) throw validationError(errors, rep.warnings);
      return { created: !existing, id: newId, renamedFrom: newId !== id && existing ? id : undefined, warnings: rep.warnings };
    });
    const e = store.getCourse(result.id);
    log(`[출제] 과목 ${result.created ? '추가' : '저장'}: ${result.id}${result.renamedFrom ? ` (← ${result.renamedFrom})` : ''}`);
    sendJson(res, result.created ? 201 : 200, Object.assign({ ok: true, course: courseSummary(result.id, e) }, result));
  }

  async function deleteCourse(res, id) {
    mustCourse(id);
    const result = await store.mutate((draft) => {
      const c = draftCourse(draft, id);
      const ids = new Set((c.problems || []).map((p) => p && p.id));
      draft.courses.delete(id);
      const removedWorkbooks = [];
      draft.workbooks = draft.workbooks.filter((w) => {
        if (w && w.course === id) { removedWorkbooks.push(w.id); return false; }
        return true;
      });
      for (const w of draft.workbooks) if (w && Array.isArray(w.problems)) w.problems = w.problems.filter((x) => !ids.has(x));
      return { removedWorkbooks };
    });
    log(`[출제] 과목 삭제: ${id} (content/_trash 에 보관)`);
    sendJson(res, 200, Object.assign({ ok: true, id }, result));
  }

  async function putProblem(req, res, cid, replaceId, afterId) {
    mustCourse(cid);
    let body = await readBody(req);
    if (body && body.problem && typeof body.problem === 'object') body = body.problem;
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new HttpError(400, '문항({ … })을 보내세요');
    const p = normalizeProblem(body);
    const result = await store.mutate((draft) => {
      const c = draftCourse(draft, cid);
      const before = Schema.validateCourse(store.getCourse(cid).data, { foreignIds: store.foreignIds(cid), only: new Set() });
      const list = c.problems;
      const oldId = replaceId && replaceId !== p.id ? replaceId : null;
      let idx = list.findIndex((x) => x && x.id === (oldId || p.id));
      if (oldId && idx < 0) throw new HttpError(404, `바꿀 문항 "${oldId}" 가 이 과목에 없습니다`);
      const created = idx < 0;
      if (oldId) {
        if (list.some((x) => x && x.id === p.id)) throw validationError([{ where: p.id, field: 'id', message: `id "${p.id}" 는 이 과목에 이미 있습니다` }]);
        for (const x of list) if (x && x.twinOf === oldId) x.twinOf = p.id;
        for (const w of draft.workbooks) if (w && Array.isArray(w.problems)) w.problems = w.problems.map((x) => (x === oldId ? p.id : x));
      }
      if (!created) {
        list[idx] = p;
      } else {
        let at = list.length;
        if (afterId) {
          const ai = list.findIndex((x) => x && x.id === afterId);
          if (ai >= 0) at = ai + 1;
        } else if (p.twinOf) {
          // 원본 바로 뒤(이미 있는 쌍둥이들 다음)에 넣는다
          let last = -1;
          list.forEach((x, i) => { if (x && (x.id === p.twinOf || x.twinOf === p.twinOf)) last = i; });
          if (last >= 0) at = last + 1;
        }
        list.splice(at, 0, p);
        idx = at;
      }
      const after = Schema.validateCourse(c, { foreignIds: store.foreignIds(cid, draft.courses), only: new Set([p.id]) });
      const errs = after.errors.filter((e) => e.where === p.id).concat(newIssues(before.errors, after.errors.filter((e) => e.where !== p.id)));
      const wbBefore = wbIssues(store, new Map(Array.from(store.courses, ([k, v]) => [k, v.data])), store.workbooks().data.workbooks).errors;
      const wbErr = newIssues(wbBefore, wbIssues(store, draft.courses, draft.workbooks).errors);
      const errors = errs.concat(wbErr);
      if (errors.length) throw validationError(errors, after.warnings.filter((w) => w.where === p.id));
      return { created, index: idx, renamedFrom: oldId || undefined, warnings: after.warnings.filter((w) => w.where === p.id) };
    });
    const e = store.getCourse(cid);
    log(`[출제] 문항 ${result.created ? '추가' : '저장'}: ${cid}/${p.id}`);
    sendJson(res, result.created ? 201 : 200, Object.assign({ ok: true, problem: e.data.problems[result.index], version: e.version, count: e.data.problems.length }, result));
  }

  async function deleteProblem(res, cid, pid, cascade) {
    mustCourse(cid);
    const result = await store.mutate((draft) => {
      const c = draftCourse(draft, cid);
      const target = c.problems.find((x) => x && x.id === pid);
      if (!target) throw new HttpError(404, `문항 "${pid}" 가 이 과목에 없습니다`);
      const twins = c.problems.filter((x) => x && x.twinOf === pid).map((x) => x.id);
      if (twins.length && !cascade) {
        throw new HttpError(400, `이 문항을 원본으로 하는 쌍둥이 문항 ${twins.length}개가 있습니다: ${twins.join(', ')} — 쌍둥이를 먼저 지우거나 함께 삭제를 선택하세요`, { twins });
      }
      const gone = new Set([pid].concat(twins));
      c.problems = c.problems.filter((x) => !(x && gone.has(x.id)));
      const removedFromWorkbooks = [];
      for (const w of draft.workbooks) {
        if (!w || !Array.isArray(w.problems)) continue;
        const n = w.problems.length;
        w.problems = w.problems.filter((x) => !gone.has(x));
        if (w.problems.length !== n) removedFromWorkbooks.push(w.id);
      }
      return { deleted: Array.from(gone), removedFromWorkbooks };
    });
    const e = store.getCourse(cid);
    log(`[출제] 문항 삭제: ${cid}/${result.deleted.join(', ')}`);
    sendJson(res, 200, Object.assign({ ok: true, version: e.version, count: e.data.problems.length }, result));
  }

  async function putPassage(req, res, cid, replaceId) {
    mustCourse(cid);
    let body = await readBody(req);
    if (body && body.passage && typeof body.passage === 'object') body = body.passage;
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new HttpError(400, '지문({ … })을 보내세요');
    const ps = normalizePassage(body);
    const result = await store.mutate((draft) => {
      const c = draftCourse(draft, cid);
      if (!Array.isArray(c.passages)) c.passages = [];
      const oldId = replaceId && replaceId !== ps.id ? replaceId : null;
      const idx = c.passages.findIndex((x) => x && x.id === (oldId || ps.id));
      if (oldId && idx < 0) throw new HttpError(404, `바꿀 지문 "${oldId}" 가 이 과목에 없습니다`);
      const rep = new Schema.Report();
      Schema.validatePassage(ps, rep);
      const foreign = store.foreignIds(cid, draft.courses);
      if (ps.id && foreign.has(ps.id)) rep.err(ps.id, 'id', `id "${ps.id}" 는 이미 다른 과목(${foreign.get(ps.id)})에서 쓰고 있습니다`);
      const clash = (c.problems || []).some((x) => x && x.id === ps.id) || c.passages.some((x, i) => x && x.id === ps.id && i !== idx);
      if (clash) rep.err(ps.id, 'id', `id "${ps.id}" 는 이 과목에서 이미 쓰고 있습니다`);
      if (rep.errors.length) throw validationError(rep.errors, rep.warnings);
      if (oldId) for (const x of c.problems) if (x && x.passageId === oldId) x.passageId = ps.id;
      if (idx >= 0) c.passages[idx] = ps; else c.passages.push(ps);
      draft.courses.set(cid, normalizeCourse(c, false));
      return { created: idx < 0, renamedFrom: oldId || undefined, warnings: rep.warnings };
    });
    const e = store.getCourse(cid);
    log(`[출제] 지문 ${result.created ? '추가' : '저장'}: ${cid}/${ps.id}`);
    sendJson(res, result.created ? 201 : 200, Object.assign({ ok: true, passage: ps, version: e.version }, result));
  }

  async function deletePassage(res, cid, pid) {
    mustCourse(cid);
    await store.mutate((draft) => {
      const c = draftCourse(draft, cid);
      const list = Array.isArray(c.passages) ? c.passages : [];
      if (!list.some((x) => x && x.id === pid)) throw new HttpError(404, `지문 "${pid}" 가 이 과목에 없습니다`);
      const users = c.problems.filter((x) => x && x.passageId === pid).map((x) => x.id);
      if (users.length) throw new HttpError(400, `이 지문을 쓰는 문항 ${users.length}개가 있습니다: ${users.join(', ')} — 문항에서 지문 연결을 먼저 해제하세요`, { problems: users });
      c.passages = list.filter((x) => !(x && x.id === pid));
      if (!c.passages.length) delete c.passages;
    });
    const e = store.getCourse(cid);
    log(`[출제] 지문 삭제: ${cid}/${pid}`);
    sendJson(res, 200, { ok: true, id: pid, version: e.version });
  }

  async function putWorkbooks(req, res) {
    const body = await readBody(req);
    const list = Array.isArray(body) ? body : body && Array.isArray(body.workbooks) ? body.workbooks : null;
    if (!list) throw new HttpError(400, '{ "workbooks": [ … ] } 형태로 보내세요');
    const normalized = list.map(normalizeWorkbook);
    const result = await store.mutate((draft) => {
      const rep = wbIssues(store, draft.courses, normalized);
      if (rep.errors.length) throw validationError(rep.errors, rep.warnings);
      draft.workbooks = normalized;
      return { warnings: rep.warnings };
    });
    const wb = store.workbooks();
    log(`[출제] 문제집 저장: ${wb.data.workbooks.length}개`);
    sendJson(res, 200, Object.assign({ ok: true, version: wb.version, count: wb.data.workbooks.length, workbooks: wb.data.workbooks }, result));
  }

  async function importContent(req, res) {
    const body = await readBody(req);
    if (!body || typeof body !== 'object') throw new HttpError(400, '가져올 JSON 을 보내세요');
    let courses = [];
    let workbooks = null;
    if (Array.isArray(body)) courses = body;
    else if (Array.isArray(body.courses) || (Array.isArray(body.workbooks) && !body.subjectId)) {
      courses = Array.isArray(body.courses) ? body.courses : [];
      workbooks = Array.isArray(body.workbooks) ? body.workbooks : null;
    } else if (body.subjectId || Array.isArray(body.problems)) courses = [body];
    else throw new HttpError(400, '과목 JSON({ subjectId, problems … }) 또는 문제집 JSON({ workbooks: [ … ] })이 아닙니다');

    const result = await store.mutate((draft) => {
      const summary = { courses: [], workbooks: null };
      const touched = [];
      const errors = [];
      for (const raw of courses) {
        if (!raw || typeof raw !== 'object' || !raw.subjectId) {
          errors.push({ where: '(가져오기)', field: 'subjectId', message: '과목 id(subjectId)가 없는 과목이 있습니다' });
          continue;
        }
        const cid = String(raw.subjectId).trim();
        const incoming = normalizeCourse(raw);
        const existing = draft.courses.get(cid);
        let c;
        let added = 0;
        let updated = 0;
        if (!existing) {
          c = incoming;
          if (!Array.isArray(c.problems)) c.problems = [];
          added = c.problems.length;
        } else {
          c = Object.assign({}, existing);
          for (const k of Object.keys(incoming)) if (k !== 'problems' && k !== 'passages') c[k] = incoming[k];
          if (Array.isArray(incoming.passages)) {
            const ps = Array.isArray(c.passages) ? c.passages.slice() : [];
            for (const x of incoming.passages) {
              const i = ps.findIndex((y) => y && x && y.id === x.id);
              if (i >= 0) ps[i] = x; else ps.push(x);
            }
            c.passages = ps;
          }
          const probs = Array.isArray(c.problems) ? c.problems.slice() : [];
          for (const x of incoming.problems || []) {
            const i = probs.findIndex((y) => y && x && y.id === x.id);
            if (i >= 0) { probs[i] = x; updated++; } else { probs.push(x); added++; }
          }
          c.problems = probs;
          c = normalizeCourse(c, false);
        }
        draft.courses.set(cid, c);
        touched.push(cid);
        summary.courses.push({ id: cid, created: !existing, added, updated, total: c.problems.length });
      }
      const warnings = [];
      for (const cid of touched) {
        const rep = Schema.validateCourse(draft.courses.get(cid), { foreignIds: store.foreignIds(cid, draft.courses) });
        errors.push(...rep.errors);
        warnings.push(...rep.warnings);
      }
      if (workbooks) {
        const list = draft.workbooks.slice();
        let added = 0;
        let updated = 0;
        for (const raw of workbooks) {
          const w = normalizeWorkbook(raw);
          const i = list.findIndex((y) => y && w && y.id === w.id);
          if (i >= 0) { list[i] = w; updated++; } else { list.push(w); added++; }
        }
        draft.workbooks = list;
        summary.workbooks = { added, updated, total: list.length };
      }
      const wbBefore = wbIssues(store, new Map(Array.from(store.courses, ([k, v]) => [k, v.data])), store.workbooks().data.workbooks);
      const wbAfter = wbIssues(store, draft.courses, draft.workbooks);
      errors.push(...newIssues(wbBefore.errors, wbAfter.errors));
      if (errors.length) throw validationError(errors, warnings);
      summary.warnings = warnings;
      return summary;
    });
    log(`[출제] 가져오기: 과목 ${result.courses.map((c) => c.id).join(', ') || '-'}${result.workbooks ? `, 문제집 ${result.workbooks.total}개` : ''}`);
    sendJson(res, 200, Object.assign({ ok: true }, result));
  }

  /** @returns {boolean} 처리했으면 true */
  function handle(req, res, url) {
    const p = url.pathname;
    const isPublic = p.startsWith('/api/content/');
    const isAdmin = p === '/api/admin' || p.startsWith('/api/admin/');
    if (!isPublic && !isAdmin) return false;
    if (req.method === 'OPTIONS') { res.writeHead(204, CORS).end(); return true; }
    const parts = p.split('/').slice(3).filter(Boolean).map((s) => { try { return decodeURIComponent(s); } catch (_) { return s; } });
    const fail = (e) => {
      if (e instanceof HttpError) {
        sendJson(res, e.status, Object.assign({ ok: false, error: e.message }, e.extra));
      } else {
        log(`콘텐츠 API 오류: ${e && e.stack ? e.stack : e}`);
        sendJson(res, 500, { ok: false, error: `서버 오류: ${e && e.message}` });
      }
    };
    try {
      if (isPublic) { handlePublic(req, res, parts); return true; }
      checkKey(req, url);
      Promise.resolve(handleAdmin(req, res, parts, url)).catch(fail);
    } catch (e) {
      fail(e);
    }
    return true;
  }

  return { handle, index };
}

module.exports = { createContentApi, normalizeProblem, normalizeCourse };
