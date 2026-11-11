#!/usr/bin/env python3
"""
원본 PDF 개념책 → 앱 개념책 (.pulinote) — 쪽을 그대로 넘겨 읽고, 예제는 눌러서 일반 풀이 화면으로 푼다.

  python3 tools/pdf_concept.py <교재 폴더> [출력 폴더]
  python3 tools/pdf_concept.py selftest

교재 폴더:
  정보.txt   - 교재명 · - 과목 · - 최종본: 파일.pdf (없으면 폴더의 첫 PDF) · - 학교 · - 시리즈 …
             (선택) - 절 머리: 정규식   절(개념) 제목 줄. 기본: `I‑1 물체의 운동` 같은 `로마숫자-번호 제목`
             (선택) - 장 머리: 정규식   단원(장) 제목 줄. 기본: `Ⅰ. 역학과 에너지`
             (선택) - 예제 머리: 정규식 기본: `예제 I‑1‑1`
             (선택) - 정답 쪽: 25-27   예제 정답과 해설이 있는 쪽 (기본: '정답과 해설' 제목이 있는 쪽부터 끝까지)
  목차.txt   (선택) 절을 직접: `제목 | 시작쪽-끝쪽 | 단원`
  예제.txt   (선택) 정답을 직접: `예제 이름 | 정답` (예: `I-1-1 | 3`)

하는 일
  1. 쪽마다 줄 맨 앞의 장·절 제목을 찾아 절(개념)마다 쪽 범위를 정한다 (예제 정답 쪽은 뺀다).
  2. 예제 머리부터 다음 머리(필수·실전·예제·절 …) 또는 단의 끝까지를 예제 영역으로 잡는다.
     객관식 ①~⑤ 자리를 찾고, 정답 쪽의 `I‑1‑1 정답 ③` 에서 정답을, 그 아래 글을 해설 영역으로 잡는다.
  3. PDF 를 교재 파일에 넣는다. 개념 = 쪽들, 예제 = 문항(원본 PDF 영역).
  4. 출력 폴더에 .pulinote 와 미리보기 그림을 만든다.
"""
import base64
import gzip
import hashlib
import json
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pdf_exam as pe  # noqa: E402
import text_book as tb  # noqa: E402

ROMAN = 'IVXⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ'
DASH = '‑‐‒–−-'
SECTION_RE = rf'^([{ROMAN}]+[{DASH}]\d+)\s+(.+)$'
CHAPTER_RE = rf'^([ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ]+|[IVX]+)\.\s+(.+)$'
EXAMPLE_RE = rf'^예제\s*([{ROMAN}]+[{DASH}]\d+[{DASH}]\d+)'
STOP_RE = rf'^(예제|필수|실전|유제|확인\s*문제|[{ROMAN}]+[{DASH}]\d+\s|[ⅠⅡⅢⅣⅤ]+\.\s)'
ANSWER_RE = rf'^([{ROMAN}]+[{DASH}]\d+[{DASH}]\d+)\s*정답\s*([➀➁➂➃➄➅➆➇➈①②③④⑤⑥⑦⑧⑨]|-?\d+(?:[./]\d+)?)'
CIRCLE_NUM = {c: i % 9 + 1 for i, c in enumerate('➀➁➂➃➄➅➆➇➈①②③④⑤⑥⑦⑧⑨')}


def norm(label):
    """'I‑1‑1' → 'I-1-1' (하이픈 모양 통일)."""
    return re.sub(f'[{DASH}]', '-', label)


def line_text(line, gap=18):
    """줄의 글 — 낱말 사이가 크게 벌어지면 (오른쪽 끝의 '자주 나오는 번호' 같은 것) 거기서 자른다."""
    out = [line[0]]
    for a, b in zip(line, line[1:]):
        if b['x0'] - a['x1'] > gap:
            break
        out.append(b)
    return ' '.join(x['t'] for x in out)


def scan(pdf, pages):
    """쪽마다 단·줄 → [(쪽, 단, (단 왼쪽, 오른쪽), 줄 y0, 줄 글, 줄 낱말들)], 쪽 정보"""
    rows, info = [], {}
    for pg in pages:
        w, h, words = pe.page_words(pdf, pg)
        img = pe.page_ink(pdf, pg)
        cols, rules = pe.columns(w, h, words, img)
        info[pg] = (w, h, img, cols, rules, words)
        top, bottom = h * pe.TOP_BAND, h * pe.BOTTOM_BAND
        for ci, (cl, cr) in enumerate(cols):
            ws = [x for x in words if x['y0'] > top and x['y1'] < bottom and cl <= (x['x0'] + x['x1']) / 2 < cr]
            for line in pe.lines_of(ws):
                rows.append((pg, ci, (cl, cr), line[0]['y0'], line_text(line), line))
    return rows, info


def region_until(info, pg, ci, y, stop_ys):
    """y 부터 같은 단의 다음 멈춤 줄(또는 단 끝)까지 잉크 영역."""
    w, h, img, cols, rules, words = info[pg]
    cl, cr = cols[ci]
    nxt = [s for s in stop_ys if s > y + 1]
    y_end = (min(nxt) - 8) if nxt else h * pe.BOTTOM_BAND  # 다음 머리의 상자 띠가 들어오지 않게
    box = pe.ink_box(img, cl + 1, y - 3, cr - 1, y_end, skip_x=rules)
    if box is None:
        return None, []
    x0, y0, x1, y1 = box
    rect = [round(max(0.0, x0 - 4), 2), round(max(0.0, y0 - 4), 2), round(min(w, x1 + 4), 2), round(min(h, y1 + 4), 2)]
    inside = [x for x in words if cl <= (x['x0'] + x['x1']) / 2 < cr and x['y0'] >= rect[1] - 1 and x['y1'] <= rect[3] + 1]
    return rect, inside


def choices_in(inside):
    found = {}
    for x in sorted(inside, key=lambda x: (round((x['y0'] + x['y1']) / 2 / 4), x['x0'])):
        c = x['t'][0]
        if c in '①②③④⑤⑥⑦⑧⑨➀➁➂➃➄➅➆➇➈':
            n = CIRCLE_NUM[c]
            hgt = x['y1'] - x['y0']
            found.setdefault(n, [round(x['x0'], 2), round(x['y0'], 2), round(min(x['x1'], x['x0'] + hgt), 2), round(x['y1'], 2)])
    ns = sorted(found)
    return [found[n] for n in ns] if ns == list(range(1, len(ns) + 1)) and len(ns) >= 2 else []


def build(folder, outdir=None, preview=True):
    meta = tb.read_info(os.path.join(folder, '정보.txt'))
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
    sec_re = meta.get('절 머리', '').strip() or SECTION_RE
    chap_re = meta.get('장 머리', '').strip() or CHAPTER_RE
    ex_re = meta.get('예제 머리', '').strip() or EXAMPLE_RE
    total = pe.page_count(pdf)
    issues = []
    rows, info = scan(pdf, range(1, total + 1))

    # ── 정답 쪽 ──
    ans_pages = set()
    if meta.get('정답 쪽'):
        m = re.fullmatch(r'\s*(\d+)\s*(?:-\s*(\d+))?\s*', meta['정답 쪽'])
        if m:
            ans_pages = set(range(int(m.group(1)), int(m.group(2) or m.group(1)) + 1))
    else:
        start = next((pg for pg, ci, col, y, t, line in rows if re.search(r'정답과\s*해설', t)), None)
        if start:
            ans_pages = set(range(start, total + 1))

    # ── 절(개념) ──
    sections = []  # (쪽, y, 단, 이름표, 제목, 장)
    chapter = ''
    for pg, ci, col, y, t, line in rows:
        if pg in ans_pages:
            continue
        m = re.match(chap_re, t)
        if m:
            chapter = t.strip()
            continue
        m = re.match(sec_re, t)
        if m:
            sections.append((pg, y, ci, norm(m.group(1)), m.group(2).strip(), chapter))
    toc_file = os.path.join(folder, '목차.txt')
    concepts_src = []
    if os.path.exists(toc_file):
        for n, raw in enumerate(open(toc_file, encoding='utf-8-sig'), 1):
            line = raw.strip()
            if not line or line.startswith('#'):
                continue
            cells = [c.strip() for c in line.split('|')]
            m = re.fullmatch(r'(\d+)(?:-(\d+))?', cells[1] if len(cells) > 1 else '')
            if not m:
                raise SystemExit(f'목차.txt {n}번째 줄: `제목 | 시작쪽-끝쪽 | 단원` — "{line}"')
            concepts_src.append((cells[0], list(range(int(m.group(1)), int(m.group(2) or m.group(1)) + 1)),
                                 cells[2] if len(cells) > 2 else ''))
    else:
        last_page = max([p for p in range(1, total + 1) if p not in ans_pages] or [total])
        for k, (pg, y, ci, label, name, chap) in enumerate(sections):
            if k + 1 < len(sections):
                npg, ny, nci = sections[k + 1][:3]
                h = info[npg][1]
                # 다음 절이 쪽 맨 위(왼쪽 단 첫머리)에서 시작하면 그 쪽은 다음 절의 것
                end = npg - 1 if (nci == 0 and ny < h * 0.12 and npg > pg) else npg
            else:
                end = last_page
            concepts_src.append((f'{label} {name}', list(range(pg, max(pg, end) + 1)), chap))
        if not concepts_src:
            issues.append('절 제목을 하나도 못 찾았어요 → 목차.txt 로 적어 주세요')
        elif sections[0][0] > 1:
            # 첫 절 앞의 쪽들 (표지·들어가며·공부법)
            concepts_src.insert(0, ('시작하며', list(range(1, sections[0][0])), ''))

    # ── 예제 ──
    answers = {}
    for pg, ci, col, y, t, line in rows:
        m = re.match(ANSWER_RE, t)
        if m:
            a = m.group(2)
            answers[norm(m.group(1))] = (str(CIRCLE_NUM[a]) if a in CIRCLE_NUM else a, pg, ci, y)
    ex_file = os.path.join(folder, '예제.txt')
    if os.path.exists(ex_file):
        for raw in open(ex_file, encoding='utf-8-sig'):
            cells = [c.strip() for c in raw.split('|')]
            if len(cells) >= 2 and cells[0] and not cells[0].startswith('#'):
                prev = answers.get(norm(cells[0]))
                answers[norm(cells[0])] = (cells[1],) + (prev[1:] if prev else (None, None, None))
    stops = {}  # (쪽, 단) → 멈춤 줄 y 들
    for pg, ci, col, y, t, line in rows:
        if re.match(STOP_RE, t) or re.match(ANSWER_RE, t) or re.match(ex_re, t):
            stops.setdefault((pg, ci), []).append(y)
    examples = []  # (이름표, 쪽, 영역, 선지, 글)
    for pg, ci, col, y, t, line in rows:
        if pg in ans_pages:
            continue
        m = re.match(ex_re, t)
        if not m:
            continue
        label = norm(m.group(1))
        rect, inside = region_until(info, pg, ci, y, stops.get((pg, ci), []))
        if rect is None:
            issues.append(f'예제 {label}: 영역을 못 찾았어요')
            continue
        text = '\n'.join(' '.join(x['t'] for x in l) for l in pe.lines_of(inside))
        examples.append((label, pg, rect, choices_in(inside), re.sub(r'^예제\s*\S+\s*', '', text)[:600]))

    # ── 묶기 ──
    cid, cname, color, group = tb.course_of(meta.get('과목', '').split(',')[0], generic=[meta.get('과목', '').split(',')[0]])
    grades = [g.strip() for g in re.split(r'[·,，/]', meta.get('대상 학년', '')) if g.strip()] or tb.DEFAULT_GRADES.get(group, [])
    course = {'subject': cname, 'subjectId': cid, 'color': color, 'group': group, 'level': 'high', 'grades': grades,
              'track': meta.get('시험', '').strip() or ('공통' if group == 'apt' else '대학' if group == 'univ' else '수능'),
              'passages': [], 'problems': [], 'concepts': []}
    sizes = {pg: [round(info[pg][0], 2), round(info[pg][1], 2)] for pg in info}
    ex_of_page = {}
    used = set()
    for label, pg, rect, chs, text in examples:
        pid = f'{book_id}-ex-{tb.item_slug(label, used)}'
        ans = answers.get(label)
        if not ans:
            issues.append(f'예제 {label}: 정답을 못 찾았어요 → 예제.txt 에 `{label} | 정답` 으로 적어 주세요')
        a = ans[0] if ans else ''
        is_choice = bool(chs) and re.fullmatch(r'[1-9]', a or '1') is not None
        unit = next((c[2] for c in concepts_src if pg in c[1]), '') or cname
        sec = next((c[0] for c in concepts_src if pg in c[1]), '')
        p = {'id': pid, 'unit': unit, 'topic': f'예제 {label}', 'section': sec, 'difficulty': 2,
             'type': 'choice' if is_choice else 'short', 'stem': text or f'예제 {label}', 'answer': a, 'solution': '',
             'pdf': {'doc': doc_id, 'page': pg, 'rect': rect, **({'choices': chs} if is_choice else {})}, 'points': 0}
        # 해설: 정답 줄부터 같은 단의 다음 정답 줄(또는 단 끝)까지
        if ans and ans[1]:
            apg, aci, ay = ans[1], ans[2], ans[3]
            srect, _ = region_until(info, apg, aci, ay, stops.get((apg, aci), []))
            if srect:
                p['solutionPdf'] = {'doc': doc_id, 'page': apg, 'rect': srect}
        course['problems'].append(p)
        ex_of_page.setdefault(pg, []).append({'page': pg, 'rect': rect, 'problem': pid})
    concept_ids = []
    for k, (name, pages, chap) in enumerate(concepts_src):
        cid_ = f'{book_id}-c{k + 1:02d}'
        course['concepts'].append({
            'id': cid_, 'title': name, 'unit': chap, 'section': chap or name, 'body': '',
            'pdf': {'doc': doc_id, 'pages': pages, 'sizes': [sizes[p][:] for p in pages if p in sizes],
                    'examples': [e for p in pages for e in ex_of_page.get(p, [])]},
        })
        concept_ids.append(cid_)
    course['units'] = list(dict.fromkeys([c['unit'] for c in course['concepts'] if c['unit']] or [cname]))
    schools = [x.strip() for x in re.split(r'[,，·/]', meta.get('학교', '')) if x.strip() in tb.UNIVERSITIES]
    wb = {'id': book_id, 'title': title, 'course': cid, 'stage': '개념',
          'scope': '·'.join(x.strip() for x in re.split(r'[,，/]', meta.get('범위', '')) if x.strip()),
          'level': meta.get('수준', '기본').strip() or '기본', 'publisher': meta.get('만든 곳', ''),
          'series': meta.get('시리즈', '').split('(')[0].strip() or title, 'desc': f'{title} — 원본 PDF 개념책',
          'problems': [p['id'] for p in course['problems']], 'concepts': concept_ids}
    if schools:
        wb['schools'] = schools
    bundle = {'format': 'pulinote-bundle', 'version': 1, 'id': book_id, 'title': title,
              'pdfs': {doc_id: base64.b64encode(raw_pdf).decode()}, 'courses': [course], 'workbooks': [wb]}
    report = {'book': title, 'id': book_id, 'concepts': len(concept_ids), 'examples': len(course['problems']),
              'answers': sum(1 for p in course['problems'] if p['answer']),
              'solutions': sum(1 for p in course['problems'] if 'solutionPdf' in p), 'issues': issues}
    if outdir:
        os.makedirs(outdir, exist_ok=True)
        path = os.path.join(outdir, f'{book_id}.pulinote')
        with open(path, 'wb') as f:
            f.write(gzip.compress(json.dumps(bundle, ensure_ascii=False, separators=(',', ':')).encode(), 9))
        report['file'], report['bytes'] = path, os.path.getsize(path)
        if preview:
            found = {}
            for p in course['problems']:
                found[p['topic']] = (p['pdf']['page'], {'rect': p['pdf']['rect'], 'choices': p['pdf'].get('choices', [])})
                if 'solutionPdf' in p:
                    found[p['topic'] + ' 해설'] = (p['solutionPdf']['page'], {'rect': p['solutionPdf']['rect'], 'choices': []})
            report['previews'] = pe.draw_previews(pdf, found, os.path.join(outdir, '미리보기'))
    return report, bundle


def selftest():
    from reportlab.lib.pagesizes import A4
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.pdfgen import canvas
    pdfmetrics.registerFont(TTFont('DV', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'))
    with tempfile.TemporaryDirectory() as tmp:
        folder = os.path.join(tmp, '개념 교재')
        os.makedirs(folder)
        pdf = os.path.join(folder, 'concept.pdf')
        c = canvas.Canvas(pdf, pagesize=A4)
        W, H = A4

        def write(x, y, s, size=10):
            c.setFont('DV', size)
            c.drawString(x, H - y, s)

        # 1쪽: 장 · 절 I-1 · 개념 · 예제 I-1-1(객관식) · 필수
        write(45, 60, 'I. Mechanics', 12)
        write(45, 90, 'I-1 Motion                                         often 1~3')
        write(45, 120, 'Velocity is displacement over time.')
        write(37, 160, '예제 I-1-1'.replace('예제', 'Ex') if False else 'Ex I-1-1')
        write(45, 180, 'Which is true?')
        write(45, 210, '① a    ② b    ③ c    ④ d    ⑤ e')
        write(46, 260, 'Key Newton laws')
        c.showPage()
        # 2쪽: 절 I-2 (쪽 맨 위) · 예제 I-2-1 (단답형)
        write(45, 60, 'I-2 Force')
        write(37, 120, 'Ex I-2-1')
        write(45, 140, 'Compute 3 + 4.')
        c.showPage()
        # 3쪽: 정답과 해설
        write(45, 60, 'Answers and solutions')
        write(37, 100, 'I-1-1 정답 ③'.replace('정답', 'ANS') if False else 'I-1-1 ANS ③')
        write(45, 120, 'Because c.')
        write(37, 160, 'I-2-1 ANS 7')
        write(45, 180, 'Add them.')
        c.showPage()
        c.save()
        open(os.path.join(folder, '정보.txt'), 'w', encoding='utf-8').write(
            '- 교재명: 시험 개념책\n- 과목: 미분적분학1\n- 최종본: concept.pdf\n- 정답 쪽: 3\n'
            '- 예제 머리: ^Ex\\s*([IVX]+-\\d+-\\d+)\n- 학교: 인하대\n')
        global ANSWER_RE, STOP_RE
        saved = (ANSWER_RE, STOP_RE)
        ANSWER_RE = r'^([IVX]+-\d+-\d+)\s*ANS\s*([①②③④⑤]|-?\d+)'
        STOP_RE = r'^(Ex|Key|[IVX]+-\d+\s|[IVX]+\.\s)'
        try:
            rep, b = build(folder, os.path.join(tmp, 'out'))
        finally:
            ANSWER_RE, STOP_RE = saved
        assert rep['issues'] == [], rep['issues']
        co = b['courses'][0]
        assert co['subjectId'] == 'calc1' and b['workbooks'][0]['stage'] == '개념' and b['workbooks'][0]['schools'] == ['인하대']
        titles = [x['title'] for x in co['concepts']]
        assert titles == ['I-1 Motion', 'I-2 Force'], titles
        assert co['concepts'][0]['pdf']['pages'] == [1] and co['concepts'][1]['pdf']['pages'] == [2], co['concepts']
        assert co['concepts'][0]['unit'] == 'I. Mechanics'
        ex1, ex2 = co['problems']
        assert ex1['type'] == 'choice' and ex1['answer'] == '3' and len(ex1['pdf']['choices']) == 5, ex1
        assert ex1['pdf']['rect'][3] < 255, ex1['pdf']['rect']  # 'Key …' 앞에서 끝
        assert ex2['type'] == 'short' and ex2['answer'] == '7', ex2
        assert ex1['solutionPdf']['page'] == 3 and ex1['solutionPdf']['rect'][3] < 158, ex1['solutionPdf']
        assert co['concepts'][0]['pdf']['examples'][0]['problem'] == ex1['id']
        assert b['workbooks'][0]['concepts'] == [x['id'] for x in co['concepts']]
        assert list(b['pdfs']) == [ex1['pdf']['doc']]
    print('pdf_concept selftest ok')


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
    print(f"{rep['book']} ({rep['id']}): 개념 {rep['concepts']}개 · 예제 {rep['examples']}개 (정답 {rep['answers']} · 해설 {rep['solutions']})")
    print(f"→ {rep['file']} ({rep['bytes'] / 1048576:.2f}MB) · 미리보기 {len(rep['previews'])}장")
    for x in rep['issues']:
        print('  ⚠', x)


if __name__ == '__main__':
    main()
