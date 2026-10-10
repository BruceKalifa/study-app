'use strict';
/**
 * 교재 창고 (/books/) — 선생님이 .pulinote 를 끌어다 놓아 올리고, 누가 받을지 고른다.
 * 앱은 올리지 않고 받기만 한다 (docs/accounts-api.md — "교재 창고").
 */

const KEY = 'pulinote.books.token';
const $ = (id) => document.getElementById(id);

let token = sessionStorage.getItem(KEY) || localStorage.getItem(KEY) || '';
let students = []; // [{ id, name, grade }]

// ───────────────────────── 서버 부르기 ─────────────────────────

async function api(path, { method = 'GET', json, body, raw } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (json !== undefined) headers['Content-Type'] = 'application/json';
  if (raw) headers['Content-Type'] = 'application/octet-stream';
  const res = await fetch(path, { method, headers, body: json !== undefined ? JSON.stringify(json) : body });
  const text = await res.text();
  let data = {};
  if (text) {
    try { data = JSON.parse(text); } catch (_) { data = { error: text.slice(0, 200) }; }
  }
  if (!res.ok) throw new Error(data.error || `서버가 ${res.status} 로 답했습니다`);
  return data;
}

// ───────────────────────── 로그인 ─────────────────────────

function show(pane) {
  $('loginPane').hidden = pane !== 'login';
  $('booksPane').hidden = pane !== 'books';
  $('who').hidden = pane !== 'books';
}

function signOut(message) {
  token = '';
  sessionStorage.removeItem(KEY);
  localStorage.removeItem(KEY);
  show('login');
  if (message) fail($('loginError'), message);
}

function fail(el, message) {
  el.textContent = message;
  el.hidden = !message;
}

$('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  fail($('loginError'), '');
  $('loginBtn').disabled = true;
  try {
    const out = await api('/api/auth/login', {
      method: 'POST',
      json: { loginId: $('loginId').value.trim(), password: $('password').value },
    });
    if (!out.user || out.user.role !== 'teacher') throw new Error('선생님 계정으로 들어와 주세요');
    token = out.token;
    sessionStorage.setItem(KEY, token);
    $('password').value = '';
    await start(out.user);
  } catch (err) {
    fail($('loginError'), err.message);
  } finally {
    $('loginBtn').disabled = false;
  }
});

$('logout').addEventListener('click', async () => {
  try { await api('/api/auth/logout', { method: 'POST' }); } catch (_) { /* 이미 끊겼으면 그만 */ }
  signOut('');
});

async function start(user) {
  $('whoName').textContent = `${user.name} 선생님`;
  show('books');
  try {
    const out = await api('/api/teacher/students');
    students = (out.students || []).map((s) => ({ id: s.id, name: s.name, grade: s.grade || '' }));
  } catch (_) {
    students = [];
  }
  await Promise.all([load(), loadCodes().catch((e) => note(e.message, false))]);
}

// ───────────────────────── 가입 추천코드 ─────────────────────────

async function loadCodes() {
  const out = await api('/api/teacher/signup-codes');
  const sel = $('codeCohort');
  if (!sel.options.length) {
    for (const k of out.cohorts || []) sel.add(new Option(`${k.label} (${(k.grades || []).join('·')})`, k.id));
  }
  const list = $('codeList');
  list.textContent = '';
  for (const c of out.codes || []) {
    const row = document.createElement('div');
    row.className = `code-row${c.active ? '' : ' off'}`;
    const kind = document.createElement('span');
    kind.className = 'kind';
    kind.textContent = c.label;
    const code = document.createElement('code');
    code.textContent = c.code;
    const uses = document.createElement('span');
    uses.className = 'uses';
    uses.textContent = `${c.uses}명 가입${c.active ? '' : ' · 꺼짐'}`;
    const copy = document.createElement('button');
    copy.type = 'button';
    copy.className = 'ghost';
    copy.textContent = '복사';
    copy.addEventListener('click', async () => {
      try { await navigator.clipboard.writeText(c.code); copy.textContent = '복사됨'; } catch (_) { copy.textContent = '길게 눌러 복사'; }
      setTimeout(() => { copy.textContent = '복사'; }, 1500);
    });
    const toggle = document.createElement('button');
    toggle.type = 'button';
    toggle.className = 'ghost';
    toggle.textContent = c.active ? '끄기' : '켜기';
    toggle.addEventListener('click', async () => {
      try {
        await api(`/api/teacher/signup-codes/${encodeURIComponent(c.code)}`, { method: 'POST', json: { active: !c.active } });
        await loadCodes();
      } catch (e) { note(e.message, false); }
    });
    const del = document.createElement('button');
    del.type = 'button';
    del.className = 'danger ghost';
    del.textContent = '지우기';
    del.addEventListener('click', async () => {
      if (!confirm(`추천코드 ${c.code} 를 지울까요? 이 코드로는 더 이상 가입할 수 없어요. (이미 가입한 학생은 그대로예요)`)) return;
      try {
        await api(`/api/teacher/signup-codes/${encodeURIComponent(c.code)}`, { method: 'DELETE' });
        await loadCodes();
      } catch (e) { note(e.message, false); }
    });
    row.append(kind, code, uses, copy, toggle, del);
    list.append(row);
  }
}

$('codeForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  try {
    await api('/api/teacher/signup-codes', { method: 'POST', json: { cohort: $('codeCohort').value, code: $('codeText').value.trim() } });
    $('codeText').value = '';
    await loadCodes();
  } catch (err) { note(err.message, false); }
});

// ───────────────────────── 목록 ─────────────────────────

const fmtSize = (n) => (n >= 1024 * 1024 ? `${(n / 1024 / 1024).toFixed(1)}MB` : `${Math.max(1, Math.round(n / 1024))}KB`);

function fmtDate(ms) {
  const d = new Date(ms);
  if (Number.isNaN(d.getTime())) return '';
  const p = (n) => `${n}`.padStart(2, '0');
  return `${d.getFullYear()}.${p(d.getMonth() + 1)}.${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

let allBooks = [];

async function load() {
  const out = await api('/api/books');
  allBooks = (out.books || []).filter((b) => b.mine);
  $('count').textContent = allBooks.length ? `${allBooks.length}권` : '';
  $('empty').hidden = allBooks.length > 0;
  draw();
}

/** 걸러 낸(이름에 글자가 든) 교재만 그린다. 한꺼번에 내리기·지우기도 이 목록에만 적용된다. */
function shownBooks() {
  const q = $('filter').value.trim().toLowerCase();
  return q ? allBooks.filter((b) => `${b.title} ${(b.titles || []).join(' ')}`.toLowerCase().includes(q)) : allBooks;
}

function draw() {
  const books = shownBooks();
  $('bulk').hidden = allBooks.length < 2;
  $('shown').textContent = books.length === allBooks.length ? `${books.length}권 모두` : `${books.length}권 / ${allBooks.length}권`;
  const list = $('list');
  list.textContent = '';
  for (const b of books) list.append(row(b));
}

async function bulk(kind) {
  const books = shownBooks();
  if (!books.length) return;
  const what = kind === 'delete' ? '서버에서 지웁니다 (학생 앱에 이미 받아 둔 교재는 그대로 남습니다)' : '학생에게서 내립니다 (서버에는 남아 있고, 다시 열 수 있습니다)';
  if (!confirm(`지금 보이는 교재 ${books.length}권을 ${what}.\n\n${books.slice(0, 5).map((b) => '· ' + b.title).join('\n')}${books.length > 5 ? `\n… 외 ${books.length - 5}권` : ''}`)) return;
  let done = 0;
  for (const b of books) {
    try {
      if (kind === 'delete') await api(`/api/books/${encodeURIComponent(b.id)}`, { method: 'DELETE' });
      else await api(`/api/books/${encodeURIComponent(b.id)}`, { method: 'POST', json: { open: false, students: [] } });
      done++;
    } catch (err) {
      note(`${b.title}: ${err.message}`, false);
    }
  }
  note(`${done}권을 ${kind === 'delete' ? '지웠습니다' : '학생에게서 내렸습니다'}`, done > 0);
  await load();
}

function row(b) {
  const el = $('rowTpl').content.firstElementChild.cloneNode(true);
  el.querySelector('.row-title').textContent = b.title;
  el.querySelector('.row-meta').textContent =
    [`${b.problems}문항`, fmtSize(b.bytes), fmtDate(b.at)].filter(Boolean).join(' · ');
  if ((b.titles || []).length > 1) {
    const t = el.querySelector('.row-titles');
    t.textContent = `묶음: ${b.titles.join(' · ')}`;
    t.hidden = false;
  }

  const open = el.querySelector('.row-open');
  const picker = el.querySelector('.row-students');
  const chips = picker.querySelector('.chips');
  open.checked = !!b.open;

  const drawChips = (chosen) => {
    chips.textContent = '';
    if (!students.length) {
      const p = document.createElement('p');
      p.className = 'muted';
      p.textContent = '연결된 학생이 아직 없습니다.';
      chips.append(p);
      return;
    }
    for (const s of students) {
      const label = document.createElement('label');
      const box = document.createElement('input');
      box.type = 'checkbox';
      box.checked = chosen.includes(s.id);
      label.classList.toggle('on', box.checked);
      box.addEventListener('change', async () => {
        const next = Array.from(chips.querySelectorAll('input'))
          .map((x, i) => (x.checked ? students[i].id : null))
          .filter(Boolean);
        label.classList.toggle('on', box.checked);
        await save(el, b, { students: next });
      });
      label.append(box, document.createTextNode(s.grade ? `${s.name} (${s.grade})` : s.name));
      chips.append(label);
    }
  };

  const syncPicker = () => {
    picker.hidden = open.checked;
    if (!open.checked) drawChips(b.students || []);
  };
  syncPicker();

  open.addEventListener('change', async () => {
    await save(el, b, { open: open.checked });
    syncPicker();
  });

  el.querySelector('.row-del').addEventListener('click', async () => {
    if (!confirm(`"${b.title}" 을 서버에서 지웁니다. 학생 앱에 이미 받아 둔 교재는 그대로 남습니다.`)) return;
    el.classList.add('busy');
    try {
      await api(`/api/books/${encodeURIComponent(b.id)}`, { method: 'DELETE' });
      await load();
    } catch (err) {
      el.classList.remove('busy');
      note(err.message, false);
    }
  });
  return el;
}

async function save(el, b, patch) {
  el.classList.add('busy');
  try {
    const out = await api(`/api/books/${encodeURIComponent(b.id)}`, { method: 'POST', json: patch });
    Object.assign(b, out.book || {});
  } catch (err) {
    note(err.message, false);
  } finally {
    el.classList.remove('busy');
  }
}

// ───────────────────────── 올리기 ─────────────────────────

function note(text, ok) {
  const log = $('log');
  log.hidden = false;
  const p = document.createElement('p');
  p.className = ok ? 'ok' : 'bad';
  p.textContent = text;
  log.prepend(p);
  while (log.children.length > 8) log.lastElementChild.remove();
}

async function upload(files) {
  const open = $('openAll').checked;
  for (const f of files) {
    if (!/\.pulinote$/i.test(f.name)) {
      note(`${f.name}: .pulinote 파일만 올릴 수 있습니다`, false);
      continue;
    }
    try {
      const buf = await f.arrayBuffer();
      // 제목은 보내지 않는다 — 서버가 교재 파일 안의 제목을 쓴다 (파일 이름보다 낫다)
      const out = await api(`/api/books?open=${open ? '1' : '0'}`, { method: 'POST', body: buf, raw: true });
      const b = out.book || {};
      note(`${b.title || f.name} — ${out.replaced ? '같은 교재를 바꿔 끼웠습니다' : '올렸습니다'} (${b.problems}문항)`, true);
    } catch (err) {
      note(`${f.name}: ${err.message}`, false);
    }
  }
  await load();
}

$('pick').addEventListener('click', () => $('file').click());
$('file').addEventListener('change', async () => {
  const files = Array.from($('file').files || []);
  $('file').value = '';
  if (files.length) await upload(files);
});
$('filter').addEventListener('input', draw);
$('hideAll').addEventListener('click', () => bulk('hide'));
$('delAll').addEventListener('click', () => bulk('delete'));
$('refresh').addEventListener('click', () => load().catch((e) => note(e.message, false)));

const drop = $('drop');
for (const type of ['dragenter', 'dragover']) {
  drop.addEventListener(type, (e) => { e.preventDefault(); drop.classList.add('over'); });
}
for (const type of ['dragleave', 'dragend']) {
  drop.addEventListener(type, () => drop.classList.remove('over'));
}
drop.addEventListener('drop', async (e) => {
  e.preventDefault();
  drop.classList.remove('over');
  const files = Array.from(e.dataTransfer?.files || []);
  if (files.length) await upload(files);
});
// 페이지 밖에 떨어뜨렸을 때 브라우저가 파일을 열어 버리지 않게
window.addEventListener('dragover', (e) => e.preventDefault());
window.addEventListener('drop', (e) => e.preventDefault());

// ───────────────────────── 들어올 때 ─────────────────────────

(async () => {
  if (!token) { show('login'); return; }
  try {
    const me = await api('/api/me');
    if (!me.user || me.user.role !== 'teacher') throw new Error('선생님 계정으로 들어와 주세요');
    await start(me.user);
  } catch (err) {
    signOut(err.message.includes('선생님') ? err.message : '');
  }
})();
