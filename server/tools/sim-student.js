#!/usr/bin/env node
'use strict';
/**
 * 가짜 학생 시뮬레이터 — 실제 태블릿 없이 선생님 화면을 확인할 때 쓴다.
 *
 *   npm run sim                         (localhost:8080 에 학생 3명 접속, 한 바퀴 풀고 종료)
 *   node tools/sim-student.js ws://192.168.0.12:8080/ws --count 2 --forever
 *
 * 옵션
 *   --count N     학생 수 (1~3, 기본 3)
 *   --rounds N    문제 묶음(2문제)을 몇 번 풀지 (기본 1)
 *   --forever     끝없이 반복 (Ctrl+C 로 종료)
 *   --speed X     필기 속도 배율 (기본 1, 2 면 두 배 빠르게)
 */

const { WebSocket } = require('ws');

// ───────────────────────── 옵션 ─────────────────────────
const argv = process.argv.slice(2);
const opt = (name, def) => {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : def;
};
const URL_ARG = argv.find((a) => /^wss?:\/\//.test(a)) || process.env.SERVER_URL || 'ws://localhost:8080/ws';
const COUNT = Math.min(3, Math.max(1, Number(opt('--count', 3)) || 3));
const ROUNDS = Math.max(1, Number(opt('--rounds', 1)) || 1);
const FOREVER = argv.includes('--forever');
const SPEED = Math.max(0.1, Number(opt('--speed', 1)) || 1);
const CHUNK_MS = 50;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms / SPEED));

// ───────────────────────── 문제 ─────────────────────────
const PROBLEMS = [
  {
    problemId: 'phy1-mech-001',
    title: '등가속도 직선 운동 · 이동 거리',
    topic: '등가속도 직선 운동',
    stem: '정지해 있던 물체가 가속도 $2\\,\\text{m/s}^2$ 으로 $3$초 동안 운동했다.\n이 동안 물체의 이동 거리는?',
    choices: ['$3\\,\\text{m}$', '$6\\,\\text{m}$', '$9\\,\\text{m}$', '$12\\,\\text{m}$', '$18\\,\\text{m}$'],
    answer: '3',
    work: ['2x9=18', '18/2=9'],
  },
  {
    problemId: 'math-quad-014',
    title: '이차함수의 꼭짓점',
    topic: '이차함수',
    stem: '이차함수 $y = x^2 - 4x + 7$ 의 그래프의 꼭짓점의 $y$좌표를 구하시오.',
    choices: null,
    answer: '3',
    work: ['4-8+7=3'],
    graph: true,
  },
  {
    problemId: 'phy1-wave-007',
    title: '파동의 속력',
    topic: '파동의 진행',
    stem: '진동수가 $5\\,\\text{Hz}$ 이고 파장이 $2\\,\\text{m}$ 인 파동의 속력은 몇 $\\text{m/s}$ 인가?',
    boxItems: ['ㄱ. 파동의 속력은 $v = f\\lambda$ 이다.', 'ㄴ. 주기는 $0.2$초이다.', 'ㄷ. 진동수가 2배가 되면 파장은 절반이 된다.'],
    choices: ['$2.5$', '$5$', '$7$', '$10$', '$20$'],
    answer: '4',
    work: ['5x2=10'],
  },
  {
    problemId: 'es1-astro-003',
    title: '별의 밝기와 등급',
    topic: '별의 물리량',
    stem: '겉보기 등급이 $1$등급인 별은 $6$등급인 별보다 약 몇 배 밝은가?',
    choices: ['$5$배', '$10$배', '$50$배', '$100$배', '$250$배'],
    answer: '4',
    work: ['2.5^5=100'],
  },
];

const STUDENTS = [
  { studentId: 'sim-minjun', name: '김민준', device: 'Galaxy Tab S9 (시뮬레이터)', skill: 0.8, x0: 70 },
  { studentId: 'sim-seoyeon', name: '이서연', device: 'Galaxy Tab S8 (시뮬레이터)', skill: 0.6, x0: 110 },
  { studentId: 'sim-jiho', name: '박지호', device: 'Galaxy Tab A9+ (시뮬레이터)', skill: 0.45, x0: 90 },
];

// ───────────────────────── 글씨 모양 ─────────────────────────
// 글자 상자: 폭 0.6, 높이 1 (y 는 아래로 증가). 각 글자는 획(제어점 배열)의 배열.
const ellipse = (cx, cy, rx, ry, a0 = -Math.PI / 2, turns = 1.05, n = 18) => {
  const pts = [];
  for (let i = 0; i <= n; i++) {
    const a = a0 - i / n * Math.PI * 2 * turns;
    pts.push([cx + Math.cos(a) * rx, cy + Math.sin(a) * ry]);
  }
  return pts;
};
const GLYPHS = {
  0: [ellipse(0.3, 0.5, 0.27, 0.5)],
  1: [[[0.18, 0.18], [0.36, 0.02], [0.36, 1]]],
  2: [[[0.04, 0.25], [0.18, 0.03], [0.42, 0.02], [0.55, 0.22], [0.42, 0.52], [0.02, 1], [0.6, 0.99]]],
  3: [[[0.05, 0.12], [0.3, 0.0], [0.53, 0.14], [0.5, 0.38], [0.24, 0.48], [0.54, 0.6], [0.58, 0.84], [0.3, 1], [0.03, 0.9]]],
  4: [[[0.42, 0.0], [0.0, 0.68], [0.62, 0.68]], [[0.45, 0.25], [0.45, 1]]],
  5: [[[0.55, 0.0], [0.1, 0.0], [0.07, 0.44]], [[0.07, 0.44], [0.35, 0.38], [0.58, 0.6], [0.5, 0.92], [0.22, 1], [0.02, 0.9]]],
  6: [[[0.5, 0.02], [0.2, 0.22], [0.05, 0.62], [0.2, 0.98], [0.48, 0.9], [0.55, 0.66], [0.3, 0.5], [0.07, 0.66]]],
  7: [[[0.0, 0.02], [0.6, 0.0], [0.24, 1]]],
  8: [[[0.48, 0.12], [0.3, 0.0], [0.08, 0.15], [0.2, 0.38], [0.48, 0.58], [0.55, 0.85], [0.3, 1], [0.05, 0.85], [0.12, 0.58], [0.42, 0.38], [0.52, 0.2], [0.48, 0.12]]],
  9: [[[0.55, 0.28], [0.3, 0.46], [0.05, 0.3], [0.16, 0.03], [0.48, 0.05], [0.55, 0.3], [0.44, 1]]],
  '=': [[[0.05, 0.38], [0.55, 0.38]], [[0.05, 0.66], [0.55, 0.66]]],
  '+': [[[0.05, 0.52], [0.55, 0.52]], [[0.3, 0.25], [0.3, 0.8]]],
  '-': [[[0.08, 0.52], [0.52, 0.52]]],
  x: [[[0.08, 0.3], [0.52, 0.86]], [[0.52, 0.3], [0.08, 0.86]]],
  '/': [[[0.5, 0.0], [0.1, 1]]],
  '^': [[[0.1, 0.3], [0.3, 0.0], [0.5, 0.3]]],
  '.': [[[0.28, 0.95], [0.3, 0.97]]],
};
const ADVANCE = { '.': 0.35, '^': 0.5, '1': 0.5 };

/** Catmull-Rom 으로 제어점을 부드럽게 이어 촘촘한 점 목록을 만든다 */
function smooth(ctrl, step) {
  if (ctrl.length < 2) return ctrl.slice();
  const out = [];
  const P = (i) => ctrl[Math.max(0, Math.min(ctrl.length - 1, i))];
  for (let i = 0; i < ctrl.length - 1; i++) {
    const p0 = P(i - 1), p1 = P(i), p2 = P(i + 1), p3 = P(i + 2);
    const len = Math.hypot(p2[0] - p1[0], p2[1] - p1[1]);
    const n = Math.max(2, Math.ceil(len / step));
    for (let j = 0; j < n; j++) {
      const t = j / n, t2 = t * t, t3 = t2 * t;
      const f = (a, b, c, d) => 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
      out.push([f(p0[0], p1[0], p2[0], p3[0]), f(p0[1], p1[1], p2[1], p3[1])]);
    }
  }
  out.push(ctrl[ctrl.length - 1]);
  return out;
}

const jitter = (amt) => (Math.random() - 0.5) * amt;
const r3 = (n) => Math.round(n * 1000) / 1000;

/** 점 배열에 필압을 붙인다 (시작·끝은 가볍게, 중간은 출렁이게) */
function withPressure(pts, base = 0.65) {
  const n = pts.length;
  const phase = Math.random() * Math.PI * 2;
  return pts.map((p, i) => {
    const t = n > 1 ? i / (n - 1) : 0.5;
    const ramp = Math.min(1, t / 0.15, (1 - t) / 0.2 + 0.3);
    const wave = 0.12 * Math.sin(i / 4 + phase);
    const pr = Math.max(0.05, Math.min(1, (base + wave) * (0.45 + 0.55 * ramp)));
    return [r3(p[0]), r3(p[1]), r3(pr)];
  });
}

/** 글자열을 획 목록으로 (논리 좌표) */
function textStrokes(text, x, y, size, slant = 0.12) {
  const strokes = [];
  let cx = x;
  for (const ch of text) {
    const g = GLYPHS[ch];
    if (!g) { cx += size * 0.4; continue; }
    const s = size * (0.94 + Math.random() * 0.1);
    const dy = jitter(size * 0.08);
    for (const ctrl of g) {
      const pts = ctrl.map(([gx, gy]) => [cx + (gx + (1 - gy) * slant) * s + jitter(1.2), y + dy + gy * s + jitter(1.2)]);
      strokes.push({ tool: 'pen', points: withPressure(smooth(pts, 3.2)) });
    }
    cx += (ADVANCE[ch] || 0.78) * size;
  }
  return { strokes, endX: cx };
}

/** 좌표축 + 포물선 그래프 */
function graphStrokes(ox, oy, w, h) {
  const strokes = [];
  const axis = (pts) => strokes.push({ tool: 'pen', points: withPressure(smooth(pts, 4), 0.55) });
  axis([[ox - 20, oy], [ox + w, oy + jitter(2)]]); // x축
  axis([[ox + w - 14, oy - 8], [ox + w, oy], [ox + w - 14, oy + 8]]);
  axis([[ox + w * 0.15, oy + 30], [ox + w * 0.15 + jitter(2), oy - h]]); // y축
  axis([[ox + w * 0.15 - 8, oy - h + 14], [ox + w * 0.15, oy - h], [ox + w * 0.15 + 8, oy - h + 14]]);
  // y = (x-2)^2 + 3 을 그래프 영역에 맞춰
  const curve = [];
  for (let i = 0; i <= 40; i++) {
    const xv = -0.6 + (i / 40) * 5.2; // -0.6 ~ 4.6
    const yv = (xv - 2) ** 2 + 3;
    curve.push([ox + w * 0.15 + xv * (w * 0.17), oy - yv * (h / 11)]);
  }
  strokes.push({ tool: 'pen', color: '#2B55D6', points: withPressure(smooth(curve, 5), 0.7) });
  // 꼭짓점 표시
  const vx = ox + w * 0.15 + 2 * (w * 0.17);
  const vy = oy - 3 * (h / 11);
  strokes.push({ tool: 'pen', color: '#D23B33', points: withPressure(smooth(ellipse(vx, vy, 9, 9, 0, 1, 14), 2), 0.8) });
  strokes.push({ tool: 'pen', color: '#2B55D6', points: withPressure(smooth([[vx, vy], [vx + jitter(1), oy]], 6), 0.4) });
  return strokes;
}

// ───────────────────────── 학생 한 명 ─────────────────────────
class SimStudent {
  constructor(info) {
    this.info = info;
    this.seq = 0;
    this.stats = { total: 0, correct: 0, streak: 0, todayCount: 0, wrongByTopic: {} };
    this.strokes = []; // 현재 페이지에 남아 있는 획 (restore 용)
  }
  log(...a) { console.log(`[${this.info.name}]`, ...a); }

  connect() {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(`${URL_ARG}${URL_ARG.includes('?') ? '&' : '?'}role=student`);
      this.ws = ws;
      ws.on('open', () => {
        this.send({ type: 'hello', studentId: this.info.studentId, name: this.info.name, device: this.info.device });
        this.pinger = setInterval(() => this.send({ type: 'ping' }), 15000);
        resolve();
      });
      ws.on('message', (data) => {
        let m;
        try { m = JSON.parse(data.toString()); } catch (_) { return; }
        if (m.type === 'message') this.log(`메시지 받음 — ${m.from || '선생님'}: ${m.text}`);
        else if (m.type === 'error') this.log('서버 오류 응답:', m.reason);
      });
      ws.on('close', () => clearInterval(this.pinger));
      ws.on('error', (e) => reject(e));
    });
  }
  send(obj) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(obj));
  }
  close() { clearInterval(this.pinger); if (this.ws) this.ws.close(1000, 'sim_done'); }

  async page(p) {
    this.strokes = [];
    this.y = 520 + jitter(30);
    this.send({
      type: 'page',
      problemId: p.problemId,
      title: p.title,
      stem: p.stem,
      choices: p.choices,
      pageHeight: 2400,
      // 추가 필드(선택): 대시보드가 단원 표시·<보기> 상자에 사용
      topic: p.topic,
      ...(p.boxItems ? { boxItems: p.boxItems } : {}),
    });
    this.startedAt = Date.now();
    await sleep(400 + Math.random() * 400);
  }

  /** 획 하나를 실제 필기처럼 50ms 마다 조금씩 보낸다 */
  async drawStroke(s) {
    const id = `${this.info.studentId}-${++this.seq}`;
    const tool = s.tool || 'pen';
    const color = s.color || (tool === 'highlighter' ? '#FFD43B' : '#1B2333');
    const width = s.width || (tool === 'highlighter' ? 22 : 3.2);
    const pts = s.points;
    const perChunk = tool === 'highlighter' ? 5 : 4 + Math.floor(Math.random() * 3);
    this.send({ type: 'stroke_begin', id, tool, color, width, points: pts.slice(0, 2) });
    for (let i = 2; i < pts.length; i += perChunk) {
      await sleep(CHUNK_MS);
      this.send({ type: 'stroke_points', id, points: pts.slice(i, i + perChunk) });
    }
    this.send({ type: 'stroke_end', id });
    this.strokes.push({ id, tool, color, width, points: pts });
    await sleep(60 + Math.random() * 120);
    return id;
  }

  async writeLine(text, size = 46) {
    const { strokes } = textStrokes(text, this.info.x0 + jitter(10), this.y, size);
    for (const s of strokes) await this.drawStroke(s);
    this.y += size * 1.9;
    await sleep(300);
  }

  async solve(p) {
    await this.page(p);
    if (p.graph) {
      const g = graphStrokes(this.info.x0 + 40, this.y + 330, 560, 330);
      for (const s of g) await this.drawStroke(s);
      this.y += 420;
    }
    for (const line of p.work) await this.writeLine(line);

    // 형광펜으로 마지막 줄 강조
    const hy = this.y - 46 * 1.9 + 26;
    await this.drawStroke({
      tool: 'highlighter',
      points: withPressure(smooth([[this.info.x0 - 10, hy], [this.info.x0 + 200, hy + 3], [this.info.x0 + 380, hy - 2]], 8), 0.5),
    });

    // 지우개 → 실행취소(restore) 흉내
    if (this.strokes.length > 3 && Math.random() < 0.7) {
      const victim = this.strokes[this.strokes.length - 2];
      this.send({ type: 'erase', ids: [victim.id] });
      await sleep(500);
      this.send({ type: 'restore', strokes: this.strokes });
      await sleep(300);
    }

    // 정답 제출
    const correct = Math.random() < this.info.skill;
    let answer = p.answer;
    if (!correct) {
      if (p.choices) answer = String(((Number(p.answer) + 1 + Math.floor(Math.random() * 3)) % 5) + 1);
      else answer = String(Number(p.answer) + 1 + Math.floor(Math.random() * 3));
    }
    const timeMs = Date.now() - this.startedAt + Math.round(20000 + Math.random() * 60000);
    this.send({ type: 'answer', problemId: p.problemId, answer, correct, timeMs });

    const st = this.stats;
    st.total++; st.todayCount++;
    if (correct) { st.correct++; st.streak++; } else {
      st.streak = 0;
      st.wrongByTopic[p.topic] = (st.wrongByTopic[p.topic] || 0) + 1;
    }
    const weakTopics = Object.entries(st.wrongByTopic).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([t]) => t);
    this.send({ type: 'stats', total: st.total, correct: st.correct, streak: st.streak, todayCount: st.todayCount, weakTopics });
    this.log(`${p.problemId} 제출: ${answer} (${correct ? '정답' : '오답'})`);
    await sleep(900);
  }
}

// ───────────────────────── 실행 ─────────────────────────
async function main() {
  console.log(`시뮬레이터: ${URL_ARG} 에 학생 ${COUNT}명 접속${FOREVER ? ' (계속 반복)' : `, ${ROUNDS}바퀴`}`);
  const sims = STUDENTS.slice(0, COUNT).map((s) => new SimStudent(s));
  try {
    await Promise.all(sims.map((s) => s.connect()));
  } catch (e) {
    console.error(`서버에 연결하지 못했습니다 (${URL_ARG}): ${e.message}\n먼저 다른 창에서 npm start 로 서버를 켜 주세요.`);
    process.exit(1);
  }
  process.on('SIGINT', () => { sims.forEach((s) => s.close()); setTimeout(() => process.exit(0), 200); });

  await Promise.all(sims.map(async (sim, idx) => {
    await sleep(idx * 700);
    for (let round = 0; FOREVER || round < ROUNDS; round++) {
      for (let k = 0; k < 2; k++) {
        const p = PROBLEMS[(idx + round * 2 + k) % PROBLEMS.length];
        await sim.solve(p);
      }
    }
  }));
  // 마지막 필기가 선생님 화면에 남도록 잠깐 기다렸다가 종료
  await sleep(500);
  sims.forEach((s) => s.close());
  console.log('시뮬레이션 끝.');
  setTimeout(() => process.exit(0), 300);
}

main();
