#!/usr/bin/env python3
"""
TeX 원본 교재 → 앱 문항 묶음 (.pulinote)  — 원문을 앱에서 다시 조판한다.

  python3 tools/tex_book.py <교재 폴더> <출력 폴더> [--preview]

교재 폴더(교재모음 형식): 정보.txt (문항 목록 표) + TeX원본/*.tex
  - 문항: \\PairPage / \\SoloPage 칸의 \\TagBox{머리표}{출처} 다음 본문 (정보.txt 순서와 같다)
  - 해설: \\SolBlock{제목}{본문} (본문이 빈 DAY 제목은 건너뜀)
  - 본문 변환: $…$ 그대로, \\[…\\] → 가운데 수식 줄, \\kbox{…} → 조건 상자, tikzpicture → SVG 그림,
    \\textbf → **굵게**, 빈 줄 → 문단
출력: <출력>/<id>.pulinote (gzip JSON — 앱 설정 → "교재 파일 가져오기")
교재 내용은 저작물이므로 출력은 저장소에 넣지 않는다.
"""

import gzip
import json
import math
import os
import re
import subprocess
import sys

# 과목 이름 → 앱 과목(course)
COURSES = {
    # 앱의 수학은 한 과목(math: 수능 "수학 영역") — 수학Ⅰ·Ⅱ·선택과목은 단원/범위로 나눈다
    '수학Ⅰ': ('math', '수학', '#E0703B', 'math'),
    '수학Ⅱ': ('math', '수학', '#E0703B', 'math'),
    '확률과 통계': ('math', '수학', '#E0703B', 'math'),
    '미적분': ('math', '수학', '#E0703B', 'math'),
    '기하': ('math', '수학', '#E0703B', 'math'),
    '공통수학': ('math', '수학', '#E0703B', 'math'),
    '물리학Ⅰ': ('phy1', '물리학Ⅰ', '#2F6BFF', 'sci'),
    '물리학Ⅱ': ('phy2', '물리학Ⅱ', '#1D4ED8', 'sci'),
    '지구과학Ⅰ': ('earth1', '지구과학Ⅰ', '#169C6B', 'sci'),
    '통합과학': ('integ', '통합과학', '#0EA5E9', 'sci'),
}


# ───────────────────────── 정보.txt ─────────────────────────
def read_info(path):
    meta, rows, header = {}, [], None
    for raw in open(path, encoding='utf-8'):
        line = raw.rstrip('\n')
        m = re.match(r'^-\s*([^:：]+)[:：]\s*(.*)$', line)
        if m and header is None:
            meta[m.group(1).strip()] = m.group(2).strip()
            continue
        if '|' in line:
            cells = [c.strip() for c in line.split('|')]
            if header is None:
                header = cells
                continue
            rows.append(dict(zip(header, cells + [''] * (len(header) - len(cells)))))
        elif header is not None and rows and not line.strip():
            break
    return meta, rows


# ───────────────────────── TeX 읽기 도우미 ─────────────────────────
def strip_comments(tex):
    return re.sub(r'(?<!\\)%[^\n]*', '', tex)


def group_at(s, i):
    """s[i] == '{' → (내용, 닫는 괄호 다음 위치)"""
    assert s[i] == '{', s[i:i + 30]
    depth = 0
    j = i
    while j < len(s):
        c = s[j]
        if c == '\\':
            j += 2
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return s[i + 1:j], j + 1
        j += 1
    raise ValueError('괄호가 닫히지 않았습니다')


def skip_ws(s, i):
    while i < len(s) and s[i] in ' \t\n':
        i += 1
    return i


def args(s, i, n):
    out = []
    for _ in range(n):
        i = skip_ws(s, i)
        g, i = group_at(s, i)
        out.append(g)
    return out, i


def find_macro(s, name):
    """\\name 사용 위치 (정의 \\newcommand{\\name} 는 제외)"""
    for m in re.finditer(r'\\' + name + r'(?![A-Za-z])', s):
        before = s[max(0, m.start() - 12):m.start()]
        if 'command{' in before:
            continue
        yield m


def problem_cells(tex):
    cells = []
    for m in sorted(list(find_macro(tex, 'PairPage')) + list(find_macro(tex, 'SoloPage')), key=lambda m: m.start()):
        if 'PairPage' in m.group(0):
            a, _ = args(tex, m.end(), 4)
            cells += [a[2], a[3]]
        else:
            a, _ = args(tex, m.end(), 2)
            cells.append(a[1])
    return cells


def solution_blocks(tex):
    out = []
    for m in find_macro(tex, 'SolBlock'):
        a, _ = args(tex, m.end(), 2)
        if a[1].strip():
            out.append((a[0], a[1]))
    return out


# ───────────────────────── TikZ → SVG ─────────────────────────
KATEX_HOME = os.environ.get('KATEX_HOME', '/opt/npm-tools/node_modules')
CM = 28.3465  # 1cm = 28.35pt


def tikz_to_svg(src, problems):
    """간단한 TikZ (draw/fill/node/foreach, -- / controls / circle / rectangle) → SVG."""
    opts_m = re.match(r'\s*\[([^\]]*)\]', src)
    scale = 1.0
    if opts_m:
        sm = re.search(r'scale\s*=\s*([\d.]+)', opts_m.group(1))
        if sm:
            scale = float(sm.group(1))
        src = src[opts_m.end():]
    src = expand_foreach(src)
    shapes = []
    pts_all = []

    def P(x, y):
        X, Y = float(x) * scale * CM, -float(y) * scale * CM
        pts_all.append((X, Y))
        return X, Y

    for stmt in split_statements(src):
        stmt = stmt.strip()
        if not stmt:
            continue
        m = re.match(r'\\(draw|fill|filldraw|path)\s*(\[[^\]]*\])?\s*(.*)$', stmt, re.S)
        n = re.match(r'\\node\s*(\[[^\]]*\])?\s*at\s*\(([^)]*)\)\s*\{(.*)\}\s*$', stmt, re.S)
        if n:
            o = (n.group(1) or '')[1:-1]
            x, y = [v.strip() for v in n.group(2).split(',')]
            X, Y = P(x, y)
            txt = re.sub(r'\\(footnotesize|small|scriptsize|tiny|large|normalsize)\s*', '', n.group(3)).strip()
            size = 8.0 if 'footnotesize' in n.group(3) else (7.0 if 'scriptsize' in n.group(3) else 10.0)
            color = 'white' if re.search(r'\bwhite\b', o) else '#000'
            shapes.append(f'<text x="{X:.2f}" y="{Y + size * 0.35:.2f}" font-size="{size}" text-anchor="middle" '
                          f'font-family="serif" fill="{color}">{escape(txt)}</text>')
            continue
        if not m:
            problems.append(f'TikZ 문장을 그리지 못함: {stmt[:60]}')
            continue
        kind, o, path = m.group(1), (m.group(2) or '[]')[1:-1], m.group(3)
        lw = 0.4
        lwm = re.search(r'line width\s*=\s*([\d.]+)\s*pt', o)
        if lwm:
            lw = float(lwm.group(1))
        if 'thick' in o and 'very' in o:
            lw = 1.2
        elif re.search(r'\bthick\b', o):
            lw = 0.8
        fill = 'none'
        fm = re.search(r'fill\s*=\s*([a-z!0-9]+)', o)
        if fm:
            fill = color_of(fm.group(1))
        elif kind in ('fill',):
            fill = '#000'
        stroke = 'none' if kind == 'fill' else '#000'
        dash = ' stroke-dasharray="3 2"' if 'dashed' in o else ''
        d, circles = path_to_d(path, P, problems)
        for (cx, cy, r) in circles:
            shapes.append(f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r:.2f}" fill="{fill}" stroke="{stroke}" stroke-width="{lw}"{dash}/>')
        if d:
            shapes.append(f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{lw}"{dash}/>')
    if not pts_all:
        return None
    xs = [p[0] for p in pts_all]
    ys = [p[1] for p in pts_all]
    pad = 10
    x0, y0, x1, y1 = min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad
    w, h = x1 - x0, y1 - y0
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:.1f}" height="{h:.1f}" '
            f'viewBox="{x0:.2f} {y0:.2f} {w:.2f} {h:.2f}">{"".join(shapes)}</svg>')


def color_of(c):
    return {'white': '#fff', 'black': '#000', 'gray': '#888', 'lightgray': '#ccc'}.get(c.split('!')[0], '#000')


def escape(t):
    return t.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def split_statements(src):
    out, cur, depth = [], '', 0
    for c in src:
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
        if c == ';' and depth == 0:
            out.append(cur)
            cur = ''
        else:
            cur += c
    out.append(cur)
    return out


def expand_foreach(src):
    while True:
        m = re.search(r'\\foreach\s+((?:\\[a-zA-Z]+/?)+)\s+in\s*\{', src)
        if not m:
            return src
        names = re.findall(r'\\([a-zA-Z]+)', m.group(1))
        items, j = group_at(src, m.end() - 1)
        j = skip_ws(src, j)
        body, k = group_at(src, j)
        out = []
        for item in items.split(','):
            vals = item.strip().split('/')
            b = body
            for nm, v in sorted(zip(names, vals), key=lambda t: -len(t[0])):
                b = re.sub(r'\\' + nm + r'(?![A-Za-z])', v.strip(), b)
            out.append(b)
        src = src[:m.start()] + ' '.join(out) + src[k:]


def path_to_d(path, P, problems):
    toks = re.findall(r'\(([^)]*)\)|(--|\.\.|controls|and|circle|rectangle|cycle)', path)
    d = []
    circles = []
    i = 0
    cur = None
    pending = None  # 'line' | 'curve' | 'circle' | 'rect'
    ctrl = []
    while i < len(toks):
        coord, word = toks[i]
        if coord:
            parts = [v.strip() for v in coord.split(',')]
            if pending == 'circle':
                r = float(re.sub(r'[a-z]+', '', parts[0])) * (P(0, 0)[0] * 0 + 1)
                # 반지름은 scale 만 곱한다
                sx = abs(P(1, 0)[0] - P(0, 0)[0])
                pts_last = cur
                circles.append((pts_last[0], pts_last[1], r * sx))
                pending = None
            elif len(parts) == 2:
                X, Y = P(parts[0], parts[1])
                if pending == 'curve-ctrl':
                    ctrl.append((X, Y))
                elif pending == 'curve-end' or (pending is None and ctrl):
                    c1, c2 = (ctrl + [ctrl[-1]])[:2]
                    d.append(f'C {c1[0]:.2f} {c1[1]:.2f} {c2[0]:.2f} {c2[1]:.2f} {X:.2f} {Y:.2f}')
                    ctrl = []
                    pending = None
                elif pending == 'line':
                    d.append(f'L {X:.2f} {Y:.2f}')
                    pending = None
                elif pending == 'rect':
                    a = cur
                    d.append(f'M {a[0]:.2f} {a[1]:.2f} L {X:.2f} {a[1]:.2f} L {X:.2f} {Y:.2f} L {a[0]:.2f} {Y:.2f} Z')
                    pending = None
                else:
                    d.append(f'M {X:.2f} {Y:.2f}')
                cur = (X, Y)
            else:
                problems.append(f'TikZ 좌표를 읽지 못함: ({coord})')
        else:
            if word == '--':
                pending = 'line'
            elif word == '..':
                pending = 'curve-ctrl' if pending is None else ('curve-end' if pending == 'curve-ctrl' else pending)
            elif word == 'controls':
                pending = 'curve-ctrl'
            elif word == 'and':
                pending = 'curve-ctrl'
            elif word == 'circle':
                pending = 'circle'
            elif word == 'rectangle':
                pending = 'rect'
            elif word == 'cycle':
                d.append('Z')
        i += 1
    # ".. controls (a) and (b) .. (c)" — 끝 '..' 다음 좌표가 끝점
    return ' '.join(d), circles


# ───────────────────────── 본문 변환 ─────────────────────────
class Conv:
    def __init__(self):
        self.problems = []
        self.math = []

    def text(self, s):
        """TeX 본문 → 앱 표기"""
        s = strip_comments(s)
        out = []
        i = 0
        n = len(s)
        buf = ''
        while i < n:
            c = s[i]
            if c == '$':
                j = s.index('$', i + 1)
                m = s[i + 1:j]
                m = re.sub(r'\s+', ' ', m).strip()
                self.math.append(m)
                buf += '$' + m + '$'
                i = j + 1
                continue
            if s.startswith('\\[', i):
                j = s.index('\\]', i)
                m = re.sub(r'\s+', ' ', s[i + 2:j]).strip()
                self.math.append(m)
                buf += '\n$$' + m + '$$\n'
                i = j + 2
                continue
            if s.startswith('\\kbox', i) and not s[i + 5:i + 6].isalpha():
                (inner,), j = args(s, i + 5, 1)
                buf += '\n[[box]]\n' + self.block(inner) + '\n[[/box]]\n'
                i = j
                continue
            if s.startswith('\\begin{center}', i):
                j = s.index('\\end{center}', i)
                inner = s[i + len('\\begin{center}'):j]
                buf += '\n[[center]]\n' + self.block(inner) + '\n[[/center]]\n'
                i = j + len('\\end{center}')
                continue
            if s.startswith('\\begin{tikzpicture}', i):
                j = s.index('\\end{tikzpicture}', i)
                svg = tikz_to_svg(s[i + len('\\begin{tikzpicture}'):j], self.problems)
                if svg:
                    buf += '\n[[svg]]' + svg + '[[/svg]]\n'
                i = j + len('\\end{tikzpicture}')
                continue
            m = re.match(r'\\(textbf|textit|emph|underline|text|mathrm)\s*\{', s[i:])
            if m:
                (inner,), j = args(s, i + m.end() - 1, 1)
                t = self.text(inner)
                buf += {'textbf': f'**{t}**', 'underline': f'__{t}__'}.get(m.group(1), t)
                i = j
                continue
            m = re.match(r'\\(vspace|hspace|vspace\*|hspace\*)\s*\{', s[i:])
            if m:
                _, j = args(s, i + m.end() - 1, 1)
                i = j
                continue
            m = re.match(r'\\([A-Za-z]+)\*?', s[i:])
            if m:
                name = m.group(1)
                rep = {
                    'textbullet': '•', 'quad': '  ', 'qquad': '    ', 'noindent': '', 'par': '\n\n', 'newline': '\n',
                    'dots': '…', 'cdots': '⋯', 'ldots': '…', 'centering': '', 'raggedright': '', 'small': '',
                    'footnotesize': '', 'normalsize': '', 'medskip': '\n\n', 'bigskip': '\n\n', 'smallskip': '\n\n',
                    'hfill': ' ', 'null': '', 'vfill': '', 'sanslabel': '', 'bfseries': '', 'LaTeX': 'LaTeX',
                }
                if name in rep:
                    buf += rep[name]
                else:
                    self.problems.append(f'모르는 명령 \\{name}')
                i += m.end()
                continue
            if s.startswith('\\\\', i):
                buf += '\n'
                i += 2
                continue
            if c == '\\' and i + 1 < n:
                nxt = s[i + 1]
                buf += {',': ' ', ' ': ' ', '%': '%', '&': '&', '#': '#', '_': '_', '$': '$', '{': '{', '}': '}', ';': ' '}.get(nxt, '')
                i += 2
                continue
            if c in '{}':
                i += 1
                continue
            if c == '~':
                buf += ' '
                i += 1
                continue
            if s.startswith('``', i):
                buf += '“'
                i += 2
                continue
            if s.startswith("''", i):
                buf += '”'
                i += 2
                continue
            if s.startswith('---', i):
                buf += '—'
                i += 3
                continue
            if s.startswith('--', i):
                buf += '–'
                i += 2
                continue
            buf += c
            i += 1
        return self.paragraphs(buf)

    def block(self, inner):
        """상자·가운데 블록 안: 문단마다 빈 줄을 두어 바깥 문단 정리에서 합쳐지지 않게."""
        return '\n\n'.join(self.text(inner).strip().split('\n'))

    @staticmethod
    def paragraphs(buf):
        """빈 줄 = 문단, 문단 안의 줄바꿈 = 띄어쓰기 (TeX 처럼). 블록 표지는 제 줄에."""
        out_lines = []
        para = []

        def flush():
            if para:
                t = re.sub(r'[ \t]+', ' ', ' '.join(para)).strip()
                if t:
                    out_lines.append(t)
                para.clear()

        for raw in buf.split('\n'):
            line = raw.strip()
            if not line:
                flush()
                continue
            if line.startswith('$$') or line.startswith('[[') or line.endswith(']]') and line.startswith('[['):
                flush()
                out_lines.append(line)
                continue
            para.append(line)
        flush()
        return '\n'.join(out_lines)


def course_of(unit, fallback):
    for name, c in COURSES.items():
        if unit.startswith(name):
            return c
    for name, c in COURSES.items():
        if fallback.startswith(name):
            return c
    return ('etc', fallback or '기타', '#5B6475', 'math')


def slug(s):
    for a, b in (('확통', 'prob'), ('숙제', 'hw'), ('수업', 'cls'), ('기출', 'gc'), ('변형', 'var'), ('심화', 'adv'),
                 ('DAY', 'd'), ('수학Ⅰ', 'm1'), ('수학Ⅱ', 'm2'), ('확률과 통계', 'prob')):
        s = s.replace(a, b)
    return re.sub(r'[^0-9A-Za-z]+', '-', s).strip('-').lower()


def build(folder, outdir, preview=False):
    meta, rows = read_info(os.path.join(folder, '정보.txt'))
    texdir = os.path.join(folder, 'TeX원본')
    texs = [f for f in os.listdir(texdir) if f.endswith('.tex') and '통합본' in f] or [f for f in os.listdir(texdir) if f.endswith('.tex')]
    tex = strip_comments(open(os.path.join(texdir, texs[0]), encoding='utf-8').read())
    title = re.sub(r'\s*문항.*$', '', meta.get('교재명', os.path.basename(folder))).strip()
    series = meta.get('시리즈', '').split('(')[0].strip() or title.split()[0]
    num = re.search(r'(\d+)\s*회차', title)
    book_id = slug(series) + (f'-{int(num.group(1)):02d}' if num else '')

    conv = Conv()
    cells = problem_cells(tex)
    sols = solution_blocks(tex)
    report = {'book': title, 'id': book_id, 'rows': len(rows), 'cells': len(cells), 'solutions': len(sols), 'issues': []}
    if len(cells) != len(rows):
        report['issues'].append(f'문항 칸 {len(cells)}개 ≠ 정보.txt {len(rows)}개')
    if len(sols) != len(rows):
        report['issues'].append(f'해설 {len(sols)}개 ≠ 정보.txt {len(rows)}개')

    courses = {}
    ids = {}
    for r in rows:
        ids[r['문항번호']] = f'{book_id}-{slug(r["문항번호"])}'
    all_ids = []
    for k, r in enumerate(rows):
        if k >= len(cells):
            break
        cell = cells[k]
        tm = re.search(r'\\TagBox(C?)\s*\{', cell)
        label, label_src, accent = '', '', False
        if tm:
            (label, label_src), j = args(cell, tm.end() - 1, 2)
            accent = tm.group(1) == 'C'
            cell = cell[:tm.start()] + cell[j:]
        stem = conv.text(cell).strip()
        sol = conv.text(sols[k][1]).strip() if k < len(sols) else ''
        cid, cname, color, group = course_of(r.get('단원', ''), meta.get('과목', ''))
        course = courses.setdefault(cid, {
            'subject': cname, 'subjectId': cid, 'color': color, 'group': group, 'level': 'high',
            'grades': ['고3', 'N수'] if '고3' in meta.get('대상 학년', '') else ['고1', '고2', '고3', 'N수'],
            'track': '수능', 'problems': []})
        unit = r.get('단원', '')
        for name in COURSES:
            if unit.startswith(name):
                unit = unit[len(name):].strip() or unit
        try:
            diff = max(1, min(5, int(r.get('난이도(1~5)', '3'))))
        except ValueError:
            diff = 3
        topic = re.split(r'[:：]', r.get('유형', ''))[0].strip()
        day = re.search(r'DAY\s*(\d+)', r.get('문항번호', ''))
        if day:
            topic = f'DAY {day.group(1)} · {topic}'
        p = {
            'id': ids[r['문항번호']],
            'unit': unit,
            'topic': topic,
            'difficulty': diff,
            'type': 'short',
            'stem': stem,
            'answer': r.get('정답', '').strip(),
            'solution': sol,
            'label': conv.text(label).strip(),
            'texStyle': True,
            'points': 0,
            'tags': [title],
        }
        if accent:
            p['labelAccent'] = True
        src = r.get('출처', '').strip() or conv.text(label_src).strip()
        if src:
            p['source'] = src
        course['problems'].append(p)
        all_ids.append(p['id'])
    for c in courses.values():
        c['units'] = list(dict.fromkeys(p['unit'] for p in c['problems']))
    stage = meta.get('커리큘럼 단계', 'N제').strip()
    main = max(courses.values(), key=lambda c: len(c['problems']))['subjectId']
    wb = {
        'id': book_id, 'title': title, 'course': main,
        'stage': stage if stage in ('개념', '유형', '기출', 'N제', '모의고사') else 'N제',
        'scope': meta.get('범위', '').replace(' / ', ' · '),
        'level': '심화' if stage == 'N제' else '기본',
        'publisher': meta.get('만든 곳', ''), 'series': series,
        'desc': meta.get('시리즈', ''), 'problems': all_ids,
    }
    bundle = {'format': 'pulinote-bundle', 'version': 1, 'id': book_id, 'title': title,
              'courses': list(courses.values()), 'workbooks': [wb]}
    os.makedirs(outdir, exist_ok=True)
    raw = json.dumps(bundle, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    path = os.path.join(outdir, f'{book_id}.pulinote')
    with open(path, 'wb') as f:
        f.write(gzip.compress(raw, 9))
    report['file'] = path
    report['bytes'] = os.path.getsize(path)
    report['problems'] = len(all_ids)
    report['issues'] += sorted(set(conv.problems))
    report['math_errors'] = check_math(conv.math)
    with open(os.path.join(outdir, f'{book_id}.json'), 'w', encoding='utf-8') as f:
        json.dump(bundle, f, ensure_ascii=False, indent=1)
    if preview:
        report['preview'] = make_preview(bundle, outdir)
    return report


def check_math(snippets):
    """KaTeX 로 모든 수식을 미리 그려 본다 (앱의 flutter_math 는 KaTeX 를 옮긴 것)."""
    here = os.path.dirname(os.path.abspath(__file__))
    js = os.path.join(here, 'katex_check.js')
    uniq = list(dict.fromkeys(snippets))
    env = dict(os.environ, NODE_PATH=os.pathsep.join(filter(None, [os.path.join(here, 'node_modules'), KATEX_HOME, os.environ.get('NODE_PATH')])))
    p = subprocess.run(['node', js], input=json.dumps(uniq), capture_output=True, text=True, env=env)
    if p.returncode != 0:
        return [f'KaTeX 검사 실패: {p.stderr[:300]}']
    return json.loads(p.stdout)


PREVIEW_CSS = """
body{margin:0;background:#E9E6DF;font-family:'Noto Serif CJK KR','NanumMyeongjo',serif;color:#1B2A4A}
.page{width:760px;margin:18px auto;background:#FFFDF8;padding:34px 40px;box-shadow:0 4px 18px #0002}
.tag{display:inline-block;background:#111;color:#fff;font:600 12px sans-serif;padding:3px 8px;margin-right:8px}
.tag.c{background:#D97757}.src{color:#96948C;font:12px sans-serif}
.stem{font-size:17px;line-height:1.75;margin-top:10px}.box{border:1px solid #1B2A4A;padding:8px 12px;margin:6px 0}
.dm{text-align:center;margin:6px 0}.ctr{text-align:center}.sol{font-size:15px;line-height:1.7;border-top:1px dashed #aaa;margin-top:24px;padding-top:12px}
.ans{color:#169C6B;font:700 14px sans-serif;margin-top:12px}
"""


def make_preview(bundle, outdir):
    """앱과 같은 표기로 HTML 을 만들어 Chromium 으로 그린다 (확인용)."""
    import html as H
    from playwright.sync_api import sync_playwright

    def render(src):
        out = []
        for line in src.split('\n'):
            if line == '[[box]]':
                out.append('<div class="box">')
            elif line == '[[/box]]':
                out.append('</div>')
            elif line == '[[center]]':
                out.append('<div class="ctr">')
            elif line == '[[/center]]':
                out.append('</div>')
            elif line.startswith('[[svg]]'):
                out.append(line[7:-8])
            elif line.startswith('$$'):
                out.append('<div class="dm">\\[' + H.escape(line[2:-2]) + '\\]</div>')
            else:
                t = H.escape(line)
                t = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', t)
                out.append('<div>' + t + '</div>')
        return ''.join(out)

    pages = []
    for c in bundle['courses']:
        for p in c['problems']:
            pages.append(f'<div class="page" id="{p["id"]}"><span class="tag{" c" if p.get("labelAccent") else ""}">{H.escape(p["label"])}</span>'
                         f'<span class="src">{H.escape(p.get("source", ""))}</span><div class="stem">{render(p["stem"])}</div>'
                         f'<div class="ans">정답 {H.escape(p["answer"])}</div><div class="sol">{render(p["solution"])}</div></div>')
    doc = ('<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="katex/katex.min.css"><script src="katex/katex.min.js"></script>'
           '<script src="katex/contrib/auto-render.min.js"></script><style>' + PREVIEW_CSS + '</style></head><body>'
           + ''.join(pages) +
           '<script>renderMathInElement(document.body,{delimiters:[{left:"\\\\[",right:"\\\\]",display:true},{left:"$",right:"$",display:false}],throwOnError:false})</script></body></html>')
    here = os.path.dirname(os.path.abspath(__file__))
    kdir = os.path.join(here, 'node_modules', 'katex', 'dist')
    if not os.path.isdir(kdir):
        kdir = os.path.join(KATEX_HOME, 'katex', 'dist')
    pdir = os.path.join(outdir, 'preview')
    os.makedirs(pdir, exist_ok=True)
    if not os.path.exists(os.path.join(pdir, 'katex')):
        os.symlink(kdir, os.path.join(pdir, 'katex'))
    with open(os.path.join(pdir, 'index.html'), 'w', encoding='utf-8') as f:
        f.write(doc)
    shots = []
    with sync_playwright() as pw:
        b = pw.chromium.launch()
        page = b.new_page(viewport={'width': 840, 'height': 1000})
        page.goto('file://' + os.path.join(pdir, 'index.html'))
        page.wait_for_timeout(800)
        for c in bundle['courses']:
            for p in c['problems']:
                el = page.query_selector('#' + p['id'])
                fn = os.path.join(pdir, p['id'] + '.png')
                el.screenshot(path=fn)
                shots.append(fn)
        b.close()
    return len(shots)


if __name__ == '__main__':
    a = [x for x in sys.argv[1:] if not x.startswith('--')]
    print(json.dumps(build(a[0], a[1], preview='--preview' in sys.argv), ensure_ascii=False, indent=1))
