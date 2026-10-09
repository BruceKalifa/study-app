/* Solvit 출제실 — 문항·지문·문제집 편집 (빌드 없이 쓰는 순수 JS)
 * 서버 API: docs/content-api.md · 데이터 형식: docs/problem-schema.md
 * 검증·표기법 파서는 schema.js(서버와 같은 파일)를 쓴다. */
(() => {
  'use strict';
  const S = window.Schema;
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const clone = (o) => (o == null ? o : JSON.parse(JSON.stringify(o)));
  const CIRCLED = ['①', '②', '③', '④', '⑤'];
  const BOX_LABELS = 'ㄱㄴㄷㄹㅁㅂㅅㅇㅈㅊ'.split('');
  const KEY_STORE = 'pulinote.adminKey';
  const UI_STORE = 'pulinote.admin.ui';

  // ───────────────────────── 상태 ─────────────────────────
  const st = {
    tab: 'problems', // 편집 탭 (problems | passages | workbooks)
    view: 'editor', // editor | community (커뮤니티 관리)
    courses: [],
    courseId: null,
    course: null,
    courseVersion: null,
    courseCache: new Map(),
    // 문항
    draft: null,
    origId: null,
    insertAfter: null,
    dirty: false,
    tplText: '',
    tplError: null,
    typeStash: {},
    serverIssues: null,
    filters: { q: '', unit: '', topic: '', diff: '', type: '', twin: '' },
    previewMode: 'paper',
    variantSeed: 1,
    // 지문
    pDraft: null,
    pOrig: null,
    pDirty: false,
    pServerIssues: null,
    // 문제집
    wbList: [],
    wbVersion: null,
    wbSel: null, // index in wbList
    wbDirty: false,
    wbAllCourses: false,
    wbAddUnit: '',
    wbAddQ: '',
    wbServerIssues: null,
    lastField: null,
  };
  try { Object.assign(st, JSON.parse(localStorage.getItem(UI_STORE) || '{}').ui || {}); } catch (_) { /* ignore */ }
  if (!['problems', 'passages', 'workbooks'].includes(st.tab)) st.tab = 'problems';
  if (st.view !== 'community') st.view = 'editor';
  function saveUi() {
    try { localStorage.setItem(UI_STORE, JSON.stringify({ ui: { courseId: st.courseId, tab: st.tab, view: st.view, wbAllCourses: st.wbAllCourses } })); } catch (_) { /* ignore */ }
  }

  // ───────────────────────── API ─────────────────────────
  class ApiError extends Error {
    constructor(status, data) { super((data && data.error) || `요청 실패 (${status})`); this.status = status; this.data = data || {}; }
  }
  let keyWaiters = null;
  const api = {
    get key() { try { return localStorage.getItem(KEY_STORE) || ''; } catch (_) { return ''; } },
    set key(v) { try { if (v) localStorage.setItem(KEY_STORE, v); else localStorage.removeItem(KEY_STORE); } catch (_) { /* ignore */ } },
    async raw(method, path, body, retry = true) {
      const res = await fetch(path, {
        method,
        headers: Object.assign({ 'x-admin-key': this.key }, body !== undefined ? { 'Content-Type': 'application/json' } : {}),
        body: body !== undefined ? JSON.stringify(body) : undefined,
        cache: 'no-store',
      });
      if (res.status === 401 && retry) {
        api.key = '';
        await askKey('키가 맞지 않거나 바뀌었습니다. 다시 입력하세요.');
        return this.raw(method, path, body, false);
      }
      return res;
    },
    async req(method, path, body) {
      let res;
      try { res = await this.raw(method, path, body); } catch (e) { throw new ApiError(0, { error: '서버에 연결할 수 없습니다. 서버가 켜져 있는지 확인하세요.' }); }
      let data = null;
      try { data = await res.json(); } catch (_) { /* 본문 없음 */ }
      if (!res.ok) throw new ApiError(res.status, data);
      return data;
    },
    get(p) { return this.req('GET', p); },
    put(p, b) { return this.req('PUT', p, b); },
    post(p, b) { return this.req('POST', p, b); },
    del(p) { return this.req('DELETE', p); },
  };

  function askKey(message) {
    const dlg = $('#keyDlg');
    $('#keyErr').textContent = message || '';
    if (!keyWaiters) {
      keyWaiters = [];
      dlg.showModal();
      setTimeout(() => dlg.querySelector('input').focus(), 30);
    }
    return new Promise((resolve) => keyWaiters.push(resolve));
  }
  $('#keyDlg').addEventListener('cancel', (e) => e.preventDefault());
  $('#keyForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const key = e.target.key.value.trim();
    if (!key) return;
    const res = await fetch('/api/admin/check', { headers: { 'x-admin-key': key }, cache: 'no-store' }).catch(() => null);
    if (!res) { $('#keyErr').textContent = '서버에 연결할 수 없습니다.'; return; }
    if (!res.ok) {
      const d = await res.json().catch(() => ({}));
      $('#keyErr').textContent = d.error || '키가 맞지 않습니다.';
      e.target.key.select();
      return;
    }
    api.key = key;
    e.target.key.value = '';
    $('#keyDlg').close();
    const w = keyWaiters || [];
    keyWaiters = null;
    w.forEach((r) => r());
  });

  // ───────────────────────── 작은 UI 도우미 ─────────────────────────
  function toast(msg, kind) {
    const t = document.createElement('div');
    t.className = 'toast' + (kind ? ' ' + kind : '');
    t.textContent = msg;
    $('#toasts').appendChild(t);
    setTimeout(() => t.remove(), kind === 'bad' ? 5200 : 2600);
  }
  function showMessage(title, html) {
    $('#msgTitle').textContent = title;
    $('#msgBody').innerHTML = html;
    $('#msgDlg').showModal();
  }
  function issueHtml(list, kind) {
    return (list || []).map((e) => `<div class="issue ${kind === 'warn' ? 'warn' : ''}" data-field="${esc(e.field || '')}" data-where="${esc(e.where || '')}"><b>${kind === 'warn' ? '주의' : '오류'}</b><span>${e.where ? `<span class="where">${esc(e.where)}${e.field ? ' · ' + esc(e.field) : ''}</span><br>` : ''}${esc(e.message)}</span></div>`).join('');
  }
  function debounce(fn, ms) {
    let t = null;
    return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); };
  }
  function isDirty() { return st.dirty || st.pDirty || st.wbDirty; }
  function updateSaveState(force) {
    const el = $('#saveState');
    let state = force || (isDirty() ? 'dirty' : 'clean');
    el.dataset.state = state;
    const parts = [];
    if (st.dirty) parts.push('문항');
    if (st.pDirty) parts.push('지문');
    if (st.wbDirty) parts.push('문제집');
    el.querySelector('.txt').textContent = state === 'saving' ? '저장 중…' : state === 'error' ? '저장 실패 — 오류 확인' : state === 'dirty' ? `저장 안 됨 (${parts.join('·')}) · Ctrl+S` : '저장됨';
    document.title = (isDirty() ? '● ' : '') + 'Solvit · 출제실';
  }
  function confirmDiscard(which) {
    const d = which === 'problem' ? st.dirty : which === 'passage' ? st.pDirty : which === 'workbook' ? st.wbDirty : isDirty();
    if (!d) return true;
    return confirm('저장하지 않은 변경이 있습니다. 버리고 이동할까요?');
  }
  window.addEventListener('beforeunload', (e) => { if (isDirty()) { e.preventDefault(); e.returnValue = ''; } });

  // ───────────────────────── 본문 표기법 → HTML ─────────────────────────
  function mathHtml(tex) {
    if (window.katex) {
      try { return window.katex.renderToString(tex, { throwOnError: true, strict: 'ignore', output: 'html' }); } catch (e) {
        return `<span class="mraw" title="${esc(e.message)}">$${esc(tex)}$</span>`;
      }
    }
    return `<i>${esc(tex)}</i>`;
  }
  function inlineHtml(s) {
    return S.inlineTokens(s).map((t) => {
      let h = t.math ? mathHtml(t.text) : esc(t.text);
      if (t.bold) h = `<b>${h}</b>`;
      if (t.underline) h = `<u>${h}</u>`;
      return h;
    }).join('');
  }
  function textBlockHtml(text) {
    const paras = text.split(/\n{2,}/).map((p) => p.replace(/^\n+|\n+$/g, '')).filter((p) => p !== '');
    return paras.map((p) => `<p>${p.split('\n').map(inlineHtml).join('<br>')}</p>`).join('');
  }
  function richHtml(s) {
    return S.parseBlocks(s || '').map((b) => {
      if (b.type === 'text') return textBlockHtml(b.text);
      const head = b.header ? `<thead><tr>${b.header.map((c) => `<th>${inlineHtml(c)}</th>`).join('')}</tr></thead>` : '';
      return `<table class="rt">${head}<tbody>${b.rows.map((r) => `<tr>${r.map((c) => `<td>${inlineHtml(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
    }).join('');
  }
  /** 마지막 문단(표 뒤에 글이 없으면 표 앞 문단) 끝에 [배점] 붙이기 */
  function appendToLast(html, extra) {
    const i = html.lastIndexOf('</p>');
    if (i >= 0) return html.slice(0, i) + extra + html.slice(i);
    return html + `<p>${extra}</p>`;
  }

  // ───────────────────────── 과목 ─────────────────────────
  async function loadCourses() {
    const d = await api.get('/api/admin/courses');
    st.courses = d.courses;
    renderCourses();
  }
  function renderCourses() {
    const groups = new Map();
    for (const g of S.GROUP_ORDER) groups.set(g, []);
    groups.set('', []);
    for (const c of st.courses) (groups.get(c.group || '') || groups.get('')).push(c);
    const html = [];
    for (const [g, list] of groups) {
      if (!list.length) continue;
      const total = list.reduce((a, c) => a + c.count, 0);
      html.push(`<div class="cg"><div class="cg-title"><span>${esc(S.GROUPS[g] || '미분류')}</span><span>${total}</span></div>`);
      for (const c of list) {
        html.push(`<button class="course ${c.id === st.courseId ? 'is-active' : ''}" data-cid="${esc(c.id)}" title="${esc(c.id)} · 원본 ${c.originals} · 쌍둥이 ${c.twins} · 지문 ${c.passages}">
          <span class="swatch" style="background:${esc(c.color || '#999')}"></span>
          <span class="nm">${esc(c.subject)}</span>
          ${c.level ? `<span class="lv">${esc(S.LEVELS[c.level] || c.level)}</span>` : ''}
          <span class="ct">${c.count}</span></button>`);
      }
      html.push('</div>');
    }
    $('#courseList').innerHTML = html.join('') || '<div class="empty">과목이 없습니다.<br>+ 과목 으로 만드세요.</div>';
    const cur = st.courses.find((c) => c.id === st.courseId);
    $('#courseFoot').innerHTML = cur ? `<button class="btn small" id="btnCourseInfo">과목 정보 · 대단원 순서</button>` : '';
  }
  $('#courseList').addEventListener('click', (e) => {
    const b = e.target.closest('[data-cid]');
    if (b && b.dataset.cid !== st.courseId) selectCourse(b.dataset.cid);
  });
  $('#courseFoot').addEventListener('click', (e) => { if (e.target.id === 'btnCourseInfo') openCourseDialog(false); });
  $('#btnNewCourse').addEventListener('click', () => openCourseDialog(true));

  async function fetchCourse(id) {
    const d = await api.get(`/api/admin/course/${encodeURIComponent(id)}`);
    st.courseCache.set(id, d.course);
    return d;
  }
  async function selectCourse(id, opts = {}) {
    if (!opts.force && !confirmDiscard('problem')) return;
    if (!opts.force && !confirmDiscard('passage')) return;
    const d = await fetchCourse(id);
    st.courseId = id;
    st.course = d.course;
    st.courseVersion = d.version;
    if (!opts.keep) {
      clearProblem();
      clearPassage();
      st.filters = { q: '', unit: '', topic: '', diff: '', type: '', twin: '' };
      $('#search').value = '';
    }
    saveUi();
    renderCourses();
    renderAll();
  }
  async function reloadCourse() {
    const d = await fetchCourse(st.courseId);
    st.course = d.course;
    st.courseVersion = d.version;
    const s = await api.get('/api/admin/courses');
    st.courses = s.courses;
    renderCourses();
  }

  // ── 과목 정보 대화상자 ──
  let courseDlgState = null;
  function openCourseDialog(isNew) {
    const c = isNew ? { subject: '', subjectId: '', color: '#2F6BFF', grades: [], units: [] } : clone(st.course);
    courseDlgState = { isNew, origId: isNew ? null : st.courseId, units: Array.isArray(c.units) ? c.units.slice() : [] };
    const f = $('#courseForm');
    $('#courseDlgTitle').textContent = isNew ? '새 과목 만들기' : `과목 정보 — ${c.subject}`;
    f.subject.value = c.subject || '';
    f.subjectId.value = c.subjectId || '';
    f.group.value = c.group || '';
    f.level.value = c.level || '';
    f.track.value = c.track || '';
    f.color.value = (c.color || '#2F6BFF').toUpperCase();
    f.colorPick.value = /^#[0-9a-fA-F]{6}$/.test(c.color || '') ? c.color : '#2F6BFF';
    $('#gradeChecks').innerHTML = S.GRADES.map((g) => `<label><input type="checkbox" value="${g}" ${(c.grades || []).includes(g) ? 'checked' : ''}>${g}</label>`).join('');
    $('#courseIssues').innerHTML = '';
    $('#courseDelete').hidden = isNew;
    $('#unitFromProblems').hidden = isNew;
    renderUnits();
    $('#courseDlg').showModal();
    setTimeout(() => f.subject.focus(), 30);
  }
  function unitCounts() {
    const m = new Map();
    for (const p of (st.course && !courseDlgState.isNew ? st.course.problems : [])) m.set(p.unit, (m.get(p.unit) || 0) + 1);
    return m;
  }
  function renderUnits() {
    const counts = unitCounts();
    $('#unitList').innerHTML = courseDlgState.units.map((u, i) => `<li><span class="n">${i + 1}</span><span class="t">${esc(u)}</span><span class="c">${counts.get(u) || 0}문항</span>
      <button type="button" class="btn small ghost" data-u="up" data-i="${i}" ${i === 0 ? 'disabled' : ''}>↑</button>
      <button type="button" class="btn small ghost" data-u="down" data-i="${i}" ${i === courseDlgState.units.length - 1 ? 'disabled' : ''}>↓</button>
      <button type="button" class="btn small ghost danger" data-u="del" data-i="${i}">✕</button></li>`).join('');
  }
  $('#unitList').addEventListener('click', (e) => {
    const b = e.target.closest('[data-u]');
    if (!b) return;
    const i = Number(b.dataset.i);
    const u = courseDlgState.units;
    if (b.dataset.u === 'up' && i > 0) [u[i - 1], u[i]] = [u[i], u[i - 1]];
    if (b.dataset.u === 'down' && i < u.length - 1) [u[i + 1], u[i]] = [u[i], u[i + 1]];
    if (b.dataset.u === 'del') u.splice(i, 1);
    renderUnits();
  });
  function addUnit() {
    const inp = $('#unitInput');
    const v = inp.value.trim();
    if (v && !courseDlgState.units.includes(v)) courseDlgState.units.push(v);
    inp.value = '';
    renderUnits();
  }
  $('#unitAdd').addEventListener('click', addUnit);
  $('#unitInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); addUnit(); } });
  $('#unitFromProblems').addEventListener('click', () => {
    for (const p of st.course.problems) if (p.unit && !courseDlgState.units.includes(p.unit)) courseDlgState.units.push(p.unit);
    renderUnits();
  });
  $('#courseForm').colorPick.addEventListener('input', (e) => { $('#courseForm').color.value = e.target.value.toUpperCase(); });
  $('#courseForm').color.addEventListener('input', (e) => { if (/^#[0-9a-fA-F]{6}$/.test(e.target.value)) $('#courseForm').colorPick.value = e.target.value; });
  $('#courseCancel').addEventListener('click', () => $('#courseDlg').close());
  $('#courseForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = e.target;
    const body = {
      subject: f.subject.value.trim(),
      subjectId: f.subjectId.value.trim(),
      color: f.color.value.trim(),
      group: f.group.value || null,
      level: f.level.value || null,
      grades: $$('#gradeChecks input:checked').map((x) => x.value),
      track: f.track.value || null,
      units: courseDlgState.units.length ? courseDlgState.units : null,
    };
    const rep = new S.Report();
    S.validateCourseMeta(body.units ? body : Object.assign({}, body, { units: undefined }), rep);
    if (courseDlgState.isNew && st.courses.some((c) => c.id === body.subjectId)) rep.err(body.subjectId, 'subjectId', '이미 있는 과목 id 입니다');
    if (rep.errors.length) { $('#courseIssues').innerHTML = issueHtml(rep.errors); return; }
    if (!courseDlgState.isNew && body.subjectId !== courseDlgState.origId && !confirm(`과목 id 를 "${courseDlgState.origId}" → "${body.subjectId}" 로 바꿉니다.\n이미 이 과목을 내려받은 앱에서는 기록이 따로 보일 수 있습니다. 계속할까요?`)) return;
    try {
      const target = courseDlgState.isNew ? body.subjectId : courseDlgState.origId;
      const r = await api.put(`/api/admin/course/${encodeURIComponent(target)}`, body);
      $('#courseDlg').close();
      toast(courseDlgState.isNew ? '과목을 만들었습니다' : '과목 정보를 저장했습니다', 'good');
      await loadCourses();
      await selectCourse(r.id, { force: true, keep: !courseDlgState.isNew });
      if (st.tab === 'workbooks') await loadWorkbooks();
    } catch (err) {
      const ed = err.data || {};
      $('#courseIssues').innerHTML = issueHtml(ed.errors || [{ message: err.message }]) + issueHtml(ed.warnings, 'warn');
    }
  });
  $('#courseDelete').addEventListener('click', async () => {
    const c = st.course;
    const typed = prompt(`"${c.subject}" 과목과 문항 ${c.problems.length}개, 이 과목의 문제집을 삭제합니다.\n(파일은 서버의 content/_trash 폴더에 보관됩니다)\n\n확인하려면 과목 id "${c.subjectId}" 를 입력하세요.`);
    if (typed == null) return;
    if (typed.trim() !== c.subjectId) { toast('과목 id 가 달라 삭제하지 않았습니다', 'bad'); return; }
    try {
      const r = await api.del(`/api/admin/course/${encodeURIComponent(c.subjectId)}`);
      $('#courseDlg').close();
      toast(`삭제했습니다${r.removedWorkbooks.length ? ` (문제집 ${r.removedWorkbooks.length}개 포함)` : ''}`);
      st.dirty = st.pDirty = false;
      st.courseId = null;
      st.course = null;
      await loadCourses();
      if (st.courses[0]) await selectCourse(st.courses[0].id, { force: true }); else renderAll();
      await loadWorkbooks();
    } catch (err) { toast(err.message, 'bad'); }
  });

  // ───────────────────────── 탭 ─────────────────────────
  $$('.tab').forEach((t) => t.addEventListener('click', () => switchTab(t.dataset.tab)));
  function switchTab(tab) {
    if (tab === 'community') {
      st.view = 'community';
      showView();
      saveUi();
      loadCommunity();
      return;
    }
    st.view = 'editor';
    st.tab = tab;
    showView();
    saveUi();
    renderAll();
  }
  /** 편집 화면(3단) ↔ 커뮤니티 관리 화면 */
  function showView() {
    const cm = st.view === 'community';
    $('#app').hidden = cm;
    $('#communityPane').hidden = !cm;
    $$('.tab').forEach((t) => t.classList.toggle('is-active', cm ? t.dataset.tab === 'community' : t.dataset.tab === st.tab));
  }
  function renderAll() {
    renderListHead();
    renderList();
    renderWork();
  }

  // ───────────────────────── 목록 머리 ─────────────────────────
  function renderListHead() {
    const c = st.course;
    $('#courseTitle').innerHTML = c ? `<span class="sw" style="background:${esc(c.color)}"></span><h1>${esc(c.subject)}</h1><span class="badge lvl">${esc(c.subjectId)}</span>` : '<h1 class="muted">과목을 고르세요</h1>';
    const tb = $('#listToolbar');
    const f = $('#filters');
    $('#search').parentElement.hidden = !c;
    if (!c) { tb.innerHTML = ''; f.innerHTML = ''; return; }
    if (st.tab === 'problems') {
      tb.innerHTML = `<button class="btn small primary" data-act="new">+ 새 문항</button>
        <button class="btn small" data-act="twin" title="고른 문항을 복사해 쌍둥이(변형) 문항을 만듭니다">쌍둥이 만들기</button>
        <button class="btn small" data-act="dup">복제</button>
        <button class="btn small danger" data-act="del">삭제</button>`;
      $('#search').placeholder = '검색: id, 본문, 유형, 태그…';
      const units = courseUnits();
      const topics = Array.from(new Set(c.problems.filter((p) => !st.filters.unit || p.unit === st.filters.unit).map((p) => p.topic).filter(Boolean)));
      const opt = (v, label, cur) => `<option value="${esc(v)}" ${v === cur ? 'selected' : ''}>${esc(label)}</option>`;
      f.innerHTML = `
        <select data-flt="unit">${opt('', '대단원 전체', st.filters.unit)}${units.map((u) => opt(u, u, st.filters.unit)).join('')}</select>
        <select data-flt="topic">${opt('', '유형 전체', st.filters.topic)}${topics.map((u) => opt(u, u, st.filters.topic)).join('')}</select>
        <select data-flt="diff">${opt('', '난이도 전체', st.filters.diff)}${[1, 2, 3, 4, 5].map((d) => opt(String(d), `난이도 ${d}`, st.filters.diff)).join('')}</select>
        <select data-flt="type">${opt('', '형식 전체', st.filters.type)}${opt('choice', '5지선다', st.filters.type)}${opt('short', '단답형', st.filters.type)}</select>
        <select data-flt="twin" style="grid-column: span 2">${opt('', '모든 문항', st.filters.twin)}${opt('has', '쌍둥이가 있는 원본', st.filters.twin)}${opt('none', '쌍둥이가 없는 원본', st.filters.twin)}${opt('twins', '쌍둥이 문항만', st.filters.twin)}${opt('tpl', '자동 변형(template) 있음', st.filters.twin)}${opt('passage', '지문형 문항', st.filters.twin)}</select>`;
    } else if (st.tab === 'passages') {
      tb.innerHTML = `<button class="btn small primary" data-act="pnew">+ 새 지문</button><button class="btn small danger" data-act="pdel">삭제</button>`;
      $('#search').placeholder = '검색: id, 제목, 본문…';
      f.innerHTML = '';
    } else {
      tb.innerHTML = `<button class="btn small primary" data-act="wbnew">+ 새 문제집</button><button class="btn small" data-act="wbdup">복제</button><button class="btn small danger" data-act="wbdel">삭제</button><button class="btn small blue" data-act="wbsave">문제집 저장</button>`;
      $('#search').placeholder = '검색: 제목, id…';
      f.innerHTML = `<label class="fld-help" style="grid-column: span 2; display:flex; gap:6px; align-items:center"><input type="checkbox" data-flt="wball" ${st.wbAllCourses ? 'checked' : ''}> 모든 과목의 문제집 보기</label>`;
    }
  }
  function courseUnits() {
    const c = st.course;
    const out = Array.isArray(c.units) ? c.units.slice() : [];
    for (const p of c.problems) if (p.unit && !out.includes(p.unit)) out.push(p.unit);
    return out;
  }
  $('#filters').addEventListener('change', (e) => {
    const k = e.target.dataset.flt;
    if (!k) return;
    if (k === 'wball') { st.wbAllCourses = e.target.checked; saveUi(); renderList(); return; }
    st.filters[k] = e.target.value;
    if (k === 'unit') { st.filters.topic = ''; renderListHead(); }
    renderList();
  });
  $('#search').addEventListener('input', debounce((e) => { st.filters.q = e.target.value.trim().toLowerCase(); renderList(); }, 120));
  $('#listToolbar').addEventListener('click', (e) => {
    const b = e.target.closest('[data-act]');
    if (!b) return;
    ({
      new: newProblem, twin: makeTwin, dup: duplicateProblem, del: deleteProblem,
      pnew: newPassage, pdel: deletePassage,
      wbnew: newWorkbook, wbdup: dupWorkbook, wbdel: deleteWorkbook, wbsave: saveWorkbooks,
    })[b.dataset.act]();
  });

  // ───────────────────────── 목록 ─────────────────────────
  function renderList() {
    const el = $('#list');
    if (!st.course && st.tab !== 'workbooks') { el.innerHTML = ''; $('#listCount').textContent = ''; return; }
    if (st.tab === 'problems') renderProblemList(el);
    else if (st.tab === 'passages') renderPassageList(el);
    else renderWorkbookList(el);
  }
  function diffDots(d) {
    return `<span class="diff d${d}" title="난이도 ${d}">${[1, 2, 3, 4, 5].map((i) => `<i class="${i <= d ? 'on' : ''}"></i>`).join('')}</span>`;
  }
  function firstLine(s) {
    const t = S.plain(String(s || '').split('\n').find((l) => l.trim() && !/^\s*\|/.test(l)) || '');
    return t.length > 90 ? t.slice(0, 90) + '…' : t;
  }
  function problemMatches(p) {
    const f = st.filters;
    if (f.unit && p.unit !== f.unit) return false;
    if (f.topic && p.topic !== f.topic) return false;
    if (f.diff && String(p.difficulty) !== f.diff) return false;
    if (f.type && p.type !== f.type) return false;
    if (f.twin) {
      const hasTwins = st.course.problems.some((x) => x.twinOf === p.id);
      if (f.twin === 'has' && (p.twinOf || !hasTwins)) return false;
      if (f.twin === 'none' && (p.twinOf || hasTwins)) return false;
      if (f.twin === 'twins' && !p.twinOf) return false;
      if (f.twin === 'tpl' && !p.template) return false;
      if (f.twin === 'passage' && !p.passageId) return false;
    }
    if (f.q) {
      const hay = [p.id, p.unit, p.topic, p.stem, p.solution, (p.tags || []).join(' '), (p.choices || []).join(' '), p.twinOf, p.passageId].join('\n').toLowerCase();
      if (!hay.includes(f.q)) return false;
    }
    return true;
  }
  function itemHtml(p, opts) {
    const active = (st.origId && p.id === st.origId) ? 'is-active' : '';
    const twins = opts.twinCount ? `<span class="badge twin" title="쌍둥이 문항 수">쌍둥이 ${opts.twinCount}</span>` : '';
    const badges = [
      p.twinOf ? `<span class="badge twin">쌍둥이${opts.orphan ? ' ← ' + esc(p.twinOf) : ''}</span>` : '',
      twins,
      p.template ? '<span class="badge tpl" title="자동 변형(template)">변형</span>' : '',
      p.passageId ? '<span class="badge" title="지문형">지문</span>' : '',
      `<span class="badge ${p.type}">${p.type === 'short' ? '단답' : '5지'}</span>`,
    ].join('');
    const dirtyMark = active && st.dirty ? '<span class="unsaved" title="저장 안 됨">●</span>' : '';
    return `<button class="item ${p.twinOf && !opts.orphan ? 'twin' : ''} ${active}" data-pid="${esc(p.id)}">
      <div class="row1">${dirtyMark}<span class="pid">${esc(p.id)}</span>${diffDots(p.difficulty)}<span class="meta">${esc(p.unit)} · ${esc(p.topic)}</span>${badges}</div>
      <div class="stem">${esc(firstLine(p.stem)) || '<span class="muted">(본문 없음)</span>'}</div></button>`;
  }
  function renderProblemList(el) {
    const probs = st.course.problems;
    const byId = new Map(probs.map((p) => [p.id, p]));
    const twinsOf = new Map();
    for (const p of probs) if (p.twinOf && byId.has(p.twinOf)) {
      if (!twinsOf.has(p.twinOf)) twinsOf.set(p.twinOf, []);
      twinsOf.get(p.twinOf).push(p);
    }
    const out = [];
    let shown = 0;
    if (st.draft && !st.origId) {
      out.push(`<button class="item is-active" data-new="1"><div class="row1"><span class="unsaved">●</span><span class="pid">${esc(st.draft.id || '(새 문항)')}</span><span class="meta">새 문항 — 저장 안 됨</span>${st.draft.twinOf ? '<span class="badge twin">쌍둥이</span>' : ''}</div><div class="stem">${esc(firstLine(st.draft.stem)) || '<span class="muted">(본문 없음)</span>'}</div></button>`);
    }
    for (const p of probs) {
      if (p.twinOf && byId.has(p.twinOf)) continue; // 원본 아래에 그린다
      const kids = twinsOf.get(p.id) || [];
      const selfOk = problemMatches(p);
      const kidsOk = kids.filter(problemMatches);
      if (selfOk) { out.push(itemHtml(p, { twinCount: kids.length, orphan: !!p.twinOf })); shown++; }
      for (const k of kidsOk) { out.push(itemHtml(k, { orphan: !selfOk })); shown++; }
    }
    el.innerHTML = out.join('') || '<div class="empty">조건에 맞는 문항이 없습니다.</div>';
    const twinsN = probs.filter((p) => p.twinOf).length;
    $('#listCount').textContent = `${shown} / ${probs.length}문항 (원본 ${probs.length - twinsN} · 쌍둥이 ${twinsN})`;
  }
  $('#list').addEventListener('click', (e) => {
    const it = e.target.closest('.item');
    if (!it) return;
    if (it.dataset.pid) selectProblem(it.dataset.pid);
    else if (it.dataset.psg) selectPassage(it.dataset.psg);
    else if (it.dataset.wb != null) selectWorkbook(Number(it.dataset.wb));
  });
  $('#list').addEventListener('keydown', (e) => {
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
    const items = $$('#list .item');
    const i = items.findIndex((x) => x.classList.contains('is-active'));
    const next = items[Math.max(0, Math.min(items.length - 1, i + (e.key === 'ArrowDown' ? 1 : -1)))];
    if (next && next !== items[i]) { e.preventDefault(); next.click(); next.scrollIntoView({ block: 'nearest' }); $('#list').focus(); }
  });

  // ───────────────────────── 문항 편집 ─────────────────────────
  function clearProblem() {
    st.draft = null; st.origId = null; st.dirty = false; st.serverIssues = null; st.insertAfter = null; st.tplError = null;
    updateSaveState();
  }
  function resetScroll() { $('#workpane').scrollTop = 0; $('#editor').scrollTop = 0; $('#preview').scrollTop = 0; }
  function setDraft(p, origId, opts = {}) {
    if (!st.draft || (origId !== st.origId && p.id !== st.draft.id)) resetScroll();
    st.draft = clone(p);
    if (st.draft.type === 'choice' && !Array.isArray(st.draft.choices)) st.draft.choices = ['', '', '', '', ''];
    if (Array.isArray(st.draft.choices)) while (st.draft.choices.length < 5 && st.draft.type === 'choice') st.draft.choices.push('');
    st.origId = origId;
    st.insertAfter = opts.after || null;
    st.dirty = !!opts.dirty;
    st.serverIssues = null;
    st.typeStash = {};
    st.tplText = st.draft.template ? JSON.stringify(st.draft.template, null, 2) : '';
    st.tplError = null;
    st.previewMode = st.previewMode === 'variant' && st.draft.template ? 'variant' : 'paper';
    updateSaveState();
  }
  function selectProblem(id) {
    if (id === st.origId && st.draft) return;
    if (!confirmDiscard('problem')) return;
    const p = st.course.problems.find((x) => x.id === id);
    if (!p) return;
    setDraft(p, id);
    renderList();
    renderWork();
  }
  function nextFreeId(base) {
    const all = new Set(st.course.problems.map((p) => p.id).concat((st.course.passages || []).map((p) => p.id)));
    const m = /^(.*?)(\d+)$/.exec(base);
    if (m) {
      let n = Number(m[2]) + 1;
      for (;;) {
        const id = m[1] + String(n).padStart(m[2].length, '0');
        if (!all.has(id)) return id;
        n++;
      }
    }
    let n = 2;
    while (all.has(`${base}-${n}`)) n++;
    return `${base}-${n}`;
  }
  function newProblem() {
    if (!st.course || !confirmDiscard('problem')) return;
    const c = st.course;
    const ref = (st.draft && st.origId && c.problems.find((p) => p.id === st.origId)) || null;
    const unit = st.filters.unit || (ref && ref.unit) || (courseUnits()[0] || '');
    const originals = c.problems.filter((p) => !p.twinOf);
    const sameUnit = originals.filter((p) => p.unit === unit);
    const last = sameUnit[sameUnit.length - 1] || originals[originals.length - 1];
    const id = last ? nextFreeId(last.id) : `${c.subjectId}-001`;
    setDraft({ id, unit, topic: st.filters.topic || (ref && ref.unit === unit ? ref.topic : ''), difficulty: 3, type: 'choice', stem: '', choices: ['', '', '', '', ''], answer: '', solution: '' }, null, { dirty: true, after: last && last.unit === unit ? lastOfFamily(last.id) : null });
    renderList();
    renderWork();
    setTimeout(() => { const s = $('#editor [data-f=stem]'); if (s) s.focus(); }, 30);
  }
  function lastOfFamily(id) {
    let last = id;
    for (const p of st.course.problems) if (p.twinOf === id) last = p.id;
    return last;
  }
  function currentSaved() {
    return st.origId ? st.course.problems.find((p) => p.id === st.origId) : null;
  }
  function makeTwin() {
    const src = currentSaved();
    if (!src) { toast('먼저 원본 문항을 고르세요 (저장된 문항)', 'bad'); return; }
    if (!confirmDiscard('problem')) return;
    const origId = src.twinOf || src.id;
    const orig = st.course.problems.find((p) => p.id === origId) || src;
    const ids = new Set(st.course.problems.map((p) => p.id));
    let n = 1;
    while (ids.has(`${origId}-t${n}`)) n++;
    const p = clone(orig);
    p.id = `${origId}-t${n}`;
    p.twinOf = origId;
    setDraft(p, null, { dirty: true });
    renderList();
    renderWork();
    toast(`쌍둥이 ${p.id} 를 만들었습니다 — 숫자·조건을 바꾸고 저장하세요`);
  }
  function duplicateProblem() {
    const src = currentSaved();
    if (!src) { toast('복제할 문항을 고르세요', 'bad'); return; }
    if (!confirmDiscard('problem')) return;
    const p = clone(src);
    p.id = nextFreeId(src.id);
    setDraft(p, null, { dirty: true, after: src.twinOf ? src.id : lastOfFamily(src.id) });
    renderList();
    renderWork();
  }
  async function deleteProblem() {
    if (st.draft && !st.origId) {
      if (confirm('저장하지 않은 새 문항을 버릴까요?')) { clearProblem(); renderList(); renderWork(); }
      return;
    }
    const src = currentSaved();
    if (!src) { toast('삭제할 문항을 고르세요', 'bad'); return; }
    const inWb = st.wbList.filter((w) => (w.problems || []).includes(src.id)).map((w) => w.title);
    if (!confirm(`문항 ${src.id} 를 삭제할까요?${inWb.length ? `\n문제집에서도 빠집니다: ${inWb.join(', ')}` : ''}`)) return;
    const path = `/api/admin/course/${encodeURIComponent(st.courseId)}/problem/${encodeURIComponent(src.id)}`;
    try {
      let r;
      try { r = await api.del(path); } catch (e) {
        if (e.status === 400 && e.data && e.data.twins) {
          if (!confirm(`${e.message}\n\n쌍둥이 ${e.data.twins.length}개도 함께 삭제할까요?`)) return;
          r = await api.del(path + '?cascade=1');
        } else throw e;
      }
      const idx = st.course.problems.findIndex((p) => p.id === src.id);
      clearProblem();
      await reloadCourse();
      if (r.removedFromWorkbooks.length) await loadWorkbooks();
      const next = st.course.problems[Math.min(idx, st.course.problems.length - 1)];
      if (next) setDraft(next, next.id);
      renderAll();
      toast(`삭제했습니다: ${r.deleted.join(', ')}`);
    } catch (e) { toast(e.message, 'bad'); }
  }

  /** 편집 중인 문항 → 서버로 보낼 문항 */
  function buildPayload() {
    const d = clone(st.draft);
    for (const k of Object.keys(d)) if (k.startsWith('_')) delete d[k];
    if (d.type === 'short') delete d.choices;
    else { delete d.answerUnit; delete d.tolerance; }
    if (d.tolerance === '' || d.tolerance == null) delete d.tolerance;
    else if (typeof d.tolerance === 'string') d.tolerance = Number(d.tolerance);
    if (Array.isArray(d.boxItems) && !d.boxItems.some((x) => x && x.trim())) delete d.boxItems;
    if (Array.isArray(d.tags) && !d.tags.length) delete d.tags;
    for (const k of ['hint', 'answerUnit', 'passageId', 'twinOf']) if (d[k] === '' || d[k] == null) delete d[k];
    if (st.tplText.trim()) { try { d.template = JSON.parse(st.tplText); } catch (_) { /* tplError 로 막음 */ } } else delete d.template;
    return d;
  }
  async function saveProblem() {
    if (!st.draft) return;
    if (st.tplError) { toast('template JSON 오류를 먼저 고치세요', 'bad'); focusField('template'); return; }
    const payload = buildPayload();
    const q = new URLSearchParams();
    if (st.origId && st.origId !== payload.id) q.set('replace', st.origId);
    if (!st.origId && st.insertAfter) q.set('after', st.insertAfter);
    updateSaveState('saving');
    try {
      const r = await api.put(`/api/admin/course/${encodeURIComponent(st.courseId)}/problem${q.toString() ? '?' + q : ''}`, payload);
      await reloadCourse();
      if (r.renamedFrom) await loadWorkbooks();
      const saved = st.course.problems.find((p) => p.id === r.problem.id) || r.problem;
      const keepMode = st.previewMode;
      setDraft(saved, saved.id);
      st.previewMode = keepMode === 'variant' && saved.template ? 'variant' : 'paper';
      st.serverIssues = { errors: [], warnings: r.warnings || [] };
      renderAll();
      toast(r.created ? `새 문항 ${saved.id} 를 저장했습니다` : `${saved.id} 저장됨`, 'good');
    } catch (e) {
      st.serverIssues = e.data && e.data.errors ? { errors: e.data.errors, warnings: e.data.warnings || [] } : { errors: [{ where: payload.id, field: '', message: e.message }], warnings: [] };
      updateSaveState('error');
      renderIssues();
      toast(e.message, 'bad');
    }
  }

  // ── 편집 폼 ──
  function renderWork() {
    const has = st.tab === 'problems' ? !!st.draft : st.tab === 'passages' ? !!st.pDraft : st.wbSel != null && !!st.wbList[st.wbSel];
    $('#emptyWork').hidden = has;
    $('#work').hidden = !has;
    $('#previewMode').hidden = st.tab !== 'problems';
    if (!has) {
      const msg = { problems: '목록에서 문항을 고르거나 <b>+ 새 문항</b>을 누르세요.', passages: '지문을 고르거나 <b>+ 새 지문</b>을 누르세요. 지문은 국어·영어 지문형 문항에 연결합니다.', workbooks: '문제집을 고르거나 <b>+ 새 문제집</b>을 누르세요.' }[st.tab];
      $('#emptyWork').querySelector('p').innerHTML = st.course || st.tab === 'workbooks' ? msg : '왼쪽에서 과목을 고르세요.';
      return;
    }
    if (st.tab === 'problems') renderProblemEditor();
    else if (st.tab === 'passages') renderPassageEditor();
    else renderWorkbookEditor();
  }

  function fieldHtml(key, label, inner, help) {
    return `<div class="fld" data-fld="${key}"><span>${label}</span>${inner}${help ? `<div class="fld-help">${help}</div>` : ''}</div>`;
  }
  function renderProblemEditor() {
    const d = st.draft;
    const c = st.course;
    const units = courseUnits();
    const topics = Array.from(new Set(c.problems.filter((p) => p.unit === d.unit).map((p) => p.topic).concat(c.problems.map((p) => p.topic)).filter(Boolean)));
    const originals = c.problems.filter((p) => !p.twinOf && p.id !== d.id);
    const passages = c.passages || [];
    const isChoice = d.type === 'choice';
    const box = Array.isArray(d.boxItems) ? d.boxItems : [];
    const no = st.origId ? c.problems.findIndex((p) => p.id === st.origId) + 1 : null;
    const ta = (f, rows, ph) => `<textarea data-f="${f}" rows="${rows}" placeholder="${esc(ph || '')}">${esc(d[f] || '')}</textarea>`;
    $('#editor').innerHTML = `
      <div class="ed-head">
        <h2>${st.origId ? `${no}번 문항` : '새 문항'}<small>${esc(c.subject)}</small></h2>
        <div class="ed-actions">
          ${st.origId ? '<button class="btn small ghost" data-ed="revert" title="저장된 내용으로 되돌리기">되돌리기</button>' : ''}
          <button class="btn primary" data-ed="save">저장 <kbd style="background:transparent;color:#fff;border-color:rgba(255,255,255,.5)">Ctrl S</kbd></button>
        </div>
      </div>
      <div class="issues" id="issues"></div>

      <div class="grid2">
        ${fieldHtml('id', '문항 id', `<input data-f="id" value="${esc(d.id || '')}" spellcheck="false" autocomplete="off">`, st.origId && d.id !== st.origId ? `저장하면 id 가 ${esc(st.origId)} → ${esc(d.id)} 로 바뀝니다 (쌍둥이·문제집 연결도 함께 바뀜)` : '')}
        ${fieldHtml('type', '형식', `<div class="seg" data-g="type"><button data-type="choice" class="${isChoice ? 'is-on' : ''}">5지선다</button><button data-type="short" class="${!isChoice ? 'is-on' : ''}">단답형</button></div>`)}
        ${fieldHtml('unit', '대단원', `<input data-f="unit" list="dlUnits" value="${esc(d.unit || '')}" autocomplete="off"><datalist id="dlUnits">${units.map((u) => `<option value="${esc(u)}">`).join('')}</datalist>`)}
        ${fieldHtml('topic', '유형 <em>약점 분석·오답 변형 기준 — 같은 유형은 같은 이름으로</em>', `<input data-f="topic" list="dlTopics" value="${esc(d.topic || '')}" autocomplete="off"><datalist id="dlTopics">${topics.map((u) => `<option value="${esc(u)}">`).join('')}</datalist>`)}
        ${fieldHtml('difficulty', `난이도 <em>배점 ${S.points(d.difficulty)}점</em>`, `<div class="seg diffs">${[1, 2, 3, 4, 5].map((v) => `<button data-diff="${v}" data-v="${v}" class="${d.difficulty === v ? 'is-on' : ''}">${v}</button>`).join('')}</div>`, '1 쉬움 · 3 보통 · 5 킬러')}
        ${fieldHtml('twinOf', '쌍둥이 원본 <em>변형 문항이면</em>', `<select data-f="twinOf"><option value="">(원본 문항)</option>${originals.map((p) => `<option value="${esc(p.id)}" ${d.twinOf === p.id ? 'selected' : ''}>${esc(p.id)} · ${esc(p.topic)}</option>`).join('')}${d.twinOf && !originals.some((p) => p.id === d.twinOf) ? `<option value="${esc(d.twinOf)}" selected>${esc(d.twinOf)} (없음)</option>` : ''}</select>`)}
      </div>
      ${passages.length || d.passageId ? fieldHtml('passageId', '지문', `<select data-f="passageId"><option value="">(지문 없음)</option>${passages.map((p) => `<option value="${esc(p.id)}" ${d.passageId === p.id ? 'selected' : ''}>${esc(p.id)}${p.title ? ' · ' + esc(p.title) : ''}</option>`).join('')}${d.passageId && !passages.some((p) => p.id === d.passageId) ? `<option value="${esc(d.passageId)}" selected>${esc(d.passageId)} (없음)</option>` : ''}</select>`) : ''}

      <div class="sec">문제</div>
      ${fieldHtml('stem', '본문', ta('stem', 6, '수식은 $...$ 안에. 예: 속력 $v=3\\,\\text{m/s}$ 로 …'), '줄바꿈은 Enter, 문단은 빈 줄. **굵게** __밑줄__ | 표 |')}
      ${fieldHtml('boxItems', '&lt;보기&gt; <em>없으면 비워 두세요</em>', `<div class="box-items">${box.map((b, i) => `<div class="box-row" data-fld="boxItems[${i}]"><textarea data-box="${i}" rows="${Math.max(1, Math.min(10, String(b).split('\n').length + (String(b).length > 70 ? 1 : 0)))}" class="box-ta">${esc(b)}</textarea><button class="btn small ghost danger" data-boxdel="${i}" title="항목 삭제">✕</button></div>`).join('')}</div>
        <div><button class="btn small" data-ed="boxadd">+ 보기 항목 (${BOX_LABELS[box.length] || '…'}.)</button>${!box.length ? ' <button class="btn small ghost" data-ed="boxfree" title="ㄱ·ㄴ·ㄷ 없이 글·표·자료를 넣는 &lt;보기&gt; (국어·사회형)">+ 자유 형식 &lt;보기&gt;</button>' : ''}${box.length > 1 ? ' <button class="btn small ghost" data-ed="boxchoices" title="ㄱ, ㄴ, ㄷ 조합으로 선택지를 채웁니다">선택지에 ㄱ·ㄴ·ㄷ 조합 넣기</button>' : ''}</div>`)}
      ${isChoice ? fieldHtml('choices', '선택지 <em>번호를 눌러 정답 표시</em>', `<div class="choices">${[0, 1, 2, 3, 4].map((i) => `<div class="choice-row" data-fld="choices[${i}]"><button class="num ${d.answer === String(i + 1) ? 'is-answer' : ''}" data-ans="${i}" title="${i + 1}번을 정답으로">${CIRCLED[i]}</button><input data-choice="${i}" value="${esc((d.choices || [])[i] || '')}"></div>`).join('')}</div>
        <div class="choice-hint" data-fld="answer">정답: <b>${d.answer && /^[1-5]$/.test(d.answer) ? CIRCLED[Number(d.answer) - 1] : '<span style="color:var(--bad)">고르지 않음</span>'}</b></div>`) : `
        <div class="grid3">
          ${fieldHtml('answer', '정답', `<input data-f="answer" value="${esc(d.answer || '')}" placeholder="예: 12, -3/2, 2.5" autocomplete="off">`)}
          ${fieldHtml('answerUnit', '단위 <em>선택</em>', `<input data-f="answerUnit" value="${esc(d.answerUnit || '')}" placeholder="예: m/s">`)}
          ${fieldHtml('tolerance', '허용 오차 <em>선택</em>', `<input data-f="tolerance" type="number" min="0" step="any" value="${d.tolerance == null ? '' : esc(d.tolerance)}" placeholder="0">`)}
        </div>`}

      <div class="sec">해설</div>
      ${fieldHtml('solution', '해설', ta('solution', 5))}
      ${fieldHtml('hint', '힌트 <em>한 줄, 선택</em>', `<input data-f="hint" value="${esc(d.hint || '')}">`)}
      ${fieldHtml('tags', '태그 <em>Enter 또는 쉼표로 추가</em>', `<div class="tags-input">${(d.tags || []).map((t, i) => `<span class="chip">${esc(t)}<button data-tagdel="${i}" title="삭제">✕</button></span>`).join('')}<input data-taginput placeholder="${(d.tags || []).length ? '' : '예: 등가속도, 변위'}"></div>`)}

      <div class="sec">자동 변형 (template)</div>
      ${fieldHtml('template', `template JSON <em>있으면 이 문제의 변형문제를 자동 생성</em> <span class="tpl-state" id="tplState"></span>`, `<textarea class="code" data-tpl rows="${st.tplText ? Math.min(22, st.tplText.split('\n').length + 1) : 3}" spellcheck="false" placeholder='비워 두면 자동 변형 없음'>${esc(st.tplText)}</textarea>`,
        `<button class="btn small" data-ed="tplsample">예시 틀 넣기</button> <button class="btn small ghost" data-ed="tplfmt">정렬</button> · 식 문법과 [[이름]] 자리표시는 docs/problem-schema.md 참고`)}
    `;
    updateTplState();
    renderIssues();
    renderPreview();
  }
  function updateTplState() {
    const el = $('#tplState');
    if (!el) return;
    el.className = 'tpl-state ' + (st.tplError ? 'bad' : st.tplText.trim() ? 'ok' : '');
    el.textContent = st.tplError ? `JSON 오류: ${st.tplError}` : st.tplText.trim() ? '✓ JSON 형식 정상' : '';
    const vb = $('#pvVariantBtn');
    if (vb) vb.disabled = !(st.tplText.trim() && !st.tplError);
  }
  function changed(structural) {
    if (!st.dirty) { st.dirty = true; updateSaveState(); renderList(); }
    st.serverIssues = null;
    if (!st.origId) {
      const it = $('#list .item[data-new] .stem');
      if (it) it.textContent = firstLine(st.draft.stem) || '(본문 없음)';
      const pid = $('#list .item[data-new] .pid');
      if (pid) pid.textContent = st.draft.id || '(새 문항)';
    }
    if (structural) renderProblemEditor();
    else { liveCheck(); renderPreviewSoon(); }
  }
  const liveCheck = debounce(() => renderIssues(), 250);
  const renderPreviewSoon = debounce(() => renderPreview(), 120);

  /** 클라이언트 검사(서버와 같은 규칙, 다른 과목과의 id 중복은 저장할 때 서버가 확인) */
  function clientIssues() {
    if (!st.draft) return { errors: [], warnings: [] };
    const payload = buildPayload();
    const c = clone(st.course);
    const i = st.origId ? c.problems.findIndex((p) => p.id === st.origId) : -1;
    if (st.origId && payload.id !== st.origId) for (const p of c.problems) if (p.twinOf === st.origId) p.twinOf = payload.id;
    if (i >= 0) c.problems[i] = payload; else c.problems.push(payload);
    const rep = S.validateCourse(c, { only: new Set([payload.id]) });
    const mine = (e) => e.where === payload.id || e.where === '(id 없음)';
    const errors = rep.errors.filter(mine);
    if (st.tplError) errors.push({ where: payload.id, field: 'template', message: `template JSON 형식 오류: ${st.tplError}` });
    if (payload.twinOf && st.origId && st.wbList.some((w) => (w.problems || []).includes(st.origId))) {
      errors.push({ where: payload.id, field: 'twinOf', message: '이 문항은 문제집에 들어 있어 쌍둥이로 바꿀 수 없습니다 (문제집에서 먼저 빼세요)' });
    }
    return { errors, warnings: rep.warnings.filter(mine) };
  }
  function renderIssues() {
    const box = $('#issues');
    if (!box) return;
    const cl = clientIssues();
    const sv = st.serverIssues;
    const seen = new Set();
    const uniq = (list) => list.filter((e) => { const k = S.formatIssue(e); if (seen.has(k)) return false; seen.add(k); return true; });
    const errors = uniq((sv ? sv.errors : []).concat(cl.errors));
    const warnings = uniq((sv ? sv.warnings : []).concat(cl.warnings));
    box.innerHTML = issueHtml(errors) + issueHtml(warnings, 'warn');
    // 필드 표시
    $$('#editor .fld-msg').forEach((x) => x.remove());
    $$('#editor .has-error, #editor .has-warn').forEach((x) => x.classList.remove('has-error', 'has-warn'));
    const mark = (e, cls) => {
      const f = e.field || '';
      const base = f.replace(/\[\d+\]$/, '').split('.')[0];
      const exact = $(`#editor [data-fld="${CSS.escape(f)}"]`);
      const fld = $(`#editor .fld[data-fld="${CSS.escape(base)}"]`);
      if (exact && exact !== fld) { const inp = exact.querySelector('input,textarea'); if (inp) inp.classList.add(cls === 'warn' ? 'has-warn' : 'has-error'); }
      if (!fld) return;
      fld.classList.add(cls === 'warn' ? 'has-warn' : 'has-error');
      const m = document.createElement('div');
      m.className = 'fld-msg' + (cls === 'warn' ? ' warn' : '');
      m.textContent = e.message;
      fld.appendChild(m);
    };
    errors.forEach((e) => mark(e));
    warnings.forEach((e) => mark(e, 'warn'));
  }
  function focusField(f) {
    const base = String(f || '').replace(/\[\d+\]$/, '').split('.')[0];
    const exact = $(`#editor [data-fld="${CSS.escape(f)}"] input, #editor [data-fld="${CSS.escape(f)}"] textarea`);
    const el = exact || $(`#editor .fld[data-fld="${CSS.escape(base)}"] input, #editor .fld[data-fld="${CSS.escape(base)}"] textarea, #editor .fld[data-fld="${CSS.escape(base)}"] select, #editor .fld[data-fld="${CSS.escape(base)}"] button`);
    if (el) { el.scrollIntoView({ block: 'center', behavior: 'smooth' }); el.focus({ preventScroll: true }); }
  }
  $('#editor').addEventListener('click', (e) => {
    const iss = e.target.closest('.issue');
    if (iss) { focusField(iss.dataset.field); return; }
    if (st.tab === 'problems') onProblemClick(e);
    else if (st.tab === 'passages') onPassageClick(e);
    else onWorkbookClick(e);
  });
  $('#editor').addEventListener('input', (e) => {
    if (st.tab === 'problems') onProblemInput(e);
    else if (st.tab === 'passages') onPassageInput(e);
    else onWorkbookInput(e);
  });
  $('#editor').addEventListener('change', (e) => {
    if (st.tab === 'problems' && e.target.matches('select[data-f]')) onProblemInput(e);
  });
  $('#editor').addEventListener('keydown', (e) => {
    if (st.tab === 'problems' && e.target.matches('[data-taginput]')) {
      if ((e.key === 'Enter' || e.key === ',') && e.target.value.trim()) {
        e.preventDefault();
        addTags(e.target.value);
      } else if (e.key === 'Backspace' && !e.target.value && (st.draft.tags || []).length) {
        st.draft.tags.pop();
        changed(true);
        setTimeout(() => $('#editor [data-taginput]').focus(), 0);
      }
    }
    if (e.key === 'Tab' && e.target.matches('textarea[data-tpl]')) {
      e.preventDefault();
      e.target.setRangeText('  ', e.target.selectionStart, e.target.selectionEnd, 'end');
      e.target.dispatchEvent(new Event('input', { bubbles: true }));
    }
  });
  $('#editor').addEventListener('focusout', (e) => {
    if (st.tab === 'problems' && e.target.matches('[data-taginput]') && e.target.value.trim()) addTags(e.target.value);
  });
  function addTags(text) {
    const tags = st.draft.tags || (st.draft.tags = []);
    for (const t of text.split(',').map((x) => x.trim()).filter(Boolean)) if (!tags.includes(t)) tags.push(t);
    changed(true);
    setTimeout(() => { const i = $('#editor [data-taginput]'); if (i) i.focus(); }, 0);
  }
  function onProblemInput(e) {
    const t = e.target;
    const d = st.draft;
    if (t.dataset.f) {
      const f = t.dataset.f;
      if (f === 'tolerance') d.tolerance = t.value === '' ? '' : Number(t.value);
      else d[f] = t.value;
      if (f === 'twinOf' || f === 'passageId') return changed(false);
      if (f === 'id') { const h = t.closest('.fld').querySelector('.fld-help'); if (h) h.textContent = st.origId && d.id !== st.origId ? `저장하면 id 가 ${st.origId} → ${d.id} 로 바뀝니다 (쌍둥이·문제집 연결도 함께 바뀜)` : ''; }
      return changed(false);
    }
    if (t.dataset.choice != null) { d.choices[Number(t.dataset.choice)] = t.value; return changed(false); }
    if (t.dataset.box != null) { d.boxItems[Number(t.dataset.box)] = t.value; return changed(false); }
    if (t.matches('[data-tpl]')) {
      st.tplText = t.value;
      if (!t.value.trim()) st.tplError = null;
      else {
        try {
          const v = JSON.parse(t.value);
          st.tplError = v && typeof v === 'object' && !Array.isArray(v) ? null : '{ } 객체여야 합니다';
        } catch (err) { st.tplError = err.message.replace(/^JSON\.parse: /, ''); }
      }
      updateTplState();
      return changed(false);
    }
  }
  function onProblemClick(e) {
    const b = e.target.closest('button');
    if (!b) return;
    const d = st.draft;
    if (b.dataset.type) {
      if (d.type === b.dataset.type) return;
      st.typeStash[d.type] = { answer: d.answer, choices: d.choices, answerUnit: d.answerUnit, tolerance: d.tolerance };
      d.type = b.dataset.type;
      const back = st.typeStash[d.type] || {};
      d.answer = back.answer || '';
      if (d.type === 'choice') d.choices = back.choices || d.choices || ['', '', '', '', ''];
      if (d.type === 'choice' && (!Array.isArray(d.choices) || d.choices.length < 5)) d.choices = (d.choices || []).concat(['', '', '', '', '']).slice(0, 5);
      if (d.type === 'short') { d.answerUnit = back.answerUnit; d.tolerance = back.tolerance; }
      return changed(true);
    }
    if (b.dataset.diff) { d.difficulty = Number(b.dataset.diff); return changed(true); }
    if (b.dataset.ans != null) { d.answer = String(Number(b.dataset.ans) + 1); return changed(true); }
    if (b.dataset.boxdel != null) { d.boxItems.splice(Number(b.dataset.boxdel), 1); return changed(true); }
    if (b.dataset.tagdel != null) { d.tags.splice(Number(b.dataset.tagdel), 1); return changed(true); }
    switch (b.dataset.ed) {
      case 'save': return saveProblem();
      case 'revert': {
        if (!confirm('저장된 내용으로 되돌릴까요?')) return;
        const p = currentSaved();
        if (p) { setDraft(p, p.id); renderList(); renderWork(); }
        return;
      }
      case 'boxadd': {
        d.boxItems = d.boxItems || [];
        d.boxItems.push(`${BOX_LABELS[d.boxItems.length] || '?'}. `);
        changed(true);
        setTimeout(() => { const ins = $$('#editor [data-box]'); const last = ins[ins.length - 1]; if (last) { last.focus(); last.setSelectionRange(last.value.length, last.value.length); } }, 0);
        return;
      }
      case 'boxfree': {
        d.boxItems = [''];
        changed(true);
        setTimeout(() => { const t = $('#editor [data-box]'); if (t) { t.rows = 4; t.focus(); } }, 0);
        return;
      }
      case 'boxchoices': {
        const n = (d.boxItems || []).length;
        const sets = n === 3 ? ['ㄱ', 'ㄴ', 'ㄱ, ㄷ', 'ㄴ, ㄷ', 'ㄱ, ㄴ, ㄷ'] : n === 2 ? ['ㄱ', 'ㄴ', 'ㄱ, ㄴ', '없음', '-'] : n === 4 ? ['ㄱ, ㄴ', 'ㄱ, ㄷ', 'ㄴ, ㄹ', 'ㄱ, ㄷ, ㄹ', 'ㄴ, ㄷ, ㄹ'] : null;
        if (!sets) { toast('보기 항목이 2~4개일 때 쓸 수 있습니다', 'bad'); return; }
        if ((d.choices || []).some((x) => x && x.trim()) && !confirm('선택지를 덮어쓸까요?')) return;
        d.type = 'choice';
        d.choices = sets.slice();
        return changed(true);
      }
      case 'tplsample': {
        if (st.tplText.trim() && !confirm('지금 template 을 예시로 바꿀까요?')) return;
        const sample = d.type === 'choice' ? {
          params: { a: { min: 1, max: 6, step: 1 }, t: { values: [2, 3, 4, 5] } },
          require: ['a*t - 3'],
          stem: '정지해 있던 물체가 가속도 $[[a]]\\,\\text{m/s}^2$ 으로 $[[t]]$ 초 동안 운동했다. 이동 거리는?',
          answer: '0.5*a*t^2',
          round: 1,
          choiceExprs: ['0.5*a*t^2', 'a*t^2', 'a*t', '0.5*a*t', '2*a*t^2'],
          choiceFormat: '[[v]] m',
          solution: '$s=\\frac{1}{2}at^2=\\frac{1}{2}\\times [[a]]\\times [[t]]^2=[[=0.5*a*t^2]]\\,\\text{m}$',
        } : {
          params: { a: { min: 1, max: 6, step: 1 }, t: { values: [2, 3, 4, 5] } },
          stem: '정지해 있던 물체가 가속도 $[[a]]\\,\\text{m/s}^2$ 으로 $[[t]]$ 초 동안 운동했다. 이동 거리는 몇 m인가?',
          answer: '0.5*a*t^2',
          round: 1,
          solution: '$s=\\frac{1}{2}at^2=[[=0.5*a*t^2]]\\,\\text{m}$',
        };
        st.tplText = JSON.stringify(sample, null, 2);
        st.tplError = null;
        return changed(true);
      }
      case 'tplfmt': {
        if (st.tplError || !st.tplText.trim()) return;
        st.tplText = JSON.stringify(JSON.parse(st.tplText), null, 2);
        return changed(true);
      }
    }
  }

  // ── 미리보기 ──
  function pointsTag(d) { return ` <span class="pts">[${S.points(d)}점]</span>`; }
  function choicesHtml(choices, answerIdx) {
    const lens = choices.map((c) => S.plain(c || '').length);
    const max = Math.max(0, ...lens);
    const cls = max <= 7 ? 'row5' : max <= 16 ? 'row3' : 'col';
    return `<div class="chs ${cls}">${choices.map((c, i) => `<div class="ch ${answerIdx === i ? 'is-answer' : ''}"><span class="cn">${CIRCLED[i]}</span><span class="rich">${inlineHtml(c || '')}</span></div>`).join('')}</div>`;
  }
  function passageBoxHtml(ps) {
    if (!ps) return '';
    return `<div class="passage-box rich">${ps.title ? `<div class="ptitle">${inlineHtml(ps.title)}</div>` : ''}${richHtml(ps.body || '')}${ps.source ? `<div class="psrc">${esc(ps.source)}</div>` : ''}</div>`;
  }
  function questionHtml(p, no, opts = {}) {
    const box = (p.boxItems || []).filter((x) => x && x.trim());
    const stem = appendToLast(richHtml(p.stem || ''), pointsTag(p.difficulty));
    let html = `<div class="q"><span class="qno">${no}.</span><div class="qbody"><div class="rich">${stem}</div>`;
    if (box.length) html += `<div class="bogi"><div class="bogi-title">&lt;보 기&gt;</div>${box.map((b) => `<div class="${box.length > 1 ? 'bogi-item ' : ''}rich">${richHtml(b)}</div>`).join('')}</div>`;
    if (p.type === 'choice') html += choicesHtml(p.choices || ['', '', '', '', ''], opts.showAnswer ? Number(p.answer) - 1 : -1);
    else html += `<div class="ansbox"><span>답</span><span class="box"></span>${p.answerUnit ? `<span>${esc(p.answerUnit)}</span>` : ''}</div>`;
    return html + '</div></div>';
  }
  function solutionHtml(p) {
    const ans = p.type === 'choice'
      ? (/^[1-5]$/.test(p.answer || '') ? `${CIRCLED[Number(p.answer) - 1]} <span class="rich" style="font-weight:400">${inlineHtml((p.choices || [])[Number(p.answer) - 1] || '')}</span>` : '<span style="color:var(--bad)">정답 미지정</span>')
      : `${esc(p.answer || '—')}${p.answerUnit ? ' ' + esc(p.answerUnit) : ''}${p.tolerance ? ` <small style="font-weight:400">(허용 오차 ±${esc(p.tolerance)})</small>` : ''}`;
    return `<div class="sheet"><span class="sheet-label sol">정답 · 해설</span><div class="sol-ans">정답: ${ans}</div><div class="rich">${richHtml(p.solution || '') || '<p class="muted">(해설 없음)</p>'}</div>${p.hint ? `<div class="sol-hint">힌트 · <span class="rich">${inlineHtml(p.hint)}</span></div>` : ''}</div>`;
  }
  function renderPreview() {
    const el = $('#preview');
    if (st.tab === 'passages') return renderPassagePreview(el);
    if (st.tab === 'workbooks') return renderWorkbookPreview(el);
    if (!st.draft) { el.innerHTML = ''; return; }
    $$('#previewMode button').forEach((b) => b.classList.toggle('is-on', b.dataset.mode === st.previewMode));
    const p = buildPayload();
    const no = st.origId ? st.course.problems.findIndex((x) => x.id === st.origId) + 1 : st.course.problems.length + 1;
    const ps = p.passageId ? (st.course.passages || []).find((x) => x.id === p.passageId) : null;
    if (st.previewMode === 'variant') {
      let tpl = null;
      try { tpl = st.tplText.trim() ? JSON.parse(st.tplText) : null; } catch (_) { tpl = null; }
      if (!tpl) { st.previewMode = 'paper'; return renderPreview(); }
      let v = null;
      let err = null;
      try { v = S.makeVariant(tpl, S.seededRandom(st.variantSeed * 7919)); } catch (e) { err = e.message; }
      if (!v) {
        el.innerHTML = `<div class="pv-note bad">변형을 만들 수 없습니다: ${esc(err || 'require 조건을 만족하는 값이 없습니다')}</div>`;
        return;
      }
      const vp = Object.assign({}, p, { stem: v.stem, solution: v.solution != null ? v.solution : p.solution, hint: v.hint != null ? v.hint : p.hint });
      if (p.type === 'choice' && v.choices) { vp.choices = v.choices; vp.answer = '1'; } else if (p.type === 'short') vp.answer = v.answer;
      el.innerHTML = `<div class="pv-note">자동 변형 예시 · 매개변수 ${esc(Object.entries(v.env).map(([k, x]) => `${k}=${S.fmtNum(x)}`).join(', '))} · 정답 ${esc(v.answer)}${p.type === 'choice' ? ' (앱에서는 선택지 순서를 섞습니다; 여기서는 ①이 정답)' : ''}
        <button class="btn small" id="pvAgain" style="margin-left:8px">다른 예시</button></div>
        ${passageBoxHtml(ps) ? `<div class="sheet">${passageBoxHtml(ps)}</div>` : ''}
        <div class="sheet"><span class="sheet-label var">변형 예시</span>${questionHtml(vp, no, { showAnswer: false })}</div>
        ${solutionHtml(vp)}`;
      return;
    }
    el.innerHTML = `<div class="sheet"><span class="sheet-label">${st.origId ? '문항' : '새 문항'}</span>${passageBoxHtml(ps)}${questionHtml(p, no)}</div>${solutionHtml(p)}`;
  }
  $('#previewMode').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-mode]');
    if (!b || b.disabled) return;
    st.previewMode = b.dataset.mode;
    renderPreview();
  });
  $('#preview').addEventListener('click', (e) => {
    if (e.target.id === 'pvAgain') { st.variantSeed++; renderPreview(); }
    const u = e.target.closest('[data-goto]');
    if (u) gotoProblem(u.dataset.goto);
  });

  // ───────────────────────── 지문 ─────────────────────────
  function clearPassage() { st.pDraft = null; st.pOrig = null; st.pDirty = false; st.pServerIssues = null; updateSaveState(); }
  function passageUsers(id) { return st.course.problems.filter((p) => p.passageId === id); }
  function renderPassageList(el) {
    const list = st.course.passages || [];
    const q = st.filters.q;
    const shown = list.filter((p) => !q || [p.id, p.title, p.body, p.source].join('\n').toLowerCase().includes(q));
    const out = [];
    if (st.pDraft && !st.pOrig) out.push(`<button class="item is-active"><div class="row1"><span class="unsaved">●</span><span class="pid">${esc(st.pDraft.id || '(새 지문)')}</span><span class="meta">새 지문 — 저장 안 됨</span></div><div class="stem">${esc(st.pDraft.title || firstLine(st.pDraft.body))}</div></button>`);
    for (const p of shown) {
      const n = passageUsers(p.id).length;
      const active = p.id === st.pOrig;
      out.push(`<button class="item ${active ? 'is-active' : ''}" data-psg="${esc(p.id)}"><div class="row1">${active && st.pDirty ? '<span class="unsaved">●</span>' : ''}<span class="pid">${esc(p.id)}</span><span class="meta"></span><span class="badge ${n ? 'twin' : ''}">문항 ${n}</span></div><div class="stem"><b>${esc(p.title || '')}</b> ${esc(firstLine(p.body))}</div></button>`);
    }
    el.innerHTML = out.join('') || '<div class="empty">지문이 없습니다.<br><span class="fld-help">국어·영어처럼 한 지문에 여러 문항이 딸린 경우 지문을 만들고 문항에서 연결하세요.</span></div>';
    $('#listCount').textContent = `지문 ${list.length}개`;
  }
  function selectPassage(id) {
    if (id === st.pOrig) return;
    if (!confirmDiscard('passage')) return;
    const p = (st.course.passages || []).find((x) => x.id === id);
    if (!p) return;
    st.pDraft = clone(p); st.pOrig = id; st.pDirty = false; st.pServerIssues = null;
    resetScroll();
    updateSaveState();
    renderList(); renderWork();
  }
  function newPassage() {
    if (!st.course || !confirmDiscard('passage')) return;
    const list = st.course.passages || [];
    const base = list.length ? list[list.length - 1].id : `${st.course.subjectId}-p00`;
    let id = base;
    const ids = new Set(list.map((p) => p.id).concat(st.course.problems.map((p) => p.id)));
    const m = /^(.*?)(\d+)$/.exec(base);
    let n = m ? Number(m[2]) : 0;
    do { n++; id = m ? m[1] + String(n).padStart(m[2].length, '0') : `${base}-${n}`; } while (ids.has(id));
    st.pDraft = { id, title: '', body: '' }; st.pOrig = null; st.pDirty = true; st.pServerIssues = null;
    updateSaveState();
    renderList(); renderWork();
  }
  async function deletePassage() {
    if (st.pDraft && !st.pOrig) { if (confirm('저장하지 않은 새 지문을 버릴까요?')) { clearPassage(); renderList(); renderWork(); } return; }
    if (!st.pOrig) { toast('삭제할 지문을 고르세요', 'bad'); return; }
    if (!confirm(`지문 ${st.pOrig} 를 삭제할까요?`)) return;
    try {
      await api.del(`/api/admin/course/${encodeURIComponent(st.courseId)}/passage/${encodeURIComponent(st.pOrig)}`);
      clearPassage();
      await reloadCourse();
      renderAll();
      toast('지문을 삭제했습니다');
    } catch (e) { toast(e.message, 'bad'); }
  }
  async function savePassage() {
    if (!st.pDraft) return;
    const body = Object.assign({}, st.pDraft);
    for (const k of ['title', 'source']) if (!body[k]) delete body[k];
    const q = st.pOrig && st.pOrig !== body.id ? `?replace=${encodeURIComponent(st.pOrig)}` : '';
    updateSaveState('saving');
    try {
      const r = await api.put(`/api/admin/course/${encodeURIComponent(st.courseId)}/passage${q}`, body);
      await reloadCourse();
      const saved = (st.course.passages || []).find((x) => x.id === r.passage.id) || r.passage;
      st.pDraft = clone(saved); st.pOrig = saved.id; st.pDirty = false; st.pServerIssues = { errors: [], warnings: r.warnings || [] };
      updateSaveState();
      renderAll();
      toast('지문을 저장했습니다', 'good');
    } catch (e) {
      const ed = e.data || {};
      st.pServerIssues = { errors: ed.errors || [{ where: body.id, message: e.message }], warnings: ed.warnings || [] };
      updateSaveState('error');
      renderPassageIssues();
      toast(e.message, 'bad');
    }
  }
  function renderPassageEditor() {
    const d = st.pDraft;
    const users = st.pOrig ? passageUsers(st.pOrig) : [];
    $('#editor').innerHTML = `
      <div class="ed-head"><h2>${st.pOrig ? '지문' : '새 지문'}<small>${esc(st.course.subject)}</small></h2>
        <div class="ed-actions"><button class="btn primary" data-ed="psave">저장</button></div></div>
      <div class="issues" id="issues"></div>
      <div class="grid2">
        ${fieldHtml('id', '지문 id', `<input data-pf="id" value="${esc(d.id || '')}" spellcheck="false">`, st.pOrig && d.id !== st.pOrig ? '저장하면 연결된 문항의 passageId 도 함께 바뀝니다' : '')}
        ${fieldHtml('title', '제목 <em>선택</em>', `<input data-pf="title" value="${esc(d.title || '')}">`)}
      </div>
      ${fieldHtml('source', '출처 <em>선택, 한 줄</em>', `<input data-pf="source" value="${esc(d.source || '')}">`)}
      ${fieldHtml('body', '본문', `<textarea data-pf="body" rows="18">${esc(d.body || '')}</textarea>`, '문단은 빈 줄로 구분. 밑줄 친 부분은 __밑줄__, 굵게 **굵게**')}
      <div class="sec">이 지문을 쓰는 문항 (${users.length})</div>
      <div class="uses">${users.map((p) => `<button data-goto="${esc(p.id)}">${esc(p.id)}</button>`).join('') || '<span class="fld-help">아직 없습니다. 문항 편집의 “지문” 칸에서 연결하세요.</span>'}</div>`;
    renderPassageIssues();
    renderPreview();
  }
  function renderPassageIssues() {
    const box = $('#issues');
    if (!box || !st.pDraft) return;
    const rep = new S.Report();
    S.validatePassage(st.pDraft, rep);
    const ids = new Set(st.course.problems.map((p) => p.id).concat((st.course.passages || []).filter((p) => p.id !== st.pOrig).map((p) => p.id)));
    if (st.pDraft.id && ids.has(st.pDraft.id)) rep.err(st.pDraft.id, 'id', '이 과목에서 이미 쓰는 id 입니다');
    const sv = st.pServerIssues || { errors: [], warnings: [] };
    box.innerHTML = issueHtml(sv.errors.concat(rep.errors)) + issueHtml(sv.warnings.concat(rep.warnings), 'warn');
  }
  const passageIssuesSoon = debounce(() => renderPassageIssues(), 200);
  function onPassageInput(e) {
    const f = e.target.dataset.pf;
    if (!f) return;
    st.pDraft[f] = e.target.value;
    if (!st.pDirty) { st.pDirty = true; updateSaveState(); renderList(); }
    st.pServerIssues = null;
    passageIssuesSoon();
    renderPreviewSoon();
  }
  function onPassageClick(e) {
    const b = e.target.closest('button');
    if (!b) return;
    if (b.dataset.ed === 'psave') savePassage();
    if (b.dataset.goto) gotoProblem(b.dataset.goto);
  }
  function renderPassagePreview(el) {
    if (!st.pDraft) { el.innerHTML = ''; return; }
    const users = st.pOrig ? passageUsers(st.pOrig).filter((p) => !p.twinOf) : [];
    el.innerHTML = `<div class="sheet"><span class="sheet-label">지문</span>${users.length ? `<p style="margin:0 0 10px;font-weight:700">[${st.course.problems.indexOf(users[0]) + 1}${users.length > 1 ? `~${st.course.problems.indexOf(users[users.length - 1]) + 1}` : ''}] 다음 글을 읽고 물음에 답하시오.</p>` : ''}${passageBoxHtml(st.pDraft)}
      ${users.map((p) => questionHtml(p, st.course.problems.indexOf(p) + 1)).join('<div style="height:18px"></div>')}</div>`;
  }
  function gotoProblem(id) {
    if (!confirmDiscard('passage')) return;
    st.pDirty = false;
    switchTab('problems');
    selectProblem(id);
    const it = $(`#list [data-pid="${CSS.escape(id)}"]`);
    if (it) it.scrollIntoView({ block: 'center' });
  }

  // ───────────────────────── 문제집 ─────────────────────────
  async function loadWorkbooks() {
    const d = await api.get('/api/admin/workbooks');
    st.wbList = d.workbooks || [];
    st.wbVersion = d.version;
    st.wbDirty = false;
    st.wbServerIssues = null;
    if (st.wbSel != null && !st.wbList[st.wbSel]) st.wbSel = null;
    updateSaveState();
  }
  function wbDirty() {
    if (!st.wbDirty) { st.wbDirty = true; updateSaveState(); }
    st.wbServerIssues = null;
  }
  function renderWorkbookList(el) {
    const q = st.filters.q;
    const out = [];
    let n = 0;
    st.wbList.forEach((w, i) => {
      if (!st.wbAllCourses && st.courseId && w.course !== st.courseId) return;
      if (q && ![w.id, w.title, w.desc, w.course].join('\n').toLowerCase().includes(q)) return;
      n++;
      const course = st.courses.find((c) => c.id === w.course);
      out.push(`<button class="item ${i === st.wbSel ? 'is-active' : ''}" data-wb="${i}"><div class="row1"><span class="pid">${esc(w.id)}</span><span class="meta">${esc(course ? course.subject : w.course)}</span>${w.level ? `<span class="badge lvl">${esc(w.level)}</span>` : ''}<span class="badge">${(w.problems || []).length}문항</span></div><div class="stem"><b>${esc(w.title || '(제목 없음)')}</b> <span class="muted">${esc(w.desc || '')}</span></div></button>`);
    });
    el.innerHTML = out.join('') || `<div class="empty">${st.wbAllCourses || !st.courseId ? '문제집이 없습니다.' : '이 과목의 문제집이 없습니다.'}</div>`;
    $('#listCount').textContent = `${n} / 전체 문제집 ${st.wbList.length}개${st.wbDirty ? ' · 저장 안 됨' : ''}`;
  }
  async function selectWorkbook(i) {
    if (st.wbSel !== i) resetScroll();
    st.wbSel = i;
    const w = st.wbList[i];
    if (w && w.course && !st.courseCache.has(w.course) && st.courses.some((c) => c.id === w.course)) await fetchCourse(w.course).catch(() => {});
    renderList();
    renderWork();
  }
  function newWorkbook() {
    const cid = st.courseId || (st.courses[0] && st.courses[0].id) || '';
    const ids = new Set(st.wbList.map((w) => w.id));
    let n = 1;
    let id = `wb-${cid}-${n}`;
    while (ids.has(id)) id = `wb-${cid}-${++n}`;
    st.wbList.push({ id, title: '', course: cid, level: '기본', desc: '', problems: [] });
    wbDirty();
    selectWorkbook(st.wbList.length - 1);
    setTimeout(() => { const t = $('#editor [data-wf=title]'); if (t) t.focus(); }, 30);
  }
  function dupWorkbook() {
    const w = st.wbList[st.wbSel];
    if (!w) { toast('복제할 문제집을 고르세요', 'bad'); return; }
    const c = clone(w);
    const ids = new Set(st.wbList.map((x) => x.id));
    let n = 2;
    while (ids.has(`${w.id}-${n}`)) n++;
    c.id = `${w.id}-${n}`;
    c.title = `${w.title} (사본)`;
    st.wbList.splice(st.wbSel + 1, 0, c);
    wbDirty();
    selectWorkbook(st.wbSel + 1);
  }
  function deleteWorkbook() {
    const w = st.wbList[st.wbSel];
    if (!w) { toast('삭제할 문제집을 고르세요', 'bad'); return; }
    if (!confirm(`문제집 "${w.title || w.id}" 를 목록에서 뺄까요? (“문제집 저장”을 눌러야 서버에 반영됩니다)`)) return;
    st.wbList.splice(st.wbSel, 1);
    st.wbSel = null;
    wbDirty();
    renderList(); renderWork();
  }
  async function saveWorkbooks() {
    updateSaveState('saving');
    try {
      const r = await api.put('/api/admin/workbooks', { workbooks: st.wbList });
      st.wbList = r.workbooks;
      st.wbVersion = r.version;
      st.wbDirty = false;
      st.wbServerIssues = { errors: [], warnings: r.warnings || [] };
      updateSaveState();
      renderList(); renderWork();
      toast(`문제집 ${r.count}개를 저장했습니다`, 'good');
    } catch (e) {
      const ed = e.data || {};
      st.wbServerIssues = { errors: ed.errors || [{ where: '문제집', message: e.message }], warnings: ed.warnings || [] };
      updateSaveState('error');
      const bad = st.wbServerIssues.errors[0];
      const i = bad ? st.wbList.findIndex((w) => w.id === bad.where) : -1;
      if (i >= 0 && st.tab === 'workbooks') selectWorkbook(i); else if (st.tab === 'workbooks') renderWork();
      toast(e.message, 'bad');
    }
  }
  function wbCourseData(w) { return st.courseCache.get(w.course) || (w.course === st.courseId ? st.course : null); }
  function renderWorkbookEditor() {
    const w = st.wbList[st.wbSel];
    const cd = wbCourseData(w);
    if (!cd && w.course && st.courses.some((c) => c.id === w.course) && !w._loading) {
      Object.defineProperty(w, '_loading', { value: true, configurable: true, enumerable: false });
      fetchCourse(w.course).then(() => { delete w._loading; if (st.tab === 'workbooks' && st.wbList[st.wbSel] === w) renderWorkbookEditor(); }).catch(() => { delete w._loading; });
    }
    const pmap = new Map(cd ? cd.problems.map((p) => [p.id, p]) : []);
    const inSet = new Set(w.problems || []);
    const units = cd ? Array.from(new Set((cd.units || []).concat(cd.problems.map((p) => p.unit)))) : [];
    $('#editor').innerHTML = `
      <div class="ed-head"><h2>문제집<small>${esc(w.id)}</small></h2>
        <div class="ed-actions"><button class="btn blue" data-ed="wbsave">문제집 저장</button></div></div>
      <div class="issues" id="issues"></div>
      ${fieldHtml('title', '제목', `<input data-wf="title" value="${esc(w.title || '')}" placeholder="예: 물리학Ⅰ 개념 완성">`)}
      <div class="grid3">
        ${fieldHtml('id', '문제집 id', `<input data-wf="id" value="${esc(w.id || '')}" spellcheck="false">`)}
        ${fieldHtml('course', '과목', `<select data-wf="course">${st.courses.map((c) => `<option value="${esc(c.id)}" ${c.id === w.course ? 'selected' : ''}>${esc(c.subject)}</option>`).join('')}${st.courses.some((c) => c.id === w.course) ? '' : `<option selected value="${esc(w.course)}">${esc(w.course)} (없음)</option>`}</select>`)}
        ${fieldHtml('level', '수준', `<select data-wf="level"><option value="">(없음)</option>${S.WB_LEVELS.map((l) => `<option ${l === w.level ? 'selected' : ''}>${l}</option>`).join('')}</select>`)}
      </div>
      <div class="grid3">
        ${fieldHtml('stage', '커리큘럼 단계', `<select data-wf="stage"><option value="">(수준으로 짐작)</option>${S.WB_STAGES.map((l) => `<option ${l === w.stage ? 'selected' : ''}>${l}</option>`).join('')}</select>`)}
        ${fieldHtml('scope', '범위 <em>선택</em>', `<input data-wf="scope" value="${esc(w.scope || '')}" placeholder="예: 수학Ⅰ, 공통수학1">`)}
        ${fieldHtml('publisher', '만든 곳 <em>선택</em>', `<input data-wf="publisher" value="${esc(w.publisher || '')}" placeholder="예: LAST30 ITEM LAB">`)}
      </div>
      ${fieldHtml('desc', '설명 <em>한 줄</em>', `<input data-wf="desc" value="${esc(w.desc || '')}" placeholder="예: 교과 개념을 유형별로 한 바퀴">`)}
      <div class="sec">문항 순서 (${(w.problems || []).length}) <span class="fld-help" style="font-weight:500;letter-spacing:0">끌어서 순서 바꾸기</span></div>
      <div class="fld" data-fld="problems" style="margin:0">
      <div class="wb-problems" id="wbProblems">${(w.problems || []).map((pid, i) => {
        const p = pmap.get(pid);
        return `<div class="wb-row ${p ? '' : 'missing'}" draggable="true" data-i="${i}"><span class="handle" title="끌어서 이동">⠿</span><span class="no">${i + 1}</span>
          <div class="info"><div class="pid">${esc(pid)}${p ? ` · ${esc(p.unit)} · ${esc(p.topic)} · 난이도 ${p.difficulty}` : ''}</div><div class="st">${p ? esc(firstLine(p.stem)) : (p === undefined && cd ? '이 과목에 없는 문항' : '')}${p && p.twinOf ? ' <span class="badge twin">쌍둥이 — 넣을 수 없음</span>' : ''}</div></div>
          <button class="btn small ghost" data-wbup="${i}" ${i === 0 ? 'disabled' : ''}>↑</button><button class="btn small ghost" data-wbdown="${i}" ${i === w.problems.length - 1 ? 'disabled' : ''}>↓</button><button class="btn small ghost danger" data-wbrm="${i}">✕</button></div>`;
      }).join('') || '<div class="empty" style="padding:18px">아래에서 문항을 추가하세요.</div>'}</div></div>
      <div class="wb-add">
        <div class="add-row"><select data-wbadd="unit"><option value="">대단원 전체</option>${units.map((u) => `<option ${u === st.wbAddUnit ? 'selected' : ''}>${esc(u)}</option>`).join('')}</select>
          <input data-wbadd="q" placeholder="문항 검색 (id, 유형, 본문)" value="${esc(st.wbAddQ)}"><button class="btn small" data-ed="wbaddall" title="아래 목록의 문항을 모두 추가">모두 추가</button></div>
        <div class="res" id="wbRes">${wbResultsHtml(cd, inSet)}</div>
      </div>`;
    renderWbIssues();
    renderPreview();
  }
  function wbCandidates(cd) {
    if (!cd) return [];
    const q = st.wbAddQ.toLowerCase();
    return cd.problems.filter((p) => !p.twinOf && (!st.wbAddUnit || p.unit === st.wbAddUnit) && (!q || [p.id, p.topic, p.unit, p.stem].join('\n').toLowerCase().includes(q)));
  }
  function wbResultsHtml(cd, inSet) {
    if (!cd) return '<div class="empty">과목 문항을 불러오는 중…</div>';
    const list = wbCandidates(cd);
    return list.map((p) => `<div class="res-row ${inSet.has(p.id) ? 'in' : ''}" draggable="true" data-addpid="${esc(p.id)}"><div class="info"><div class="pid">${esc(p.id)} · ${esc(p.topic)} · 난이도 ${p.difficulty}</div><div class="st">${esc(firstLine(p.stem))}</div></div>${inSet.has(p.id) ? '<span class="badge">들어 있음</span>' : `<button class="btn small" data-wbaddone="${esc(p.id)}">+ 추가</button>`}</div>`).join('') || '<div class="empty">조건에 맞는 원본 문항이 없습니다.</div>';
  }
  function renderWbIssues() {
    const box = $('#issues');
    if (!box) return;
    const w = st.wbList[st.wbSel];
    const sv = st.wbServerIssues || { errors: [], warnings: [] };
    const cd = wbCourseData(w);
    const idx = new Map();
    if (cd) for (const p of cd.problems) idx.set(p.id, { course: w.course, twinOf: p.twinOf || null });
    const rep = cd ? S.validateWorkbooks([w], idx, new Set(st.courses.map((c) => c.id))) : new S.Report();
    const ids = st.wbList.filter((x, i) => i !== st.wbSel).map((x) => x.id);
    if (ids.includes(w.id)) rep.err(w.id, 'id', '같은 id 의 문제집이 이미 있습니다');
    const mine = (e) => e.where === w.id || !st.wbList.some((x) => x.id === e.where);
    box.innerHTML = issueHtml(sv.errors.filter(mine).concat(rep.errors.filter((e) => !(e.field === 'problems' && /다른 과목/.test(e.message))))) + issueHtml(sv.warnings.filter(mine).concat(rep.warnings), 'warn');
  }
  function onWorkbookInput(e) {
    const w = st.wbList[st.wbSel];
    const t = e.target;
    if (t.dataset.wf) {
      w[t.dataset.wf] = t.value;
      wbDirty();
      if (t.dataset.wf === 'course') {
        st.wbAddUnit = '';
        if (!st.courseCache.has(w.course)) fetchCourse(w.course).then(() => renderWorkbookEditor()).catch(() => {});
        else renderWorkbookEditor();
        return;
      }
      renderWbIssues();
      renderList();
      renderPreviewSoon();
    }
    if (t.dataset.wbadd) {
      if (t.dataset.wbadd === 'unit') st.wbAddUnit = t.value; else st.wbAddQ = t.value;
      const cd = wbCourseData(w);
      $('#wbRes').innerHTML = wbResultsHtml(cd, new Set(w.problems || []));
    }
  }
  $('#editor').addEventListener('change', (e) => { if (st.tab === 'workbooks' && e.target.matches('select')) onWorkbookInput(e); });
  function wbMutate(fn) {
    const w = st.wbList[st.wbSel];
    w.problems = w.problems || [];
    fn(w.problems);
    wbDirty();
    const sc = $('#editor').scrollTop;
    renderWorkbookEditor();
    $('#editor').scrollTop = sc;
    renderList();
  }
  function onWorkbookClick(e) {
    const b = e.target.closest('button');
    if (!b) return;
    if (b.dataset.ed === 'wbsave') return saveWorkbooks();
    if (b.dataset.wbup) return wbMutate((l) => { const i = Number(b.dataset.wbup); [l[i - 1], l[i]] = [l[i], l[i - 1]]; });
    if (b.dataset.wbdown) return wbMutate((l) => { const i = Number(b.dataset.wbdown); [l[i + 1], l[i]] = [l[i], l[i + 1]]; });
    if (b.dataset.wbrm) return wbMutate((l) => l.splice(Number(b.dataset.wbrm), 1));
    if (b.dataset.wbaddone) return wbMutate((l) => { if (!l.includes(b.dataset.wbaddone)) l.push(b.dataset.wbaddone); });
    if (b.dataset.ed === 'wbaddall') {
      const w = st.wbList[st.wbSel];
      const add = wbCandidates(wbCourseData(w)).map((p) => p.id).filter((id) => !(w.problems || []).includes(id));
      if (!add.length) return;
      if (add.length > 10 && !confirm(`${add.length}문항을 추가할까요?`)) return;
      return wbMutate((l) => l.push(...add));
    }
  }
  // 끌어서 놓기: 순서 바꾸기 + 검색 결과에서 끌어 넣기
  let dragData = null;
  $('#editor').addEventListener('dragstart', (e) => {
    const row = e.target.closest('.wb-row, .res-row');
    if (!row || st.tab !== 'workbooks') return;
    dragData = row.classList.contains('wb-row') ? { from: Number(row.dataset.i) } : { add: row.dataset.addpid };
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', JSON.stringify(dragData));
    row.classList.add('dragging');
  });
  $('#editor').addEventListener('dragend', (e) => {
    const row = e.target.closest('.wb-row, .res-row');
    if (row) row.classList.remove('dragging');
    $$('.drop-before, .drop-after').forEach((x) => x.classList.remove('drop-before', 'drop-after'));
  });
  $('#editor').addEventListener('dragover', (e) => {
    if (!dragData) return;
    const box = e.target.closest('#wbProblems');
    if (!box) return;
    e.preventDefault();
    $$('.drop-before, .drop-after').forEach((x) => x.classList.remove('drop-before', 'drop-after'));
    const row = e.target.closest('.wb-row');
    if (row) {
      const r = row.getBoundingClientRect();
      row.classList.add(e.clientY < r.top + r.height / 2 ? 'drop-before' : 'drop-after');
    }
  });
  $('#editor').addEventListener('drop', (e) => {
    if (!dragData) return;
    const box = e.target.closest('#wbProblems');
    if (!box) return;
    e.preventDefault();
    const row = e.target.closest('.wb-row');
    const w = st.wbList[st.wbSel];
    let to = (w.problems || []).length;
    if (row) {
      const r = row.getBoundingClientRect();
      to = Number(row.dataset.i) + (e.clientY < r.top + r.height / 2 ? 0 : 1);
    }
    const dd = dragData;
    dragData = null;
    wbMutate((l) => {
      if (dd.add != null) { if (!l.includes(dd.add)) l.splice(to, 0, dd.add); return; }
      const [x] = l.splice(dd.from, 1);
      l.splice(dd.from < to ? to - 1 : to, 0, x);
    });
  });
  function renderWorkbookPreview(el) {
    const w = st.wbList[st.wbSel];
    if (!w) { el.innerHTML = ''; return; }
    const cd = wbCourseData(w);
    const pmap = new Map(cd ? cd.problems.map((p) => [p.id, p]) : []);
    const probs = (w.problems || []).map((id) => pmap.get(id)).filter(Boolean);
    const byUnit = new Map();
    const diffs = [0, 0, 0, 0, 0];
    for (const p of probs) { byUnit.set(p.unit, (byUnit.get(p.unit) || 0) + 1); diffs[(p.difficulty || 1) - 1]++; }
    const course = st.courses.find((c) => c.id === w.course);
    el.innerHTML = `<div class="sheet"><span class="sheet-label">문제집</span>
      <div style="font-family:var(--font)"><div style="font-size:12px;color:var(--muted)">${esc(course ? course.subject : w.course)}${w.level ? ' · ' + esc(w.level) : ''}</div>
      <div style="font-size:22px;font-weight:800;letter-spacing:-.4px;margin:2px 0 4px">${esc(w.title || '(제목 없음)')}</div>
      <div style="color:var(--muted)">${esc(w.desc || '')}</div>
      <div style="display:flex;gap:18px;margin-top:14px;font-size:13px"><div><b style="font-size:20px">${probs.length}</b> 문항</div>
      <div>난이도 ${diffs.map((n, i) => `<span title="난이도 ${i + 1}" style="margin-right:6px">${i + 1}:<b>${n}</b></span>`).join('')}</div></div>
      <ul style="margin:12px 0 0;padding-left:18px;font-size:13px">${Array.from(byUnit).map(([u, n]) => `<li>${esc(u)} — ${n}문항</li>`).join('')}</ul></div></div>
      ${probs.slice(0, 8).map((p, i) => `<div class="sheet">${questionHtml(p, i + 1)}</div>`).join('')}
      ${probs.length > 8 ? `<div class="pv-note">… 외 ${probs.length - 8}문항</div>` : ''}`;
  }

  // ───────────────────────── 저장 단축키 ─────────────────────────
  document.addEventListener('keydown', (e) => {
    const mod = e.ctrlKey || e.metaKey;
    if (mod && (e.key === 's' || e.key === 'S')) {
      e.preventDefault();
      if ($('#courseDlg').open) { $('#courseForm').requestSubmit(); return; }
      if (st.view === 'community') return;
      if (st.tab === 'problems' && st.draft) saveProblem();
      else if (st.tab === 'passages' && st.pDraft) savePassage();
      else if (st.tab === 'workbooks') saveWorkbooks();
    }
    if (mod && e.key === '/') { e.preventDefault(); toggleLatex(); }
    if (e.key === 'Escape' && !$('#latexPanel').hidden && !document.querySelector('dialog[open]')) toggleLatex(false);
  });

  // ───────────────────────── 가져오기 · 내보내기 ─────────────────────────
  $('#btnIO').addEventListener('click', (e) => { e.stopPropagation(); $('#ioMenu').hidden = !$('#ioMenu').hidden; });
  document.addEventListener('click', () => { $('#ioMenu').hidden = true; });
  $('#ioMenu').addEventListener('click', async (e) => {
    const b = e.target.closest('[data-io]');
    if (!b) return;
    $('#ioMenu').hidden = true;
    const k = b.dataset.io;
    if (k === 'import') { $('#importFile').value = ''; $('#importFile').click(); return; }
    const path = k === 'export-course' ? (st.courseId ? `/api/admin/export/${encodeURIComponent(st.courseId)}` : null) : k === 'export-workbooks' ? '/api/admin/export/workbooks' : '/api/admin/export';
    if (!path) { toast('과목을 먼저 고르세요', 'bad'); return; }
    try {
      const res = await api.raw('GET', path);
      if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || '내보내기 실패');
      const blob = await res.blob();
      const cd = res.headers.get('Content-Disposition') || '';
      const m = /filename="([^"]+)"/.exec(cd);
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = m ? decodeURIComponent(m[1]) : 'export.json';
      document.body.appendChild(a);
      a.click();
      setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
    } catch (err) { toast(err.message, 'bad'); }
  });
  $('#importFile').addEventListener('change', async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    if (isDirty() && !confirm('저장하지 않은 변경이 있습니다. 가져오기 후 목록을 다시 읽으면 사라집니다. 계속할까요?')) return;
    let data;
    try { data = JSON.parse((await file.text()).replace(/^\uFEFF/, '')); } catch (err) { showMessage('가져오기 실패', `<p>JSON 형식이 아닙니다.</p><p class="muted">${esc(err.message)}</p>`); return; }
    const what = Array.isArray(data) ? `과목 ${data.length}개` : data.courses ? `과목 ${data.courses.length}개${data.workbooks ? ` + 문제집 ${data.workbooks.length}개` : ''}` : data.subjectId ? `과목 “${data.subject || data.subjectId}” (문항 ${(data.problems || []).length}개)` : data.workbooks ? `문제집 ${data.workbooks.length}개` : '알 수 없는 형식';
    if (!confirm(`${file.name}\n${what}\n\n같은 id 는 덮어쓰고, 새 id 는 추가합니다. 가져올까요?`)) return;
    try {
      const r = await api.post('/api/admin/import', data);
      st.dirty = st.pDirty = st.wbDirty = false;
      await loadCourses();
      await loadWorkbooks();
      const first = r.courses[0];
      if (first) await selectCourse(first.id, { force: true }); else if (st.courseId) await selectCourse(st.courseId, { force: true }); else renderAll();
      showMessage('가져오기 완료', `<ul class="result-list">${r.courses.map((c) => `<li><b>${esc(c.id)}</b> — ${c.created ? '새 과목' : '기존 과목'} · 추가 ${c.added} · 덮어씀 ${c.updated} · 전체 ${c.total}문항</li>`).join('')}${r.workbooks ? `<li>문제집 — 추가 ${r.workbooks.added} · 덮어씀 ${r.workbooks.updated} · 전체 ${r.workbooks.total}개</li>` : ''}</ul>${(r.warnings || []).length ? `<p class="muted">주의 ${r.warnings.length}건</p><div class="msg-errors">${issueHtml(r.warnings.slice(0, 50), 'warn')}</div>` : ''}`);
    } catch (err) {
      const errs = (err.data && err.data.errors) || [];
      showMessage('가져오기 실패 — 아무것도 바뀌지 않았습니다', `<p>${esc(err.message)}</p><div class="msg-errors">${issueHtml(errs.slice(0, 100))}${errs.length > 100 ? `<p class="muted">… 외 ${errs.length - 100}건</p>` : ''}</div>`);
    }
  });
  $('#btnLogout').addEventListener('click', async () => {
    if (!confirm('관리자 키를 다시 입력할까요?')) return;
    api.key = '';
    await askKey();
    toast('키를 바꿨습니다');
  });

  // ───────────────────────── LaTeX 도움말 ─────────────────────────
  const SNIPPETS = [
    ['분수 · 루트 · 지수', [
      ['분수', '\\frac{▮}{}', '\\frac{a}{b}'], ['루트', '\\sqrt{▮}', '\\sqrt{x}'], ['n제곱근', '\\sqrt[3]{▮}', '\\sqrt[3]{x}'],
      ['지수', '^{▮}', 'x^{2}'], ['아래첨자', '_{▮}', 'x_{1}'], ['곱하기', '\\times ', '\\times'], ['나누기', '\\div ', '\\div'],
      ['점 곱', '\\cdot ', '\\cdot'], ['±', '\\pm ', '\\pm'],
    ]],
    ['비교 · 기호', [
      ['≤', '\\le ', '\\le'], ['≥', '\\ge ', '\\ge'], ['≠', '\\ne ', '\\ne'], ['≈', '\\approx ', '\\approx'],
      ['→', '\\to ', '\\to'], ['∞', '\\infty', '\\infty'], ['각도', '^\\circ', '30^\\circ'], ['절댓값', '\\left|▮\\right|', '|x|'],
      ['괄호', '\\left(▮\\right)', '\\left(\\frac{a}{b}\\right)'],
    ]],
    ['물리 · 단위', [
      ['벡터', '\\vec{▮}', '\\vec{F}'], ['m/s', '\\,\\text{m/s}', '3\\,\\text{m/s}'], ['m/s²', '\\,\\text{m/s}^2', '\\text{m/s}^2'],
      ['N', '\\,\\text{N}', '\\text{N}'], ['J', '\\,\\text{J}', '\\text{J}'], ['kg', '\\,\\text{kg}', '\\text{kg}'], ['Ω', '\\,\\Omega', '\\Omega'],
      ['단위 직접', '\\,\\text{▮}', '\\text{unit}'], ['Δ', '\\Delta ', '\\Delta t'],
    ]],
    ['그리스 문자', [
      ['θ', '\\theta', '\\theta'], ['α', '\\alpha', '\\alpha'], ['β', '\\beta', '\\beta'], ['λ', '\\lambda', '\\lambda'], ['ω', '\\omega', '\\omega'],
      ['π', '\\pi', '\\pi'], ['μ', '\\mu', '\\mu'], ['ρ', '\\rho', '\\rho'], ['σ', '\\sigma', '\\sigma'],
    ]],
    ['함수 · 미적분', [
      ['sin', '\\sin ', '\\sin\\theta'], ['cos', '\\cos ', '\\cos\\theta'], ['log', '\\log_{▮}', '\\log_{2}x'], ['lim', '\\lim_{x \\to ▮}', '\\lim_{x\\to 0}'],
      ['Σ', '\\sum_{k=1}^{n} ', '\\sum_{k=1}^{n}'], ['∫', '\\int_{▮}^{} ', '\\int_{a}^{b}'], ['선분', '\\overline{▮}', '\\overline{AB}'],
    ]],
  ];
  const MARKUP = [
    ['수식 $…$', '$▮$'], ['굵게', '**▮**'], ['밑줄', '__▮__'], ['글자 $', '\\$'],
    ['표', '\n| 구분 | A | B |\n|---|---|---|\n| ▮ |  |  |\n'], ['㉠', '㉠'], ['㉡', '㉡'], ['㉢', '㉢'], ['ㄱ. ', 'ㄱ. '],
  ];
  function renderLatexPanel() {
    $('#latexGroups').innerHTML = SNIPPETS.map(([title, items], gi) => `<div class="lp-group"><h4>${title}</h4><div class="lp-btns">${items.map(([label, , demo], i) => `<button data-snip="${gi}:${i}" title="${esc(label)}">${mathHtml(demo)}<small>${esc(label)}</small></button>`).join('')}</div></div>`).join('')
      + `<div class="lp-group"><h4>표기법</h4><div class="lp-btns">${MARKUP.map(([label], i) => `<button data-mk="${i}">${esc(label)}</button>`).join('')}</div></div>`;
  }
  function toggleLatex(force) {
    const p = $('#latexPanel');
    p.hidden = force === undefined ? !p.hidden : !force;
    if (!p.hidden) renderLatexPanel();
  }
  $('#btnLatex').addEventListener('click', () => toggleLatex());
  $('#latexClose').addEventListener('click', () => toggleLatex(false));
  document.addEventListener('focusin', (e) => {
    const t = e.target;
    if ((t.tagName === 'TEXTAREA' && !t.matches('[data-tpl]')) || (t.tagName === 'INPUT' && (t.type === 'text' || !t.getAttribute('type')) && !t.matches('[data-taginput], [data-f=id], [data-pf=id], [data-wf=id], #search'))) st.lastField = t;
  });
  $('#latexPanel').addEventListener('mousedown', (e) => { if (e.target.closest('button[data-snip], button[data-mk]')) e.preventDefault(); });
  $('#latexPanel').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-snip], button[data-mk]');
    if (!b) return;
    if (b.dataset.snip) {
      const [g, i] = b.dataset.snip.split(':').map(Number);
      insertSnippet(SNIPPETS[g][1][i][1], true);
    } else insertSnippet(MARKUP[Number(b.dataset.mk)][1], false);
  });
  function insertSnippet(snip, isMath) {
    const el = st.lastField;
    if (!el || !document.body.contains(el)) { toast('먼저 문제 본문 같은 입력 칸을 누르세요'); return; }
    const v = el.value;
    const a = el.selectionStart;
    const b = el.selectionEnd;
    const sel = v.slice(a, b);
    let text = snip;
    if (isMath && S.countDollars(v.slice(0, a)) % 2 === 0) text = '$' + text + '$';
    const mark = text.indexOf('▮');
    text = text.replace('▮', sel).replace(/▮/g, '');
    el.focus();
    el.setRangeText(text, a, b, 'end');
    if (mark >= 0) {
      const caret = a + mark + sel.length;
      el.setSelectionRange(sel ? a + mark : caret, caret);
    }
    el.dispatchEvent(new Event('input', { bubbles: true }));
  }

  // ───────────────────────── 커뮤니티 관리 ─────────────────────────
  // API: docs/community-api.md (관리: /api/admin/community/…). 학생 userId 는 서버가 내보내지 않는다.
  const BOARD_NAMES = {
    free: '자유', qna: '질문', proof: '공부인증', info: '입시정보', mind: '고민·멘탈', tips: '공부법·꿀팁', study: '스터디 모집',
    naesin: '내신', suneung: '수능·모의고사', math: '수학', sci: '과학', lang: '국어·영어', soc: '사회탐구', sisi: '수시·정시',
    nsu: 'N수·재수', apt: '인적성·NCS', job: '취업정보', hyu: '한양대 라운지', univmath: '공업수학·미분적분학', univexam: '시험·학점',
    transfer: '편입정보', trmath: '편입수학',
  };
  const CM_PAGE = 50;
  const cm = { reports: [], posts: [], q: '', open: new Set(), more: false, loaded: false };

  function fmtTime(ms) {
    if (!ms) return '';
    const diff = Date.now() - ms;
    if (diff < 60000) return '방금';
    if (diff < 3600000) return `${Math.floor(diff / 60000)}분 전`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}시간 전`;
    const d = new Date(ms);
    const p2 = (n) => String(n).padStart(2, '0');
    const y = d.getFullYear() !== new Date().getFullYear() ? `${d.getFullYear()}년 ` : '';
    return `${y}${d.getMonth() + 1}월 ${d.getDate()}일 ${p2(d.getHours())}:${p2(d.getMinutes())}`;
  }
  async function loadCommunity() {
    try {
      const [r, p] = await Promise.all([
        api.get('/api/admin/community/reports'),
        api.get(`/api/admin/community/posts?limit=${CM_PAGE}${cm.q ? '&q=' + encodeURIComponent(cm.q) : ''}`),
      ]);
      cm.reports = r.posts;
      cm.posts = p.posts;
      cm.total = p.total;
      cm.more = p.posts.length >= CM_PAGE;
      cm.loaded = true;
      renderCommunity();
    } catch (e) { toast(e.message, 'bad'); }
  }
  async function loadMorePosts() {
    const last = cm.posts[cm.posts.length - 1];
    if (!last) return;
    try {
      const p = await api.get(`/api/admin/community/posts?limit=${CM_PAGE}&before=${last.createdAt}${cm.q ? '&q=' + encodeURIComponent(cm.q) : ''}`);
      cm.posts = cm.posts.concat(p.posts);
      cm.more = p.posts.length >= CM_PAGE;
      renderCommunity();
    } catch (e) { toast(e.message, 'bad'); }
  }
  function cmCard(p, mode) {
    const open = cm.open.has(p.id);
    const who = `${esc(p.author)}${p.grade ? ' · ' + esc(p.grade) : ''} · ${fmtTime(p.createdAt)}`;
    const badges = `<span class="badge">${esc(BOARD_NAMES[p.board] || p.board)}</span>`
      + (p.hidden ? '<span class="badge bad">숨김</span>' : '')
      + (p.reportCount ? `<span class="badge warn">신고 ${p.reportCount}</span>` : '')
      + (p.problemId ? `<span class="badge lvl" title="연결된 문제">${esc(p.problemId)}</span>` : '');
    const reasons = mode === 'report' && p.reports.length
      ? `<ul class="cm-reasons">${p.reports.map((r) => `<li><b>${esc(r.reason)}</b><span>${fmtTime(r.at)}</span></li>`).join('')}</ul>` : '';
    const comments = open
      ? `<ul class="cm-comments">${p.comments.map((c) => `<li><div><div class="cm-meta">${esc(c.author)}${c.grade ? ' · ' + esc(c.grade) : ''} · ${fmtTime(c.createdAt)}</div><p>${esc(c.body)}</p></div>
          <button class="btn small ghost danger" data-cm="cdel" data-cid="${esc(c.id)}">삭제</button></li>`).join('') || '<li class="muted">댓글이 없습니다.</li>'}</ul>` : '';
    const actions = (mode === 'report'
      ? `<button class="btn small" data-cm="restore" title="숨김을 풀고 신고 기록을 지웁니다">복구</button>` : '')
      + `<button class="btn small" data-cm="toggle">${open ? '접기' : `댓글 ${p.comments.length}`}</button>`
      + `<button class="btn small danger" data-cm="del">삭제</button>`;
    return `<article class="cm-card ${p.hidden ? 'is-hidden' : ''}" data-pid="${esc(p.id)}">
      <div class="cm-meta">${badges}<span class="who">${who}</span></div>
      <h3>${esc(p.title)}</h3>
      <p class="cm-body ${open ? '' : 'clamp'}">${esc(p.body)}</p>
      ${reasons}${comments}
      <div class="cm-foot"><span class="cm-stats">좋아요 ${p.likes} · 댓글 ${p.comments.length} · 조회 ${p.views}</span>${actions}</div>
    </article>`;
  }
  function renderCommunity() {
    const hiddenN = cm.reports.filter((p) => p.hidden).length;
    $('#cmReportCount').textContent = cm.reports.length ? `${cm.reports.length}개 · 숨김 ${hiddenN}` : '';
    $('#cmReports').innerHTML = cm.reports.map((p) => cmCard(p, 'report')).join('')
      || '<div class="empty">신고된 글이 없습니다.</div>';
    $('#cmPostCount').textContent = cm.loaded ? (cm.q ? `검색 결과 ${cm.posts.length}${cm.more ? '+' : ''}개` : `전체 ${cm.total || 0}개`) : '';
    $('#cmPosts').innerHTML = cm.posts.map((p) => cmCard(p, 'post')).join('')
      || `<div class="empty">${cm.q ? '검색 결과가 없습니다.' : '아직 글이 없습니다.'}</div>`;
    $('#cmMore').hidden = !cm.more;
  }
  function cmFind(id) {
    return cm.reports.find((p) => p.id === id) || cm.posts.find((p) => p.id === id);
  }
  $('#communityPane').addEventListener('click', async (e) => {
    const b = e.target.closest('[data-cm]');
    if (!b) return;
    const card = b.closest('[data-pid]');
    const id = card.dataset.pid;
    const p = cmFind(id);
    if (!p) return;
    const act = b.dataset.cm;
    try {
      if (act === 'toggle') {
        if (cm.open.has(id)) cm.open.delete(id); else cm.open.add(id);
        renderCommunity();
        return;
      }
      if (act === 'restore') {
        await api.post(`/api/admin/community/posts/${encodeURIComponent(id)}/restore`, {});
        toast(p.hidden ? '글을 다시 보이게 했습니다' : '신고 기록을 지웠습니다', 'good');
      } else if (act === 'del') {
        if (!confirm(`"${p.title}" 글을 삭제할까요?\n댓글도 함께 지워지고 되돌릴 수 없습니다.`)) return;
        await api.del(`/api/admin/community/posts/${encodeURIComponent(id)}`);
        toast('글을 삭제했습니다');
      } else if (act === 'cdel') {
        const c = p.comments.find((x) => x.id === b.dataset.cid);
        if (!c || !confirm(`${c.author} 님의 댓글을 삭제할까요?\n\n${c.body.slice(0, 120)}`)) return;
        await api.del(`/api/admin/community/posts/${encodeURIComponent(id)}/comments/${encodeURIComponent(c.id)}`);
        toast('댓글을 삭제했습니다');
      }
      await loadCommunity();
    } catch (err) {
      toast(err.message, 'bad');
      if (err.status === 404) loadCommunity();
    }
  });
  $('#cmRefresh').addEventListener('click', () => loadCommunity().then(() => toast('새로 고쳤습니다')));
  $('#cmMore').addEventListener('click', loadMorePosts);
  $('#cmSearch').addEventListener('input', debounce((e) => { cm.q = e.target.value.trim(); loadCommunity(); }, 250));

  // ───────────────────────── 시작 ─────────────────────────
  async function start() {
    if (!api.key) await askKey();
    try {
      await loadCourses();
    } catch (e) {
      showMessage('서버 오류', `<p>${esc(e.message)}</p>`);
      return;
    }
    await loadWorkbooks().catch((e) => toast(e.message, 'bad'));
    const want = st.courseId && st.courses.some((c) => c.id === st.courseId) ? st.courseId : st.courses[0] && st.courses[0].id;
    showView();
    if (want) await selectCourse(want, { force: true });
    else renderAll();
    if (st.view === 'community') loadCommunity();
  }
  // KaTeX 가 늦게 오면 다시 그린다
  window.addEventListener('load', () => { if (st.draft || st.pDraft || st.wbSel != null) renderPreview(); if (!$('#latexPanel').hidden) renderLatexPanel(); });
  start();
})();
