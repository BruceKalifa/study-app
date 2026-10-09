'use strict';
/**
 * 계정 · 선생님-학생 연결 · 풀이 기록 API (문서: docs/accounts-api.md)
 *
 *  인증:  Authorization: Bearer <token>   (로그인/가입 응답의 token)
 *
 *    POST   /api/auth/signup         { role: student|teacher, loginId, password, name, grade? }
 *    POST   /api/auth/login          { loginId, password }
 *    POST   /api/auth/logout
 *    GET    /api/me
 *    POST   /api/me                  { name?, grade? }
 *    POST   /api/me/password         { current, next }
 *
 *  학생:
 *    POST   /api/student/teachers    { code }          선생님 초대 코드로 연결
 *    DELETE /api/student/teachers/:teacherId           연결 끊기
 *    POST   /api/student/sync        { attempts?, learner?, wrongNote? }
 *    GET    /api/student/records                       (새 기기에서 기록 되살리기)
 *
 *  선생님:
 *    GET    /api/teacher/students                      연결된 학생 + 요약
 *    GET    /api/teacher/students/:id                  한 학생의 오답 · 과목별 · 최근 풀이 · 내 교재
 *    DELETE /api/teacher/students/:id                  연결 끊기
 *    POST   /api/teacher/invite                        초대 코드 새로 만들기
 *
 * 비밀번호는 scrypt(+salt)로만 저장하고, 토큰은 sha256 해시만 저장한다.
 * 선생님은 자기에게 연결된 학생의 기록만 볼 수 있다.
 * 저장: DATA_DIR/accounts.json (계정·세션), DATA_DIR/study.json (학생별 기록)
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { JsonStore } = require('./json-store');
const { CORS, HttpError, sendJson, sendError, readJson, pathParts, charLen, GRADES } = require('./http-util');

const ROLES = ['student', 'teacher'];
const LOGIN_RE = /^[a-z0-9][a-z0-9._-]{3,19}$/;
const LIMITS = { name: 20, school: 40, password: [6, 100] };
const MAX_BODY_BYTES = 4 * 1024 * 1024; // 기록 동기화 한 번 최대 4MB
const MAX_ATTEMPTS_PER_SYNC = 2000;
const MAX_ATTEMPTS_KEPT = 30000; // 학생 한 명당 보관하는 풀이 수
const MAX_LEARNER_BYTES = 64 * 1024;
const SESSION_DAYS = 180;
const DAY_MS = 86400000;
const TZ_OFFSET_MS = (Number(process.env.TZ_OFFSET_MIN) || 540) * 60000; // 날짜 계산: 한국 시간
const INVITE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 헷갈리는 0/O, 1/I 제외
const CTRL = /[\u0000-\u001F\u007F\u200B\u2028\u2029]/g; // eslint-disable-line no-control-regex

function dayOf(ms) { return new Date(ms + TZ_OFFSET_MS).toISOString().slice(0, 10); }
function sha256(s) { return crypto.createHash('sha256').update(s).digest('hex'); }
function newId(prefix) { return `${prefix}_${Date.now().toString(36)}${crypto.randomBytes(5).toString('hex')}`; }
function randomCode(n = 6) {
  const bytes = crypto.randomBytes(n);
  let s = '';
  for (let i = 0; i < n; i++) s += INVITE_ALPHABET[bytes[i] % INVITE_ALPHABET.length];
  return s;
}
function scrypt(password, salt) {
  return new Promise((resolve, reject) => {
    crypto.scrypt(password, salt, 32, { N: 16384, r: 8, p: 1 }, (e, key) => (e ? reject(e) : resolve(key.toString('hex'))));
  });
}
function lineText(v) { return typeof v === 'string' ? v.replace(CTRL, ' ').replace(/\s+/g, ' ').trim() : ''; }
function s(v, max) { return typeof v === 'string' ? v.slice(0, max) : v == null ? '' : String(v).slice(0, max); }
function n(v, def = 0) { const x = Number(v); return Number.isFinite(x) ? x : def; }

function needName(v) {
  const t = lineText(v);
  if (charLen(t) < 1) throw new HttpError(400, '이름을 입력하세요');
  if (charLen(t) > LIMITS.name) throw new HttpError(400, `이름은 ${LIMITS.name}자까지 쓸 수 있습니다`);
  return t;
}
function needGrade(v) {
  const g = typeof v === 'string' ? v.trim() : '';
  if (g === '') return '';
  if (!GRADES.includes(g)) throw new HttpError(400, '학년은 고1·고2·고3·N수·취준·한양대·편입 중에서 골라야 합니다');
  return g;
}
/** 학년·과정 여러 개 (복수 선택). 첫 번째가 대표 학년이다. 옛 앱은 `grade` 하나만 보낸다. */
function needGrades(list, single) {
  const raw = Array.isArray(list) ? list : (single !== undefined && single !== null ? [single] : []);
  if (raw.length > 12) throw new HttpError(400, '학년을 너무 많이 골랐습니다');
  const out = [];
  for (const x of raw) {
    const g = needGrade(x);
    if (g && !out.includes(g)) out.push(g);
  }
  return out;
}
function gradesOf(u) {
  if (Array.isArray(u.grades) && u.grades.length) return u.grades.filter((g) => GRADES.includes(g));
  return u.grade ? [u.grade] : [];
}
function needPassword(v, label = '비밀번호') {
  const p = typeof v === 'string' ? v : '';
  const [min, max] = LIMITS.password;
  if (p.length < min) throw new HttpError(400, `${label}는 ${min}자 이상이어야 합니다`);
  if (p.length > max) throw new HttpError(400, `${label}가 너무 깁니다`);
  return p;
}
function normLoginId(v) { return typeof v === 'string' ? v.trim().toLowerCase() : ''; }

/** 앱이 보낸 풀이 한 개 → 저장할 모양 (잘못된 것은 null) */
function cleanAttempt(a) {
  if (!a || typeof a !== 'object') return null;
  const id = s(a.id, 80).trim();
  const problemId = s(a.pid ?? a.problemId, 160).trim();
  const at = Math.round(n(a.at));
  if (!id || !problemId || at <= 0) return null;
  return {
    id,
    pid: problemId,
    base: s(a.base ?? a.baseId, 160).trim() || problemId,
    sub: s(a.sub ?? a.subjectId, 60),
    unit: s(a.unit, 120),
    topic: s(a.topic, 120),
    ans: s(a.ans ?? a.answer, 200),
    exp: s(a.exp ?? a.expected, 200),
    ok: (a.ok ?? a.correct) === true,
    ms: Math.max(0, Math.min(6 * 3600000, Math.round(n(a.ms ?? a.timeMs)))),
    at,
    mode: s(a.mode, 20) || 'practice',
  };
}

function createAccountsApi({ dataDir, log, seedFile }) {
  log = log || ((m) => console.warn(m));
  const accounts = new JsonStore({
    file: path.join(dataDir, 'accounts.json'),
    empty: () => ({ version: 1, users: [], sessions: {} }),
    log,
  }).load();
  const study = new JsonStore({
    file: path.join(dataDir, 'study.json'),
    empty: () => ({ version: 1, students: {} }),
    log,
  }).load();
  if (!Array.isArray(accounts.data.users)) accounts.data.users = [];
  if (!accounts.data.sessions || typeof accounts.data.sessions !== 'object') accounts.data.sessions = {};
  if (!study.data.students || typeof study.data.students !== 'object') study.data.students = {};

  const users = () => accounts.data.users;
  const sessions = () => accounts.data.sessions;
  let byId = new Map();
  let byLogin = new Map();
  let byInvite = new Map();
  function reindex() {
    byId = new Map(users().map((u) => [u.id, u]));
    byLogin = new Map(users().map((u) => [u.loginId, u]));
    byInvite = new Map(users().filter((u) => u.role === 'teacher' && u.inviteCode).map((u) => [u.inviteCode, u]));
  }
  // 처음 켤 때(계정이 하나도 없을 때)만 미리 만들어 둔 계정을 넣는다.
  // seed 파일에는 비밀번호가 없고 scrypt 해시와 salt 만 있다 (공개 저장소에 있어도 비밀번호는 알 수 없음).
  if (users().length === 0 && seedFile && fs.existsSync(seedFile)) {
    try {
      const seed = JSON.parse(fs.readFileSync(seedFile, 'utf8'));
      for (const u of Array.isArray(seed.users) ? seed.users : []) {
        if (!u || !ROLES.includes(u.role) || !LOGIN_RE.test(String(u.loginId)) || !u.id || !u.salt || !u.passHash) continue;
        const nu = { id: u.id, role: u.role, loginId: u.loginId, name: lineText(u.name) || u.loginId, salt: u.salt,
          passHash: u.passHash, createdAt: Date.now() };
        if (u.role === 'teacher') nu.inviteCode = typeof u.inviteCode === 'string' ? u.inviteCode : randomCode();
        if (u.role === 'student') {
          nu.grade = u.grade || '고3';
          if (Array.isArray(u.grades) && u.grades.length) nu.grades = u.grades.filter((g) => GRADES.includes(g));
          nu.teachers = Array.isArray(u.teachers) ? u.teachers : [];
        }
        users().push(nu);
      }
      accounts.save().catch((e) => log(`seed accounts: ${e.message}`));
      log(`seed accounts: ${users().length}`);
    } catch (e) {
      log(`seed accounts: ${e.message}`);
    }
  }
  for (const u of users()) {
    if (u.role === 'student' && !Array.isArray(u.teachers)) u.teachers = [];
    if (!u.communityKey) u.communityKey = crypto.randomBytes(12).toString('hex');
  }
  reindex();

  async function persist(...stores) {
    try {
      await Promise.all((stores.length ? stores : [accounts]).map((x) => x.save()));
    } catch (e) {
      throw new HttpError(500, '저장하지 못했습니다. 잠시 뒤 다시 시도하세요.');
    }
  }

  // ── 실패 횟수 제한 (메모리) ──
  const loginFails = new Map(); // loginId → { n, until }
  const signups = new Map(); // ip → [times]
  function checkLoginRate(loginId) {
    const f = loginFails.get(loginId);
    if (f && f.n >= 8 && Date.now() < f.until) {
      const min = Math.ceil((f.until - Date.now()) / 60000);
      throw new HttpError(429, `비밀번호를 여러 번 틀렸습니다. ${min}분 뒤에 다시 시도하세요.`);
    }
  }
  function markLoginFail(loginId) {
    const f = loginFails.get(loginId);
    const fresh = !f || Date.now() >= f.until;
    loginFails.set(loginId, { n: fresh ? 1 : f.n + 1, until: Date.now() + 10 * 60000 });
    if (loginFails.size > 5000) for (const [k, v] of loginFails) if (Date.now() >= v.until) loginFails.delete(k);
  }
  function checkSignupRate(ip) {
    const now = Date.now();
    const list = (signups.get(ip) || []).filter((t) => now - t < 3600000);
    if (list.length >= 30) throw new HttpError(429, '가입 요청이 너무 많습니다. 잠시 뒤 다시 시도하세요.');
    list.push(now);
    signups.set(ip, list);
  }

  // ── 응답 모양 ──
  function publicUser(u) {
    const out = { id: u.id, role: u.role, loginId: u.loginId, name: u.name, createdAt: u.createdAt };
    if (u.role === 'student') { out.grade = u.grade || ''; out.grades = gradesOf(u); }
    if (u.school) out.school = u.school;
    return out;
  }
  function brief(u) {
    return u ? { id: u.id, name: u.name, ...(u.role === 'student' ? { grade: gradesOf(u).join(' · ') } : {}) } : null;
  }

  // ── 세션 ──
  function newSession(u) {
    const token = crypto.randomBytes(32).toString('base64url');
    sessions()[sha256(token)] = { userId: u.id, createdAt: Date.now(), lastUsed: Date.now() };
    // 오래된 세션 정리
    const cutoff = Date.now() - SESSION_DAYS * DAY_MS;
    for (const [k, v] of Object.entries(sessions())) if (!v || v.lastUsed < cutoff || !byId.has(v.userId)) delete sessions()[k];
    return token;
  }
  function tokenOf(req) {
    const h = String(req.headers.authorization || '');
    const m = /^Bearer\s+(\S+)$/i.exec(h);
    return m ? m[1] : '';
  }
  /** 요청의 로그인 사용자 (없으면 401) */
  function auth(req) {
    const token = tokenOf(req);
    if (!token) throw new HttpError(401, '로그인이 필요합니다');
    const sess = sessions()[sha256(token)];
    const u = sess && byId.get(sess.userId);
    if (!u || sess.lastUsed < Date.now() - SESSION_DAYS * DAY_MS) throw new HttpError(401, '로그인이 만료되었습니다. 다시 로그인하세요.');
    if (Date.now() - sess.lastUsed > 3600000) { sess.lastUsed = Date.now(); accounts.save().catch(() => {}); }
    return u;
  }
  function need(u, role) {
    if (u.role !== role) throw new HttpError(403, role === 'teacher' ? '선생님 계정만 쓸 수 있습니다' : '학생 계정만 쓸 수 있습니다');
  }
  function isLinked(studentId, teacherId) {
    const st = byId.get(studentId);
    return !!st && st.role === 'student' && st.teachers.includes(teacherId);
  }
  function studentsOf(teacher) {
    return users().filter((u) => u.role === 'student' && u.teachers.includes(teacher.id));
  }
  function uniqueInvite() {
    for (let i = 0; i < 50; i++) {
      const c = randomCode(6);
      if (!byInvite.has(c)) return c;
    }
    throw new HttpError(500, '초대 코드를 만들지 못했습니다');
  }

  // 질문 API 가 알림 수를 넣을 수 있게 (questions.js 가 설정)
  let countsFor = () => ({});

  function meView(u) {
    const out = { user: publicUser(u), communityKey: u.communityKey, counts: countsFor(u) };
    if (u.role === 'teacher') {
      out.inviteCode = u.inviteCode;
      out.studentCount = studentsOf(u).length;
    } else {
      out.teachers = u.teachers.map((id) => brief(byId.get(id))).filter(Boolean);
    }
    return out;
  }

  // ── 가입 · 로그인 ──
  async function signup(req) {
    const b = await readJson(req, 16 * 1024);
    const role = typeof b.role === 'string' ? b.role.trim() : '';
    if (!ROLES.includes(role)) throw new HttpError(400, '학생 또는 선생님을 골라 주세요');
    const loginId = normLoginId(b.loginId);
    if (!LOGIN_RE.test(loginId)) throw new HttpError(400, '아이디는 영문 소문자·숫자로 시작하는 4~20자(영문·숫자·. _ -)여야 합니다');
    const password = needPassword(b.password);
    const name = needName(b.name);
    const grades = role === 'student' ? needGrades(b.grades, b.grade) : [];
    const grade = grades[0] || '';
    const school = charLen(lineText(b.school)) <= LIMITS.school ? lineText(b.school) : '';
    checkSignupRate(req.socket.remoteAddress || '');
    if (byLogin.has(loginId)) throw new HttpError(409, '이미 쓰고 있는 아이디입니다');
    const salt = crypto.randomBytes(16).toString('hex');
    const u = {
      id: newId('u'),
      role,
      loginId,
      name,
      salt,
      passHash: await scrypt(password, salt),
      communityKey: crypto.randomBytes(12).toString('hex'),
      createdAt: Date.now(),
    };
    if (school) u.school = school;
    if (role === 'student') { u.grade = grade; u.grades = grades; u.teachers = []; }
    if (role === 'teacher') u.inviteCode = uniqueInvite();
    if (byLogin.has(loginId)) throw new HttpError(409, '이미 쓰고 있는 아이디입니다'); // scrypt 기다리는 사이 같은 아이디
    users().push(u);
    reindex();
    const token = newSession(u);
    await persist();
    return Object.assign({ token }, meView(u));
  }

  async function login(req) {
    const b = await readJson(req, 16 * 1024);
    const loginId = normLoginId(b.loginId);
    const password = typeof b.password === 'string' ? b.password : '';
    if (!loginId || !password) throw new HttpError(400, '아이디와 비밀번호를 입력하세요');
    checkLoginRate(loginId);
    const u = byLogin.get(loginId);
    // 없는 아이디도 같은 시간이 걸리게 한 번 계산한다
    const hash = await scrypt(password, u ? u.salt : 'no-such-user-salt');
    const ok = !!u && crypto.timingSafeEqual(Buffer.from(hash, 'hex'), Buffer.from(u.passHash, 'hex'));
    if (!ok) {
      markLoginFail(loginId);
      throw new HttpError(401, '아이디 또는 비밀번호가 맞지 않습니다');
    }
    loginFails.delete(loginId);
    const token = newSession(u);
    await persist();
    return Object.assign({ token }, meView(u));
  }

  async function logout(req) {
    const token = tokenOf(req);
    if (token) delete sessions()[sha256(token)];
    await persist();
    return { ok: true };
  }

  async function updateMe(req, u) {
    const b = await readJson(req, 16 * 1024);
    if (b.name !== undefined) u.name = needName(b.name);
    if (u.role === 'student') {
      if (b.grades !== undefined) {
        const gs = needGrades(b.grades);
        if (gs.length) { u.grades = gs; u.grade = gs[0]; }
      } else if (b.grade !== undefined) {
        const g = needGrade(b.grade);
        u.grade = g;
        if (g) u.grades = [g, ...gradesOf(u).filter((x) => x !== g)];
      }
    }
    await persist();
    return meView(u);
  }

  async function changePassword(req, u) {
    const b = await readJson(req, 16 * 1024);
    const current = typeof b.current === 'string' ? b.current : '';
    const hash = await scrypt(current, u.salt);
    if (!crypto.timingSafeEqual(Buffer.from(hash, 'hex'), Buffer.from(u.passHash, 'hex'))) {
      throw new HttpError(401, '지금 비밀번호가 맞지 않습니다');
    }
    const next = needPassword(b.next, '새 비밀번호');
    u.salt = crypto.randomBytes(16).toString('hex');
    u.passHash = await scrypt(next, u.salt);
    // 다른 기기의 로그인은 모두 끊고 지금 기기만 남긴다
    const keep = sha256(tokenOf(req));
    for (const [k, v] of Object.entries(sessions())) if (v.userId === u.id && k !== keep) delete sessions()[k];
    await persist();
    return { ok: true };
  }

  // ── 학생 ──
  async function joinTeacher(req, u) {
    need(u, 'student');
    const b = await readJson(req, 4096);
    const code = (typeof b.code === 'string' ? b.code : '').replace(/[\s-]/g, '').toUpperCase();
    if (!code) throw new HttpError(400, '선생님 초대 코드를 입력하세요');
    const t = byInvite.get(code);
    if (!t) throw new HttpError(404, '초대 코드가 맞지 않습니다. 선생님께 다시 확인하세요.');
    if (!u.teachers.includes(t.id)) {
      if (u.teachers.length >= 10) throw new HttpError(400, '선생님은 10명까지 연결할 수 있습니다');
      u.teachers.push(t.id);
      (u.joinedAt ||= {})[t.id] = Date.now();
      await persist();
    }
    return { teacher: brief(t) };
  }

  async function leaveTeacher(u, teacherId) {
    need(u, 'student');
    const i = u.teachers.indexOf(teacherId);
    if (i < 0) throw new HttpError(404, '연결된 선생님이 아닙니다');
    u.teachers.splice(i, 1);
    if (u.joinedAt) delete u.joinedAt[teacherId];
    await persist();
    return { ok: true };
  }

  function recordOf(studentId) {
    const all = study.data.students;
    let r = all[studentId];
    if (!r || typeof r !== 'object') {
      r = all[studentId] = { attempts: [], learner: null, wrongNote: null, syncedAt: 0 };
    }
    if (!Array.isArray(r.attempts)) r.attempts = [];
    return r;
  }

  async function sync(req, u) {
    need(u, 'student');
    const b = await readJson(req, MAX_BODY_BYTES);
    const r = recordOf(u.id);
    let stored = 0;
    if (b.attempts !== undefined) {
      if (!Array.isArray(b.attempts)) throw new HttpError(400, 'attempts 는 배열이어야 합니다');
      if (b.attempts.length > MAX_ATTEMPTS_PER_SYNC) throw new HttpError(400, `한 번에 ${MAX_ATTEMPTS_PER_SYNC}개까지 보낼 수 있습니다`);
      const have = new Set(r.attempts.map((a) => a.id));
      for (const raw of b.attempts) {
        const a = cleanAttempt(raw);
        if (!a || have.has(a.id)) continue;
        have.add(a.id);
        r.attempts.push(a);
        stored++;
      }
      if (stored) {
        r.attempts.sort((x, y) => x.at - y.at);
        if (r.attempts.length > MAX_ATTEMPTS_KEPT) r.attempts.splice(0, r.attempts.length - MAX_ATTEMPTS_KEPT);
      }
    }
    if (b.learner !== undefined) {
      if (b.learner !== null && (typeof b.learner !== 'object' || Array.isArray(b.learner))) throw new HttpError(400, 'learner 는 객체여야 합니다');
      if (JSON.stringify(b.learner || {}).length > MAX_LEARNER_BYTES) throw new HttpError(413, 'learner 가 너무 큽니다');
      r.learner = b.learner;
      if (b.learner && Array.isArray(b.learner.grades)) {
        const gs = b.learner.grades.filter((g) => typeof g === 'string' && GRADES.includes(g));
        const uniq = gs.filter((g, i) => gs.indexOf(g) === i);
        if (uniq.length) { u.grades = uniq; u.grade = uniq[0]; }
      } else if (b.learner && typeof b.learner.grade === 'string' && GRADES.includes(b.learner.grade)) u.grade = b.learner.grade;
    }
    if (b.wrongNote !== undefined) {
      if (!Array.isArray(b.wrongNote)) throw new HttpError(400, 'wrongNote 는 배열이어야 합니다');
      r.wrongNote = b.wrongNote.slice(0, 20000).map((x) => s(x, 160)).filter(Boolean);
    }
    r.syncedAt = Date.now();
    await persist(study, accounts);
    return { ok: true, stored, total: r.attempts.length, syncedAt: r.syncedAt };
  }

  function records(u) {
    need(u, 'student');
    const r = recordOf(u.id);
    return { attempts: r.attempts, learner: r.learner, wrongNote: r.wrongNote, syncedAt: r.syncedAt };
  }

  // ── 선생님 ──
  function tally(list) {
    let solved = 0, correct = 0, ms = 0;
    for (const a of list) { solved++; if (a.ok) correct++; ms += a.ms; }
    return { solved, correct, timeMs: ms };
  }
  function wrongList(r) {
    const fam = new Map();
    for (const a of r.attempts) {
      let f = fam.get(a.base);
      if (!f) fam.set(a.base, (f = { tries: 0, correct: 0, wrongs: 0, last: null, lastWrong: null }));
      f.tries++;
      if (a.ok) f.correct++; else { f.wrongs++; f.lastWrong = a; }
      f.last = a;
    }
    const note = Array.isArray(r.wrongNote) ? new Set(r.wrongNote) : null;
    const out = [];
    for (const [base, f] of fam) {
      if (!f.lastWrong) continue;
      const open = note ? note.has(base) : !f.last.ok;
      const w = f.lastWrong;
      out.push({
        baseId: base,
        problemId: w.pid,
        subjectId: w.sub,
        unit: w.unit,
        topic: w.topic,
        answer: w.ans,
        expected: w.exp,
        wrongAt: w.at,
        lastAt: f.last.at,
        lastCorrect: f.last.ok,
        tries: f.tries,
        correct: f.correct,
        wrongs: f.wrongs,
        open,
      });
    }
    out.sort((a, b) => (b.open ? 1 : 0) - (a.open ? 1 : 0) || b.wrongAt - a.wrongAt);
    return out;
  }
  function summaryOf(st, teacherId) {
    const r = recordOf(st.id);
    const today = dayOf(Date.now());
    const weekStart = dayOf(Date.now() - 6 * DAY_MS);
    const todayList = [], weekList = [];
    for (const a of r.attempts) {
      const d = dayOf(a.at);
      if (d >= weekStart) weekList.push(a);
      if (d === today) todayList.push(a);
    }
    const all = tally(r.attempts);
    const wrong = wrongList(r);
    return {
      id: st.id,
      name: st.name,
      grade: gradesOf(st).join(' · '),
      joinedAt: (st.joinedAt && st.joinedAt[teacherId]) || null,
      syncedAt: r.syncedAt || null,
      lastActiveAt: r.attempts.length ? r.attempts[r.attempts.length - 1].at : null,
      solved: all.solved,
      correct: all.correct,
      today: tally(todayList),
      week: tally(weekList),
      wrongOpen: wrong.filter((w) => w.open).length,
    };
  }

  function teacherStudents(u) {
    need(u, 'teacher');
    const list = studentsOf(u).map((st) => summaryOf(st, u.id));
    list.sort((a, b) => (b.lastActiveAt || 0) - (a.lastActiveAt || 0) || a.name.localeCompare(b.name, 'ko'));
    return { inviteCode: u.inviteCode, students: list };
  }

  function linkedStudent(u, id) {
    need(u, 'teacher');
    const st = byId.get(id);
    if (!st || st.role !== 'student' || !st.teachers.includes(u.id)) throw new HttpError(404, '연결된 학생이 아닙니다');
    return st;
  }

  function teacherStudent(u, id) {
    const st = linkedStudent(u, id);
    const r = recordOf(st.id);
    const bySub = new Map();
    for (const a of r.attempts) {
      const t = bySub.get(a.sub) || { subjectId: a.sub, solved: 0, correct: 0, timeMs: 0 };
      t.solved++; if (a.ok) t.correct++; t.timeMs += a.ms;
      bySub.set(a.sub, t);
    }
    const days = [];
    const byDay = new Map();
    for (const a of r.attempts) {
      const d = dayOf(a.at);
      const t = byDay.get(d) || { day: d, solved: 0, correct: 0, timeMs: 0 };
      t.solved++; if (a.ok) t.correct++; t.timeMs += a.ms;
      byDay.set(d, t);
    }
    for (let i = 13; i >= 0; i--) {
      const d = dayOf(Date.now() - i * DAY_MS);
      days.push(byDay.get(d) || { day: d, solved: 0, correct: 0, timeMs: 0 });
    }
    const L = r.learner && typeof r.learner === 'object' ? r.learner : {};
    return {
      student: summaryOf(st, u.id),
      learner: {
        grade: Array.isArray(L.grades) && L.grades.length ? L.grades.filter((g) => typeof g === 'string').join(' · ') : typeof L.grade === 'string' ? L.grade : gradesOf(st).join(' · '),
        goal: typeof L.goal === 'string' ? L.goal : '',
        workbooks: Array.isArray(L.workbooks) ? L.workbooks.map((x) => s(x, 120)) : [],
        examName: typeof L.examName === 'string' ? L.examName : '',
        examDate: Number(L.examDate) || 0,
      },
      wrong: wrongList(r),
      bySubject: [...bySub.values()].sort((a, b) => b.solved - a.solved),
      byDay: days,
      recent: r.attempts.slice(-150).reverse(),
    };
  }

  async function removeStudent(u, id) {
    const st = linkedStudent(u, id);
    st.teachers = st.teachers.filter((t) => t !== u.id);
    if (st.joinedAt) delete st.joinedAt[u.id];
    await persist();
    return { ok: true };
  }

  async function newInvite(u) {
    need(u, 'teacher');
    u.inviteCode = uniqueInvite();
    reindex();
    await persist();
    return { inviteCode: u.inviteCode };
  }

  // ── 라우팅 ──
  async function route(req, res, url) {
    const m = req.method;
    const parts = pathParts(url.pathname).slice(1); // 'api' 다음
    const [a, b, c] = parts;
    const ok = (obj) => sendJson(res, 200, obj);
    if (a === 'auth' && parts.length === 2 && m === 'POST') {
      if (b === 'signup') return ok(await signup(req));
      if (b === 'login') return ok(await login(req));
      if (b === 'logout') return ok(await logout(req));
    }
    const u = auth(req);
    if (a === 'me') {
      if (parts.length === 1 && m === 'GET') return ok(meView(u));
      if (parts.length === 1 && m === 'POST') return ok(await updateMe(req, u));
      if (parts.length === 2 && b === 'password' && m === 'POST') return ok(await changePassword(req, u));
    }
    if (a === 'student') {
      if (b === 'teachers' && parts.length === 2 && m === 'POST') return ok(await joinTeacher(req, u));
      if (b === 'teachers' && parts.length === 3 && m === 'DELETE') return ok(await leaveTeacher(u, c));
      if (b === 'sync' && parts.length === 2 && m === 'POST') return ok(await sync(req, u));
      if (b === 'records' && parts.length === 2 && m === 'GET') return ok(records(u));
    }
    if (a === 'teacher') {
      if (b === 'students' && parts.length === 2 && m === 'GET') return ok(teacherStudents(u));
      if (b === 'students' && parts.length === 3 && m === 'GET') return ok(teacherStudent(u, c));
      if (b === 'students' && parts.length === 3 && m === 'DELETE') return ok(await removeStudent(u, c));
      if (b === 'invite' && parts.length === 2 && m === 'POST') return ok(await newInvite(u));
    }
    throw new HttpError(404, '없는 주소이거나 지원하지 않는 방식입니다');
  }

  /** @returns {boolean} 처리했으면 true */
  function handle(req, res, url) {
    const p = url.pathname;
    const mine = /^\/api\/(auth|me|student|teacher)(\/|$)/.test(p);
    if (!mine) return false;
    if (req.method === 'OPTIONS') { res.writeHead(204, CORS).end(); return true; }
    Promise.resolve().then(() => route(req, res, url)).catch((e) => sendError(res, e, log));
    return true;
  }

  return {
    handle,
    auth,
    need,
    isLinked,
    userById: (id) => byId.get(id) || null,
    brief,
    setCounts: (fn) => { countsFor = fn; },
    saveSync: () => { accounts.saveSync(); study.saveSync(); },
  };
}

module.exports = { createAccountsApi, cleanAttempt, dayOf };
