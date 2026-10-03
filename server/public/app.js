/* 풀이노트 · 선생님 대시보드 (빌드 없이 동작하는 순수 JS) */
'use strict';

(() => {
  // ───────────────────────── 상수 ─────────────────────────
  const PAGE_W = 1000; // 논리 페이지 폭
  const GRID = 40; // 모눈 간격 (논리 좌표)
  const HIGHLIGHTER_ALPHA = 0.32;
  const WRITING_MS = 1600; // 마지막 필기 후 이 시간 동안 "쓰는 중" 표시
  const MAX_HISTORY = 200;
  const CIRCLED = ['①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨', '⑩'];

  // ───────────────────────── 상태 ─────────────────────────
  /** studentId → 학생 */
  const students = new Map();
  let ws = null;
  let attempt = 0;
  let reconnectTimer = null;
  let lastRecvAt = 0;
  let focusId = null;
  let msgSeq = 0;
  const pendingMsgs = new Map(); // clientId → {name}

  const $ = (sel, root = document) => root.querySelector(sel);
  const el = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  };

  function makeStudent(raw) {
    const strokes = new Map();
    for (const s of raw.strokes || []) strokes.set(String(s.id), normStroke(s, true));
    return {
      studentId: raw.studentId,
      name: raw.name || raw.studentId,
      device: raw.device || '',
      online: !!raw.online,
      page: raw.page || null,
      strokes,
      lastAnswer: raw.lastAnswer || null,
      stats: raw.stats || null,
      history: Array.isArray(raw.history) ? raw.history : [],
      lastSeen: raw.lastSeen || null,
      writingAt: 0,
      lastY: lastPointY(strokes),
      views: new Set(),
      tile: null,
    };
  }
  function normStroke(s, done) {
    return {
      id: String(s.id),
      tool: s.tool === 'highlighter' ? 'highlighter' : 'pen',
      color: typeof s.color === 'string' ? s.color : '#1B2333',
      width: Number(s.width) > 0 ? Number(s.width) : 3,
      points: Array.isArray(s.points) ? s.points.slice() : [],
      done: done || !!s.done,
    };
  }
  function lastPointY(strokes) {
    let last = null;
    for (const s of strokes.values()) last = s;
    if (!last || !last.points.length) return null;
    return last.points[last.points.length - 1][1];
  }
  function getStudent(id, name) {
    let st = students.get(id);
    if (!st) {
      st = makeStudent({ studentId: id, name });
      students.set(id, st);
    }
    return st;
  }

  // ───────────────────────── 캔버스 뷰 ─────────────────────────
  const dirtyViews = new Set();
  let rafId = 0;
  function schedule(view) {
    dirtyViews.add(view);
    if (!rafId) rafId = requestAnimationFrame(frame);
  }
  function frame() {
    rafId = 0;
    const list = Array.from(dirtyViews);
    dirtyViews.clear();
    for (const v of list) v.render();
  }

  class SheetView {
    /**
     * @param {HTMLCanvasElement} canvas
     * @param {HTMLElement} wrap   크기 기준이 되는 요소
     * @param {{onScroll?:Function, idleEl?:HTMLElement}} opts
     */
    constructor(canvas, wrap, opts = {}) {
      this.canvas = canvas;
      this.ctx = canvas.getContext('2d');
      this.wrap = wrap;
      this.opts = opts;
      this.student = null;
      this.offsetY = 0; // 논리 좌표 기준 스크롤 위치
      this.follow = true;
      this.cssW = 0;
      this.cssH = 0;
      this.dpr = 1;
      this.full = true;
      this.pending = new Set();
      this.drawn = new Map(); // strokeId → 그려진 조각 수
      this.ro = new ResizeObserver(() => this.resize());
      this.ro.observe(wrap);
    }
    setStudent(st) {
      if (this.student) this.student.views.delete(this);
      this.student = st;
      if (st) st.views.add(this);
      this.offsetY = 0;
      this.follow = true;
      this.snapToLatest();
      this.invalidate();
    }
    destroy() {
      this.ro.disconnect();
      if (this.student) this.student.views.delete(this);
      dirtyViews.delete(this);
      this.student = null;
    }
    get k() { return this.cssW / PAGE_W; } // css px per logical unit
    get viewH() { return this.k > 0 ? this.cssH / this.k : 0; } // 보이는 높이 (논리)
    contentH() {
      const st = this.student;
      let h = st && st.page ? Number(st.page.pageHeight) || 0 : 0;
      if (st) for (const s of st.strokes.values()) {
        const p = s.points[s.points.length - 1];
        if (p && p[1] + 60 > h) h = p[1] + 60;
      }
      return Math.max(h, this.viewH);
    }
    maxOffset() { return Math.max(0, this.contentH() - this.viewH); }
    resize() {
      const r = this.wrap.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 3);
      const w = Math.max(1, Math.round(r.width));
      const h = Math.max(1, Math.round(r.height));
      if (w === this.cssW && h === this.cssH && dpr === this.dpr) return;
      this.cssW = w; this.cssH = h; this.dpr = dpr;
      this.canvas.width = Math.round(w * dpr);
      this.canvas.height = Math.round(h * dpr);
      if (this.follow) this.snapToLatest();
      this.offsetY = Math.min(this.offsetY, this.maxOffset());
      this.invalidate();
    }
    invalidate() { this.full = true; this.pending.clear(); schedule(this); }
    touch(strokeId) {
      if (this.full) return schedule(this);
      this.pending.add(strokeId);
      schedule(this);
    }
    /** 최신 필기가 화면 밖으로 나가면 따라간다. 위치가 바뀌면 true */
    followTo(y) {
      if (!this.follow || y == null || !this.viewH) return false;
      const vh = this.viewH;
      if (y > this.offsetY + vh * 0.88 || y < this.offsetY + vh * 0.04) {
        const next = clamp(y - vh * 0.45, 0, Math.max(0, this.contentH() - vh));
        if (Math.abs(next - this.offsetY) > 1) { this.offsetY = next; return true; }
      }
      return false;
    }
    snapToLatest() {
      const st = this.student;
      this.offsetY = 0;
      if (st && st.lastY != null) this.followTo(st.lastY);
    }
    scrollBy(dy) {
      this.follow = false;
      const next = clamp(this.offsetY + dy, 0, this.maxOffset());
      if (next !== this.offsetY) { this.offsetY = next; this.invalidate(); }
      if (this.opts.onFollowChange) this.opts.onFollowChange(false);
    }
    setFollow(on) {
      this.follow = on;
      if (on) { this.snapToLatest(); this.invalidate(); }
    }

    render() {
      const st = this.student;
      if (!this.cssW || !this.cssH) return;
      if (this.dpr !== Math.min(window.devicePixelRatio || 1, 3)) { this.cssW = 0; this.resize(); return; }
      const ctx = this.ctx;
      const s = this.dpr * this.k;
      if (this.full || !st) {
        this.full = false;
        this.pending.clear();
        this.drawn.clear();
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.fillStyle = '#FFFFFF';
        ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
        ctx.setTransform(s, 0, 0, s, 0, -this.offsetY * s);
        this.drawPaper(ctx, s);
        if (st) {
          // 형광펜을 먼저(아래), 펜을 나중에(위)
          for (const stroke of st.strokes.values()) if (stroke.tool === 'highlighter') drawHighlighter(ctx, stroke);
          for (const stroke of st.strokes.values()) {
            if (stroke.tool === 'highlighter') continue;
            const n = stroke.points.length;
            drawPen(ctx, stroke, 0, n, s); // 꼬리까지 모두
            this.drawn.set(stroke.id, stroke.done ? n : Math.max(0, n - 1));
          }
        }
      } else if (this.pending.size) {
        ctx.setTransform(s, 0, 0, s, 0, -this.offsetY * s);
        for (const id of this.pending) {
          const stroke = st.strokes.get(id);
          if (!stroke || stroke.tool === 'highlighter') continue;
          const n = stroke.points.length;
          const avail = stroke.done ? n : Math.max(0, n - 1);
          const from = this.drawn.get(id) || 0;
          if (avail > from) {
            drawPen(ctx, stroke, from, avail, s);
            this.drawn.set(id, avail);
          }
        }
        this.pending.clear();
      }
      if (this.opts.idleEl) this.opts.idleEl.hidden = !!(st && st.strokes.size);
      if (this.opts.onScroll) this.opts.onScroll(this);
    }

    drawPaper(ctx, s) {
      const top = this.offsetY;
      const bottom = this.offsetY + this.viewH;
      const pageH = this.student && this.student.page ? Number(this.student.page.pageHeight) || 0 : 0;
      ctx.lineWidth = 1 / s;
      ctx.strokeStyle = '#EDF0F4';
      ctx.beginPath();
      for (let x = GRID; x < PAGE_W; x += GRID) { ctx.moveTo(x, top); ctx.lineTo(x, bottom); }
      for (let y = Math.ceil(top / GRID) * GRID; y < bottom; y += GRID) { ctx.moveTo(0, y); ctx.lineTo(PAGE_W, y); }
      ctx.stroke();
      // 페이지 끝 아래는 책상 색으로
      if (pageH && pageH < bottom && pageH >= this.viewH) {
        ctx.fillStyle = '#F3F4F6';
        ctx.fillRect(0, pageH, PAGE_W, bottom - pageH);
        ctx.strokeStyle = '#D3D9E2';
        ctx.beginPath(); ctx.moveTo(0, pageH); ctx.lineTo(PAGE_W, pageH); ctx.stroke();
      }
    }
  }

  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

  /**
   * 펜 획을 조각 단위로 그린다 (중점 이차곡선 보간).
   * n개의 점 → 조각 0..n-1
   *   0       : p0 → m0 (직선)
   *   i       : m(i-1) → m(i)  제어점 p(i)
   *   n-1     : m(n-2) → p(n-1) (꼬리)
   */
  function drawPen(ctx, stroke, from, to, s) {
    const pts = stroke.points;
    const n = pts.length;
    if (!n) return;
    const base = stroke.width;
    const minW = 1 / s; // 최소 1 기기 픽셀
    ctx.strokeStyle = stroke.color;
    ctx.fillStyle = stroke.color;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.globalAlpha = 1;
    const wOf = (p) => Math.max(minW, base * (0.35 + 0.65 * (p == null ? 0.5 : p)));
    if (n === 1) {
      if (from === 0 && to >= 1) {
        const r = wOf(pts[0][2]) / 2;
        ctx.beginPath(); ctx.arc(pts[0][0], pts[0][1], r, 0, Math.PI * 2); ctx.fill();
      }
      return;
    }
    const mid = (i) => [(pts[i][0] + pts[i + 1][0]) / 2, (pts[i][1] + pts[i + 1][1]) / 2];
    for (let i = from; i < to && i < n; i++) {
      ctx.beginPath();
      if (i === 0) {
        const m = mid(0);
        ctx.lineWidth = wOf((pts[0][2] + pts[1][2]) / 2);
        ctx.moveTo(pts[0][0], pts[0][1]);
        ctx.lineTo(m[0], m[1]);
      } else if (i === n - 1) {
        const m = mid(n - 2);
        ctx.lineWidth = wOf(pts[n - 1][2]);
        ctx.moveTo(m[0], m[1]);
        ctx.lineTo(pts[n - 1][0], pts[n - 1][1]);
      } else {
        const a = mid(i - 1);
        const b = mid(i);
        ctx.lineWidth = wOf(pts[i][2]);
        ctx.moveTo(a[0], a[1]);
        ctx.quadraticCurveTo(pts[i][0], pts[i][1], b[0], b[1]);
      }
      ctx.stroke();
    }
  }

  function drawHighlighter(ctx, stroke) {
    const pts = stroke.points;
    const n = pts.length;
    if (!n) return;
    ctx.save();
    ctx.globalAlpha = HIGHLIGHTER_ALPHA;
    ctx.strokeStyle = stroke.color;
    ctx.fillStyle = stroke.color;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.lineWidth = Math.max(8, stroke.width);
    ctx.beginPath();
    if (n === 1) {
      ctx.arc(pts[0][0], pts[0][1], ctx.lineWidth / 2, 0, Math.PI * 2);
      ctx.fill();
    } else {
      ctx.moveTo(pts[0][0], pts[0][1]);
      for (let i = 1; i < n - 1; i++) {
        const mx = (pts[i][0] + pts[i + 1][0]) / 2;
        const my = (pts[i][1] + pts[i + 1][1]) / 2;
        ctx.quadraticCurveTo(pts[i][0], pts[i][1], mx, my);
      }
      ctx.lineTo(pts[n - 1][0], pts[n - 1][1]);
      ctx.stroke();
    }
    ctx.restore();
  }

  // 학생 필기 변화 → 그 학생을 보는 모든 뷰에 알림
  function strokesChanged(st, strokeId, needFull) {
    for (const v of st.views) {
      const moved = v.followTo(st.lastY);
      if (needFull || moved) v.invalidate();
      else v.touch(strokeId);
    }
  }
  function strokesReset(st) {
    st.lastY = lastPointY(st.strokes);
    for (const v of st.views) {
      if (v.follow) v.snapToLatest();
      else v.offsetY = Math.min(v.offsetY, v.maxOffset());
      v.invalidate();
    }
  }

  // ───────────────────────── 학생 타일 ─────────────────────────
  const grid = $('#grid');
  const tileTpl = $('#tileTpl');

  function ensureTile(st) {
    if (st.tile) return st.tile;
    const node = tileTpl.content.firstElementChild.cloneNode(true);
    node.dataset.id = st.studentId;
    const sheet = $('.sheet', node);
    const tile = {
      node,
      dot: $('.dot', node),
      name: $('.tile-name', node),
      device: $('.tile-device', node),
      problem: $('.tile-problem', node),
      badge: $('.badge', node),
      time: $('.tile-time', node),
      view: new SheetView($('canvas', node), sheet, { idleEl: $('.sheet-idle', node) }),
      lastAnswerAt: null,
    };
    tile.view.setStudent(st);
    node.addEventListener('click', () => openFocus(st.studentId));
    node.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openFocus(st.studentId); }
    });
    st.tile = tile;
    return tile;
  }

  function removeTile(st) {
    if (!st.tile) return;
    st.tile.view.destroy();
    st.tile.node.remove();
    st.tile = null;
  }

  function isToday(ts) {
    if (!ts) return false;
    const d = new Date(ts);
    const n = new Date();
    return d.getFullYear() === n.getFullYear() && d.getMonth() === n.getMonth() && d.getDate() === n.getDate();
  }

  /** 실시간 화면에 보일 학생: 접속 중이거나 오늘 접속했던 학생 */
  function visibleOnLive(st) {
    return st.online || isToday(st.lastSeen) || (st.page && st.strokes.size > 0);
  }

  function answerLabel(st, a) {
    if (!a) return '';
    const ans = String(a.answer ?? '');
    const page = st.page;
    if (page && page.problemId === a.problemId && Array.isArray(page.choices) && /^\d+$/.test(ans)) {
      const i = Number(ans) - 1;
      if (i >= 0 && i < CIRCLED.length) return CIRCLED[i];
    }
    return ans;
  }

  function fillBadge(badge, st, a) {
    badge.textContent = '';
    badge.className = 'badge';
    if (!a) {
      badge.classList.add('none');
      badge.textContent = '아직 제출 없음';
      return;
    }
    badge.classList.add(a.correct ? 'good' : 'bad');
    badge.append(a.correct ? '정답' : '오답');
    const ans = answerLabel(st, a);
    if (ans) badge.append(' ', el('span', 'ans', ans));
  }

  function updateTile(st, opts = {}) {
    const t = ensureTile(st);
    t.dot.className = 'dot' + (st.online ? ' on' : '');
    t.dot.title = st.online ? '접속 중' : '접속 안 함';
    t.name.textContent = st.name;
    t.device.textContent = st.device || '';
    t.node.classList.toggle('is-offline', !st.online);
    t.node.setAttribute('aria-label', `${st.name} 크게 보기`);
    t.problem.textContent = '';
    if (st.page && (st.page.title || st.page.problemId)) {
      t.problem.textContent = st.page.title || st.page.problemId;
      t.problem.title = t.problem.textContent;
    } else {
      t.problem.append(el('span', 'none', st.online ? '문제를 고르는 중' : '접속하지 않았어요'));
    }
    fillBadge(t.badge, st, st.lastAnswer);
    if (opts.pop) {
      t.badge.classList.remove('pop');
      void t.badge.offsetWidth;
      t.badge.classList.add('pop');
    }
    t.time.textContent = st.lastAnswer ? relTime(st.lastAnswer.at) : '';
    t.time.title = st.lastAnswer && st.lastAnswer.at ? fmtWhen(st.lastAnswer.at) : '';
  }

  function sortedStudents() {
    return Array.from(students.values()).sort((a, b) =>
      (b.online - a.online) || a.name.localeCompare(b.name, 'ko') || a.studentId.localeCompare(b.studentId));
  }

  function layoutGrid() {
    const list = sortedStudents();
    let shown = 0;
    let prev = null;
    for (const st of list) {
      if (!visibleOnLive(st)) { removeTile(st); continue; }
      updateTile(st);
      const node = st.tile.node;
      const want = prev ? prev.nextSibling : grid.firstChild;
      if (node !== want) grid.insertBefore(node, want);
      prev = node;
      shown++;
    }
    $('#emptyLive').hidden = shown > 0;
    if (!shown) loadAddresses();
    updateCounts();
  }

  function updateCounts() {
    let on = 0;
    for (const st of students.values()) if (st.online) on++;
    $('#onlineCount').textContent = students.size ? `접속 ${on}명 / ${students.size}명` : '접속 0명';
  }

  // 쓰는 중 표시 · 상대 시간 갱신
  setInterval(() => {
    const now = Date.now();
    for (const st of students.values()) {
      if (!st.tile) continue;
      st.tile.node.classList.toggle('is-writing', st.online && now - st.writingAt < WRITING_MS);
    }
  }, 400);
  setInterval(() => {
    for (const st of students.values()) if (st.tile && st.lastAnswer) st.tile.time.textContent = relTime(st.lastAnswer.at);
  }, 30000);

  // ───────────────────────── 접속 주소 안내 ─────────────────────────
  let addrLoaded = false;
  function loadAddresses() {
    if (addrLoaded) return;
    addrLoaded = true;
    const list = $('#addrList');
    const local = /^(localhost|127\.|\[?::1\]?$)/.test(location.hostname);
    const render = (urls) => {
      list.textContent = '';
      for (const u of urls) {
        const li = el('li');
        li.append(el('span', null, u));
        const b = el('button', 'btn btn-ghost', '복사');
        b.type = 'button';
        b.addEventListener('click', () => copyText(u).then(() => toast('주소를 복사했어요')));
        li.append(b);
        list.append(li);
      }
    };
    if (!local) {
      render([`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws`]);
      return;
    }
    fetch('/api/info').then((r) => r.json()).then((info) => {
      if (info.wsUrls && info.wsUrls.length) render(info.wsUrls);
      else render([`ws://${location.host}/ws`]);
    }).catch(() => { addrLoaded = false; });
  }
  function copyText(t) {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(t);
    const ta = el('textarea');
    ta.value = t;
    ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.append(ta);
    ta.select();
    try { document.execCommand('copy'); } catch (_) { /* ignore */ }
    ta.remove();
    return Promise.resolve();
  }

  // ───────────────────────── 크게 보기 ─────────────────────────
  const focus = $('#focus');
  const followBtn = $('#followBtn');
  const focusThumb = $('#focusThumb');
  const focusView = new SheetView($('#focusCanvas'), $('#focusSheet'), {
    onScroll: (v) => {
      const total = v.contentH();
      const vh = v.viewH;
      const track = focusThumb.parentElement.clientHeight;
      if (!total || total <= vh + 1) { focusThumb.style.display = 'none'; return; }
      focusThumb.style.display = '';
      focusThumb.style.top = `${(v.offsetY / total) * track}px`;
      focusThumb.style.height = `${Math.max(24, (vh / total) * track)}px`;
    },
    onFollowChange: (on) => followBtn.setAttribute('aria-pressed', String(on)),
  });
  let lastFocusTrigger = null;

  function openFocus(id) {
    const st = students.get(id);
    if (!st) return;
    focusId = id;
    lastFocusTrigger = document.activeElement;
    focus.hidden = false;
    document.body.style.overflow = 'hidden';
    focusView.setStudent(st);
    followBtn.setAttribute('aria-pressed', 'true');
    renderFocus({ problem: true });
    focusView.resize();
    $('#msgInput').value = '';
    setTimeout(() => $('#msgInput').focus({ preventScroll: true }), 30);
  }
  function closeFocus() {
    focus.hidden = true;
    focusId = null;
    focusView.setStudent(null);
    document.body.style.overflow = '';
    if (lastFocusTrigger && lastFocusTrigger.focus) lastFocusTrigger.focus();
  }
  focus.addEventListener('click', (e) => { if (e.target.closest('[data-close]')) closeFocus(); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !focus.hidden) closeFocus(); });
  followBtn.addEventListener('click', () => {
    const on = followBtn.getAttribute('aria-pressed') !== 'true';
    followBtn.setAttribute('aria-pressed', String(on));
    focusView.setFollow(on);
  });

  // 휠 / 드래그로 페이지 위아래 보기
  const focusSheet = $('#focusSheet');
  focusSheet.addEventListener('wheel', (e) => {
    e.preventDefault();
    const k = focusView.k || 1;
    const dy = e.deltaMode === 1 ? e.deltaY * 16 : e.deltaMode === 2 ? e.deltaY * focusView.cssH : e.deltaY;
    focusView.scrollBy(dy / k);
  }, { passive: false });
  let drag = null;
  focusSheet.addEventListener('pointerdown', (e) => {
    drag = { y: e.clientY, id: e.pointerId };
    focusSheet.setPointerCapture(e.pointerId);
  });
  focusSheet.addEventListener('pointermove', (e) => {
    if (!drag || drag.id !== e.pointerId) return;
    const dy = drag.y - e.clientY;
    drag.y = e.clientY;
    if (dy) focusView.scrollBy(dy / (focusView.k || 1));
  });
  const endDrag = () => { drag = null; };
  focusSheet.addEventListener('pointerup', endDrag);
  focusSheet.addEventListener('pointercancel', endDrag);

  function renderMath(node) {
    if (typeof window.renderMathInElement !== 'function') return;
    try {
      window.renderMathInElement(node, {
        delimiters: [
          { left: '$$', right: '$$', display: true },
          { left: '$', right: '$', display: false },
        ],
        throwOnError: false,
      });
    } catch (_) { /* 수식이 깨져도 원문은 그대로 보인다 */ }
  }

  function renderFocus({ problem = false } = {}) {
    if (!focusId) return;
    const st = students.get(focusId);
    if (!st) return closeFocus();
    $('#focusName').textContent = st.name;
    $('#focusDot').className = 'dot' + (st.online ? ' on' : '');
    $('#focusDevice').textContent = st.online ? (st.device || '접속 중') : `접속 안 함${st.lastSeen ? ' (' + relTime(st.lastSeen) + ')' : ''}`;

    const a = st.lastAnswer && st.page && st.lastAnswer.problemId === st.page.problemId ? st.lastAnswer : null;
    if (problem) {
      const p = st.page;
      const meta = $('#focusMeta');
      const title = $('#focusTitle');
      const stem = $('#focusStem');
      const box = $('#focusBox');
      const choices = $('#focusChoices');
      meta.textContent = p ? [p.subject, p.unit, p.topic].filter(Boolean).join(' / ') || (p.problemId || '') : '';
      title.textContent = p ? (p.title || p.problemId || '') : '';
      stem.className = 'problem-stem';
      if (p && p.stem) {
        stem.textContent = p.stem;
        renderMath(stem);
      } else {
        stem.classList.add('none');
        stem.textContent = p ? '문제 본문이 없어요.' : '학생이 아직 문제를 열지 않았어요.';
      }
      box.textContent = '';
      box.hidden = !(p && Array.isArray(p.boxItems) && p.boxItems.length);
      if (!box.hidden) {
        for (const item of p.boxItems) box.append(el('li', null, item));
        renderMath(box);
      }
      choices.textContent = '';
      if (p && Array.isArray(p.choices)) {
        p.choices.forEach((c, i) => {
          const li = el('li');
          li.dataset.n = String(i + 1);
          li.append(el('span', 'num', CIRCLED[i] || String(i + 1)), el('span', 'txt', c));
          choices.append(li);
        });
        renderMath(choices);
      }
    }
    // 고른 선택지 표시
    for (const li of $('#focusChoices').children) {
      li.classList.remove('picked-good', 'picked-bad');
      if (a && String(a.answer) === li.dataset.n) li.classList.add(a.correct ? 'picked-good' : 'picked-bad');
    }
    // 마지막 제출
    const box = $('#focusAnswer');
    box.textContent = '';
    if (st.lastAnswer) {
      const la = st.lastAnswer;
      const badge = el('span');
      fillBadge(badge, st, la);
      box.append(badge);
      const same = st.page && la.problemId === st.page.problemId;
      const parts = [];
      if (!same) parts.push(`이전 문제 ${la.title || la.problemId}`);
      if (la.timeMs) parts.push(`${fmtDuration(la.timeMs)} 걸림`);
      if (la.at) parts.push(relTime(la.at));
      box.append(el('span', null, parts.join(', ')));
    }
  }

  $('#msgQuick').addEventListener('click', (e) => {
    const chip = e.target.closest('.chip');
    if (!chip) return;
    const input = $('#msgInput');
    input.value = chip.textContent;
    input.focus();
  });
  $('#msgForm').addEventListener('submit', (e) => {
    e.preventDefault();
    const input = $('#msgInput');
    const text = input.value.trim();
    if (!text || !focusId) return;
    const st = students.get(focusId);
    if (sendMessage(text, focusId, st ? st.name : '')) input.value = '';
  });

  function sendMessage(text, studentId, name) {
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      toast('서버와 연결이 끊겨 보내지 못했어요. 다시 연결되면 보내 주세요.', 'warn');
      return false;
    }
    const clientId = `m${++msgSeq}`;
    pendingMsgs.set(clientId, { name, studentId });
    const msg = { type: 'message', text, clientId };
    if (studentId) msg.studentId = studentId;
    ws.send(JSON.stringify(msg));
    return true;
  }

  // 전체 메시지
  const dlg = $('#broadcastDialog');
  $('#broadcastBtn').addEventListener('click', () => {
    let on = 0;
    for (const st of students.values()) if (st.online) on++;
    $('#broadcastSub').textContent = on
      ? `지금 접속한 학생 ${on}명의 화면에 알림으로 표시돼요.`
      : '지금 접속한 학생이 없어요. 학생이 접속한 뒤에 보내 주세요.';
    $('#broadcastText').value = '';
    if (typeof dlg.showModal === 'function') dlg.showModal(); else dlg.setAttribute('open', '');
    $('#broadcastText').focus();
  });
  $('#broadcastCancel').addEventListener('click', () => dlg.close());
  $('#broadcastForm').addEventListener('submit', (e) => {
    e.preventDefault();
    const text = $('#broadcastText').value.trim();
    if (!text) { $('#broadcastText').focus(); return; }
    if (sendMessage(text, null, '')) dlg.close();
  });
  $('#broadcastText').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) $('#broadcastForm').requestSubmit();
  });

  // ───────────────────────── 토스트 ─────────────────────────
  function toast(text, kind) {
    const t = el('div', 'toast' + (kind ? ' ' + kind : ''), text);
    $('#toasts').append(t);
    setTimeout(() => t.remove(), 3200);
  }

  // ───────────────────────── 기록 탭 ─────────────────────────
  const recordsBody = $('#recordsBody');
  const openRows = new Set();
  const historyLimit = new Map();
  let sortKey = 'name';
  let sortAsc = true;
  let recordsTimer = 0;

  function summary(st) {
    const h = st.history;
    const s = st.stats;
    const total = s ? s.total : h.length;
    const correct = s ? s.correct : h.filter((x) => x.correct).length;
    let streak = 0;
    if (s) streak = s.streak;
    else for (const x of h) { if (x.correct) streak++; else break; }
    const histToday = h.filter((x) => isToday(x.at)).length;
    const today = s && isToday(s.at) ? Math.max(s.todayCount, histToday) : histToday;
    return {
      total, correct, streak, today,
      acc: total ? correct / total : null,
      weak: s && Array.isArray(s.weakTopics) ? s.weakTopics : [],
      last: h.length ? h[0].at : null,
    };
  }

  function scheduleRecords() {
    if ($('#view-records').hidden) return;
    if (recordsTimer) return;
    recordsTimer = setTimeout(() => { recordsTimer = 0; renderRecords(); }, 250);
  }

  function renderRecords() {
    const rows = Array.from(students.values()).map((st) => ({ st, sum: summary(st) }));
    const dir = sortAsc ? 1 : -1;
    rows.sort((a, b) => {
      let d = 0;
      switch (sortKey) {
        case 'name': d = a.st.name.localeCompare(b.st.name, 'ko'); break;
        case 'acc': d = (a.sum.acc ?? -1) - (b.sum.acc ?? -1); break;
        case 'last': d = (a.sum.last || 0) - (b.sum.last || 0); break;
        default: d = (a.sum[sortKey] || 0) - (b.sum[sortKey] || 0);
      }
      return d * dir || a.st.name.localeCompare(b.st.name, 'ko');
    });
    for (const th of document.querySelectorAll('#recordsTable th[data-sort]')) {
      th.classList.toggle('sorted', th.dataset.sort === sortKey);
      th.classList.toggle('asc', th.dataset.sort === sortKey && sortAsc);
    }
    recordsBody.textContent = '';
    for (const { st, sum } of rows) {
      const tr = el('tr', 'row' + (openRows.has(st.studentId) ? ' open' : ''));
      tr.tabIndex = 0;
      tr.dataset.id = st.studentId;
      tr.setAttribute('aria-expanded', String(openRows.has(st.studentId)));

      const who = el('div', 'who');
      who.append(el('span', 'dot' + (st.online ? ' on' : '')), el('span', null, st.name));
      if (st.device) who.append(el('small', null, st.device));
      tr.append(td(who, 'col-name'));
      tr.append(td(String(sum.total), 'num'));

      const acc = el('div', 'acc');
      if (sum.acc == null) acc.append(el('span', 'muted', '—'));
      else {
        const bar = el('div', 'acc-bar');
        const fill = el('div', 'acc-fill');
        fill.style.width = `${Math.round(sum.acc * 100)}%`;
        bar.append(fill);
        acc.append(bar, el('span', 'acc-val', `${Math.round(sum.acc * 100)}%`));
      }
      tr.append(td(acc));
      tr.append(td(sum.streak ? `${sum.streak}개` : '0', 'num'));
      tr.append(td(String(sum.today), 'num'));
      const weak = el('div', 'weak');
      if (sum.weak.length) for (const w of sum.weak.slice(0, 4)) weak.append(el('span', 'tag', w));
      else weak.append(el('span', 'muted', '—'));
      tr.append(td(weak));
      tr.append(td(sum.last ? fmtWhen(sum.last) : '—', sum.last ? '' : 'muted'));
      const tog = el('span', 'toggle-ico', '›');
      tr.append(td(tog, 'col-toggle'));
      recordsBody.append(tr);

      if (openRows.has(st.studentId)) recordsBody.append(historyRow(st));
    }
    $('#emptyRecords').hidden = rows.length > 0;
    $('#recordsTable').parentElement.hidden = rows.length === 0;
    const totalSubs = rows.reduce((n, r) => n + r.sum.today, 0);
    $('#recordsSub').textContent = rows.length
      ? `학생 ${rows.length}명, 오늘 제출 ${totalSubs}개. 행을 누르면 최근 제출이 펼쳐져요.`
      : '제출할 때마다 자동으로 갱신돼요.';
  }

  function td(content, cls) {
    const c = el('td', cls);
    if (typeof content === 'string') c.textContent = content; else c.append(content);
    return c;
  }

  function historyRow(st) {
    const tr = el('tr', 'detail');
    const cell = el('td');
    cell.colSpan = 8;
    if (!st.history.length) {
      cell.append(el('p', 'muted', '아직 제출한 문제가 없어요.'));
      tr.append(cell);
      return tr;
    }
    const limit = historyLimit.get(st.studentId) || 20;
    const table = el('table', 'history');
    const head = el('tr');
    for (const h of ['문제', '제출한 답', '결과', '걸린 시간', '제출 시각']) head.append(el('th', null, h));
    const thead = el('thead');
    thead.append(head);
    const tbody = el('tbody');
    for (const h of st.history.slice(0, limit)) {
      const r = el('tr');
      const pid = el('span', 'pid', h.title || h.problemId);
      if (h.title && h.problemId) pid.append(el('small', null, h.problemId));
      r.append(td(pid));
      r.append(td(h.answer != null && h.answer !== '' ? String(h.answer) : '—'));
      const b = el('span', 'badge ' + (h.correct ? 'good' : 'bad'), h.correct ? '정답' : '오답');
      r.append(td(b));
      r.append(td(h.timeMs ? fmtDuration(h.timeMs) : '—'));
      r.append(td(h.at ? fmtWhen(h.at) : '—'));
      tbody.append(r);
    }
    table.append(thead, tbody);
    cell.append(table);
    if (st.history.length > limit) {
      const more = el('div', 'history-more');
      const btn = el('button', null, `더 보기 (${st.history.length - limit}개 남음)`);
      btn.type = 'button';
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        historyLimit.set(st.studentId, Math.min(MAX_HISTORY, limit + 40));
        renderRecords();
      });
      more.append(btn);
      cell.append(more);
    }
    tr.append(cell);
    return tr;
  }

  recordsBody.addEventListener('click', (e) => {
    const tr = e.target.closest('tr.row');
    if (!tr) return;
    const id = tr.dataset.id;
    if (openRows.has(id)) openRows.delete(id); else openRows.add(id);
    renderRecords();
  });
  recordsBody.addEventListener('keydown', (e) => {
    const tr = e.target.closest('tr.row');
    if (tr && (e.key === 'Enter' || e.key === ' ')) {
      e.preventDefault();
      tr.click();
      const again = recordsBody.querySelector(`tr.row[data-id="${CSS.escape(tr.dataset.id)}"]`);
      if (again) again.focus();
    }
  });
  for (const th of document.querySelectorAll('#recordsTable th[data-sort]')) {
    th.addEventListener('click', () => {
      const key = th.dataset.sort;
      if (sortKey === key) sortAsc = !sortAsc;
      else { sortKey = key; sortAsc = key === 'name'; }
      renderRecords();
    });
  }

  // ───────────────────────── 탭 ─────────────────────────
  for (const tab of document.querySelectorAll('.tab')) {
    tab.addEventListener('click', () => showTab(tab.dataset.tab));
  }
  function showTab(name) {
    for (const tab of document.querySelectorAll('.tab')) {
      const on = tab.dataset.tab === name;
      tab.classList.toggle('is-active', on);
      tab.setAttribute('aria-selected', String(on));
    }
    $('#view-live').hidden = name !== 'live';
    $('#view-records').hidden = name !== 'records';
    if (name === 'records') renderRecords();
    try { sessionStorage.setItem('tab', name); } catch (_) { /* ignore */ }
  }
  try { if (sessionStorage.getItem('tab') === 'records') showTab('records'); } catch (_) { /* ignore */ }

  // ───────────────────────── 시간 표시 ─────────────────────────
  function pad(n) { return String(n).padStart(2, '0'); }
  function fmtWhen(ts) {
    const d = new Date(ts);
    const hm = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    if (isToday(ts)) return `오늘 ${hm}`;
    const y = new Date(); y.setDate(y.getDate() - 1);
    if (d.toDateString() === y.toDateString()) return `어제 ${hm}`;
    return `${d.getMonth() + 1}월 ${d.getDate()}일 ${hm}`;
  }
  function relTime(ts) {
    if (!ts) return '';
    const s = Math.max(0, Math.round((Date.now() - ts) / 1000));
    if (s < 45) return '방금';
    const m = Math.round(s / 60);
    if (m < 60) return `${m}분 전`;
    const h = Math.round(m / 60);
    if (h < 24 && isToday(ts)) return `${h}시간 전`;
    return fmtWhen(ts);
  }
  function fmtDuration(ms) {
    const s = Math.round(ms / 1000);
    if (s < 60) return `${s}초`;
    const m = Math.floor(s / 60);
    if (m < 60) return `${m}분 ${pad(s % 60)}초`;
    return `${Math.floor(m / 60)}시간 ${m % 60}분`;
  }

  // ───────────────────────── 서버 메시지 ─────────────────────────
  function onMessage(msg) {
    const id = msg.studentId;
    switch (msg.type) {
      case 'snapshot': {
        const seen = new Set();
        for (const raw of msg.students || []) {
          seen.add(raw.studentId);
          const old = students.get(raw.studentId);
          const st = makeStudent(raw);
          if (old) {
            // 타일·뷰는 재사용
            st.tile = old.tile;
            st.views = old.views;
            for (const v of st.views) v.student = st;
          }
          students.set(st.studentId, st);
          strokesReset(st);
        }
        for (const [sid, st] of students) {
          if (!seen.has(sid)) { removeTile(st); students.delete(sid); }
        }
        layoutGrid();
        scheduleRecords();
        renderFocus({ problem: true });
        return;
      }
      case 'student_online': {
        const st = getStudent(id, msg.name);
        st.online = true;
        if (msg.name) st.name = msg.name;
        if (msg.device != null) st.device = msg.device;
        st.lastSeen = Date.now();
        layoutGrid();
        scheduleRecords();
        if (focusId === id) renderFocus();
        return;
      }
      case 'student_offline': {
        const st = students.get(id);
        if (!st) return;
        st.online = false;
        st.lastSeen = Date.now();
        layoutGrid();
        scheduleRecords();
        if (focusId === id) renderFocus();
        return;
      }
      case 'hello': {
        const st = getStudent(id, msg.name);
        if (msg.name) st.name = msg.name;
        if (msg.device != null) st.device = msg.device;
        if (st.tile) updateTile(st);
        return;
      }
      case 'pong':
      case 'welcome':
        return;
      case 'message_ack': {
        const info = pendingMsgs.get(msg.clientId) || {};
        pendingMsgs.delete(msg.clientId);
        if (msg.studentId) {
          const name = info.name || (students.get(msg.studentId) || {}).name || '학생';
          if (msg.ok) toast(`${name}에게 메시지를 보냈어요`);
          else toast(`${name} 학생이 접속 중이 아니라서 보내지 못했어요`, 'warn');
        } else if (msg.ok) toast(`접속한 학생 ${msg.delivered}명에게 메시지를 보냈어요`);
        else toast('접속한 학생이 없어 메시지를 보내지 못했어요', 'warn');
        return;
      }
      case 'error':
        console.warn('서버 오류 응답:', msg);
        return;
      default:
        break;
    }
    if (!id) return;
    const st = getStudent(id);
    switch (msg.type) {
      case 'page': {
        const { type, studentId, ...page } = msg;
        st.page = page;
        st.strokes = new Map();
        strokesReset(st);
        if (!st.tile && visibleOnLive(st)) layoutGrid();
        else if (st.tile) updateTile(st);
        if (focusId === id) renderFocus({ problem: true });
        return;
      }
      case 'stroke_begin': {
        const replaced = st.strokes.has(String(msg.id));
        const stroke = normStroke(msg, false);
        st.strokes.delete(stroke.id);
        st.strokes.set(stroke.id, stroke);
        for (const v of st.views) v.drawn.delete(stroke.id);
        markWriting(st, stroke);
        strokesChanged(st, stroke.id, replaced || stroke.tool === 'highlighter');
        return;
      }
      case 'stroke_points': {
        const sid = String(msg.id);
        const stroke = st.strokes.get(sid);
        if (!stroke || !Array.isArray(msg.points)) return;
        for (const p of msg.points) stroke.points.push(p);
        markWriting(st, stroke);
        strokesChanged(st, sid, stroke.tool === 'highlighter');
        return;
      }
      case 'stroke_end': {
        const sid = String(msg.id);
        const stroke = st.strokes.get(sid);
        if (!stroke) return;
        stroke.done = true;
        strokesChanged(st, sid, stroke.tool === 'highlighter');
        return;
      }
      case 'erase': {
        for (const sid of msg.ids || []) st.strokes.delete(String(sid));
        st.writingAt = Date.now();
        strokesReset(st);
        return;
      }
      case 'restore': {
        st.strokes = new Map();
        for (const s of msg.strokes || []) {
          const ns = normStroke(s, true);
          st.strokes.set(ns.id, ns);
        }
        strokesReset(st);
        return;
      }
      case 'clear': {
        st.strokes = new Map();
        strokesReset(st);
        return;
      }
      case 'answer': {
        const { type, studentId, ...entry } = msg;
        if (!entry.at) entry.at = Date.now();
        st.lastAnswer = entry;
        st.history.unshift(entry);
        if (st.history.length > MAX_HISTORY) st.history.length = MAX_HISTORY;
        if (st.tile) updateTile(st, { pop: true });
        if (focusId === id) renderFocus();
        scheduleRecords();
        return;
      }
      case 'stats': {
        const { type, studentId, ...stats } = msg;
        if (!stats.at) stats.at = Date.now();
        st.stats = stats;
        scheduleRecords();
        return;
      }
      default:
        // 앱이 새로 추가한 메시지는 무시
    }
  }

  function markWriting(st, stroke) {
    st.writingAt = Date.now();
    const p = stroke.points[stroke.points.length - 1];
    if (p) st.lastY = p[1];
  }

  // ───────────────────────── 연결 (자동 재접속) ─────────────────────────
  const conn = $('#conn');
  function setConn(state, text) {
    conn.dataset.state = state;
    $('.conn-text', conn).textContent = text;
  }

  function connect() {
    clearTimeout(reconnectTimer);
    const proto = location.protocol === 'https:' ? 'wss' : 'ws';
    const url = `${proto}://${location.host}/ws?role=teacher`;
    setConn(attempt ? 'retry' : 'connecting', attempt ? '다시 연결 중' : '연결 중');
    let sock;
    try { sock = new WebSocket(url); } catch (_) { return scheduleReconnect(); }
    ws = sock;
    sock.onopen = () => {
      attempt = 0;
      lastRecvAt = Date.now();
      setConn('open', '연결됨');
    };
    sock.onmessage = (ev) => {
      lastRecvAt = Date.now();
      let msg;
      try { msg = JSON.parse(ev.data); } catch (_) { return; }
      if (msg && typeof msg.type === 'string') {
        try { onMessage(msg); } catch (e) { console.error('메시지 처리 오류', e, msg); }
      }
    };
    sock.onclose = () => {
      if (ws !== sock) return;
      ws = null;
      scheduleReconnect();
    };
    sock.onerror = () => { /* onclose 에서 처리 */ };
  }

  function scheduleReconnect() {
    attempt++;
    const base = Math.min(10000, 500 * Math.pow(2, attempt - 1));
    const delay = Math.round(base * (0.8 + Math.random() * 0.4));
    setConn('retry', `연결 끊김, ${Math.max(1, Math.round(delay / 1000))}초 뒤 다시 연결`);
    clearTimeout(reconnectTimer);
    reconnectTimer = setTimeout(connect, delay);
  }

  // 연결 유지 확인: 20초마다 ping, 45초 동안 아무것도 못 받으면 다시 연결
  setInterval(() => {
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    if (Date.now() - lastRecvAt > 45000) { try { ws.close(); } catch (_) { /* ignore */ } return; }
    try { ws.send('{"type":"ping"}'); } catch (_) { /* ignore */ }
  }, 20000);

  // 탭이 다시 보이거나 네트워크가 돌아오면 바로 재접속
  window.addEventListener('online', () => { if (!ws) { attempt = 0; connect(); } });
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && !ws) { attempt = 0; connect(); }
  });

  layoutGrid();
  connect();
})();
