/**
 * 교재 창고 웹페이지(/books/) 를 진짜 브라우저로 눌러 본다.
 *
 *   node tools/test-books-web.mjs <서버주소> <선생님아이디> <비밀번호> <학생아이디> <학생비밀번호> <교재.pulinote> …
 *
 * playwright 가 있어야 한다 (`npx playwright install chromium`, 또는 PLAYWRIGHT=<모듈 경로>).
 * CI 는 돌리지 않는다 — 서버 API 는 tools/test-books.js 가, 앱은 flutter test 가 본다.
 */
import fs from 'node:fs';

const mod = await import(process.env.PLAYWRIGHT ?? 'playwright');
const { chromium } = mod.default ?? mod;

const [BASE, TID, PW, SID, SPW, ...FILES] = process.argv.slice(2);
if (!BASE || !TID || !PW || !SID || !SPW || FILES.length < 2) {
  console.error('쓰임: node tools/test-books-web.mjs <서버주소> <선생님아이디> <비밀번호> <학생아이디> <학생비밀번호> <교재1.pulinote> <교재2.pulinote>');
  process.exit(2);
}
const fails = [];
const ok = (cond, what) => { if (!cond) fails.push(what); else console.log('  ✔', what); };

const browser = await chromium.launch();
const page = await browser.newPage();
const errors = [];
// 401 은 일부러 틀린 비밀번호를 넣어 본 것이므로 오류가 아니다
page.on('console', (m) => { if (m.type() === 'error' && !/401/.test(m.text())) errors.push(m.text()); });
page.on('pageerror', (e) => errors.push(String(e)));

await page.goto(new URL('/books/', BASE).href);
console.log('■ 로그인');
ok(await page.locator('#loginPane').isVisible(), '처음엔 로그인 화면');
ok(!(await page.locator('#booksPane').isVisible()), '교재 목록은 숨어 있다');

// 틀린 비밀번호
await page.fill('#loginId', TID);
await page.fill('#password', `${PW}-nope`);
await page.click('#loginBtn');
await page.waitForSelector('#loginError:not([hidden])');
ok((await page.textContent('#loginError')).length > 0, '틀리면 이유를 보여 준다');

// 학생 계정은 들어올 수 없다
await page.fill('#loginId', SID);
await page.fill('#password', SPW);
await page.click('#loginBtn');
await page.waitForFunction(() => document.getElementById('loginError').textContent.includes('선생님'));
ok(true, '학생 계정은 막는다');

// 선생님 로그인
await page.fill('#loginId', TID);
await page.fill('#password', PW);
await page.click('#loginBtn');
await page.waitForSelector('#booksPane:not([hidden])');
ok((await page.textContent('#whoName')).includes('선생님'), '이름이 보인다');

// 빈 창고에서 시작한다 (먼저 돌린 자리가 남아 있을 수 있다)
await page.evaluate(async () => {
  const t = sessionStorage.getItem('pulinote.books.token');
  const h = { Authorization: `Bearer ${t}` };
  const { books } = await (await fetch('/api/books', { headers: h })).json();
  for (const b of books.filter((x) => x.mine)) {
    await fetch(`/api/books/${encodeURIComponent(b.id)}`, { method: 'DELETE', headers: h });
  }
});
await page.click('#refresh');
await page.waitForSelector('#empty:not([hidden])');
ok(true, '아직 교재가 없다고 알려 준다');

console.log('■ 올리기');
await page.setInputFiles('#file', FILES.slice(0, 2));
await page.waitForFunction(() => document.querySelectorAll('#list .row').length === 2, null, { timeout: 15000 });
const titles = await page.locator('.row-title').allTextContents();
ok(titles.length === 2 && titles.every((t) => t && !/\.pulinote$/.test(t)),
   `교재 파일 안의 제목을 쓴다 (파일 이름이 아니라) — ${titles.join(', ')}`);
const meta = await page.locator('.row-meta').first().textContent();
ok(/문항/.test(meta) && /KB|MB/.test(meta), `문항 수와 크기를 보여 준다 — ${meta}`);
ok((await page.textContent('#count')) === '2권', '권수를 보여 준다');
const logText = await page.locator('#log p').first().textContent();
ok(/올렸습니다/.test(logText), `올린 결과를 알려 준다 — ${logText}`);

console.log('■ 다시 올리면 바꿔 끼운다');
await page.setInputFiles('#file', [FILES[0]]);
await page.waitForFunction(() => /바꿔/.test(document.querySelector('#log p')?.textContent || ''), null, { timeout: 15000 });
ok((await page.locator('#list .row').count()) === 2, '권수가 늘지 않는다');

console.log('■ 누가 받을지');
const pick = titles[1];
const row = page.locator('.row').filter({ hasText: pick });
ok(await row.locator('.row-open').isChecked(), '올리면서 모두에게 열었다');
ok(!(await row.locator('.row-students').isVisible()), '모두에게 열려 있으면 학생 고르기는 숨는다');
await row.locator('.row-open').uncheck();
await row.locator('.row-students').waitFor({ state: 'visible' });
ok(true, '끄면 학생 고르기가 나온다');
const chip = row.locator('.chips label').first();
ok((await chip.textContent()).trim().length > 0, `연결된 학생이 나온다 — ${(await chip.textContent()).trim()}`);
await chip.locator('input').check();
await page.waitForTimeout(600);

// 서버에 정말 저장됐나
const res = await page.evaluate(async () => {
  const t = sessionStorage.getItem('pulinote.books.token');
  const r = await fetch('/api/books', { headers: { Authorization: `Bearer ${t}` } });
  return (await r.json()).books.map((b) => ({ title: b.title, open: b.open, students: b.students }));
});
const gs = res.find((b) => b.title === pick);
ok(gs && gs.open === false, '서버에도 "모두에게 열기 끔" 이 저장됐다');
ok(gs && gs.students.length === 1, '고른 학생이 서버에 저장됐다');

console.log('■ 학생이 받는 것');
const seen = await page.evaluate(async ({ id, pw }) => {
  const login = await (await fetch('/api/auth/login', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ loginId: id, password: pw }),
  })).json();
  const r = await fetch('/api/books', { headers: { Authorization: `Bearer ${login.token}` } });
  return (await r.json()).books.map((b) => b.title);
}, { id: SID, pw: SPW });
ok(seen.length === 2, `학생에게 두 권 다 보인다 (열린 것 + 지정된 것) — ${seen.join(', ')}`);

console.log('■ 지우기');
page.on('dialog', (d) => d.accept());
await row.locator('.row-del').click();
await page.waitForFunction(() => document.querySelectorAll('#list .row').length === 1, null, { timeout: 15000 });
ok(true, '지우면 목록에서 빠진다');

console.log('■ 다시 들어와도');
await page.reload();
await page.waitForSelector('#booksPane:not([hidden])');
ok((await page.locator('#list .row').count()) === 1, '로그인이 유지되고 목록이 그대로다');

await page.click('#logout');
await page.waitForSelector('#loginPane:not([hidden])');
ok(true, '로그아웃하면 로그인 화면으로');

ok(errors.length === 0, `자바스크립트 오류 없음 — ${errors.join(' | ') || '없음'}`);
await browser.close();
console.log(fails.length ? `\n✘ 실패 ${fails.length}: ${fails.join(' / ')}` : '\n✔ 모두 통과');
process.exit(fails.length ? 1 : 0);
