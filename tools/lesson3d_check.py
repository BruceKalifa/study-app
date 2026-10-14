#!/usr/bin/env python3
"""3D 수업 HTML 을 앱에 올리기 전에 미리 검사한다.

    python3 tools/lesson3d_check.py 수업.html [그림저장폴더]

1) 규칙 검사 — Solvit3D.lesson 이 있는지 · 400KB 이하 · 인터넷 주소/통신/저장소를 안 쓰는지 (text_book.py 와 같은 검사)
2) 그려 보기 — Playwright(Chromium)가 있으면 단계마다 열어 오류를 모으고 화면 그림(PNG)을 저장한다.
   없으면 1) 만 한다  (pip install playwright && playwright install chromium).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from text_book import load_lesson3d  # noqa: E402


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    path = os.path.abspath(argv[0])
    outdir = os.path.abspath(argv[1]) if len(argv) > 1 else None
    problems = []
    load_lesson3d(os.path.dirname(path), os.path.basename(path), problems, os.path.basename(path))
    for p in problems:
        print('✗', p)
    if problems:
        return 1
    print('✓ 규칙 검사 통과')

    runtime = None
    for d in (os.path.dirname(path), os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'lesson3d')):
        q = os.path.join(d, 'solvit3d-runtime.js')
        if os.path.isfile(q):
            runtime = os.path.abspath(q)
            break
    try:
        from playwright.sync_api import sync_playwright
    except Exception:
        print('(Playwright 가 없어서 그려 보기는 건너뛰었어요)')
        return 0
    if not runtime:
        print('(solvit3d-runtime.js 를 못 찾아 그려 보기는 건너뛰었어요)')
        return 0

    html = open(path, encoding='utf-8-sig').read()
    import re
    html = re.sub(r'<script\b[^>]*\bsrc\s*=\s*["\'][^"\']*solvit3d[^"\']*["\'][^>]*>\s*</script>', '', html, flags=re.I)
    inline = open(runtime, encoding='utf-8').read().replace('</script', '<\\/script')
    page_html = '<!doctype html><html><head><meta charset="utf-8"><script>' + inline + '</script></head><body>' + html + '</body></html>'
    # <head> 가 이미 있는 파일은 그대로 두면 안 되므로 head 안에 끼운다
    m = re.search(r'<head[^>]*>', html, flags=re.I)
    if m:
        page_html = html[:m.end()] + '<script>' + inline + '</script>' + html[m.end():]

    exe = os.environ.get('CHROMIUM', '/opt/pw-browsers/chromium')
    kw = dict(args=['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--no-sandbox'])
    if os.path.exists(exe):
        kw['executable_path'] = exe
    errs = []
    with sync_playwright() as pw:
        b = pw.chromium.launch(**kw)
        pg = b.new_page(viewport={'width': 1280, 'height': 800})
        pg.on('console', lambda m: errs.append(f'{m.type}: {m.text}') if m.type in ('error', 'warning') else None)
        pg.on('pageerror', lambda e: errs.append(f'pageerror: {e}'))
        tmp = os.path.join(os.path.dirname(path), '.lesson3d_preview.html')
        with open(tmp, 'w', encoding='utf-8') as f:
            f.write(page_html)
        try:
            pg.goto('file://' + tmp)
            pg.wait_for_timeout(1500)
            st = pg.evaluate('Solvit3D.state()')
            if not st:
                print('✗ 수업이 시작되지 않았어요 (Solvit3D.lesson 이 실행되지 않음)')
                return 1
            n = st['steps']
            if outdir:
                os.makedirs(outdir, exist_ok=True)
            for i in range(n):
                pg.evaluate(f'Solvit3D.goto({i})')
                pg.wait_for_timeout(1200)
                s = pg.evaluate('Solvit3D.state()')
                if s.get('error'):
                    errs.append(f'{i + 1}단계: {s["error"]}')
                if outdir:
                    pg.screenshot(path=os.path.join(outdir, f'단계{i + 1}.png'))
            print(f'✓ {n}단계를 그려 봤어요' + (f' — 그림: {outdir}' if outdir else ''))
        finally:
            b.close()
            try:
                os.remove(tmp)
            except OSError:
                pass
    for e in errs[:10]:
        print('✗', e)
    return 1 if errs else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
