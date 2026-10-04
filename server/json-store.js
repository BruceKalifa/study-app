'use strict';
/**
 * 작은 JSON 파일 저장소 (커뮤니티·공부시간 순위용)
 *
 *  - 데이터는 메모리에 들고, save() 로 파일에 쓴다.
 *  - 쓰기는 하나의 대기열로 직렬화하고, 아직 시작하지 않은 저장이 있으면 그것과 합친다(연속 변경 → 한 번 쓰기).
 *  - 임시 파일에 쓴 뒤 rename 으로 바꿔 끼우므로(원자적) 쓰는 도중 꺼져도 파일이 깨지지 않는다.
 *  - 깨진 파일은 덮어쓰기 전에 <파일>.broken-<시각> 으로 보관한다.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

class JsonStore {
  /**
   * @param {{file: string, empty: () => any, log?: (m: string) => void}} opts
   */
  constructor(opts) {
    this.file = path.resolve(opts.file);
    this.empty = opts.empty;
    this.log = opts.log || ((m) => console.warn(m));
    this.data = this.empty();
    this.chain = Promise.resolve();
    this.queued = null;
    this.dirty = false;
  }

  load() {
    try {
      const raw = fs.readFileSync(this.file, 'utf8').replace(/^\uFEFF/, '');
      const data = JSON.parse(raw);
      if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('객체가 아닙니다');
      this.data = Object.assign(this.empty(), data);
    } catch (e) {
      if (e.code !== 'ENOENT') {
        const bad = `${this.file}.broken-${Date.now()}`;
        try { fs.renameSync(this.file, bad); } catch (_) { /* ignore */ }
        this.log(`${path.basename(this.file)} 을(를) 읽지 못해 ${path.basename(bad)} 로 옮기고 새로 시작합니다: ${e.message}`);
      }
      this.data = this.empty();
    }
    return this;
  }

  /** 지금 메모리 내용을 파일에 쓴다 (직렬화 + 합치기). 실패하면 reject */
  save() {
    this.dirty = true;
    if (this.queued) return this.queued;
    const p = this.chain.then(() => {
      this.queued = null; // 이제부터 바뀐 내용은 다음 저장에 들어간다
      return this.writeNow();
    });
    this.queued = p;
    this.chain = p.catch((e) => this.log(`${path.basename(this.file)} 저장 실패: ${e.message}`));
    return p;
  }

  async writeNow() {
    this.dirty = false;
    const body = JSON.stringify(this.data) + '\n';
    const dir = path.dirname(this.file);
    await fs.promises.mkdir(dir, { recursive: true });
    const tmp = path.join(dir, `.${path.basename(this.file)}.${process.pid}.${crypto.randomBytes(3).toString('hex')}.tmp`);
    try {
      await fs.promises.writeFile(tmp, body, 'utf8');
      await fs.promises.rename(tmp, this.file);
    } catch (e) {
      fs.promises.unlink(tmp).catch(() => {});
      this.dirty = true;
      throw e;
    }
  }

  /** 종료 직전 동기 저장 (아직 쓰지 않은 변경이 있을 때만) */
  saveSync() {
    if (!this.dirty) return;
    this.dirty = false;
    try {
      fs.mkdirSync(path.dirname(this.file), { recursive: true });
      const tmp = `${this.file}.${process.pid}.tmp`;
      fs.writeFileSync(tmp, JSON.stringify(this.data) + '\n', 'utf8');
      fs.renameSync(tmp, this.file);
    } catch (e) {
      this.log(`${path.basename(this.file)} 저장 실패: ${e.message}`);
    }
  }
}

module.exports = { JsonStore };
