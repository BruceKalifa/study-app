#!/usr/bin/env node
'use strict';
/**
 * 예전 샘플 문제 정리 점검: legacy-samples.json 의 지문과 바이트까지 같은 파일만 지우고,
 * 고쳤거나 새로 만든 과목은 남긴다. 빈 저장소는 앱에 실린 골격 과목으로 채운다.
 *
 *   node tools/test-purge.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { ContentStore } = require('../content-store');

const FIX = path.join(__dirname, '..', '..', 'test', 'fixtures', 'problems');
const SEED = path.join(__dirname, '..', '..', 'assets', 'problems');
let failed = 0;
function ok(cond, label) { console.log(`  ${cond ? '✔' : '✘'} ${label}`); if (!cond) failed++; }
const quiet = () => {};

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pulinote-purge-'));
try {
  console.log('■ 예전 샘플 지우기');
  const dir = path.join(tmp, 'old');
  fs.mkdirSync(dir);
  fs.copyFileSync(path.join(FIX, 'math.json'), path.join(dir, 'math.json')); // 그대로 → 지움
  fs.copyFileSync(path.join(FIX, 'workbooks.json'), path.join(dir, 'workbooks.json')); // 그대로 → 지움
  const edited = JSON.parse(fs.readFileSync(path.join(FIX, 'phy1.json'), 'utf8'));
  edited.subject = '물리학Ⅰ (내가 고침)';
  fs.writeFileSync(path.join(dir, 'phy1.json'), JSON.stringify(edited, null, 2) + '\n'); // 고친 것 → 남김
  fs.writeFileSync(path.join(dir, 'mine.json'), JSON.stringify({ subject: '내 과목', subjectId: 'mine', group: 'sci', level: 'high', grades: ['고3'], problems: [] }));
  const store = new ContentStore({ dir, seedDir: SEED, log: quiet }).init();
  ok(!fs.existsSync(path.join(dir, 'math.json')), '그대로인 샘플 과목은 지운다');
  const wbNow = JSON.parse(fs.readFileSync(path.join(dir, 'workbooks.json'), 'utf8'));
  ok(Array.isArray(wbNow.workbooks) && wbNow.workbooks.length === 0, '그대로인 샘플 문제집은 비운다');
  ok(fs.existsSync(path.join(dir, 'phy1.json')), '고친 과목은 남긴다');
  ok(fs.existsSync(path.join(dir, 'mine.json')), '새로 만든 과목은 남긴다');
  ok(fs.existsSync(path.join(dir, '.seeded')), '다시 채우지 않게 표시한다');
  ok([...store.courses.keys()].sort().join(',') === 'mine,phy1', '남은 과목만 읽는다: ' + [...store.courses.keys()].join(','));

  console.log('■ 다시 켜도 그대로');
  const again = new ContentStore({ dir, seedDir: SEED, log: quiet }).init();
  ok([...again.courses.keys()].sort().join(',') === 'mine,phy1', '골격 과목을 덧붙이지 않는다');

  console.log('■ 빈 저장소');
  const fresh = new ContentStore({ dir: path.join(tmp, 'fresh'), seedDir: SEED, log: quiet }).init();
  ok([...fresh.courses.keys()].sort().join(',') === 'calc1,calc2,emath1,emath2', '앱에 실린 골격 과목 4개: ' + [...fresh.courses.keys()].join(','));
  ok([...fresh.courses.values()].every((c) => c.data.problems.length === 0), '문제는 하나도 없다');
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
console.log(failed ? `\n✘ 실패 ${failed}` : '\n✔ 모두 통과');
process.exit(failed ? 1 : 0);
