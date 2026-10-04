// stdin: JSON array of TeX math strings → stdout: JSON list of KaTeX errors ("수식: 오류")
// (앱의 flutter_math_fork 는 KaTeX 를 옮긴 것이라 여기서 통과하면 앱에서도 대개 그려진다)
const katex = require('katex');
let src = '';
process.stdin.on('data', (c) => (src += c));
process.stdin.on('end', () => {
  const out = [];
  for (const m of JSON.parse(src || '[]')) {
    try {
      katex.renderToString(m, { throwOnError: true, strict: 'ignore' });
    } catch (e) {
      out.push(`${m.slice(0, 80)} → ${String(e.message).slice(0, 160)}`);
    }
  }
  process.stdout.write(JSON.stringify(out));
});
