'use strict';
/**
 * 풀이노트 실시간 필기 공유 서버
 *
 *  - 학생 앱(Flutter)  ⇄  ws://<서버>:8080/ws?role=student
 *  - 선생님 웹          ⇄  ws://<서버>:8080/ws?role=teacher   (http://<서버>:8080/ 에서 제공)
 *
 * 프로토콜: docs/live-protocol.md (필드 이름은 바꾸지 않고, 필요한 필드만 추가한다)
 */

const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { WebSocketServer, WebSocket } = require('ws');
const { ContentStore } = require('./content-store');
const { createContentApi } = require('./content-api');
const { createCommunityApi } = require('./community');
const { createRankingApi } = require('./ranking');
const { createAccountsApi } = require('./accounts');
const { createQuestionsApi } = require('./questions');
const { createBooksApi } = require('./books');

// ───────────────────────── 설정 ─────────────────────────
const PORT = Number(process.env.PORT) || 8080;
const HOST = process.env.HOST || '0.0.0.0';
const PUBLIC_DIR = path.join(__dirname, 'public');
const DATA_DIR = process.env.DATA_DIR ? path.resolve(process.env.DATA_DIR) : path.join(__dirname, 'data');
const RECORDS_FILE = path.join(DATA_DIR, 'records.json');
// 문제 콘텐츠(과목별 JSON + workbooks.json). 비어 있으면 SEED_DIR(기본: 앱의 assets/problems)에서 복사
const CONTENT_DIR = process.env.CONTENT_DIR ? path.resolve(process.env.CONTENT_DIR) : path.join(__dirname, 'content');
const SEED_DIR = process.env.SEED_DIR ? path.resolve(process.env.SEED_DIR) : path.join(__dirname, '..', 'assets', 'problems');

const MAX_MESSAGE_BYTES = 2 * 1024 * 1024; // 메시지 1개 최대 2MB
const MAX_STROKES_PER_PAGE = 5000; // 페이지당 최근 5000획만 유지
const MAX_POINTS_PER_STROKE = 20000; // 획 하나의 최대 점 수
const MAX_HISTORY = 200; // 학생별 최근 제출 200개
const MAX_TEXT = 500; // 선생님 메시지 최대 글자 수
const SAVE_DEBOUNCE_MS = 1000;
const HEARTBEAT_MS = 30000;
const TEACHER_MAX_BUFFER = 16 * 1024 * 1024; // 느린 선생님 소켓은 끊고 재접속 시 snapshot 으로 복구

// ───────────────────────── 상태 ─────────────────────────
/** @type {Map<string, Student>} */
const students = new Map();
/** @type {Set<WebSocket>} */
const teachers = new Set();

/**
 * @typedef {Object} Student
 * @property {string} studentId
 * @property {string} name
 * @property {string} device
 * @property {boolean} online
 * @property {WebSocket|null} socket
 * @property {Object|null} page
 * @property {Map<string, Object>} strokes  현재 페이지 획 (메모리에만)
 * @property {Object|null} lastAnswer
 * @property {Object|null} stats
 * @property {Object[]} history  최근 제출 (최신이 앞)
 * @property {number|null} lastSeen
 */

function getOrCreateStudent(studentId) {
  let s = students.get(studentId);
  if (!s) {
    s = {
      studentId,
      name: studentId,
      device: '',
      online: false,
      socket: null,
      page: null,
      strokes: new Map(),
      lastAnswer: null,
      stats: null,
      history: [],
      lastSeen: null,
    };
    students.set(studentId, s);
  }
  return s;
}

function publicStudent(s) {
  return {
    studentId: s.studentId,
    name: s.name,
    device: s.device,
    online: s.online,
    page: s.page,
    strokes: Array.from(s.strokes.values()),
    lastAnswer: s.lastAnswer,
    stats: s.stats,
    history: s.history,
    lastSeen: s.lastSeen,
  };
}

// ───────────────────────── 저장 (records.json) ─────────────────────────
let saveTimer = null;
let saving = false;
let saveAgain = false;

function recordsPayload() {
  const out = {};
  for (const s of students.values()) {
    out[s.studentId] = {
      studentId: s.studentId,
      name: s.name,
      device: s.device,
      lastAnswer: s.lastAnswer,
      stats: s.stats,
      history: s.history,
      lastSeen: s.lastSeen,
    };
  }
  return JSON.stringify({ version: 1, savedAt: Date.now(), students: out }, null, 1);
}

function loadRecords() {
  try {
    const raw = fs.readFileSync(RECORDS_FILE, 'utf8');
    const data = JSON.parse(raw);
    const list = data && data.students ? Object.values(data.students) : [];
    for (const r of list) {
      if (!r || typeof r.studentId !== 'string') continue;
      const s = getOrCreateStudent(r.studentId);
      s.name = str(r.name, 40) || s.studentId;
      s.device = str(r.device, 80);
      s.lastAnswer = r.lastAnswer || null;
      s.stats = r.stats || null;
      s.history = Array.isArray(r.history) ? r.history.slice(0, MAX_HISTORY) : [];
      s.lastSeen = typeof r.lastSeen === 'number' ? r.lastSeen : null;
    }
    console.log(`기록 불러옴: 학생 ${list.length}명 (${RECORDS_FILE})`);
  } catch (e) {
    if (e.code !== 'ENOENT') {
      // 깨진 파일은 덮어쓰기 전에 보관해 둔다
      const bad = RECORDS_FILE + '.broken-' + Date.now();
      try { fs.renameSync(RECORDS_FILE, bad); } catch (_) { /* ignore */ }
      console.warn(`records.json 을 읽지 못해 ${path.basename(bad)} 로 옮겼습니다:`, e.message);
    }
  }
}

function scheduleSave() {
  if (saveTimer) return;
  saveTimer = setTimeout(() => {
    saveTimer = null;
    saveNow();
  }, SAVE_DEBOUNCE_MS);
}

function saveNow() {
  if (saving) { saveAgain = true; return; }
  saving = true;
  const body = recordsPayload();
  const tmp = RECORDS_FILE + '.tmp';
  fs.promises.mkdir(DATA_DIR, { recursive: true })
    .then(() => fs.promises.writeFile(tmp, body, 'utf8'))
    .then(() => fs.promises.rename(tmp, RECORDS_FILE))
    .catch((e) => console.error('기록 저장 실패:', e.message))
    .finally(() => {
      saving = false;
      if (saveAgain) { saveAgain = false; saveNow(); }
    });
}

function saveSync() {
  if (saveTimer) { clearTimeout(saveTimer); saveTimer = null; }
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    fs.writeFileSync(RECORDS_FILE + '.tmp', recordsPayload(), 'utf8');
    fs.renameSync(RECORDS_FILE + '.tmp', RECORDS_FILE);
  } catch (e) {
    console.error('기록 저장 실패:', e.message);
  }
}

// ───────────────────────── 값 정리 도우미 ─────────────────────────
function str(v, max = 200) {
  if (typeof v !== 'string') return v == null ? '' : String(v).slice(0, max);
  return v.slice(0, max);
}
function num(v, def = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : def;
}
function round3(n) {
  return Math.round(n * 1000) / 1000;
}
/** [[x,y,p], ...] 만 남긴다 */
function cleanPoints(points, limit = MAX_POINTS_PER_STROKE) {
  if (!Array.isArray(points)) return [];
  const out = [];
  for (let i = 0; i < points.length && out.length < limit; i++) {
    const pt = points[i];
    if (!Array.isArray(pt) || pt.length < 2) continue;
    const x = Number(pt[0]);
    const y = Number(pt[1]);
    if (!Number.isFinite(x) || !Number.isFinite(y)) continue;
    let p = pt.length > 2 ? Number(pt[2]) : 0.5;
    if (!Number.isFinite(p)) p = 0.5;
    out.push([round3(x), round3(y), round3(Math.min(1, Math.max(0, p)))]);
  }
  return out;
}
const COLOR_RE = /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/;
function cleanStroke(m) {
  if (!m || (typeof m.id !== 'string' && typeof m.id !== 'number')) return null;
  return {
    id: String(m.id).slice(0, 80),
    tool: m.tool === 'highlighter' ? 'highlighter' : 'pen',
    color: typeof m.color === 'string' && COLOR_RE.test(m.color) ? m.color : '#1C2430',
    width: Math.min(200, Math.max(0.1, num(m.width, 3))),
    points: cleanPoints(m.points),
  };
}
function addStroke(s, stroke) {
  if (s.strokes.has(stroke.id)) s.strokes.delete(stroke.id); // 같은 id 는 새 획으로 교체(순서도 맨 뒤로)
  s.strokes.set(stroke.id, stroke);
  while (s.strokes.size > MAX_STROKES_PER_PAGE) {
    s.strokes.delete(s.strokes.keys().next().value);
  }
}

// ───────────────────────── 전송 도우미 ─────────────────────────
function send(ws, obj) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(typeof obj === 'string' ? obj : JSON.stringify(obj));
  }
}
function toTeachers(obj) {
  if (teachers.size === 0) return;
  const data = JSON.stringify(obj);
  for (const t of teachers) {
    if (t.readyState !== WebSocket.OPEN) continue;
    if (t.bufferedAmount > TEACHER_MAX_BUFFER) {
      // 너무 밀리면 끊는다 → 선생님 웹이 다시 접속해 snapshot 으로 따라잡는다
      t.terminate();
      continue;
    }
    t.send(data);
  }
}

// ───────────────────────── 학생 메시지 처리 ─────────────────────────
function handleStudent(ws, msg) {
  const type = msg.type;

  if (type === 'ping') {
    send(ws, { type: 'pong', t: Date.now() });
    return;
  }

  if (type === 'hello') {
    const studentId = str(msg.studentId, 80).trim();
    if (!studentId) {
      send(ws, { type: 'error', reason: 'studentId_required' });
      return;
    }
    // 이 소켓이 다른 학생으로 hello 했었다면 이전 학생은 오프라인 처리
    if (ws.studentId && ws.studentId !== studentId) detachStudent(ws);

    const s = getOrCreateStudent(studentId);
    if (s.socket && s.socket !== ws) {
      // 같은 학생이 다시 접속 → 예전 소켓을 대체 (예전 소켓 close 는 offline 을 보내지 않는다)
      const old = s.socket;
      old.replaced = true;
      try { old.close(4000, 'replaced'); } catch (_) { /* ignore */ }
      setTimeout(() => { if (old.readyState !== WebSocket.CLOSED) old.terminate(); }, 2000);
    }
    s.socket = ws;
    s.online = true;
    s.lastSeen = Date.now();
    s.name = str(msg.name, 40).trim() || s.name || studentId;
    s.device = str(msg.device, 80);
    ws.studentId = studentId;
    scheduleSave();

    console.log(`학생 접속: ${s.name} (${studentId}${s.device ? ', ' + s.device : ''})`);
    send(ws, { type: 'welcome', studentId, serverTime: Date.now() });
    toTeachers({ type: 'student_online', studentId, name: s.name, device: s.device });
    toTeachers({ type: 'hello', studentId, name: s.name, device: s.device });
    return;
  }

  const s = ws.studentId ? students.get(ws.studentId) : null;
  if (!s) {
    send(ws, { type: 'error', reason: 'hello_required' });
    return;
  }
  s.lastSeen = Date.now();
  const studentId = s.studentId;

  switch (type) {
    case 'page': {
      const page = {
        problemId: str(msg.problemId, 120),
        title: str(msg.title, 200),
        stem: str(msg.stem, 20000),
        choices: Array.isArray(msg.choices) ? msg.choices.slice(0, 10).map((c) => str(c, 2000)) : null,
        pageHeight: Math.min(20000, Math.max(100, num(msg.pageHeight, 1400))),
      };
      // 추가(선택) 필드: 문제 메타 정보 — 앱이 보내면 대시보드가 표시한다
      if (Array.isArray(msg.boxItems)) page.boxItems = msg.boxItems.slice(0, 10).map((c) => str(c, 2000));
      if (msg.topic != null) page.topic = str(msg.topic, 120);
      if (msg.unit != null) page.unit = str(msg.unit, 120);
      if (msg.subject != null) page.subject = str(msg.subject, 60);
      page.at = Date.now();
      s.page = page;
      s.strokes = new Map();
      toTeachers({ type: 'page', studentId, ...page });
      return;
    }
    case 'stroke_begin': {
      const stroke = cleanStroke(msg);
      if (!stroke) return;
      addStroke(s, stroke);
      toTeachers({ type: 'stroke_begin', studentId, ...stroke });
      return;
    }
    case 'stroke_points': {
      const id = msg.id == null ? '' : String(msg.id).slice(0, 80);
      const stroke = s.strokes.get(id);
      let points;
      if (stroke) {
        const room = MAX_POINTS_PER_STROKE - stroke.points.length;
        if (room <= 0) return;
        points = cleanPoints(msg.points, room);
        for (const p of points) stroke.points.push(p);
      } else {
        points = cleanPoints(msg.points);
      }
      if (points.length === 0) return;
      toTeachers({ type: 'stroke_points', studentId, id, points });
      return;
    }
    case 'stroke_end': {
      const id = msg.id == null ? '' : String(msg.id).slice(0, 80);
      const stroke = s.strokes.get(id);
      if (stroke) stroke.done = true;
      toTeachers({ type: 'stroke_end', studentId, id });
      return;
    }
    case 'erase': {
      const ids = Array.isArray(msg.ids) ? msg.ids.map((x) => String(x).slice(0, 80)) : [];
      for (const id of ids) s.strokes.delete(id);
      toTeachers({ type: 'erase', studentId, ids });
      return;
    }
    case 'restore': {
      const list = Array.isArray(msg.strokes) ? msg.strokes : [];
      s.strokes = new Map();
      for (const raw of list) {
        const st = cleanStroke(raw);
        if (st) { st.done = true; addStroke(s, st); }
      }
      toTeachers({ type: 'restore', studentId, strokes: Array.from(s.strokes.values()) });
      return;
    }
    case 'clear': {
      s.strokes = new Map();
      toTeachers({ type: 'clear', studentId });
      return;
    }
    case 'answer': {
      const entry = {
        problemId: str(msg.problemId, 120),
        answer: str(msg.answer, 200),
        correct: msg.correct === true,
        timeMs: Math.max(0, Math.round(num(msg.timeMs, 0))),
        at: Date.now(), // 추가: 서버 수신 시각(ms)
      };
      // 추가: 지금 보고 있는 페이지와 같은 문제면 제목/단원을 함께 기록
      if (s.page && s.page.problemId === entry.problemId) {
        if (s.page.title) entry.title = s.page.title;
        if (s.page.topic) entry.topic = s.page.topic;
      } else if (msg.title != null) {
        entry.title = str(msg.title, 200);
      }
      if (msg.topic != null) entry.topic = str(msg.topic, 120);
      s.lastAnswer = entry;
      s.history.unshift(entry);
      if (s.history.length > MAX_HISTORY) s.history.length = MAX_HISTORY;
      scheduleSave();
      toTeachers({ type: 'answer', studentId, ...entry });
      return;
    }
    case 'stats': {
      const stats = {
        total: Math.max(0, Math.round(num(msg.total))),
        correct: Math.max(0, Math.round(num(msg.correct))),
        streak: Math.max(0, Math.round(num(msg.streak))),
        todayCount: Math.max(0, Math.round(num(msg.todayCount))),
        weakTopics: Array.isArray(msg.weakTopics) ? msg.weakTopics.slice(0, 10).map((t) => str(t, 60)) : [],
        at: Date.now(), // 추가: 받은 시각 (todayCount 가 오늘 값인지 판단용)
      };
      s.stats = stats;
      scheduleSave();
      toTeachers({ type: 'stats', studentId, ...stats });
      return;
    }
    default:
      // 모르는 type 도 그대로 중계 (앱이 새 메시지를 추가해도 서버를 고치지 않아도 되도록)
      if (typeof type === 'string' && type.length <= 40) {
        toTeachers({ ...msg, studentId });
      } else {
        send(ws, { type: 'error', reason: 'unknown_type' });
      }
  }
}

function detachStudent(ws) {
  const id = ws.studentId;
  if (!id) return;
  const s = students.get(id);
  ws.studentId = null;
  if (!s || s.socket !== ws) return; // 이미 새 소켓으로 대체됨
  s.socket = null;
  s.online = false;
  s.lastSeen = Date.now();
  scheduleSave();
  toTeachers({ type: 'student_offline', studentId: id, name: s.name });
}

// ───────────────────────── 선생님 메시지 처리 ─────────────────────────
function handleTeacher(ws, msg) {
  switch (msg.type) {
    case 'ping':
      send(ws, { type: 'pong', t: Date.now() });
      return;
    case 'message': {
      const text = str(msg.text, MAX_TEXT).trim();
      if (!text) {
        send(ws, { type: 'message_ack', ok: false, reason: 'empty_text', clientId: msg.clientId });
        return;
      }
      const target = msg.studentId ? String(msg.studentId) : null;
      const out = JSON.stringify({ type: 'message', text, from: str(msg.from, 40) || '선생님', at: Date.now() });
      let delivered = 0;
      if (target) {
        const s = students.get(target);
        if (s && s.socket && s.socket.readyState === WebSocket.OPEN) { s.socket.send(out); delivered = 1; }
      } else {
        for (const s of students.values()) {
          if (s.socket && s.socket.readyState === WebSocket.OPEN) { s.socket.send(out); delivered++; }
        }
      }
      // 추가: 전달 결과 알림 (선생님 화면 토스트용)
      send(ws, { type: 'message_ack', ok: delivered > 0, studentId: target, delivered, text, clientId: msg.clientId });
      return;
    }
    case 'snapshot_request': // 추가: 선생님 웹이 전체 상태를 다시 요청
      sendSnapshot(ws);
      return;
    default:
      send(ws, { type: 'error', reason: 'unknown_type' });
  }
}

function sendSnapshot(ws) {
  const list = Array.from(students.values()).map(publicStudent);
  send(ws, { type: 'snapshot', students: list, serverTime: Date.now() });
}

// ───────────────────────── 문제 콘텐츠 + 관리자 키 ─────────────────────────
/** ADMIN_KEY 환경변수 → data/admin-key.txt → 새로 만든 6자리 숫자(파일에 저장해 다음에도 같은 키) */
function loadAdminKey() {
  const env = (process.env.ADMIN_KEY || '').trim();
  if (env) return { key: env, source: 'env' };
  const file = path.join(DATA_DIR, 'admin-key.txt');
  try {
    const k = fs.readFileSync(file, 'utf8').trim();
    if (/^\S{4,}$/.test(k)) return { key: k, source: 'file', file };
  } catch (_) { /* 처음 */ }
  const key = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    fs.writeFileSync(file, key + '\n', { mode: 0o600 });
  } catch (e) {
    console.warn('관리자 키를 파일에 저장하지 못했습니다(이번 실행에서만 유효):', e.message);
  }
  return { key, source: 'new', file };
}
const ADMIN = loadAdminKey();
const contentStore = new ContentStore({ dir: CONTENT_DIR, seedDir: SEED_DIR }).init();
const contentApi = createContentApi({ store: contentStore, adminKey: ADMIN.key });
// 커뮤니티 게시판 + 공부시간 순위 (docs/community-api.md) — DATA_DIR/community.json, ranking.json
const communityApi = createCommunityApi({ dataDir: DATA_DIR, checkKey: contentApi.checkKey });
const rankingApi = createRankingApi({ dataDir: DATA_DIR });
// 학생·선생님 계정, 풀이 기록, 1:1 질문 (docs/accounts-api.md) — DATA_DIR/accounts.json, study.json, questions.json
// 처음 켤 때 넣는 계정: server/seed/accounts.json (SEED_ACCOUNTS 로 바꿀 수 있음, 빈 값이면 넣지 않음)
const SEED_ACCOUNTS = process.env.SEED_ACCOUNTS ?? path.join(__dirname, 'seed', 'accounts.json');
const accountsApi = createAccountsApi({ dataDir: DATA_DIR, seedFile: SEED_ACCOUNTS || null });
const questionsApi = createQuestionsApi({ dataDir: DATA_DIR, accounts: accountsApi });
const booksApi = createBooksApi({ dataDir: DATA_DIR, accounts: accountsApi });

// ───────────────────────── HTTP (정적 파일) ─────────────────────────
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
};

function lanAddresses() {
  const out = [];
  const ifs = os.networkInterfaces();
  for (const name of Object.keys(ifs)) {
    for (const a of ifs[name] || []) {
      const v4 = a.family === 'IPv4' || a.family === 4;
      if (v4 && !a.internal) out.push(a.address);
    }
  }
  return out;
}

const server = http.createServer((req, res) => {
  let urlPath;
  let reqUrl;
  try {
    reqUrl = new URL(req.url, 'http://x');
    urlPath = decodeURIComponent(reqUrl.pathname);
  } catch (_) {
    res.writeHead(400).end('Bad Request');
    return;
  }

  // 커뮤니티(/api/community/…, /api/admin/community/…)·순위(/api/ranking…) — /api/admin/ 전체를 받는 콘텐츠 API 보다 먼저
  if (communityApi.handle(req, res, reqUrl)) return;
  if (rankingApi.handle(req, res, reqUrl)) return;
  if (accountsApi.handle(req, res, reqUrl)) return;
  if (questionsApi.handle(req, res, reqUrl)) return;
  // 선생님이 올린 교재 받기 (로그인한 학생만)
  if (booksApi.handle(req, res, reqUrl)) return;
  // 문제 콘텐츠 API (앱 다운로드용 /api/content/…, 출제 웹용 /api/admin/…)
  if (contentApi.handle(req, res, reqUrl)) return;
  if (urlPath === '/admin') {
    res.writeHead(301, { Location: '/admin/' + (reqUrl.search || '') }).end();
    return;
  }

  if (urlPath === '/api/info') {
    // 추가: 선생님 웹 빈 화면에 학생 앱이 입력할 주소를 보여주기 위함
    const ips = lanAddresses();
    const body = JSON.stringify({
      port: PORT,
      wsUrls: ips.map((ip) => `ws://${ip}:${PORT}/ws`),
      teacherUrls: ips.map((ip) => `http://${ip}:${PORT}/`),
      adminUrls: ips.map((ip) => `http://${ip}:${PORT}/admin`), // 추가: 출제 도구 주소
      students: students.size,
      online: Array.from(students.values()).filter((s) => s.online).length,
    });
    res.writeHead(200, { 'Content-Type': MIME['.json'], 'Cache-Control': 'no-store' }).end(body);
    return;
  }
  if (urlPath === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'text/plain' }).end('ok');
    return;
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405).end();
    return;
  }
  if (urlPath.endsWith('/')) urlPath += 'index.html';
  const filePath = path.normalize(path.join(PUBLIC_DIR, urlPath));
  if (!filePath.startsWith(PUBLIC_DIR + path.sep)) {
    res.writeHead(403).end('Forbidden');
    return;
  }
  fs.stat(filePath, (err, st) => {
    if (err || !st.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Not Found');
      return;
    }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(filePath).toLowerCase()] || 'application/octet-stream',
      'Content-Length': st.size,
      'Cache-Control': 'no-cache',
    });
    if (req.method === 'HEAD') { res.end(); return; }
    fs.createReadStream(filePath).pipe(res);
  });
});

// ───────────────────────── WebSocket ─────────────────────────
const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_MESSAGE_BYTES, perMessageDeflate: false });

server.on('upgrade', (req, socket, head) => {
  let url;
  try { url = new URL(req.url, 'http://x'); } catch (_) { socket.destroy(); return; }
  if (url.pathname !== '/ws') {
    socket.write('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
    socket.destroy();
    return;
  }
  const role = url.searchParams.get('role');
  if (role !== 'student' && role !== 'teacher') {
    socket.write('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\nrole=student|teacher required');
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    ws.role = role;
    wss.emit('connection', ws, req);
  });
});

wss.on('connection', (ws, req) => {
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
  ws.on('error', (e) => console.warn(`[${ws.role}] 소켓 오류:`, e.message));

  if (ws.role === 'teacher') {
    teachers.add(ws);
    console.log(`선생님 접속 (${req.socket.remoteAddress}) — 선생님 ${teachers.size}명`);
    sendSnapshot(ws);
  }

  ws.on('message', (data, isBinary) => {
    ws.isAlive = true;
    if (isBinary) { send(ws, { type: 'error', reason: 'text_only' }); return; }
    let msg;
    try {
      msg = JSON.parse(data.toString('utf8'));
    } catch (_) {
      send(ws, { type: 'error', reason: 'bad_json' });
      return;
    }
    if (!msg || typeof msg !== 'object' || Array.isArray(msg) || typeof msg.type !== 'string') {
      send(ws, { type: 'error', reason: 'bad_message' });
      return;
    }
    try {
      if (ws.role === 'student') handleStudent(ws, msg);
      else handleTeacher(ws, msg);
    } catch (e) {
      console.error('메시지 처리 오류:', e);
      send(ws, { type: 'error', reason: 'server_error' });
    }
  });

  ws.on('close', (code) => {
    if (ws.role === 'teacher') {
      teachers.delete(ws);
      console.log(`선생님 나감 — 선생님 ${teachers.size}명`);
    } else if (ws.studentId) {
      const s = students.get(ws.studentId);
      if (!ws.replaced) {
        detachStudent(ws);
        console.log(`학생 나감: ${s ? s.name : ws.studentId} (code ${code})`);
      }
    }
  });
});

// 끊긴 연결 정리 (Wi-Fi 끊김 등으로 close 가 오지 않는 경우)
const heartbeat = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    try { ws.ping(); } catch (_) { /* ignore */ }
  }
}, HEARTBEAT_MS);

// ───────────────────────── 시작/종료 ─────────────────────────
loadRecords();

server.listen(PORT, HOST, () => {
  const ips = lanAddresses();
  const line = '─'.repeat(52);
  console.log(`\n${line}\n 풀이노트 실시간 서버가 켜졌습니다 (포트 ${PORT})\n${line}`);
  if (ips.length === 0) {
    console.log(' 네트워크 주소를 찾지 못했습니다. Wi-Fi 연결을 확인하세요.');
    console.log(` 이 컴퓨터에서 보기: http://localhost:${PORT}/`);
  }
  for (const ip of ips) {
    console.log(` 선생님 화면 주소:   http://${ip}:${PORT}/`);
    console.log(` 문제 출제 도구:     http://${ip}:${PORT}/admin`);
    console.log(` 학생 앱 서버 주소:  ws://${ip}:${PORT}/ws`);
  }
  console.log(` (이 컴퓨터에서는 http://localhost:${PORT}/ , http://localhost:${PORT}/admin 로도 열 수 있습니다)`);
  console.log(` 기록 파일: ${RECORDS_FILE}`);
  console.log(` 문제 폴더: ${CONTENT_DIR}`);
  console.log(line);
  console.log(` ★ 출제 도구 관리자 키:  ${ADMIN.key}`);
  if (ADMIN.source === 'env') console.log('   (ADMIN_KEY 환경변수로 정한 키입니다)');
  else console.log(`   (처음 한 번 만들어 ${ADMIN.file} 에 저장했습니다. 바꾸려면 이 파일을 지우거나 ADMIN_KEY 환경변수를 쓰세요)`);
  console.log('   이 키를 아는 사람은 문제를 고치거나 지울 수 있으니 학생에게 알려 주지 마세요.');
  console.log(`${line}\n 끄려면 Ctrl + C\n`);
});

server.on('error', (e) => {
  if (e.code === 'EADDRINUSE') {
    console.error(`포트 ${PORT} 가 이미 사용 중입니다. 이미 서버가 켜져 있는지 확인하거나 PORT=8081 npm start 처럼 다른 포트를 쓰세요.`);
  } else {
    console.error('서버 오류:', e);
  }
  process.exit(1);
});

let shuttingDown = false;
function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log('\n서버를 끄는 중… 기록을 저장합니다.');
  clearInterval(heartbeat);
  saveSync();
  communityApi.saveSync();
  rankingApi.saveSync();
  accountsApi.saveSync();
  questionsApi.saveSync();
  booksApi.saveSync();
  for (const ws of wss.clients) { try { ws.close(1001, 'server_shutdown'); } catch (_) { /* ignore */ } }
  server.close();
  setTimeout(() => process.exit(0), 300).unref();
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
