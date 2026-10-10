#!/usr/bin/env python3
"""
PDF → 앱 개념 교재 (.pulinote) — TeX 원문이 없는 PDF 를 고화질 쪽 이미지로 싣는다.

  python3 tools/pdf_book.py <PDF> <출력.pulinote> --title "교재 이름" --course 물리학1 [옵션]

앱에서는 쪽 이미지가 PDF 그대로 펼쳐지고, 그 위에 펜으로 필기한다 (개념 페이지와 같다).

옵션
  --pages 3-30        싣을 쪽 (기본: 전부). 쉼표로 여러 구간: 3-12,40-45
  --per 1             개념 하나에 쪽을 몇 장씩 묶을지 (기본 1)
  --toc 목차.txt      개념을 직접 나눈다. 한 줄에 `제목 | 시작쪽-끝쪽 | 단원(선택) | 종류(선택)` (# 으로 시작하면 주석)
  --width 2000        이미지 가로 픽셀 (기본 2000 — 태블릿에서 두 배 확대해도 선명)
  --quality 82        WebP 품질 (기본 82)
  --mask 쪽:x0,y0,x1,y1   가릴 영역(쪽 크기에 대한 0~1 비율). 풀이가 인쇄돼 있어 먼저 보이면 안 되는 곳. 여러 번 쓸 수 있다
  --grades 고3,N수    대상 학년 (기본: 과목에 맞게)
  --unit 단원         개념의 단원 이름 (기본: 교재 이름)
  --kind 개념         개념 | 실전개념 | 공식 정리
  --id 아이디         교재 id (기본: 이름에서 만든다)
  --publisher 이름    만든 곳
쪽당 용량은 대개 100~250KB 이다. 서버는 파일 하나 40MB 까지 받으니 한 교재가 크면 --pages 로 나눠 만든다.
교재 내용은 저작물이므로 출력은 저장소에 넣지 않는다.
"""
import argparse
import base64
import gzip
import io
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import text_book as tb  # noqa: E402

KINDS = ('개념', '실전개념', '공식 정리')
MAX_FILE = 40 * 1024 * 1024


def parse_ranges(spec, total):
    if not spec:
        return list(range(1, total + 1))
    out = []
    for part in spec.split(','):
        part = part.strip()
        if not part:
            continue
        m = re.fullmatch(r'(\d+)(?:-(\d+))?', part)
        if not m:
            raise SystemExit(f'쪽 범위를 읽을 수 없어요: "{part}" (예: 3-30 또는 3-12,40-45)')
        a, b = int(m.group(1)), int(m.group(2) or m.group(1))
        if a < 1 or b < a or b > total:
            raise SystemExit(f'쪽 범위가 PDF({total}쪽) 밖이에요: "{part}"')
        out.extend(range(a, b + 1))
    return list(dict.fromkeys(out))


def parse_toc(path, total):
    items = []
    for n, line in enumerate(open(path, encoding='utf-8-sig'), 1):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        cells = [c.strip() for c in line.split('|')]
        if len(cells) < 2:
            raise SystemExit(f'{path} {n}번째 줄: `제목 | 시작쪽-끝쪽` 으로 써 주세요 — "{line}"')
        pages = parse_ranges(cells[1], total)
        kind = cells[3] if len(cells) > 3 and cells[3] else '개념'
        if kind not in KINDS:
            raise SystemExit(f'{path} {n}번째 줄: 종류는 {" · ".join(KINDS)} 중에서 — "{kind}"')
        items.append({'title': cells[0], 'pages': pages, 'unit': cells[2] if len(cells) > 2 else '', 'kind': kind})
    return items


def parse_masks(specs):
    masks = {}
    for s in specs or []:
        m = re.fullmatch(r'(\d+):([\d.]+),([\d.]+),([\d.]+),([\d.]+)', s.strip())
        if not m:
            raise SystemExit(f'--mask 는 쪽:x0,y0,x1,y1 (0~1) 으로 써 주세요 — "{s}"')
        page = int(m.group(1))
        box = [float(m.group(i)) for i in range(2, 6)]
        if not (0 <= box[0] < box[2] <= 1 and 0 <= box[1] < box[3] <= 1):
            raise SystemExit(f'--mask 영역이 0~1 범위/순서가 아니에요: "{s}"')
        masks.setdefault(page, []).append(box)
    return masks


def render_page(pdf, page, width, quality, masks, tmp):
    """한 쪽을 가로 width 픽셀 WebP 로. 반환: (data URI, 가로, 세로, 바이트)."""
    from PIL import Image, ImageDraw
    prefix = os.path.join(tmp, f'p{page}')
    subprocess.run(['pdftoppm', '-r', '72', '-scale-to-x', str(width), '-scale-to-y', '-1', '-f', str(page), '-l', str(page),
                    '-png', pdf, prefix], check=True)
    cands = [f for f in os.listdir(tmp) if f.startswith(f'p{page}-') and f.endswith('.png')]
    if not cands:
        raise SystemExit(f'{page}쪽을 그리지 못했어요 (pdftoppm)')
    path = os.path.join(tmp, sorted(cands)[0])
    im = Image.open(path).convert('RGB')
    for x0, y0, x1, y1 in masks.get(page, []):
        w, h = im.size
        ImageDraw.Draw(im).rectangle([x0 * w, y0 * h, x1 * w, y1 * h], fill=(255, 255, 255))
    buf = io.BytesIO()
    im.save(buf, 'WEBP', quality=quality, method=6)
    os.remove(path)
    raw = buf.getvalue()
    return 'data:image/webp;base64,' + base64.b64encode(raw).decode(), im.size[0], im.size[1], len(raw)


def build(pdf, title, course, pages, per, toc, width, quality, masks, grades, unit, kind, book_id, publisher, log=print):
    cid, cname, color, group = tb.course_of(course, generic=[course])
    book_id = book_id or tb.stable_slug(title)
    unit = unit or title
    if toc:
        groups = toc
    else:
        groups = []
        for i in range(0, len(pages), per):
            chunk = pages[i:i + per]
            t = f'{chunk[0]}쪽' if len(chunk) == 1 else f'{chunk[0]}–{chunk[-1]}쪽'
            groups.append({'title': t, 'pages': chunk, 'unit': '', 'kind': kind})
    concepts, total_bytes = [], 0
    with tempfile.TemporaryDirectory() as tmp:
        for g in groups:
            imgs = []
            for pg in g['pages']:
                uri, w, h, n = render_page(pdf, pg, width, quality, masks, tmp)
                imgs.append(uri)
                total_bytes += n
            concepts.append({
                'id': f'{book_id}-p{g["pages"][0]:04d}',
                'title': g['title'],
                'kind': g['kind'],
                'unit': g['unit'] or unit,
                'topic': '',
                'section': g['unit'] or unit,
                'body': '',
                'images': imgs,
            })
            log(f'  {g["title"]}: {len(imgs)}쪽')
    course_obj = {
        'subject': cname, 'subjectId': cid, 'color': color, 'group': group,
        'level': 'mid' if grades and all(x.startswith('중') for x in grades) else 'high',
        'grades': grades or tb.DEFAULT_GRADES.get(group, ['고2', '고3']), 'track': '수능' if group in ('sci', 'math') else '공통',
        'passages': [], 'problems': [], 'units': [], 'concepts': concepts,
    }
    wb = {'id': book_id, 'title': title, 'course': cid, 'stage': '개념', 'scope': '', 'level': '기본',
          'publisher': publisher, 'series': title, 'desc': f'{title} — PDF 그대로 ({len(pages)}쪽)',
          'problems': [], 'concepts': [c['id'] for c in concepts]}
    bundle = {'format': 'pulinote-bundle', 'version': 1, 'id': book_id, 'title': title, 'courses': [course_obj], 'workbooks': [wb]}
    return bundle, total_bytes


def main(argv=None):
    ap = argparse.ArgumentParser(description='PDF → 개념 교재(.pulinote)', add_help=True)
    ap.add_argument('pdf')
    ap.add_argument('out')
    ap.add_argument('--title', required=True)
    ap.add_argument('--course', required=True)
    ap.add_argument('--pages', default='')
    ap.add_argument('--per', type=int, default=1)
    ap.add_argument('--toc')
    ap.add_argument('--width', type=int, default=2000)
    ap.add_argument('--quality', type=int, default=82)
    ap.add_argument('--mask', action='append')
    ap.add_argument('--grades', default='')
    ap.add_argument('--unit', default='')
    ap.add_argument('--kind', default='개념')
    ap.add_argument('--id', default='')
    ap.add_argument('--publisher', default='')
    a = ap.parse_args(argv)
    if a.kind not in KINDS:
        raise SystemExit(f'--kind 는 {" · ".join(KINDS)} 중에서 골라 주세요')
    info = subprocess.run(['pdfinfo', a.pdf], capture_output=True, text=True, check=True).stdout
    total = int(re.search(r'Pages:\s+(\d+)', info).group(1))
    pages = parse_ranges(a.pages, total)
    toc = parse_toc(a.toc, total) if a.toc else None
    grades = [g.strip() for g in a.grades.split(',') if g.strip()]
    print(f'{os.path.basename(a.pdf)}: {total}쪽 중 {len(toc and [p for g in toc for p in g["pages"]] or pages)}쪽을 만들어요')
    bundle, n = build(a.pdf, a.title, a.course, pages, max(1, a.per), toc, a.width, a.quality, parse_masks(a.mask), grades,
                      a.unit, a.kind, a.id, a.publisher)
    data = gzip.compress(json.dumps(bundle, ensure_ascii=False, separators=(',', ':')).encode())
    open(a.out, 'wb').write(data)
    mb = len(data) / 1048576
    print(f'→ {a.out}  ({mb:.1f}MB, 이미지 {n / 1048576:.1f}MB)')
    if len(data) > MAX_FILE:
        print('⚠ 서버 한도(40MB)를 넘어요. --pages 로 나눠서 여러 교재로 만들어 주세요.')


def selftest():
    """PIL 로 만든 3쪽 PDF 로 변환 전체를 돌려 본다."""
    from PIL import Image, ImageDraw
    with tempfile.TemporaryDirectory() as tmp:
        pages = []
        for k in range(3):
            im = Image.new('RGB', (595, 842), 'white')
            ImageDraw.Draw(im).text((60, 60 + k * 10), f'page {k + 1}', fill='black')
            pages.append(im)
        pdf = os.path.join(tmp, 't.pdf')
        pages[0].save(pdf, save_all=True, append_images=pages[1:])
        out = os.path.join(tmp, 'o.pulinote')
        toc = os.path.join(tmp, 'toc.txt')
        open(toc, 'w', encoding='utf-8').write('# 주석\n첫 장 | 1-2 | 1단원\n공식 | 3 | 1단원 | 공식 정리\n')
        main([pdf, out, '--title', '시험 교재', '--course', '물리학1', '--toc', toc, '--width', '800', '--mask', '1:0,0,0.5,0.5'])
        b = json.loads(gzip.decompress(open(out, 'rb').read()))
        c = b['courses'][0]['concepts']
        assert [x['title'] for x in c] == ['첫 장', '공식'], c
        assert [len(x['images']) for x in c] == [2, 1]
        assert c[1]['kind'] == '공식 정리' and c[0]['section'] == '1단원'
        assert b['workbooks'][0]['concepts'] == [x['id'] for x in c]
        assert b['courses'][0]['subjectId'] == 'phy1', b['courses'][0]['subjectId']
        assert c[0]['images'][0].startswith('data:image/webp;base64,')
        im = Image.open(io.BytesIO(base64.b64decode(c[0]['images'][0].split(',', 1)[1])))
        assert im.size[0] == 800, im.size
        assert im.getpixel((10, 10)) == (255, 255, 255), '가린 영역은 흰색'
        out2 = os.path.join(tmp, 'o2.pulinote')
        main([pdf, out2, '--title', '시험 교재 2', '--course', '물리학1', '--per', '2', '--width', '400'])
        b2 = json.loads(gzip.decompress(open(out2, 'rb').read()))
        assert [x['title'] for x in b2['courses'][0]['concepts']] == ['1–2쪽', '3쪽']
    print('pdf_book selftest ok')


if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == 'selftest':
        selftest()
    else:
        main()
