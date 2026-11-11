#!/usr/bin/env python3
"""
원본 PDF 문제 교재 → 앱 교재 (.pulinote) — 문항을 PDF 모양 그대로 보여 준다 (그림으로 찍지 않는다).

  python3 tools/pdf_exam.py <교재 폴더> [출력 폴더]
  python3 tools/pdf_exam.py selftest

교재 폴더:
  정보.txt   머리말(- 교재명: … · - 과목: … · - 최종본: 파일.pdf …)과 [문항 목록] 표
             문항번호 | PDF 쪽 | 단원 | 유형 | 객관식/단답형 | 정답 | 난이도(1~5) | 배점 | 쌍둥이 원본 번호 | 출처
  *.pdf      최종본 (정보.txt 의 '최종본', 없으면 폴더의 첫 PDF)
  영역.txt   (선택) 자동으로 못 찾은 문항의 영역을 직접: `문항번호 | 쪽 | x0,y0,x1,y1` (포인트, 쪽 왼쪽 위 원점)

하는 일
  1. 쪽마다 글자 위치(pdftotext -bbox)와 잉크(pdftoppm)를 읽어 단(column)을 나누고,
     줄 맨 앞의 문항 머리(기출문제·변형·심화·예제·1. …)로 문항의 시작을 찾는다.
     머리 모양이 다른 교재는 정보.txt 에 `- 문항 시작: 정규식` 으로 알려 준다.
  2. 다음 문항 머리(또는 단의 끝)까지를 그 문항의 영역으로 잡고, 잉크가 있는 곳까지 줄인다.
  3. 객관식이면 영역 안의 ①~⑤ 글자 자리를 찾아 둔다 (앱에서 그 자리를 눌러 고른다).
  4. PDF 를 교재 파일 안에 넣는다 (`pdfs`). 앱은 그 PDF 를 pdfium 으로 그대로 그린다.
  5. 출력 폴더에 `<id>.pulinote` 와 확인용 `미리보기/` (쪽마다 잡은 영역을 그린 그림)를 만든다.

교재 내용은 저작물이므로 출력은 저장소에 넣지 않는다.
"""
import base64
import gzip
import hashlib
import html
import io
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import text_book as tb  # noqa: E402

# 줄 맨 앞 글(낱말을 띄어 이은 것)이 이렇게 시작하면 문항 머리. '숙제 문항 • DAY 1' 같은 목차 제목은 아니다.
DEFAULT_ANCHOR = r'^(기출문제|기출(?!\s*문항)|변형|심화|예제|유제|확인\s*문제\s*\d|문제\s*\d|숙제\s*\d|\d{1,2}\.(?!\d)|\d{1,2}\)|\[\d{1,2}\]|[Qq]\d{1,2}\.?)'
CIRCLED = '①②③④⑤⑥⑦⑧⑨'
TOP_BAND, BOTTOM_BAND = 0.055, 0.955  # 머리말·꼬리말 줄 (쪽 높이 비율)


# ───────────────────────── PDF 읽기 ─────────────────────────

def page_count(pdf):
    out = subprocess.run(['pdfinfo', pdf], capture_output=True, text=True, check=True).stdout
    return int(re.search(r'Pages:\s+(\d+)', out).group(1))


def page_words(pdf, page):
    """→ (쪽 가로, 세로, [{x0,y0,x1,y1,t}])  좌표는 포인트, 왼쪽 위 원점."""
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, 'w.html')
        subprocess.run(['pdftotext', '-f', str(page), '-l', str(page), '-bbox', pdf, out], check=True,
                       capture_output=True)
        s = open(out, encoding='utf-8').read()
    m = re.search(r'<page width="([\d.]+)" height="([\d.]+)"', s)
    w, h = float(m.group(1)), float(m.group(2))
    words = []
    for x0, y0, x1, y1, t in re.findall(
            r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', s):
        t = html.unescape(t).strip()
        if t:
            words.append({'x0': float(x0), 'y0': float(y0), 'x1': float(x1), 'y1': float(y1), 't': t})
    return w, h, words


def page_ink(pdf, page):
    """→ 72dpi 흑백 그림 (1픽셀 = 1포인트). 밝기 200 미만을 잉크로 본다."""
    from PIL import Image
    with tempfile.TemporaryDirectory() as tmp:
        base = os.path.join(tmp, 'p')
        subprocess.run(['pdftoppm', '-f', str(page), '-l', str(page), '-r', '72', '-gray', '-singlefile', pdf, base],
                       check=True, capture_output=True)
        return Image.open(base + '.pgm').copy()


def ink_box(img, x0, y0, x1, y1, skip_x=()):
    """[x0,x1)×[y0,y1) 안에서 잉크가 있는 가장 작은 네모 (없으면 None). skip_x: 무시할 세로줄 x 들."""
    W, H = img.size
    x0, y0 = max(0, int(x0)), max(0, int(y0))
    x1, y1 = min(W, int(x1 + 0.999)), min(H, int(y1 + 0.999))
    if x1 <= x0 or y1 <= y0:
        return None
    px = img.load()
    bx0 = by0 = 10 ** 9
    bx1 = by1 = -1
    for y in range(y0, y1):
        for x in range(x0, x1):
            if any(abs(x - s) <= 2 for s in skip_x):
                continue
            if px[x, y] < 200:
                if x < bx0:
                    bx0 = x
                if x > bx1:
                    bx1 = x
                if y < by0:
                    by0 = y
                if y > by1:
                    by1 = y
    if bx1 < 0:
        return None
    return bx0, by0, bx1 + 1, by1 + 1


def vertical_rule(img, top, bottom):
    """쪽 가운데쯤 단을 가르는 세로줄의 x (없으면 None)."""
    W, H = img.size
    px = img.load()
    span = max(1, int(bottom) - int(top))
    best, best_x = 0, None
    for x in range(int(W * 0.35), int(W * 0.65)):
        n = sum(1 for y in range(int(top), int(bottom)) if px[x, y] < 160)
        if n > best:
            best, best_x = n, x
    return best_x if best > span * 0.45 else None


def columns(w, h, words, img):
    """단의 [왼쪽, 오른쪽] 들과 세로줄 x 들."""
    top, bottom = h * TOP_BAND, h * BOTTOM_BAND
    rule = vertical_rule(img, top, bottom)
    if rule is not None:
        return [(0.0, float(rule)), (float(rule) + 1, w)], [rule]
    body = [x for x in words if x['y0'] > top and x['y1'] < bottom]
    # 가운데쯤에서 어떤 낱말도 걸치지 않는 틈
    lo, hi = int(w * 0.35), int(w * 0.65)
    covered = [False] * (int(w) + 2)
    for x in body:
        for k in range(int(x['x0']), int(x['x1']) + 1):
            if 0 <= k < len(covered):
                covered[k] = True
    run, best = None, (0, None)
    for k in range(lo, hi + 1):
        if not covered[k]:
            run = k if run is None else run
            if k - run + 1 > best[0]:
                best = (k - run + 1, (run + k) / 2)
        else:
            run = None
    if best[0] >= 8 and best[1] is not None:
        left = sum(1 for x in body if x['x1'] < best[1])
        right = sum(1 for x in body if x['x0'] > best[1])
        if left >= 8 and right >= 8:
            return [(0.0, best[1]), (best[1], w)], []
    return [(0.0, w)], []


def lines_of(ws):
    """같은 높이의 낱말끼리 한 줄로 → [[낱말…]] (위에서 아래, 줄 안은 왼쪽부터)."""
    out = []
    for x in sorted(ws, key=lambda x: (x['y0'] + x['y1']) / 2):
        mid = (x['y0'] + x['y1']) / 2
        if out and abs(mid - out[-1][0]) < 3.2:
            out[-1][1].append(x)
        else:
            out.append([mid, [x]])
    return [sorted(l, key=lambda x: x['x0']) for _, l in out]


# ───────────────────────── 문항 영역 찾기 ─────────────────────────

def find_regions(pdf, page, want, anchor_re):
    """쪽 [page] 에서 문항 머리들을 읽는 순서대로 찾아 영역을 돌려준다.
    → ([{'rect': [x0,y0,x1,y1], 'choices': [...], 'text': 글}], 쪽 크기, 알림들)"""
    w, h, words = page_words(pdf, page)
    img = page_ink(pdf, page)
    top, bottom = h * TOP_BAND, h * BOTTOM_BAND
    cols, rules = columns(w, h, words, img)
    notes = []
    starts = []  # (단 번호, y, 머리 낱말)
    col_words = []
    for ci, (cl, cr) in enumerate(cols):
        ws = [x for x in words if x['y0'] > top and x['y1'] < bottom and cl <= (x['x0'] + x['x1']) / 2 < cr]
        col_words.append(ws)
        if not ws:
            continue
        left = min(x['x0'] for x in ws)
        for line in lines_of(ws):
            first = line[0]
            if first['x0'] - left > 25:
                continue
            if re.match(anchor_re, ' '.join(x['t'] for x in line)):
                starts.append((ci, first['y0'], first))
    if len(starts) != want:
        notes.append(f'{page}쪽: 문항 머리를 {len(starts)}개 찾았는데 표에는 {want}문항이에요')
    starts = starts[:want]
    out = []
    for k, (ci, y, head) in enumerate(starts):
        cl, cr = cols[ci]
        nxt = [s for s in starts if s[0] == ci and s[1] > y + 1]
        y_end = min(s[1] for s in nxt) - 8 if nxt else bottom  # 다음 머리의 상자 띠가 들어오지 않게
        box = ink_box(img, cl + 1, y - 4, cr - 1, y_end, skip_x=rules)
        if box is None:
            notes.append(f'{page}쪽 {k + 1}번째 문항: 잉크가 없어요')
            continue
        x0, y0, x1, y1 = box
        rect = [max(0.0, x0 - 4), max(0.0, y0 - 4), min(w, x1 + 4), min(h, y1 + 4)]
        inside = [x for x in col_words[ci] if x['y0'] >= rect[1] - 1 and x['y1'] <= rect[3] + 1]
        choices = []
        for x in sorted(inside, key=lambda x: (round((x['y0'] + x['y1']) / 2 / 4), x['x0'])):
            if x['t'][0] in CIRCLED:
                hgt = x['y1'] - x['y0']
                choices.append((CIRCLED.index(x['t'][0]),
                                [round(x['x0'], 2), round(x['y0'], 2), round(min(x['x1'], x['x0'] + hgt), 2), round(x['y1'], 2)]))
        # ①②③… 순서대로 한 번씩만
        seen, ordered = set(), []
        for n, r in sorted(choices, key=lambda c: c[0]):
            if n not in seen:
                seen.add(n)
                ordered.append(r)
        if [n for n in sorted(seen)] != list(range(len(seen))):
            ordered = []
        text = '\n'.join(' '.join(x['t'] for x in line) for line in lines_of(inside))
        text = re.sub(r'^(기출문제|변형|심화|예제|유제)\s*', '', text).strip()
        out.append({'rect': [round(v, 2) for v in rect], 'choices': ordered, 'text': text[:600]})
    return out, (w, h), notes


# ───────────────────────── 정보.txt ─────────────────────────

COLS = ('문항번호', 'PDF 쪽', '단원', '유형', '객관식/단답형', '정답', '난이도', '배점', '쌍둥이 원본 번호', '출처')


def read_table(path):
    rows, in_table = [], False
    for raw in open(path, encoding='utf-8-sig'):
        line = raw.strip()
        if line.startswith('[문항 목록]'):
            in_table = True
            continue
        if not in_table or '|' not in line:
            continue
        cells = [c.strip() for c in line.split('|')]
        if cells[0] == '문항번호':
            continue
        cells += [''] * (len(COLS) - len(cells))
        rows.append(dict(zip(COLS, cells)))
    return rows


def read_overrides(path):
    out = {}
    if not os.path.exists(path):
        return out
    for n, raw in enumerate(open(path, encoding='utf-8-sig'), 1):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        cells = [c.strip() for c in line.split('|')]
        try:
            rect = [float(v) for v in cells[2].split(',')]
            assert len(rect) == 4 and rect[2] > rect[0] and rect[3] > rect[1]
            out[cells[0]] = (int(cells[1]), rect)
        except Exception:
            raise SystemExit(f'영역.txt {n}번째 줄을 읽을 수 없어요: "{line}" (문항번호 | 쪽 | x0,y0,x1,y1)')
    return out


def section_of(no):
    """'수업-15-기출' → 수업, '숙제-DAY1-15-1' → 숙제 DAY 1."""
    parts = no.split('-')
    if len(parts) > 1 and re.fullmatch(r'DAY\d+', parts[1], re.I):
        return f'{parts[0]} DAY {parts[1][3:]}'
    return parts[0] if len(parts) > 1 else ''


# ───────────────────────── 만들기 ─────────────────────────

def build(folder, outdir=None, preview=True):
    meta = tb.read_info(os.path.join(folder, '정보.txt'))
    rows = read_table(os.path.join(folder, '정보.txt'))
    if not rows:
        raise SystemExit(f'{folder}/정보.txt 에 [문항 목록] 표가 없어요')
    pdf_name = meta.get('최종본', '').split('(')[0].strip()
    pdf = os.path.join(folder, pdf_name) if pdf_name else ''
    if not pdf or not os.path.exists(pdf):
        cands = sorted(f for f in os.listdir(folder) if f.lower().endswith('.pdf'))
        if not cands:
            raise SystemExit(f'{folder} 에 PDF 가 없어요')
        pdf = os.path.join(folder, cands[0])
    raw_pdf = open(pdf, 'rb').read()
    title = meta.get('교재명', os.path.basename(folder.rstrip('/'))).split('(')[0].strip()
    book_id = meta.get('아이디', '').strip() or tb.stable_slug(title)
    doc_id = f'{book_id}-{hashlib.sha1(raw_pdf).hexdigest()[:10]}'
    anchor_re = meta.get('문항 시작', '').strip() or DEFAULT_ANCHOR
    overrides = read_overrides(os.path.join(folder, '영역.txt'))
    total = page_count(pdf)
    issues = []

    by_page = {}
    for r in rows:
        try:
            pg = int(re.sub(r'[^0-9]', '', r['PDF 쪽']))
        except ValueError:
            issues.append(f'{r["문항번호"]}: PDF 쪽 "{r["PDF 쪽"]}" 을 읽을 수 없어요')
            continue
        if not 1 <= pg <= total:
            issues.append(f'{r["문항번호"]}: PDF 쪽 {pg} 이 PDF({total}쪽) 밖이에요')
            continue
        by_page.setdefault(pg, []).append(r)

    found = {}  # 문항번호 → (쪽, 영역)
    page_sizes = {}
    for pg, rs in sorted(by_page.items()):
        todo = [r for r in rs if r['문항번호'] not in overrides]
        regions, size, notes = find_regions(pdf, pg, len(rs), anchor_re)
        page_sizes[pg] = size
        issues.extend(notes)
        # 표의 순서 = 쪽에서 읽는 순서. 직접 정한 문항은 그 자리를 건너뛴다
        auto = iter(regions)
        for r in rs:
            no = r['문항번호']
            if no in overrides:
                opg, rect = overrides[no]
                found[no] = (opg, {'rect': rect, 'choices': [], 'text': ''})
                next(auto, None)
                continue
            reg = next(auto, None)
            if reg is None:
                issues.append(f'{no}: {pg}쪽에서 영역을 못 찾았어요 → 영역.txt 에 직접 적어 주세요')
                continue
            found[no] = (pg, reg)
        del todo

    grades_meta = [g.strip() for g in re.split(r'[·,，/]', meta.get('대상 학년', '')) if g.strip()]
    courses, used, ids = {}, set(), {}
    for r in rows:
        ids[r['문항번호']] = f'{book_id}-{tb.item_slug(r["문항번호"], used)}'
    all_ids = []
    for r in rows:
        no = r['문항번호']
        if no not in found:
            continue
        pg, reg = found[no]
        cid, cname, color, group = tb.course_of(r['단원'], meta.get('과목', '').split(',')[0],
                                                generic=[meta.get('과목', '').split(',')[0]])
        grades = grades_meta or tb.DEFAULT_GRADES.get(group, [])
        course = courses.setdefault(cid, {
            'subject': cname, 'subjectId': cid, 'color': color, 'group': group,
            'level': 'high', 'grades': grades,
            'track': meta.get('시험', '').strip() or ('공통' if group == 'apt' else '대학' if group == 'univ' else '수능'),
            'passages': [], 'problems': []})
        kind = r['객관식/단답형']
        is_choice = kind.startswith('객관')
        answer = r['정답'].strip()
        if not answer:
            issues.append(f'{no}: 정답이 비어 있어요')
        if is_choice and not re.fullmatch(r'[1-9]', answer):
            issues.append(f'{no}: 객관식 정답은 번호로 — 지금 "{answer}"')
        if is_choice and len(reg['choices']) not in (0, 5, 4):
            issues.append(f'{no}: 선지 자리를 {len(reg["choices"])}개 찾았어요')
        try:
            diff = max(1, min(5, int(re.sub(r'[^0-9]', '', r['난이도']) or 3)))
        except ValueError:
            diff = 3
        region = {'doc': doc_id, 'page': pg, 'rect': reg['rect']}
        if is_choice and reg['choices']:
            region['choices'] = reg['choices']
        p = {
            'id': ids[no], 'unit': r['단원'] or cname, 'topic': r['유형'], 'section': section_of(no),
            'difficulty': diff, 'type': 'choice' if is_choice else 'short',
            'stem': reg['text'] or no, 'answer': answer, 'solution': '', 'pdf': region,
        }
        if r['배점'].strip().isdigit():
            p['points'] = int(r['배점'])
        twin = r['쌍둥이 원본 번호'].strip()
        if twin and twin in ids:
            p['twinOf'] = ids[twin]
        if r['출처'].strip():
            p['source'] = r['출처'].strip()
        course['problems'].append(p)
        all_ids.append(p['id'])
    for c in courses.values():
        c['units'] = list(dict.fromkeys(p['unit'] for p in c['problems']))
    stage = meta.get('커리큘럼 단계', 'N제').strip()
    main = max(courses.values(), key=lambda c: len(c['problems']))['subjectId'] if courses else 'apt'
    schools = [x.strip() for x in re.split(r'[,，·/]', meta.get('학교', '')) if x.strip() in tb.UNIVERSITIES]
    wb = {
        'id': book_id, 'title': title, 'course': main,
        'stage': stage if stage in tb.STAGES else 'N제',
        'scope': '·'.join(x.strip() for x in re.split(r'[,，/]', meta.get('범위', '')) if x.strip()),
        'level': meta.get('수준', '실전').strip() or '실전',
        'publisher': meta.get('만든 곳', ''), 'series': meta.get('시리즈', '').split('(')[0].strip() or title,
        'desc': f'{title} — 원본 PDF 그대로', 'problems': all_ids,
    }
    if schools:
        wb['schools'] = schools
    bundle = {'format': 'pulinote-bundle', 'version': 1, 'id': book_id, 'title': title,
              'pdfs': {doc_id: base64.b64encode(raw_pdf).decode()},
              'courses': list(courses.values()), 'workbooks': [wb]}
    report = {'book': title, 'id': book_id, 'problems': len(all_ids), 'rows': len(rows),
              'choice_spots': sum(1 for c in courses.values() for p in c['problems'] if p['pdf'].get('choices')),
              'issues': issues}
    if outdir:
        os.makedirs(outdir, exist_ok=True)
        path = os.path.join(outdir, f'{book_id}.pulinote')
        with open(path, 'wb') as f:
            f.write(gzip.compress(json.dumps(bundle, ensure_ascii=False, separators=(',', ':')).encode(), 9))
        report['file'] = path
        report['bytes'] = os.path.getsize(path)
        if preview:
            report['previews'] = draw_previews(pdf, found, os.path.join(outdir, '미리보기'))
    return report, bundle


def draw_previews(pdf, found, outdir):
    """쪽마다 잡은 영역(빨강)과 선지 자리(파랑)를 그린 그림."""
    from PIL import Image, ImageDraw
    os.makedirs(outdir, exist_ok=True)
    pages = {}
    for no, (pg, reg) in found.items():
        pages.setdefault(pg, []).append((no, reg))
    files = []
    dpi = 100
    k = dpi / 72
    for pg, items in sorted(pages.items()):
        with tempfile.TemporaryDirectory() as tmp:
            base = os.path.join(tmp, 'p')
            subprocess.run(['pdftoppm', '-f', str(pg), '-l', str(pg), '-r', str(dpi), '-png', '-singlefile', pdf, base],
                           check=True, capture_output=True)
            im = Image.open(base + '.png').convert('RGB')
        d = ImageDraw.Draw(im)
        for no, reg in items:
            x0, y0, x1, y1 = [v * k for v in reg['rect']]
            d.rectangle([x0, y0, x1, y1], outline=(220, 40, 40), width=3)
            d.text((x0 + 4, y1 - 14), no, fill=(220, 40, 40))
            for c in reg['choices']:
                d.rectangle([v * k for v in c], outline=(40, 90, 230), width=2)
        f = os.path.join(outdir, f'p{pg:03d}.png')
        im.save(f)
        files.append(f)
    return files


# ───────────────────────── 시험 ─────────────────────────

def selftest():
    """reportlab 으로 만든 2단 시험지 PDF 로 영역 찾기 전체를 돌려 본다."""
    from reportlab.lib.pagesizes import A4
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.pdfgen import canvas
    font = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
    pdfmetrics.registerFont(TTFont('DV', font))
    with tempfile.TemporaryDirectory() as tmp:
        folder = os.path.join(tmp, '시험 교재')
        os.makedirs(folder)
        pdf = os.path.join(folder, 'exam.pdf')
        c = canvas.Canvas(pdf, pagesize=A4)
        W, H = A4

        def write(x, y, s, size=10):
            c.setFont('DV', size)
            c.drawString(x, H - y, s)

        # 1쪽: 머리말 + 세로줄 + 왼쪽 단 2문항(객관식·단답형), 오른쪽 단 1문항(객관식, 그림)
        write(40, 25, 'EXAM HEADER  page 1', 8)
        c.line(W / 2, H - 50, W / 2, H - 780)
        write(45, 70, '1. Find the value of x when 2x + 3 = 11.')
        write(60, 88, 'Choose one.')
        write(60, 110, '① 1     ② 2     ③ 3     ④ 4     ⑤ 5')
        write(45, 170, '2. Compute 12 x 3.')
        write(60, 188, 'Write the number.')
        write(310, 70, '3. Look at the graph.')
        c.rect(330, H - 200, 180, 100)
        c.line(330, H - 200, 510, H - 100)
        write(325, 230, '① a     ② b     ③ c     ④ d     ⑤ e')
        write(280, 815, 'footer 1', 8)
        c.showPage()
        # 2쪽: 한 단, 머리 1개
        write(45, 80, '4. Last one: what is 7 + 8?')
        write(60, 100, 'Short answer.')
        c.showPage()
        c.save()
        info = ('- 교재명: 시험 교재\n- 과목: 공업수학1\n- 커리큘럼 단계: 모의고사\n- 최종본: exam.pdf\n- 학교: 인하대\n\n'
                '[문항 목록]\n' + ' | '.join(COLS) + '\n'
                '1 | 1 | 1장 미분방정식 | 계산 | 객관식 | 4 | 2 | 3 |  | \n'
                '2 | 1 | 1장 미분방정식 | 계산 | 단답형 | 36 | 1 | 2 |  | \n'
                '3 | 1 | 2장 라플라스 | 그래프 | 객관식 | 2 | 3 | 4 | 1 | 2025 중간 3번\n'
                '4 | 2 | 2장 라플라스 | 계산 | 단답형 | 15 | 1 | 2 |  | \n')
        open(os.path.join(folder, '정보.txt'), 'w', encoding='utf-8').write(info)
        out = os.path.join(tmp, 'out')
        rep, b = build(folder, out)
        assert rep['issues'] == [], rep['issues']
        assert rep['problems'] == 4 and rep['choice_spots'] == 2, rep
        ps = b['courses'][0]['problems']
        assert b['courses'][0]['subjectId'] == 'emath1' and b['courses'][0]['grades'] == ['대학생']
        assert b['workbooks'][0]['schools'] == ['인하대']
        doc = ps[0]['pdf']['doc']
        assert list(b['pdfs']) == [doc] and base64.b64decode(b['pdfs'][doc])[:5] == b'%PDF-'
        r1, r2, r3, r4 = [p['pdf'] for p in ps]
        assert r1['page'] == r2['page'] == r3['page'] == 1 and r4['page'] == 2
        # 1번: 왼쪽 단 위, 2번 머리 전에 끝난다. 머리말·세로줄은 안 들어간다
        assert r1['rect'][0] < 50 and r1['rect'][2] < W / 2 and r1['rect'][1] > 50, r1
        assert r1['rect'][3] < 165 and r2['rect'][1] > 150, (r1, r2)
        assert r3['rect'][0] > W / 2 - 2 and r3['rect'][3] >= 228, r3  # 그림과 선지까지
        # 선지 다섯 자리가 왼쪽부터
        xs = [c[0] for c in r1['choices']]
        assert len(xs) == 5 and xs == sorted(xs), r1['choices']
        assert 'choices' not in r2 and ps[1]['type'] == 'short'
        assert ps[2]['twinOf'] == ps[0]['id'] and ps[2]['source'] == '2025 중간 3번'
        assert '2x + 3 = 11' in ps[0]['stem'], ps[0]['stem']
        assert os.path.exists(rep['file']) and len(rep['previews']) == 2
        # 영역.txt 로 직접 정하면 그 영역
        open(os.path.join(folder, '영역.txt'), 'w', encoding='utf-8').write('# 직접\n4 | 2 | 40,60,300,120\n')
        rep2, b2 = build(folder, None)
        assert b2['courses'][0]['problems'][3]['pdf']['rect'] == [40.0, 60.0, 300.0, 120.0], b2['courses'][0]['problems'][3]
        # 표와 머리 수가 다르면 알린다
        open(os.path.join(folder, '영역.txt'), 'w', encoding='utf-8').write('')
        with open(os.path.join(folder, '정보.txt'), 'a', encoding='utf-8') as f:
            f.write('5 | 2 | 2장 라플라스 | 계산 | 단답형 | 1 | 1 | 2 |  | \n')
        rep3, _ = build(folder, None)
        assert any('2쪽' in x and '1개' in x for x in rep3['issues']), rep3['issues']
        assert any(x.startswith('5:') for x in rep3['issues']), rep3['issues']
    print('pdf_exam selftest ok')


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    if argv == ['selftest']:
        return selftest()
    if not argv:
        print(__doc__)
        return
    folder = argv[0]
    outdir = argv[1] if len(argv) > 1 else os.path.join(folder, '_앱')
    rep, _ = build(folder, outdir)
    print(f"{rep['book']} ({rep['id']}): {rep['problems']}/{rep['rows']}문항, 선지 자리 {rep['choice_spots']}문항")
    print(f"→ {rep['file']} ({rep['bytes'] / 1048576:.2f}MB) · 미리보기 {len(rep['previews'])}장: {os.path.dirname(rep['previews'][0]) if rep['previews'] else '-'}")
    for x in rep['issues']:
        print('  ⚠', x)


if __name__ == '__main__':
    main()
