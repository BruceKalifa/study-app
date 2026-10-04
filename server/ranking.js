'use strict';
/**
 * 공부시간 순위 API (문서: docs/community-api.md — "공부시간 순위")
 *
 *    POST /api/ranking/report   { userId, name, grade, day, studyMs, solved }
 *    GET  /api/ranking?period=day|week&day=YYYY-MM-DD&grade=&me=
 *
 * 개인정보 보호:
 *  - 이름은 저장할 때 가린다: 첫 글자 + "XX" (오예진 → 오XX, Kim → KXX, 빈 이름 → 익명). 전체 이름은 저장하지 않는다.
 *  - userId 는 저장만 하고 응답에는 내보내지 않는다 (내 순위는 me 로만).
 * 저장: DATA_DIR/ranking.json  { version, days: { "YYYY-MM-DD": { userId: { name, grade, studyMs, solved, at } } } }
 * 90일 지난 날짜는 정리한다.
 */

const path = require('path');
const { JsonStore } = require('./json-store');
const { CORS, HttpError, sendJson, sendError, readJson, pathParts, firstGrapheme, GRADES } = require('./http-util');

const DAY_MS = 86400000;
const MAX_STUDY_MS = 24 * 3600 * 1000;
const MAX_SOLVED = 100000;
const KEEP_DAYS = 90;
const TOP_N = 50;
const MAX_BODY_BYTES = 16 * 1024;
const DAY_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

/** 이름 가리기: 첫 글자(자소 결합·이모지도 한 글자) + XX, 비었으면 익명 */
function maskName(name) {
  const s = typeof name === 'string' ? name.replace(/[\u0000-\u001F\u007F\u200B]/g, '').trim() : ''; // eslint-disable-line no-control-regex
  const first = firstGrapheme(s);
  return first ? first + 'XX' : '익명';
}

// ── 날짜 (서버 현지 시각 기준) ──
function pad(n) { return String(n).padStart(2, '0'); }
function dayKey(d) { return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; }
function today() { return dayKey(new Date()); }
/** "YYYY-MM-DD" → 그 날 정오(현지)의 Date. 잘못된 날짜면 null */
function parseDay(s) {
  const m = DAY_RE.exec(s || '');
  if (!m) return null;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 12);
  return dayKey(d) === s ? d : null;
}
function addDays(s, n) {
  const d = parseDay(s);
  d.setDate(d.getDate() + n);
  return dayKey(d);
}

function createRankingApi({ dataDir, log }) {
  log = log || ((m) => console.warn(m));
  const store = new JsonStore({
    file: path.join(dataDir, 'ranking.json'),
    empty: () => ({ version: 1, days: {} }),
    log,
  }).load();
  if (!store.data.days || typeof store.data.days !== 'object' || Array.isArray(store.data.days)) store.data.days = {};
  const days = () => store.data.days;

  /** KEEP_DAYS 보다 오래된 날짜 지우기. 지운 게 있으면 true */
  function prune() {
    const oldest = addDays(today(), -(KEEP_DAYS - 1));
    let changed = false;
    for (const k of Object.keys(days())) {
      if (!parseDay(k) || k < oldest) { delete days()[k]; changed = true; }
    }
    return changed;
  }
  if (prune()) store.save().catch(() => {});

  async function report(req) {
    const b = await readJson(req, MAX_BODY_BYTES);
    const userId = typeof b.userId === 'string' ? b.userId.trim() : '';
    if (!userId) throw new HttpError(400, 'userId 가 필요합니다');
    if (userId.length > 100) throw new HttpError(400, 'userId 가 너무 깁니다');
    const day = b.day == null || b.day === '' ? today() : String(b.day);
    if (!parseDay(day)) throw new HttpError(400, '날짜(day)는 YYYY-MM-DD 형식이어야 합니다');
    const now = today();
    if (day > addDays(now, 1)) throw new HttpError(400, '미래 날짜는 보고할 수 없습니다');
    if (day < addDays(now, -(KEEP_DAYS - 1))) throw new HttpError(400, `${KEEP_DAYS}일보다 오래된 기록은 받지 않습니다`);
    const grade = typeof b.grade === 'string' ? b.grade.trim() : '';
    if (grade && !GRADES.includes(grade)) throw new HttpError(400, '학년은 고1·고2·고3·N수 중 하나이거나 비워 두어야 합니다');
    let studyMs = Number(b.studyMs);
    if (!Number.isFinite(studyMs)) studyMs = 0;
    studyMs = Math.round(Math.min(MAX_STUDY_MS, Math.max(0, studyMs)));
    let solved = Number(b.solved);
    if (!Number.isFinite(solved)) solved = 0;
    solved = Math.round(Math.min(MAX_SOLVED, Math.max(0, solved)));

    const rec = { name: maskName(b.name), grade, studyMs, solved, at: Date.now() };
    if (!days()[day]) days()[day] = {};
    days()[day][userId] = rec; // 같은 userId·day 는 덮어쓴다
    prune();
    try { await store.save(); } catch (_) { throw new HttpError(500, '저장하지 못했습니다. 잠시 뒤 다시 시도하세요.'); }
    return { ok: true, day, name: rec.name, grade, studyMs, solved };
  }

  function query(url) {
    const sp = url.searchParams;
    const period = (sp.get('period') || 'day').trim();
    if (period !== 'day' && period !== 'week') throw new HttpError(400, 'period 는 day 또는 week 이어야 합니다');
    const day = (sp.get('day') || '').trim() || today();
    if (!parseDay(day)) throw new HttpError(400, '날짜(day)는 YYYY-MM-DD 형식이어야 합니다');
    const grade = (sp.get('grade') || '').trim();
    if (grade && !GRADES.includes(grade)) throw new HttpError(400, '학년은 고1·고2·고3·N수 중 하나여야 합니다');
    const me = (sp.get('me') || '').trim();

    const span = period === 'week' ? 7 : 1;
    const from = addDays(day, -(span - 1));
    // userId → 합계 (이름·학년은 가장 최근 날의 값)
    const agg = new Map();
    for (let i = 0; i < span; i++) {
      const k = addDays(from, i);
      const recs = days()[k];
      if (!recs) continue;
      for (const uid of Object.keys(recs)) {
        const r = recs[uid];
        const a = agg.get(uid) || { name: r.name, grade: r.grade || '', studyMs: 0, solved: 0, at: 0 };
        a.studyMs += Number(r.studyMs) || 0;
        a.solved += Number(r.solved) || 0;
        a.name = r.name; // 날짜 순으로 돌므로 마지막 = 가장 최근
        a.grade = r.grade || '';
        a.at = Math.max(a.at, Number(r.at) || 0);
        agg.set(uid, a);
      }
    }
    let list = Array.from(agg, ([uid, a]) => Object.assign({ uid }, a));
    if (grade) list = list.filter((x) => x.grade === grade);
    list.sort((x, y) => y.studyMs - x.studyMs || y.solved - x.solved || x.at - y.at);

    const entries = list.slice(0, TOP_N).map((x, i) => ({
      rank: i + 1, name: x.name, grade: x.grade, studyMs: x.studyMs, solved: x.solved, me: !!me && x.uid === me,
    }));
    let mine = null;
    if (me) {
      const i = list.findIndex((x) => x.uid === me);
      if (i >= 0) mine = { rank: i + 1, studyMs: list[i].studyMs, solved: list[i].solved };
    }
    const out = { period, day };
    if (period === 'week') out.from = from;
    return Object.assign(out, { total: list.length, entries, me: mine });
  }

  /** @returns {boolean} 처리했으면 true */
  function handle(req, res, url) {
    const p = url.pathname;
    if (p !== '/api/ranking' && !p.startsWith('/api/ranking/')) return false;
    if (req.method === 'OPTIONS') { res.writeHead(204, CORS).end(); return true; }
    const parts = pathParts(p).slice(2);
    const fail = (e) => sendError(res, e, log);
    const run = async () => {
      if (parts.length === 0 && req.method === 'GET') return sendJson(res, 200, query(url));
      if (parts.length === 1 && parts[0] === 'report' && req.method === 'POST') return sendJson(res, 200, await report(req));
      throw new HttpError(404, '없는 주소이거나 지원하지 않는 방식입니다');
    };
    run().catch(fail);
    return true;
  }

  return { handle, store, saveSync: () => store.saveSync() };
}

module.exports = { createRankingApi, maskName };
