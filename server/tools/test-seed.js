// 처음 켤 때 seed 계정이 들어가는지 (비밀번호는 테스트용으로 따로 해시를 만든다 — 실제 seed 비밀번호는 저장소에 없음)
const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { createAccountsApi } = require('../accounts');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'seed-'));
const salt = 'aa'.repeat(16);
const passHash = crypto.scryptSync('test-pass-1', salt, 32, { N: 16384, r: 8, p: 1 }).toString('hex');
const seedFile = path.join(dir, 'seed.json');
fs.writeFileSync(seedFile, JSON.stringify({ users: [
  { id: 'u_t', role: 'teacher', loginId: 'seed.teacher', name: '선생님', salt, passHash, inviteCode: 'ABCDEF' },
  { id: 'u_s', role: 'student', loginId: 'seed.student', name: '학생', grade: '고2', salt, passHash, teachers: ['u_t'] },
  { id: 'u_x', role: 'admin', loginId: 'bad.role', salt, passHash },
] }));

const api = createAccountsApi({ dataDir: path.join(dir, 'data'), seedFile, log: () => {} });
const t = api.userById('u_t');
const s = api.userById('u_s');
assert.ok(t && t.inviteCode === 'ABCDEF', 'teacher seeded with invite code');
assert.ok(s && s.teachers.includes('u_t') && s.grade === '고2', 'student seeded and linked');
assert.ok(!api.userById('u_x'), 'invalid role skipped');
assert.ok(api.isLinked('u_s', 'u_t'), 'linked');

// a second start with accounts present does not seed again
setTimeout(() => {
  const again = createAccountsApi({ dataDir: path.join(dir, 'data'), seedFile, log: () => {} });
  assert.ok(again.userById('u_t'), 'kept after restart');
  const none = createAccountsApi({ dataDir: path.join(dir, 'empty'), seedFile: null, log: () => {} });
  assert.ok(!none.userById('u_t'), 'no seed file → no accounts');
  console.log('seed: all 6 checks passed');
}, 300);
