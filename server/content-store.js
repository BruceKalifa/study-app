'use strict';
/**
 * 문제 콘텐츠 저장소 — server/content/*.json (과목 하나 = 파일 하나) + workbooks.json
 *
 *  - 처음 켤 때 과목 파일이 하나도 없으면 ../assets/problems 의 기본 문제를 복사해 채운다.
 *  - 모든 변경은 mutate() 하나의 대기열로 순서대로 처리하고, 파일은 임시 파일 → rename 으로 원자적으로 쓴다.
 *  - version = 파일 내용의 sha1 앞 16자리 (파일이 바뀌면 반드시 바뀐다).
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const WORKBOOKS_FILE = 'workbooks.json';

function sha1(buf) {
  return crypto.createHash('sha1').update(buf).digest('hex').slice(0, 16);
}
function serialize(obj) {
  return JSON.stringify(obj, null, 2) + '\n';
}
function clone(obj) {
  return JSON.parse(JSON.stringify(obj));
}
function isCourseFile(name) {
  return name.endsWith('.json') && name !== WORKBOOKS_FILE && !name.startsWith('_') && !name.startsWith('.');
}

class ContentStore {
  /**
   * @param {{dir: string, seedDir?: string, log?: (msg: string) => void}} opts
   */
  constructor(opts) {
    this.dir = path.resolve(opts.dir);
    this.seedDir = opts.seedDir ? path.resolve(opts.seedDir) : null;
    this.log = opts.log || ((m) => console.log(m));
    /** @type {Map<string, {data: any, canon: string, version: string, file: string, updatedAt: number, bytes: number}>} */
    this.courses = new Map();
    this.wb = { data: { workbooks: [] }, canon: serialize({ workbooks: [] }), version: '', updatedAt: 0, exists: false };
    this.queue = Promise.resolve();
    this.seeded = 0;
  }

  // ───────────── 시작 ─────────────
  init() {
    fs.mkdirSync(this.dir, { recursive: true });
    this.purgeLegacySamples();
    const hasCourse = fs.readdirSync(this.dir).some(isCourseFile);
    // .seeded 표시가 있으면(예전에 채운 뒤 선생님이 과목을 모두 지운 경우) 다시 채우지 않는다
    if (!hasCourse && !fs.existsSync(path.join(this.dir, '.seeded'))) this.seed();
    else this.seedWorkbooksIfMissing();
    this.loadAll();
    return this;
  }

  /**
   * 예전에 기본으로 넣었던 샘플 문제 파일을 지운다. legacy-samples.json 의 지문(sha256)과
   * 바이트까지 똑같은 파일만 지우므로, 선생님이 고치거나 새로 만든 과목·문제집은 그대로 남는다.
   * (교재는 별도 저장소(books)에 있어 건드리지 않는다.)
   */
  purgeLegacySamples() {
    let legacy;
    try {
      legacy = JSON.parse(fs.readFileSync(path.join(__dirname, 'legacy-samples.json'), 'utf8')).files || {};
    } catch (_) {
      return;
    }
    let n = 0;
    for (const [name, hashes] of Object.entries(legacy)) {
      if (!name.endsWith('.json') || name !== path.basename(name)) continue;
      const full = path.join(this.dir, name);
      let buf;
      try { buf = fs.readFileSync(full); } catch (_) { continue; }
      const h = crypto.createHash('sha256').update(buf).digest('hex');
      if (!Array.isArray(hashes) || !hashes.includes(h)) continue;
      try { fs.unlinkSync(full); n++; } catch (e) { this.log(`샘플 문제 ${name} 을(를) 지우지 못했습니다: ${e.message}`); }
    }
    if (n) {
      const mark = path.join(this.dir, '.seeded');
      // 다시 채우지 않도록 표시
      try { if (!fs.existsSync(mark)) fs.writeFileSync(mark, new Date().toISOString() + '\n'); } catch (_) { /* ignore */ }
      this.log(`예전 샘플 문제 파일 ${n}개를 지웠습니다 → ${this.dir}`);
    }
  }

  seed() {
    if (!this.seedDir) return;
    let files = [];
    try {
      const idx = JSON.parse(fs.readFileSync(path.join(this.seedDir, '_index.json'), 'utf8'));
      files = Array.isArray(idx.files) ? idx.files : [];
    } catch (e) {
      this.log(`기본 문제 목록(_index.json)을 읽지 못했습니다: ${e.message}`);
      return;
    }
    let n = 0;
    for (const f of files) {
      const name = path.basename(String(f));
      if (!isCourseFile(name)) continue;
      try {
        const buf = fs.readFileSync(path.join(this.seedDir, name));
        JSON.parse(buf.toString('utf8')); // 깨진 파일은 복사하지 않는다
        this.writeFileSync(name, buf);
        n++;
      } catch (e) {
        this.log(`기본 문제 ${name} 복사 실패: ${e.message}`);
      }
    }
    const wbSrc = path.join(this.seedDir, WORKBOOKS_FILE);
    if (fs.existsSync(wbSrc)) {
      try {
        const buf = fs.readFileSync(wbSrc);
        JSON.parse(buf.toString('utf8'));
        this.writeFileSync(WORKBOOKS_FILE, buf);
      } catch (e) {
        this.log(`기본 문제집 workbooks.json 복사 실패: ${e.message}`);
      }
    }
    this.seeded = n;
    try { fs.writeFileSync(path.join(this.dir, '.seeded'), new Date().toISOString() + '\n'); } catch (_) { /* ignore */ }
    this.log(`문제 저장소가 비어 있어 기본 문제 ${n}개 과목을 복사했습니다 → ${this.dir}`);
  }

  /** 과목은 이미 있는데 workbooks.json 만 없으면(기본 문제집이 나중에 생긴 경우) 그것만 복사 */
  seedWorkbooksIfMissing() {
    if (!this.seedDir || fs.existsSync(path.join(this.dir, WORKBOOKS_FILE))) return;
    const src = path.join(this.seedDir, WORKBOOKS_FILE);
    if (!fs.existsSync(src)) return;
    try {
      const buf = fs.readFileSync(src);
      JSON.parse(buf.toString('utf8'));
      this.writeFileSync(WORKBOOKS_FILE, buf);
      this.log(`기본 문제집 workbooks.json 을 복사했습니다 → ${this.dir}`);
    } catch (e) {
      this.log(`기본 문제집 workbooks.json 복사 실패: ${e.message}`);
    }
  }

  writeFileSync(name, buf) {
    const tmp = path.join(this.dir, `.${name}.${process.pid}.tmp`);
    fs.writeFileSync(tmp, buf);
    fs.renameSync(tmp, path.join(this.dir, name));
  }

  loadAll() {
    this.courses.clear();
    for (const name of fs.readdirSync(this.dir).filter(isCourseFile).sort()) {
      const full = path.join(this.dir, name);
      try {
        const buf = fs.readFileSync(full);
        const data = JSON.parse(buf.toString('utf8'));
        if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('과목 객체가 아닙니다');
        const id = typeof data.subjectId === 'string' && data.subjectId ? data.subjectId : name.replace(/\.json$/, '');
        if (!Array.isArray(data.problems)) data.problems = [];
        if (this.courses.has(id)) {
          this.log(`과목 id "${id}" 가 두 파일에 있습니다. ${name} 은(는) 건너뜁니다.`);
          continue;
        }
        this.courses.set(id, {
          data,
          canon: serialize(data),
          version: sha1(buf),
          file: name,
          updatedAt: fs.statSync(full).mtimeMs,
          bytes: buf.length,
        });
      } catch (e) {
        this.log(`과목 파일 ${name} 을(를) 읽지 못했습니다(건너뜀): ${e.message}`);
      }
    }
    const wbPath = path.join(this.dir, WORKBOOKS_FILE);
    if (fs.existsSync(wbPath)) {
      try {
        const buf = fs.readFileSync(wbPath);
        let data = JSON.parse(buf.toString('utf8'));
        if (Array.isArray(data)) data = { workbooks: data };
        if (!data || !Array.isArray(data.workbooks)) data = { workbooks: [] };
        this.wb = { data, canon: serialize(data), version: sha1(buf), updatedAt: fs.statSync(wbPath).mtimeMs, exists: true };
      } catch (e) {
        this.log(`workbooks.json 을 읽지 못했습니다: ${e.message}`);
      }
    }
    if (!this.wb.version) this.wb.version = sha1(this.wb.canon);
    this.log(`문제 저장소: 과목 ${this.courses.size}개, 문제집 ${this.wb.data.workbooks.length}개 (${this.dir})`);
  }

  // ───────────── 읽기 ─────────────
  courseIds() {
    return Array.from(this.courses.keys());
  }
  getCourse(id) {
    return this.courses.get(id) || null;
  }
  workbooks() {
    return this.wb;
  }

  /** 다른 과목의 문항·지문 id → 과목 id */
  foreignIds(exceptCourseId, coursesMap) {
    const out = new Map();
    const src = coursesMap || new Map(Array.from(this.courses, ([k, v]) => [k, v.data]));
    for (const [cid, c] of src) {
      if (cid === exceptCourseId) continue;
      for (const p of c.problems || []) if (p && typeof p.id === 'string') out.set(p.id, cid);
      for (const p of c.passages || []) if (p && typeof p.id === 'string') out.set(p.id, cid);
    }
    return out;
  }

  /** 문항 id → { course, twinOf } (문제집 검증용) */
  problemIndex(coursesMap) {
    const out = new Map();
    const src = coursesMap || new Map(Array.from(this.courses, ([k, v]) => [k, v.data]));
    for (const [cid, c] of src) {
      for (const p of c.problems || []) if (p && typeof p.id === 'string') out.set(p.id, { course: cid, twinOf: p.twinOf || null });
    }
    return out;
  }

  // ───────────── 쓰기 ─────────────
  /**
   * 변경을 대기열에 넣는다. fn(draft) 은 draft.courses(Map id → 과목 객체)와 draft.workbooks(배열)를
   * 자유롭게 고치고 결과를 돌려준다. 예외를 던지면 아무것도 저장하지 않는다.
   * 과목 이름 변경: draft.renames.set(새id, 옛id)
   */
  mutate(fn) {
    const run = async () => {
      const draft = {
        courses: new Map(Array.from(this.courses, ([k, v]) => [k, clone(v.data)])),
        workbooks: clone(this.wb.data.workbooks),
        renames: new Map(),
      };
      const result = await fn(draft);
      await this.commit(draft);
      return result;
    };
    const p = this.queue.then(run, run);
    this.queue = p.catch(() => {});
    return p;
  }

  async commit(draft) {
    const now = Date.now();
    const writes = [];
    const nextCourses = new Map();
    const usedFiles = new Set();
    for (const [id, data] of draft.courses) {
      const prevId = draft.renames.get(id) || id;
      const prev = this.courses.get(prevId);
      if (!Array.isArray(data.problems)) data.problems = [];
      const canon = serialize(data);
      let file = prev && prevId === id ? prev.file : `${id}.json`;
      if (usedFiles.has(file)) file = `${id}.json`;
      usedFiles.add(file);
      if (prev && prevId === id && prev.canon === canon) {
        nextCourses.set(id, prev);
        continue;
      }
      const buf = Buffer.from(canon, 'utf8');
      writes.push({ file, buf });
      nextCourses.set(id, { data, canon, version: sha1(buf), file, updatedAt: now, bytes: buf.length });
    }
    const removeFiles = [];
    for (const [, prev] of this.courses) {
      if (!usedFiles.has(prev.file)) removeFiles.push(prev.file);
    }
    let nextWb = this.wb;
    const wbData = { workbooks: draft.workbooks };
    const wbCanon = serialize(wbData);
    if (wbCanon !== this.wb.canon) {
      const buf = Buffer.from(wbCanon, 'utf8');
      writes.push({ file: WORKBOOKS_FILE, buf });
      nextWb = { data: wbData, canon: wbCanon, version: sha1(buf), updatedAt: now, exists: true };
    }
    await fs.promises.mkdir(this.dir, { recursive: true });
    for (const w of writes) {
      const tmp = path.join(this.dir, `.${w.file}.${process.pid}.${crypto.randomBytes(3).toString('hex')}.tmp`);
      await fs.promises.writeFile(tmp, w.buf);
      await fs.promises.rename(tmp, path.join(this.dir, w.file));
    }
    if (removeFiles.length) await fs.promises.mkdir(path.join(this.dir, '_trash'), { recursive: true });
    for (const f of removeFiles) {
      // 바로 지우지 않고 _trash/ 로 옮겨 실수를 되돌릴 수 있게 한다
      const from = path.join(this.dir, f);
      const to = path.join(this.dir, '_trash', `${now}-${f}`);
      try { await fs.promises.rename(from, to); } catch (e) { if (e.code !== 'ENOENT') throw e; }
    }
    this.courses = nextCourses;
    this.wb = nextWb;
    return { written: writes.map((w) => w.file), removed: removeFiles };
  }
}

module.exports = { ContentStore, serialize, sha1 };
