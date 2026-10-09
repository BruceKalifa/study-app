/**
 * Solvit 문제 데이터(v2) 공용 모듈 — 서버(Node)와 출제 웹(브라우저)이 같은 파일을 쓴다.
 *   - 본문 표기법 파서: $수식$, **굵게**, __밑줄__, |표|
 *   - 변형문제(template) 식 계산기 (docs/problem-schema.md 의 식 문법, tools/validate_problems.py 와 동일)
 *   - 검증: 문항 / 지문 / 과목 / 문제집  → [{ where, field, message }] (한국어)
 *
 * 형식 문서: docs/problem-schema.md
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.Schema = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // ───────────────────────── 상수 ─────────────────────────
  const GROUPS = { kor: '국어', math: '수학', eng: '영어', soc: '사회', sci: '과학', apt: '인적성', univ: '대학' };
  const GROUP_ORDER = ['kor', 'math', 'eng', 'soc', 'sci', 'apt', 'univ'];
  const LEVELS = { mid: '중등', high: '고등', univ: '대학' };
  const GRADES = ['중1', '중2', '중3', '고1', '고2', '고3', 'N수', '취준', '한양대', '편입'];
  const TRACKS = ['수능', '내신', '공통', '대학'];
  const WB_LEVELS = ['기본', '실전', '심화', '모의고사'];
  const WB_STAGES = ['개념', '유형', '기출', 'N제', '모의고사'];
  const RESERVED_COURSE_IDS = ['workbooks', 'index', '_index', 'admin'];

  const COURSE_ID_RE = /^[a-z0-9][a-z0-9-]{0,47}$/;
  const ITEM_ID_RE = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$/;
  const COLOR_RE = /^#[0-9A-Fa-f]{6}$/;
  const HANGUL_RE = /[ᄀ-ᇿ㄰-㆏가-힣]/;
  const PLACEHOLDER_RE = /\[\[(.*?)\]\]/g;
  const PARAM_NAME_RE = /^[a-z][a-z0-9]*$/;
  const NUM_RE = /^-?(\d+(\.\d+)?|\.\d+)$/;
  const FRAC_RE = /^-?\d+\/\d+$/;
  const ALLOWED_CMDS = new Set((
    'frac sqrt times cdot div pm le ge ne approx theta alpha beta lambda omega Delta pi mu rho sigma circ vec ' +
    'overline text left right infty sum int lim log sin cos tan to ln cdots quad neq leq geq lt gt gamma phi ' +
    'varphi epsilon tau Omega rightarrow Rightarrow prime angle triangle perp parallel propto Phi'
  ).split(' ').concat([',', ';', '!', ' ', '%', '{', '}', '|']));

  // ───────────────────────── 본문 표기법 ─────────────────────────

  /** 앱(MathText.split)과 같은 규칙: 이스케이프되지 않은 $ 로 나눈다. `\$` 는 글자 $.
   *  반환: [{ math: bool, text }]. 닫히지 않은 $ 뒤는 글자로 취급. */
  function splitMath(s) {
    const out = [];
    let buf = '';
    let inMath = false;
    s = s == null ? '' : String(s);
    for (let i = 0; i < s.length; i++) {
      const ch = s[i];
      if (ch === '\\' && s[i + 1] === '$') { buf += '$'; i++; continue; }
      if (ch === '$') {
        if (buf) out.push({ math: inMath, text: buf });
        buf = '';
        inMath = !inMath;
        continue;
      }
      buf += ch;
    }
    if (buf) out.push({ math: false, text: inMath ? '$' + buf : buf });
    return out;
  }

  /** 이스케이프되지 않은 $ 개수 */
  function countDollars(s) {
    let n = 0;
    for (let i = 0; i < s.length; i++) {
      if (s[i] === '\\' && s[i + 1] === '$') { i++; continue; }
      if (s[i] === '$') n++;
    }
    return n;
  }

  /** 수식 밖에서만 c 로 나눈다 (표 칸 나누기용) */
  function splitOutsideMath(line, c) {
    const cells = [];
    let buf = '';
    let inMath = false;
    for (let i = 0; i < line.length; i++) {
      const ch = line[i];
      if (ch === '\\' && line[i + 1] === '$') { buf += '\\$'; i++; continue; }
      if (ch === '$') inMath = !inMath;
      if (ch === c && !inMath) { cells.push(buf); buf = ''; continue; }
      buf += ch;
    }
    cells.push(buf);
    return cells;
  }

  function isTableLine(line) { return /^\s*\|/.test(line); }
  const SEP_RE = /^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$/;

  function tableCells(line) {
    let t = line.trim();
    const cells = splitOutsideMath(t, '|');
    // 앞뒤 | 로 생긴 빈 칸 제거
    if (cells.length && cells[0].trim() === '') cells.shift();
    if (cells.length && t.endsWith('|') && cells[cells.length - 1].trim() === '') cells.pop();
    return cells.map((x) => x.trim());
  }

  /** 본문을 블록으로: { type:'text', text } | { type:'table', header: [..]|null, rows: [[..]] , lines:[n..] } */
  function parseBlocks(s) {
    const lines = String(s == null ? '' : s).split('\n');
    const blocks = [];
    let text = [];
    const flush = () => { if (text.length) { blocks.push({ type: 'text', text: text.join('\n') }); text = []; } };
    for (let i = 0; i < lines.length; i++) {
      if (!isTableLine(lines[i])) { text.push(lines[i]); continue; }
      flush();
      const start = i;
      const rows = [];
      while (i < lines.length && isTableLine(lines[i])) { rows.push(lines[i]); i++; }
      i--;
      let header = null;
      let body = rows;
      if (rows.length >= 2 && SEP_RE.test(rows[1])) {
        header = tableCells(rows[0]);
        body = rows.slice(2);
      }
      blocks.push({ type: 'table', header, rows: body.map(tableCells), startLine: start, raw: rows });
    }
    flush();
    return blocks;
  }

  /** 글자 부분의 **굵게** / __밑줄__ 을 토큰으로. 반환 [{ text, bold, underline }] */
  function parseEmphasis(text, state) {
    state = state || { bold: false, underline: false };
    const out = [];
    let buf = '';
    for (let i = 0; i < text.length; i++) {
      const two = text.substr(i, 2);
      if (two === '**' || two === '__') {
        if (buf) out.push({ text: buf, bold: state.bold, underline: state.underline });
        buf = '';
        if (two === '**') state.bold = !state.bold; else state.underline = !state.underline;
        i++;
        continue;
      }
      buf += text[i];
    }
    if (buf) out.push({ text: buf, bold: state.bold, underline: state.underline });
    return out;
  }

  /** 한 줄(또는 표 칸)을 인라인 토큰으로: [{ math, text, bold, underline }] */
  function inlineTokens(s) {
    const state = { bold: false, underline: false };
    const out = [];
    for (const part of splitMath(s)) {
      if (part.math) out.push({ math: true, text: part.text, bold: state.bold, underline: state.underline });
      else for (const t of parseEmphasis(part.text, state)) out.push(Object.assign({ math: false }, t));
    }
    return out;
  }

  /** 미리보기용 평문 (목록에 한 줄 표시) */
  function plain(s) {
    let t = String(s == null ? '' : s).replace(/\\\$/g, '\u0000').replace(/\$/g, '').replace(/\u0000/g, '$');
    t = t.replace(/\\frac\{([^{}]*)\}\{([^{}]*)\}/g, '$1/$2');
    t = t.replace(/\\text\{([^{}]*)\}/g, '$1').replace(/\\sqrt\{([^{}]*)\}/g, '√$1');
    const map = {
      '\\times': '×', '\\cdot': '·', '\\div': '÷', '\\pm': '±', '\\le': '≤', '\\ge': '≥', '\\ne': '≠',
      '\\approx': '≈', '\\theta': 'θ', '\\alpha': 'α', '\\beta': 'β', '\\lambda': 'λ', '\\omega': 'ω',
      '\\Delta': 'Δ', '\\pi': 'π', '\\mu': 'μ', '\\rho': 'ρ', '\\sigma': 'σ', '\\circ': '°', '\\Omega': 'Ω',
      '\\infty': '∞', '\\to': '→', '\\rightarrow': '→', '\\,': ' ', '\\left': '', '\\right': '',
    };
    for (const k of Object.keys(map)) t = t.split(k).join(map[k]);
    t = t.replace(/\\[a-zA-Z]+/g, '').replace(/[{}]/g, '').replace(/\*\*|__/g, '');
    return t;
  }

  // ───────────────────────── 식 계산기 ─────────────────────────
  const FUNCS = { sqrt: 1, abs: 1, sin: 1, cos: 1, tan: 1, log: 1, ln: 1, exp: 1, min: 2, max: 2, round: 2, floor: 1, ceil: 1 };
  const CONSTS = { pi: Math.PI, e: Math.E };

  class ExprError extends Error {}

  function tokenize(src) {
    const toks = [];
    let i = 0;
    const n = src.length;
    const isDigit = (c) => c >= '0' && c <= '9';
    while (i < n) {
      const c = src[i];
      if (' \t\r\n'.includes(c)) { i++; continue; }
      if (isDigit(c) || (c === '.' && isDigit(src[i + 1] || ''))) {
        const start = i;
        while (i < n && isDigit(src[i])) i++;
        if (src[i] === '.') { i++; while (i < n && isDigit(src[i])) i++; }
        if (src[i] === 'e' || src[i] === 'E') {
          let j = i + 1;
          if (src[j] === '+' || src[j] === '-') j++;
          if (j < n && isDigit(src[j])) { i = j; while (i < n && isDigit(src[i])) i++; }
        }
        toks.push({ k: 'num', v: parseFloat(src.slice(start, i)), pos: start });
        continue;
      }
      if (/[A-Za-z_]/.test(c)) {
        const start = i;
        while (i < n && /[A-Za-z0-9_]/.test(src[i])) i++;
        toks.push({ k: 'id', v: src.slice(start, i), pos: start });
        continue;
      }
      if ('+-*/^(),'.includes(c)) { toks.push({ k: c, v: c, pos: i }); i++; continue; }
      throw new ExprError(`${i + 1}번째 글자 '${c}' 를 해석할 수 없습니다`);
    }
    toks.push({ k: 'end', v: '', pos: n });
    return toks;
  }

  function parseExpr(src) {
    const toks = tokenize(String(src));
    let p = 0;
    const cur = () => toks[p];
    const eat = (k) => {
      if (cur().k !== k) throw new ExprError(`'${k}' 가 필요합니다 (${cur().pos + 1}번째 글자)`);
      p++;
    };
    function expr() {
      let node = term();
      while (cur().k === '+' || cur().k === '-') { const op = cur().k; p++; node = ['bin', op, node, term()]; }
      return node;
    }
    function term() {
      let node = unary();
      while (cur().k === '*' || cur().k === '/') { const op = cur().k; p++; node = ['bin', op, node, unary()]; }
      return node;
    }
    function unary() {
      if (cur().k === '-') { p++; return ['neg', unary()]; }
      return power();
    }
    function power() {
      const base = primary();
      if (cur().k === '^') { p++; return ['bin', '^', base, unary()]; }
      return base;
    }
    function primary() {
      const t = cur();
      if (t.k === 'num') { p++; return ['num', t.v]; }
      if (t.k === '(') { p++; const node = expr(); eat(')'); return node; }
      if (t.k === 'id') {
        p++;
        if (cur().k === '(') {
          p++;
          const args = [];
          if (cur().k !== ')') {
            args.push(expr());
            while (cur().k === ',') { p++; args.push(expr()); }
          }
          eat(')');
          if (!(t.v in FUNCS)) throw new ExprError(`모르는 함수 '${t.v}'`);
          if (args.length !== FUNCS[t.v]) throw new ExprError(`${t.v} 는 인수 ${FUNCS[t.v]}개가 필요합니다`);
          return ['call', t.v, args];
        }
        if (t.v in FUNCS) throw new ExprError(`함수 '${t.v}' 뒤에 괄호가 없습니다`);
        return ['var', t.v];
      }
      if (t.k === 'end') throw new ExprError('식이 중간에 끝났습니다');
      throw new ExprError(`'${t.v}' 를 해석할 수 없습니다 (${t.pos + 1}번째 글자)`);
    }
    if (cur().k === 'end') throw new ExprError('빈 식입니다');
    const node = expr();
    if (cur().k !== 'end') throw new ExprError(`'${cur().v}' 를 해석할 수 없습니다 (${cur().pos + 1}번째 글자)`);
    return node;
  }

  function exprNames(node, out) {
    out = out || new Set();
    if (node[0] === 'var') { if (!(node[1] in CONSTS)) out.add(node[1]); }
    else if (node[0] === 'neg') exprNames(node[1], out);
    else if (node[0] === 'bin') { exprNames(node[2], out); exprNames(node[3], out); }
    else if (node[0] === 'call') for (const a of node[2]) exprNames(a, out);
    return out;
  }

  function roundTo(v, d) {
    if (!Number.isFinite(v)) return v;
    const f = Math.pow(10, d);
    const scaled = Math.abs(v) * f;
    if (!Number.isFinite(scaled) || scaled >= 1e15) return v;
    const cleaned = parseFloat(scaled.toPrecision(15));
    let r = Math.floor(cleaned);
    if (cleaned - r >= 0.5) r += 1;
    r = r / f;
    return v < 0 ? -r : r;
  }

  const RAD = Math.PI / 180;
  function evalAst(node, env) {
    switch (node[0]) {
      case 'num': return node[1];
      case 'var':
        if (env && Object.prototype.hasOwnProperty.call(env, node[1])) return Number(env[node[1]]);
        if (node[1] in CONSTS) return CONSTS[node[1]];
        throw new ExprError(`정의되지 않은 이름 '${node[1]}'`);
      case 'neg': return -evalAst(node[1], env);
      case 'bin': {
        const a = evalAst(node[2], env);
        const b = evalAst(node[3], env);
        switch (node[1]) {
          case '+': return a + b;
          case '-': return a - b;
          case '*': return a * b;
          case '/': return b === 0 ? (a === 0 ? NaN : (a > 0 ? Infinity : -Infinity)) : a / b;
          case '^': return Math.pow(a, b);
        }
        break;
      }
      case 'call': {
        const a = node[2].map((x) => evalAst(x, env));
        switch (node[1]) {
          case 'sqrt': return Math.sqrt(a[0]);
          case 'abs': return Math.abs(a[0]);
          case 'sin': return Math.sin(a[0] * RAD);
          case 'cos': return Math.cos(a[0] * RAD);
          case 'tan': return Math.tan(a[0] * RAD);
          case 'log': return Math.log10(a[0]);
          case 'ln': return Math.log(a[0]);
          case 'exp': return Math.exp(a[0]);
          case 'min': return Math.min(a[0], a[1]);
          case 'max': return Math.max(a[0], a[1]);
          case 'round': return Number.isFinite(a[1]) ? roundTo(a[0], Math.trunc(roundTo(a[1], 0))) : NaN;
          case 'floor': return Math.floor(a[0]);
          case 'ceil': return Math.ceil(a[0]);
        }
      }
    }
    throw new ExprError('잘못된 식');
  }

  function evaluate(src, env) { return evalAst(parseExpr(src), env || {}); }

  function fmtNum(v, maxDecimals) {
    if (Number.isNaN(v)) return 'NaN';
    if (!Number.isFinite(v)) return v > 0 ? '∞' : '-∞';
    const d = Math.max(0, maxDecimals == null ? 3 : maxDecimals);
    const r = roundTo(v, d);
    if (r === 0) return '0';
    if (Number.isInteger(r) && Math.abs(r) < 1e15) return String(r);
    let s = r.toFixed(Math.min(d, 20));
    if (s.includes('.')) s = s.replace(/0+$/, '').replace(/\.$/, '');
    return s === '-0' ? '0' : s;
  }

  function paramChoices(spec) {
    if (spec && Array.isArray(spec.values)) return spec.values.map(Number);
    if (Array.isArray(spec)) return spec.map(Number);
    const lo = Number(spec.min);
    const hi = Number(spec.max);
    const step = Number(spec.step == null ? 1 : spec.step);
    const n = Math.floor((hi - lo) / step + 1e-9);
    const out = [];
    for (let k = 0; k <= n && k < 10000; k++) out.push(Math.round((lo + k * step) * 1e10) / 1e10);
    return out;
  }

  function renderPlaceholders(s, env) {
    return String(s == null ? '' : s).replace(PLACEHOLDER_RE, (_, body) => {
      if (body.startsWith('=')) return fmtNum(evaluate(body.slice(1), env), 3);
      return fmtNum(Number(env[body]), 3);
    });
  }

  /** 변형문제 하나 만들기. rnd: () => [0,1). 실패하면 null */
  function makeVariant(tpl, rnd) {
    rnd = rnd || Math.random;
    const pools = {};
    for (const k of Object.keys(tpl.params || {})) pools[k] = paramChoices(tpl.params[k]);
    const reqs = Array.isArray(tpl.require) ? tpl.require : [];
    for (let tries = 0; tries < 200; tries++) {
      const env = {};
      for (const k of Object.keys(pools)) env[k] = pools[k][Math.floor(rnd() * pools[k].length)];
      let ok = true;
      for (const r of reqs) {
        const v = evaluate(r, env);
        if (!(Number.isFinite(v) && v > 0)) { ok = false; break; }
      }
      if (!ok) continue;
      const nd = tpl.round == null ? 3 : tpl.round;
      const ans = evaluate(tpl.answer, env);
      const out = {
        env,
        stem: renderPlaceholders(tpl.stem, env),
        answerValue: ans,
        answer: fmtNum(ans, nd),
      };
      if (tpl.solution != null) out.solution = renderPlaceholders(tpl.solution, env);
      if (tpl.hint != null) out.hint = renderPlaceholders(tpl.hint, env);
      if (Array.isArray(tpl.choiceExprs)) {
        const fmt = tpl.choiceFormat || '[[v]]';
        out.choiceValues = tpl.choiceExprs.map((c) => evaluate(c, env));
        out.choices = out.choiceValues.map((v) => fmt.replace('[[v]]', fmtNum(v, nd)));
      }
      return out;
    }
    return null;
  }

  /** 작은 시드 난수 (검증을 매번 같게) */
  function seededRandom(seed) {
    let s = seed >>> 0 || 1;
    return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
  }

  // ───────────────────────── 검증 ─────────────────────────
  function Report() { this.errors = []; this.warnings = []; }
  Report.prototype.err = function (where, field, message) { this.errors.push({ where, field, message }); };
  Report.prototype.warn = function (where, field, message) { this.warnings.push({ where, field, message }); };

  const isStr = (v) => typeof v === 'string';
  const nonEmpty = (v) => isStr(v) && v.trim() !== '';

  /** 본문 표기법 검사 (stem, body, boxItems, choices, solution, hint) */
  function checkText(s, where, field, rep, opts) {
    opts = opts || {};
    if (!isStr(s)) { rep.err(where, field, '글자(문자열)여야 합니다'); return; }
    if (/[\x00-\x09\x0b-\x1f]/.test(s)) rep.err(where, field, '보이지 않는 제어 문자가 들어 있습니다 (JSON 에서 \\f 를 \\\\f 로 써야 하는 경우가 많습니다)');
    const nd = countDollars(s);
    if (nd % 2) { rep.err(where, field, `수식 기호 $ 의 짝이 맞지 않습니다 ($ ${nd}개)`); }
    const parts = splitMath(s);
    let outside = '';
    let mathIndex = 0;
    for (const part of parts) {
      if (!part.math) { outside += part.text + '\n'; continue; }
      mathIndex++;
      const seg = part.text;
      const show = seg.length > 40 ? seg.slice(0, 40) + '…' : seg;
      if (HANGUL_RE.test(seg)) rep.err(where, field, `수식($…$) 안에 한글이 있습니다: $${show}$ — 한글은 $ 밖에 쓰세요`);
      if (seg.includes('\\begin')) rep.err(where, field, `\\begin{…} 환경은 쓸 수 없습니다: $${show}$`);
      if (seg.includes('\\\\')) rep.err(where, field, `수식 줄바꿈 \\\\ 는 쓸 수 없습니다: $${show}$`);
      let depth = 0;
      let bad = false;
      for (let i = 0; i < seg.length; i++) {
        if (seg[i] === '\\') { i++; continue; }
        if (seg[i] === '{') depth++;
        else if (seg[i] === '}') { depth--; if (depth < 0) bad = true; }
      }
      if (depth !== 0 || bad) rep.err(where, field, `수식의 중괄호 { } 짝이 맞지 않습니다: $${show}$`);
      const textRe = /\\text\{([^}]*)\}/g;
      let m;
      while ((m = textRe.exec(seg))) {
        if (!/^[\x00-\x7F]*$/.test(m[1])) rep.err(where, field, `\\text{} 안에는 영문·숫자·단위만 쓸 수 있습니다: \\text{${m[1]}}`);
      }
      const cmdRe = /\\([A-Za-z]+|.)/g;
      const unknown = new Set();
      while ((m = cmdRe.exec(seg))) if (!ALLOWED_CMDS.has(m[1])) unknown.add('\\' + m[1]);
      if (unknown.size) rep.warn(where, field, `앱에서 지원하지 않을 수 있는 명령: ${Array.from(unknown).join(' ')}`);
      if (!seg.trim()) rep.warn(where, field, '빈 수식 $$ 이 있습니다');
    }
    void mathIndex;
    const nb = (outside.match(/\*\*/g) || []).length;
    if (nb % 2) rep.err(where, field, `굵게 표시 ** 의 짝이 맞지 않습니다 (${nb}개)`);
    const nu = (outside.match(/__/g) || []).length;
    if (nu % 2) rep.err(where, field, `밑줄 표시 __ 의 짝이 맞지 않습니다 (${nu}개)`);
    if (/_{3,}/.test(outside)) rep.warn(where, field, '수식 밖의 ___ (밑줄 3개 이상)은 __밑줄__ 표시와 겹칩니다. 빈칸은 __   __ 처럼 쓰세요');
    for (const b of parseBlocks(s)) {
      if (b.type !== 'table') continue;
      const counts = b.rows.map((r) => r.length);
      if (b.header) counts.unshift(b.header.length);
      const first = counts[0];
      const badRow = counts.findIndex((c) => c !== first);
      if (badRow >= 0) {
        rep.err(where, field, `표의 칸 수가 줄마다 다릅니다 (${counts.join(', ')}칸) — 모든 줄의 | 개수를 맞추세요`);
      }
      if (b.raw.length < 2) { rep.warn(where, field, `표가 한 줄뿐입니다: ${b.raw[0].trim().slice(0, 40)}`); continue; }
      b.raw.forEach((r, i) => {
        if (i !== 1 && SEP_RE.test(r)) rep.warn(where, field, `표 구분선 |---| 은 둘째 줄에만 씁니다 (${i + 1}번째 줄)`);
        if (!r.trim().endsWith('|')) rep.warn(where, field, `표 ${i + 1}번째 줄이 | 로 끝나지 않습니다`);
      });
      if (b.header && !b.rows.length) rep.warn(where, field, '표에 머리글만 있고 내용 줄이 없습니다');
    }
    if (!opts.allowPlaceholders && s.includes('[[')) rep.err(where, field, '[[…]] 자리표시는 변형문제(template) 안에서만 쓸 수 있습니다');
  }

  function checkPlaceholders(s, where, field, names, rep, allowV) {
    if (!isStr(s)) return;
    let m;
    const re = new RegExp(PLACEHOLDER_RE.source, 'g');
    while ((m = re.exec(s))) {
      const body = m[1];
      if (body.startsWith('=')) {
        try {
          const used = exprNames(parseExpr(body.slice(1)));
          const bad = Array.from(used).filter((x) => !names.has(x));
          if (bad.length) rep.err(where, field, `[[${body}]] 에 정의되지 않은 매개변수: ${bad.join(', ')}`);
        } catch (e) {
          rep.err(where, field, `[[${body}]] 식 오류: ${e.message}`);
        }
      } else if (!(body === 'v' && allowV) && !names.has(body)) {
        rep.err(where, field, `[[${body}]] 는 정의된 매개변수가 아닙니다`);
      }
    }
    if (s.replace(new RegExp(PLACEHOLDER_RE.source, 'g'), '').includes('[[')) rep.err(where, field, '[[ 가 닫히지 않았습니다');
  }

  function parseAnswerNumber(s) {
    s = String(s).trim();
    if (NUM_RE.test(s)) return parseFloat(s);
    if (FRAC_RE.test(s)) {
      const [a, b] = s.replace('-', '').split('/').map(Number);
      if (b === 0) return null;
      return s.startsWith('-') ? -a / b : a / b;
    }
    return null;
  }

  // 숫자·분수 말고도 복소수(3+2i, 1±i), 여러 값(1, -2 · ±3), 구간·집합([1,3) ∪ (5,∞), {1,2}), 제곱근·π 식(2√3, 3π/2) 도 정답으로 쓸 수 있다.
  // 앱 채점기(lib/core/grader.dart)가 읽는 글자만 허용하고, 괄호 짝과 숫자·기호가 하나라도 있는지만 본다.
  const EXT_ANSWER_RE = /^[0-9A-Za-z.+\-*\/^()\[\]{},;±∞∪<>≤≥√πθ°\s]+$/;
  function isExtendedAnswer(s) {
    s = String(s).trim();
    if (!s || !EXT_ANSWER_RE.test(s)) return false;
    if (!/[0-9iπeθ]|sqrt|∞/.test(s)) return false;
    const st = [];
    const pairs = { ')': '(', ']': '[', '}': '{' };
    for (const ch of s) {
      if ('([{'.includes(ch)) st.push(ch);
      else if (ch in pairs) {
        const o = st.pop();
        if (o === undefined) return false;
        // 구간은 [1,3) 처럼 모양이 섞이는 게 정상이라 ( 와 [ 짝은 서로 허용
        if (ch === '}' ? o !== '{' : o === '{') return false;
      }
    }
    return st.length === 0;
  }

  function validateTemplate(p, where, rep) {
    const tpl = p.template;
    const F = 'template';
    if (!tpl || typeof tpl !== 'object' || Array.isArray(tpl)) { rep.err(where, F, 'template 은 { } 객체여야 합니다'); return; }
    const before = rep.errors.length;
    for (const k of ['params', 'stem', 'answer']) if (!(k in tpl)) rep.err(where, F, `template 에 '${k}' 가 없습니다`);
    if (tpl.params && (typeof tpl.params !== 'object' || Array.isArray(tpl.params))) rep.err(where, F, 'template.params 는 { 이름: {min,max,step} 또는 {values:[…]} } 형태여야 합니다');
    if (rep.errors.length > before) return;
    const names = new Set(Object.keys(tpl.params));
    if (!names.size) rep.err(where, F, 'template.params 에 매개변수가 하나도 없습니다');
    for (const name of names) {
      const spec = tpl.params[name];
      const w = `template.params.${name}`;
      if (!PARAM_NAME_RE.test(name)) rep.err(where, F, `${w}: 매개변수 이름은 영문 소문자로 시작하는 소문자·숫자여야 합니다`);
      if (name in FUNCS || name in CONSTS || name === 'v') rep.err(where, F, `${w}: '${name}' 은(는) 예약된 이름입니다`);
      if (spec && Array.isArray(spec.values)) {
        if (!spec.values.length || !spec.values.every((x) => typeof x === 'number' && Number.isFinite(x))) rep.err(where, F, `${w}: values 는 숫자 목록이어야 합니다`);
      } else if (spec && typeof spec.min === 'number' && typeof spec.max === 'number') {
        const st = spec.step == null ? 1 : spec.step;
        if (!(typeof st === 'number' && st > 0) || spec.max < spec.min) rep.err(where, F, `${w}: min/max/step 이 잘못되었습니다`);
      } else {
        rep.err(where, F, `${w}: {"min":…, "max":…, "step":…} 또는 {"values":[…]} 가 필요합니다`);
      }
    }
    const exprs = [['answer', tpl.answer]];
    (Array.isArray(tpl.require) ? tpl.require : []).forEach((r, i) => exprs.push([`require[${i}]`, r]));
    (Array.isArray(tpl.choiceExprs) ? tpl.choiceExprs : []).forEach((c, i) => exprs.push([`choiceExprs[${i}]`, c]));
    for (const [label, src] of exprs) {
      try {
        const bad = Array.from(exprNames(parseExpr(src))).filter((x) => !names.has(x));
        if (bad.length) rep.err(where, F, `template.${label}: 정의되지 않은 매개변수 ${bad.join(', ')} (${src})`);
      } catch (e) {
        rep.err(where, F, `template.${label}: 식 "${src}" 오류 — ${e.message}`);
      }
    }
    for (const key of ['stem', 'solution', 'hint']) {
      if (key in tpl) {
        checkText(tpl[key], where, `template.${key}`, rep, { allowPlaceholders: true });
        checkPlaceholders(tpl[key], where, `template.${key}`, names, rep);
      }
    }
    if ('choiceFormat' in tpl) {
      checkPlaceholders(tpl.choiceFormat, where, 'template.choiceFormat', names, rep, true);
      if (!String(tpl.choiceFormat).includes('[[v]]')) rep.err(where, F, 'template.choiceFormat 에 [[v]] 가 있어야 합니다');
    }
    if ('round' in tpl && !(Number.isInteger(tpl.round) && tpl.round >= 0 && tpl.round <= 6)) rep.err(where, F, 'template.round 는 0~6 정수여야 합니다');
    const ce = tpl.choiceExprs;
    if (p.type === 'choice') {
      if (!Array.isArray(ce) || ce.length !== 5) { rep.err(where, F, '선택형 문항의 template 은 choiceExprs 5개가 필요합니다 (첫 번째 = 정답 식)'); return; }
    } else if (ce != null) {
      rep.err(where, F, '단답형 문항의 template 에는 choiceExprs 를 쓰지 않습니다');
    }
    if (rep.errors.length > before) return;
    // 표본 변형을 만들어 실제로 계산되는지 확인
    const rnd = seededRandom(12345);
    for (let i = 0; i < 20; i++) {
      let v;
      try { v = makeVariant(tpl, rnd); } catch (e) { rep.err(where, F, `변형 계산 실패: ${e.message}`); return; }
      if (!v) { rep.err(where, F, 'require 조건을 만족하는 매개변수 조합을 찾지 못했습니다 (200회 시도)'); return; }
      if (!Number.isFinite(v.answerValue)) { rep.err(where, F, `정답 값이 유한하지 않습니다 (${JSON.stringify(v.env)})`); return; }
      for (const key of ['stem', 'solution', 'hint']) {
        if (v[key] != null && /NaN|∞/.test(v[key])) { rep.err(where, F, `template.${key} 에 계산 불가 값이 나옵니다 (${JSON.stringify(v.env)})`); return; }
      }
      if (v.choiceValues) {
        if (!v.choiceValues.every(Number.isFinite)) { rep.err(where, F, `선택지 값이 유한하지 않습니다 (${JSON.stringify(v.env)})`); return; }
        const a = v.choiceValues[0];
        const b = v.answerValue;
        if (Math.abs(a - b) > 1e-9 * Math.max(1, Math.abs(a), Math.abs(b))) {
          rep.err(where, F, `choiceExprs 첫 번째(${fmtNum(a)})가 정답(${fmtNum(b)})과 다릅니다 (${JSON.stringify(v.env)})`);
          return;
        }
      }
    }
  }

  const PROBLEM_REQUIRED = ['id', 'unit', 'topic', 'difficulty', 'type', 'stem', 'answer', 'solution'];
  const KNOWN_PROBLEM_KEYS = PROBLEM_REQUIRED.concat(['choices', 'boxItems', 'answerUnit', 'tolerance', 'hint', 'tags', 'template', 'passageId', 'twinOf']);
  const FIELD_KO = { id: 'id', unit: '대단원', topic: '유형', difficulty: '난이도', type: '형식', stem: '문제 본문', answer: '정답', solution: '해설' };

  /** 문항 하나 (다른 문항과의 관계는 validateCourse 가 본다) */
  function validateProblem(p, rep, whereOverride) {
    const where = whereOverride || (p && isStr(p.id) && p.id) || '(id 없음)';
    if (!p || typeof p !== 'object' || Array.isArray(p)) { rep.err(where, '', '문항은 { } 객체여야 합니다'); return; }
    for (const k of PROBLEM_REQUIRED) {
      if (!(k in p) || p[k] == null || (isStr(p[k]) && !p[k].trim())) rep.err(where, k, `${FIELD_KO[k]}(${k}) 를 입력하세요`);
    }
    for (const k of ['id', 'unit', 'topic', 'type', 'stem', 'answer', 'solution']) {
      if (k in p && p[k] != null && !isStr(p[k])) rep.err(where, k, `${FIELD_KO[k]}(${k}) 는 글자여야 합니다`);
    }
    if (isStr(p.id) && p.id && !ITEM_ID_RE.test(p.id)) rep.err(where, 'id', 'id 는 영문·숫자·- _ . 만 쓸 수 있습니다 (예: phy1-mech-001)');
    if ('difficulty' in p && !(Number.isInteger(p.difficulty) && p.difficulty >= 1 && p.difficulty <= 5)) rep.err(where, 'difficulty', '난이도는 1~5 정수여야 합니다');
    if (p.type === 'choice') {
      const ch = p.choices;
      if (!Array.isArray(ch) || ch.length !== 5) {
        rep.err(where, 'choices', `선택형은 선택지가 정확히 5개여야 합니다 (지금 ${Array.isArray(ch) ? ch.length : 0}개)`);
      } else {
        ch.forEach((c, i) => {
          if (!nonEmpty(c)) rep.err(where, `choices[${i}]`, `${i + 1}번 선택지가 비어 있습니다`);
          else checkText(c, where, `choices[${i}]`, rep);
        });
        if (ch.every(isStr) && new Set(ch.map((c) => c.trim())).size !== ch.length) rep.err(where, 'choices', '같은 선택지가 두 번 이상 있습니다');
      }
      if (p.answer != null && !['1', '2', '3', '4', '5'].includes(String(p.answer))) rep.err(where, 'answer', `선택형 정답은 "1"~"5" 중 하나여야 합니다 (지금 "${p.answer}")`);
      if (p.answerUnit) rep.warn(where, 'answerUnit', '선택형 문항에는 answerUnit 이 쓰이지 않습니다');
    } else if (p.type === 'short') {
      if (Array.isArray(p.choices) && p.choices.length) rep.err(where, 'choices', '단답형 문항에는 선택지를 넣지 않습니다');
      if (nonEmpty(p.answer) && parseAnswerNumber(p.answer) == null && !isExtendedAnswer(p.answer)) rep.err(where, 'answer', `단답형 정답 "${p.answer}" 은(는) 숫자·분수·복소수·구간 꼴이어야 합니다 (예: 12, -3/2, 2.5, 3+2i, 1±√2, [1,3)) — 단위는 "단위" 칸에`);
      if ('tolerance' in p && !(typeof p.tolerance === 'number' && p.tolerance >= 0)) rep.err(where, 'tolerance', '허용 오차는 0 이상의 숫자여야 합니다');
    } else if ('type' in p) {
      rep.err(where, 'type', '형식(type)은 "choice"(5지선다) 또는 "short"(단답형) 이어야 합니다');
    }
    for (const k of ['stem', 'solution', 'hint']) if (isStr(p[k])) checkText(p[k], where, k, rep);
    if ('hint' in p && p.hint != null && !isStr(p.hint)) rep.err(where, 'hint', '힌트는 글자여야 합니다');
    if ('answerUnit' in p && p.answerUnit != null && !isStr(p.answerUnit)) rep.err(where, 'answerUnit', '단위는 글자여야 합니다');
    if ('boxItems' in p) {
      const bi = p.boxItems;
      if (!Array.isArray(bi)) rep.err(where, 'boxItems', '<보기> 항목은 목록이어야 합니다');
      else bi.forEach((b, i) => {
        if (!nonEmpty(b)) rep.err(where, `boxItems[${i}]`, `<보기> ${i + 1}번째 항목이 비어 있습니다`);
        else {
          checkText(b, where, `boxItems[${i}]`, rep);
          if (bi.length > 1 && !/^[ㄱ-ㅎ]\. /.test(b)) rep.warn(where, `boxItems[${i}]`, '<보기> 항목은 "ㄱ. " 처럼 시작하는 것이 보통입니다');
        }
      });
    }
    if ('tags' in p && !(Array.isArray(p.tags) && p.tags.every(isStr))) rep.err(where, 'tags', '태그는 글자 목록이어야 합니다');
    if ('passageId' in p && p.passageId != null && !nonEmpty(p.passageId)) rep.err(where, 'passageId', '지문 id 가 비어 있습니다');
    if ('twinOf' in p && p.twinOf != null) {
      if (!nonEmpty(p.twinOf)) rep.err(where, 'twinOf', '원본 문항 id 가 비어 있습니다');
      else if (p.twinOf === p.id) rep.err(where, 'twinOf', '자기 자신을 원본으로 지정할 수 없습니다');
    }
    if ('template' in p && p.template != null) validateTemplate(p, where, rep);
    const unknown = Object.keys(p).filter((k) => !KNOWN_PROBLEM_KEYS.includes(k));
    if (unknown.length) rep.warn(where, '', `알 수 없는 필드: ${unknown.join(', ')} (앱이 무시합니다)`);
  }

  function validatePassage(ps, rep) {
    const where = (ps && isStr(ps.id) && ps.id) || '(지문 id 없음)';
    if (!ps || typeof ps !== 'object' || Array.isArray(ps)) { rep.err(where, '', '지문은 { } 객체여야 합니다'); return; }
    if (!nonEmpty(ps.id)) rep.err(where, 'id', '지문 id 를 입력하세요');
    else if (!ITEM_ID_RE.test(ps.id)) rep.err(where, 'id', '지문 id 는 영문·숫자·- _ . 만 쓸 수 있습니다');
    if (ps.title != null && !isStr(ps.title)) rep.err(where, 'title', '제목은 글자여야 합니다');
    else if (isStr(ps.title) && ps.title.trim()) checkText(ps.title, where, 'title', rep);
    else rep.warn(where, 'title', '지문 제목이 없습니다');
    if (!nonEmpty(ps.body)) rep.err(where, 'body', '지문 본문을 입력하세요');
    else checkText(ps.body, where, 'body', rep);
    if (ps.source != null && !isStr(ps.source)) rep.err(where, 'source', '출처는 글자여야 합니다');
  }

  function validateCourseMeta(c, rep) {
    const where = (c && isStr(c.subjectId) && c.subjectId) || '(과목)';
    if (!c || typeof c !== 'object' || Array.isArray(c)) { rep.err(where, '', '과목은 { } 객체여야 합니다'); return; }
    if (!nonEmpty(c.subject)) rep.err(where, 'subject', '과목 이름을 입력하세요');
    if (!nonEmpty(c.subjectId)) rep.err(where, 'subjectId', '과목 id 를 입력하세요');
    else if (!COURSE_ID_RE.test(c.subjectId)) rep.err(where, 'subjectId', '과목 id 는 영문 소문자·숫자·- 만 쓸 수 있습니다 (예: phy1, math-mid2)');
    else if (RESERVED_COURSE_IDS.includes(c.subjectId)) rep.err(where, 'subjectId', `'${c.subjectId}' 는 과목 id 로 쓸 수 없습니다`);
    if (!COLOR_RE.test(String(c.color || ''))) rep.err(where, 'color', '색은 #RRGGBB 형식이어야 합니다 (예: #3B6FE0)');
    if (!Object.prototype.hasOwnProperty.call(GROUPS, c.group)) rep.err(where, 'group', '교과군(국어·수학·영어·사회·과학)을 고르세요');
    if (!Object.prototype.hasOwnProperty.call(LEVELS, c.level)) rep.err(where, 'level', '학교급(중등·고등)을 고르세요');
    if (!Array.isArray(c.grades) || !c.grades.length) rep.err(where, 'grades', '대상 학년을 하나 이상 고르세요');
    else if (!c.grades.every((g) => GRADES.includes(g))) rep.err(where, 'grades', `대상 학년은 ${GRADES.join(' ')} 중에서 고르세요`);
    else if (new Set(c.grades).size !== c.grades.length) rep.err(where, 'grades', '같은 학년이 두 번 있습니다');
    else if (c.level === 'mid' && c.grades.some((g) => !g.startsWith('중'))) rep.warn(where, 'grades', '중등 과목인데 고등 학년이 들어 있습니다');
    else if (c.level === 'high' && c.grades.some((g) => g.startsWith('중'))) rep.warn(where, 'grades', '고등 과목인데 중학교 학년이 들어 있습니다');
    if (c.track != null && c.track !== '' && !TRACKS.includes(c.track)) rep.err(where, 'track', `트랙은 ${TRACKS.join('·')} 중 하나여야 합니다`);
    if (c.units != null) {
      if (!Array.isArray(c.units) || !c.units.every(nonEmpty)) rep.err(where, 'units', '대단원 목록은 비어 있지 않은 글자 목록이어야 합니다');
      else if (new Set(c.units).size !== c.units.length) rep.err(where, 'units', '같은 대단원이 두 번 있습니다');
    }
    if (c.problems != null && !Array.isArray(c.problems)) rep.err(where, 'problems', 'problems 는 목록이어야 합니다');
    if (c.passages != null && !Array.isArray(c.passages)) rep.err(where, 'passages', 'passages 는 목록이어야 합니다');
  }

  /**
   * 과목 전체 검증.
   *  opts.foreignIds: Map<id, 다른과목id>  — 다른 과목의 문항·지문 id (전체 유일성 검사용)
   *  opts.only: Set<id> — 이 문항/지문만 자세히 검사(나머지는 관계만). 없으면 전부 검사
   */
  function validateCourse(c, opts) {
    opts = opts || {};
    const rep = new Report();
    validateCourseMeta(c, rep);
    if (!c || typeof c !== 'object' || Array.isArray(c)) return rep;
    const problems = Array.isArray(c.problems) ? c.problems : [];
    const passages = Array.isArray(c.passages) ? c.passages : [];
    const only = opts.only || null;
    const foreign = opts.foreignIds || new Map();
    const seen = new Map();
    const checkId = (id, kind) => {
      if (!isStr(id) || !id) return;
      if (seen.has(id)) rep.err(id, 'id', `id "${id}" 가 이 과목 안에서 중복됩니다 (${seen.get(id)})`);
      else if (foreign.has(id)) rep.err(id, 'id', `id "${id}" 는 이미 다른 과목(${foreign.get(id)})에서 쓰고 있습니다`);
      seen.set(id, kind);
    };
    const passageIds = new Set();
    for (const ps of passages) {
      if (!only || only.has(ps && ps.id)) validatePassage(ps, rep);
      if (ps && isStr(ps.id)) { checkId(ps.id, '지문'); passageIds.add(ps.id); }
    }
    const byId = new Map();
    for (const p of problems) {
      if (p && isStr(p.id)) { checkId(p.id, '문항'); byId.set(p.id, p); }
    }
    for (const p of problems) {
      const detailed = !only || only.has(p && p.id);
      if (detailed) validateProblem(p, rep);
      if (!p || typeof p !== 'object') continue;
      const where = p.id || '(id 없음)';
      if (p.passageId != null && nonEmpty(p.passageId) && !passageIds.has(p.passageId) && (detailed || !only)) {
        rep.err(where, 'passageId', `지문 "${p.passageId}" 가 이 과목에 없습니다`);
      }
      if (p.twinOf != null && nonEmpty(p.twinOf) && p.twinOf !== p.id) {
        const orig = byId.get(p.twinOf);
        if (!orig) rep.err(where, 'twinOf', `원본 문항 "${p.twinOf}" 가 이 과목에 없습니다`);
        else if (orig.twinOf) rep.err(where, 'twinOf', `원본 "${p.twinOf}" 도 쌍둥이 문항입니다 — 쌍둥이의 쌍둥이는 만들 수 없으니 원본 "${orig.twinOf}" 를 지정하세요`);
        else if (detailed && (orig.unit !== p.unit || orig.topic !== p.topic)) rep.warn(where, 'twinOf', '쌍둥이는 원본과 같은 대단원·유형을 쓰는 것을 권장합니다');
      }
      if (detailed && Array.isArray(c.units) && c.units.length && isStr(p.unit) && p.unit && !c.units.includes(p.unit)) {
        rep.warn(where, 'unit', `대단원 "${p.unit}" 가 과목의 대단원 목록(units)에 없습니다`);
      }
    }
    return rep;
  }

  /**
   * 문제집 목록 검증. problemIndex: Map<문항id, { course, twinOf }>, courseIds: Set
   */
  function validateWorkbooks(list, problemIndex, courseIds) {
    const rep = new Report();
    if (!Array.isArray(list)) { rep.err('workbooks', '', 'workbooks 는 목록이어야 합니다'); return rep; }
    const seen = new Set();
    list.forEach((wb, i) => {
      const where = (wb && isStr(wb.id) && wb.id) || `문제집 ${i + 1}`;
      if (!wb || typeof wb !== 'object' || Array.isArray(wb)) { rep.err(where, '', '문제집은 { } 객체여야 합니다'); return; }
      if (!nonEmpty(wb.id)) rep.err(where, 'id', '문제집 id 를 입력하세요');
      else if (!COURSE_ID_RE.test(wb.id)) rep.err(where, 'id', '문제집 id 는 영문 소문자·숫자·- 만 쓸 수 있습니다 (예: wb-phy1-concept)');
      else if (seen.has(wb.id)) rep.err(where, 'id', `문제집 id "${wb.id}" 가 중복됩니다`);
      seen.add(wb.id);
      if (!nonEmpty(wb.title)) rep.err(where, 'title', '문제집 제목을 입력하세요');
      if (!nonEmpty(wb.course)) rep.err(where, 'course', '과목을 고르세요');
      else if (courseIds && !courseIds.has(wb.course)) rep.err(where, 'course', `과목 "${wb.course}" 가 없습니다`);
      if (wb.level != null && !WB_LEVELS.includes(wb.level)) rep.err(where, 'level', `수준은 ${WB_LEVELS.join('·')} 중 하나여야 합니다`);
      if (wb.desc != null && !isStr(wb.desc)) rep.err(where, 'desc', '설명은 글자여야 합니다');
      if (wb.stage != null && wb.stage !== '' && !WB_STAGES.includes(wb.stage)) rep.err(where, 'stage', `단계는 ${WB_STAGES.join('·')} 중 하나여야 합니다`);
      for (const k of ['scope', 'publisher', 'series']) if (wb[k] != null && !isStr(wb[k])) rep.err(where, k, '글자여야 합니다');
      if (!Array.isArray(wb.problems)) { rep.err(where, 'problems', '문항 목록(problems)이 필요합니다'); return; }
      if (!wb.problems.length) rep.err(where, 'problems', '문항을 하나 이상 넣으세요');
      const inWb = new Set();
      wb.problems.forEach((pid) => {
        if (!isStr(pid)) { rep.err(where, 'problems', '문항 id 는 글자여야 합니다'); return; }
        if (inWb.has(pid)) rep.err(where, 'problems', `문항 "${pid}" 가 두 번 들어 있습니다`);
        inWb.add(pid);
        const info = problemIndex && problemIndex.get(pid);
        if (!info) rep.err(where, 'problems', `문항 "${pid}" 가 없습니다`);
        else {
          if (info.twinOf) rep.err(where, 'problems', `"${pid}" 는 쌍둥이 문항이라 문제집에 넣을 수 없습니다 (원본 "${info.twinOf}" 를 넣으세요)`);
          if (wb.course && info.course !== wb.course) rep.warn(where, 'problems', `문항 "${pid}" 는 다른 과목(${info.course})의 문항입니다`);
        }
      });
    });
    return rep;
  }

  /** 오류 하나를 한 줄 글로 */
  function formatIssue(e) {
    const f = e.field ? ` [${e.field}]` : '';
    return `${e.where}${f}: ${e.message}`;
  }

  /** 배점: 난이도 ≤2 → 2점, 3 → 3점, ≥4 → 4점 */
  function points(difficulty) {
    const d = Number(difficulty) || 1;
    return d <= 2 ? 2 : d === 3 ? 3 : 4;
  }

  return {
    GROUPS, GROUP_ORDER, LEVELS, GRADES, TRACKS, WB_LEVELS, WB_STAGES, RESERVED_COURSE_IDS, COURSE_ID_RE, ITEM_ID_RE,
    splitMath, countDollars, parseBlocks, inlineTokens, parseEmphasis, plain, tableCells,
    ExprError, parseExpr, evaluate, exprNames, fmtNum, roundTo, paramChoices, renderPlaceholders, makeVariant, seededRandom,
    Report, checkText, validateProblem, validatePassage, validateCourseMeta, validateCourse, validateWorkbooks,
    parseAnswerNumber, isExtendedAnswer, formatIssue, points,
  };
});
