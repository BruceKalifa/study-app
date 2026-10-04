#!/usr/bin/env python3
"""
TeX 원본 교재 → 앱 문항 묶음 (.pulinote)  — 원문을 앱에서 다시 조판한다.

  python3 tools/tex_book.py <교재 폴더> <출력 폴더> [--preview]
  python3 tools/tex_book.py collect <묶음.pulinote> <교재1.pulinote> …   (여러 권을 한 파일로)

교재 폴더(교재모음 형식): 정보.txt (문항 목록 표) + TeX원본/*.tex
  - 문항: \\PairPage / \\SoloPage 칸의 \\TagBox{머리표}{출처} 다음 본문 (정보.txt 순서와 같다)
  - 해설: \\SolBlock / \\SolBlockLast {제목}{본문} (본문이 빈 DAY 제목은 건너뜀)
  - 본문 변환: $…$ 그대로, \\[…\\] → 가운데 수식 줄, \\kbox{…} → 조건 상자, \\TextTable → 나란히,
    tabular → 표, itemize → 목록, \\textbf → **굵게**, 빈 줄 → 문단
  - 그림: tikzpicture 를 원문 머리말 그대로 XeLaTeX 로 조판 → SVG (선·글자 모두 원문과 같음)
필요: xelatex · pdftocairo (그림), node + katex (수식 검사), playwright (--preview)
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
    ms = sorted(list(find_macro(tex, 'SolBlock')) + list(find_macro(tex, 'SolBlockLast')), key=lambda m: m.start())
    for m in ms:
        a, _ = args(tex, m.end(), 2)
        if a[1].strip():
            out.append((a[0], a[1]))
    return out


# ───────────────────────── 그림 (TikZ) → SVG ─────────────────────────
class Figures:
    """그림은 원문 TeX(같은 머리말·글꼴)로 그대로 조판한 뒤 SVG 벡터로 옮긴다 — 선·글자 모두 원문과 같다.

    교재 하나의 그림을 한 번에 XeLaTeX(preview 패키지, 그림마다 한 쪽)로 만들고 pdftocairo 로 쪽마다 SVG 를 뽑은 뒤,
    앱(flutter_svg)이 확실히 그리는 꼴(path · g · transform)로 단순하게 편다.
    """

    def __init__(self, preamble, workdir):
        self.preamble = preamble
        self.workdir = workdir
        self.items = []

    def add(self, tex):
        self.items.append(tex)
        return f'@@FIG{len(self.items) - 1}@@'

    def compile(self):
        if not self.items:
            return []
        os.makedirs(self.workdir, exist_ok=True)
        pre = self.preamble.replace('\\begin{document}', '')
        pre += '\n\\usepackage[active,tightpage]{preview}\n\\setlength\\PreviewBorder{1.5pt}\n'
        body = '\n'.join('\\begin{preview}' + t + '\\end{preview}\n' for t in self.items)
        doc = pre + '\\begin{document}\n\\pagestyle{empty}\n' + body + '\\end{document}\n'
        tex = os.path.join(self.workdir, 'figs.tex')
        with open(tex, 'w', encoding='utf-8') as f:
            f.write(doc)
        r = subprocess.run(['xelatex', '-interaction=nonstopmode', '-halt-on-error', 'figs.tex'],
                           cwd=self.workdir, capture_output=True, text=True, timeout=600)
        pdf = os.path.join(self.workdir, 'figs.pdf')
        if r.returncode != 0 or not os.path.exists(pdf):
            raise RuntimeError('그림 조판 실패:\n' + r.stdout[-2500:])
        out = []
        for k in range(len(self.items)):
            svg_path = os.path.join(self.workdir, f'fig{k}.svg')
            subprocess.run(['pdftocairo', '-svg', '-f', str(k + 1), '-l', str(k + 1), pdf, svg_path], check=True)
            out.append(flatten_svg(open(svg_path, encoding='utf-8').read()))
        return out


KATEX_HOME = os.environ.get('KATEX_HOME', '/opt/npm-tools/node_modules')
SVG_NS = 'http://www.w3.org/2000/svg'
XLINK = '{http://www.w3.org/1999/xlink}href'


def flatten_svg(text):
    """pdftocairo SVG → 글자 모양(<symbol>/<use>)을 펼친 단순한 SVG (pt 단위 숫자 width/height)."""
    import copy
    import xml.etree.ElementTree as ET
    ET.register_namespace('', SVG_NS)
    root = ET.fromstring(text.encode('utf-8'))
    q = lambda t: f'{{{SVG_NS}}}{t}'
    symbols = {}
    for el in root.iter():
        if el.tag in (q('symbol'), q('g')) and el.get('id'):
            symbols[el.get('id')] = el

    def expand(parent):
        for i, child in enumerate(list(parent)):
            if child.tag == q('use'):
                ref = (child.get(XLINK) or child.get('href') or '').lstrip('#')
                sym = symbols.get(ref)
                g = ET.Element(q('g'))
                x, y = float(child.get('x', 0)), float(child.get('y', 0))
                tr = child.get('transform', '')
                g.set('transform', (tr + ' ' if tr else '') + f'translate({x:.3f},{y:.3f})')
                for k in ('fill', 'stroke', 'style', 'fill-opacity', 'stroke-width'):
                    if child.get(k):
                        g.set(k, child.get(k))
                if sym is not None:
                    for c in sym:
                        g.append(copy.deepcopy(c))
                    expand(g)
                parent.remove(child)
                parent.insert(i, g)
            else:
                expand(child)

    defs = [d for d in root if d.tag == q('defs')]
    for d in defs:
        root.remove(d)
    expand(root)
    for el in root.iter():
        for k in ('clip-path', 'mask'):
            if k in el.attrib:
                del el.attrib[k]
    # empty groups / page rects left by cairo
    w = float(re.sub(r'[a-z]+$', '', root.get('width', '0')))
    h = float(re.sub(r'[a-z]+$', '', root.get('height', '0')))
    root.set('width', f'{w:.2f}')
    root.set('height', f'{h:.2f}')
    if not root.get('viewBox'):
        root.set('viewBox', f'0 0 {w:.2f} {h:.2f}')
    out = ET.tostring(root, encoding='unicode')
    # rgb(12%, 50%, 0%) → #1F8000 (모든 SVG 읽개가 아는 꼴)
    out = re.sub(r'rgb\(\s*([\d.]+)%\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*\)',
                 lambda m: '#' + ''.join(f'{round(float(v) * 2.55):02X}' for v in m.groups()), out)
    out = re.sub(r'\s+', ' ', out)
    out = re.sub(r'(\d+\.\d{3})\d+', r'\1', out)  # 숫자 자리 줄이기
    return out


# ───────────────────────── 본문 변환 ─────────────────────────
CIRCLED = '⓪①②③④⑤⑥⑦⑧⑨⑩'

# 글 속 명령 → 글자 (나머지 꾸밈 명령은 버린다)
TEXT_REP = {
    'textbullet': '•', 'quad': '  ', 'qquad': '    ', 'noindent': '', 'par': '\n\n', 'newline': '\n',
    'dots': '…', 'cdots': '⋯', 'ldots': '…', 'centering': '', 'raggedright': '', 'raggedleft': '',
    'small': '', 'footnotesize': '', 'normalsize': '', 'scriptsize': '', 'large': '', 'tiny': '', 'Large': '',
    'medskip': '\n\n', 'bigskip': '\n\n', 'smallskip': '\n\n', 'hfill': ' ', 'null': '', 'vfill': '',
    'sanslabel': '', 'bfseries': '', 'mdseries': '', 'itshape': '', 'normalfont': '', 'selectfont': '',
    'LaTeX': 'LaTeX', 'enspace': ' ', 'thinspace': ' ', 'hline': '', 'clearpage': '', 'newpage': '',
    'linebreak': '\n', 'pagebreak': '', 'allowbreak': '', 'relax': '', 'protect': '', 'strut': '',
    'textbar': '|', 'textendash': '–', 'textemdash': '—', 'S': '§', 'times': '×',
}
# 인자를 받아 버리는 명령 (인자 개수)
DROP_ARGS = {'vspace': 1, 'hspace': 1, 'setlength': 2, 'renewcommand': 2, 'color': 1, 'needspace': 1,
             'addtolength': 2, 'fontsize': 2, 'phantom': 1, 'label': 1, 'Section': 1, 'PageLead': 1, 'rule': 2}


def expand_math(m):
    """원문 머리말의 수식 매크로를 KaTeX 가 아는 꼴로."""
    m = re.sub(r'\s+', ' ', m).strip()
    for _ in range(4):
        k = m.find('\\fitm')
        if k < 0:
            break
        j = skip_ws(m, k + 5)
        if j < len(m) and m[j] == '{':
            inner, e = group_at(m, j)
            m = m[:k] + inner.strip() + m[e:]
        else:
            m = m[:k] + m[k + 5:]
    # array 열 지정의 @{…}·!{…} 는 KaTeX/flutter_math 가 모른다 (간격만 바뀜)
    m = re.sub(r'(\\begin\{array\}\s*\{)([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}',
               lambda x: x.group(1) + re.sub(r'[@!]\{[^{}]*\}', '', x.group(2)) + '}', m)
    # 빈칸 상자: \\mbox{\\setlength{\\fboxsep}{..}\\fbox{(가)}} → \\boxed{(가)}
    m = re.sub(r'\\mbox\s*\{\s*\\setlength\s*\{\\fboxsep\}\s*\{[^{}]*\}\s*\\fbox\s*\{([^{}]*)\}\s*\}', r'\\boxed{\1}', m)
    m = re.sub(r'\\fbox\s*\{([^{}]*)\}', r'\\boxed{\1}', m)
    m = re.sub(r'\\fboxsep\s*=?\s*[\d.]+\s*(pt|em|ex|mm)', '', m)
    m = re.sub(r'\\setlength\s*\{\\fboxsep\}\s*\{[^{}]*\}', '', m)
    # 수식 속 한글 빈칸 이름 (가)·(나) 는 글자로
    m = re.sub(r'(?<!\\text\{)\(([가-힣])\)', r'\\text{(\1)}', m)
    m = re.sub(r'\\circnum\s*\{(\d+)\}', lambda x: '\\text{' + CIRCLED[int(x.group(1))] + '}', m)
    m = re.sub(r'\\textcircled\s*\{\\scriptsize\s*(\d+)\}', lambda x: '\\text{' + CIRCLED[int(x.group(1))] + '}', m)
    return m.strip()


class Conv:
    def __init__(self, figs=None):
        self.problems = []
        self.math = []
        self.figs = figs
        self._lists = []

    def mathed(self, m):
        m = expand_math(m)
        self.math.append(m)
        return m

    def text(self, s):
        """TeX 본문 → 앱 표기"""
        s = strip_comments(s)
        n = len(s)
        buf = ''
        i = 0
        while i < n:
            c = s[i]
            if c == '$':
                if s.startswith('$$', i):
                    j = s.index('$$', i + 2)
                    buf += '\n$$' + self.mathed(s[i + 2:j]) + '$$\n'
                    i = j + 2
                    continue
                j = i + 1
                while True:
                    j = s.index('$', j)
                    if s[j - 1] != '\\':
                        break
                    j += 1
                buf += '$' + self.mathed(s[i + 1:j]) + '$'
                i = j + 1
                continue
            if s.startswith('\\[', i):
                j = s.index('\\]', i)
                buf += '\n$$' + self.mathed(s[i + 2:j]) + '$$\n'
                i = j + 2
                continue
            if s.startswith('\\begin{', i):
                (env,), j = args(s, i + 6, 1)
                end = self.env_end(s, j, env)
                inner = s[j:end]
                after = end + len('\\end{' + env + '}')
                buf += self.environment(env, inner)
                i = after
                continue
            m = re.match(r'\\([A-Za-z]+)\*?', s[i:])
            if m:
                name = m.group(1)
                j = i + m.end()
                if name == 'kbox':
                    (inner,), j = args(s, j, 1)
                    buf += '\n[[box]]\n' + self.block(inner) + '\n[[/box]]\n'
                    i = j
                    continue
                if name == 'TextTable':
                    (left, right), j = args(s, j, 2)
                    buf += '\n[[cols:58:39]]\n' + self.block(left) + '\n[[col]]\n' + self.block(right) + '\n[[/cols]]\n'
                    i = j
                    continue
                if name in ('textbf', 'textit', 'emph', 'underline', 'text', 'mathrm', 'textrm', 'textsf', 'mbox',
                            'sanslabel', 'textsc', 'texttt'):
                    k = skip_ws(s, j)
                    if k < n and s[k] == '{':
                        (inner,), j = args(s, k, 1)
                        t = self.text(inner)
                        buf += {'textbf': f'**{t}**', 'underline': f'__{t}__'}.get(name, t)
                        i = j
                        continue
                if name == 'fbox':
                    (inner,), j = args(s, j, 1)
                    buf += '$' + self.mathed('\\boxed{' + inner + '}') + '$'
                    i = j
                    continue
                if name == 'fboxsep':
                    mm = re.match(r'\s*=?\s*[\d.]+\s*(pt|em|ex|mm)', s[j:])
                    i = j + (mm.end() if mm else 0)
                    continue
                if name in ('circnum', 'textcircled'):
                    (inner,), j = args(s, j, 1)
                    d = re.sub(r'\D', '', inner)
                    buf += CIRCLED[int(d)] if d and int(d) < len(CIRCLED) else inner
                    i = j
                    continue
                if name in DROP_ARGS:
                    for _ in range(DROP_ARGS[name]):
                        k = skip_ws(s, j)
                        if k < n and s[k] == '[':
                            j = s.index(']', k) + 1
                            k = skip_ws(s, j)
                        if k < n and s[k] == '{':
                            _, j = args(s, k, 1)
                        elif k < n and s[k] == '\\':
                            mm = re.match(r'\\[A-Za-z]+', s[k:])
                            j = k + (mm.end() if mm else 1)
                    i = j
                    continue
                if name == 'item':
                    buf += '\n' + self.item_mark() + ' '
                    i = j
                    continue
                if name in TEXT_REP:
                    buf += TEXT_REP[name]
                    # "\textbullet\ " 같은 띄어쓰기는 아래 '\\ ' 처리
                else:
                    self.problems.append(f'모르는 명령 \\{name}')
                i = j
                continue
            if s.startswith('\\\\', i):
                buf += '\n'
                i += 2
                k = skip_ws(s, i)
                if k < n and s[k] == '[':
                    i = s.index(']', k) + 1
                continue
            if c == '\\' and i + 1 < n:
                nxt = s[i + 1]
                buf += {',': ' ', ' ': ' ', '%': '%', '&': '&', '#': '#', '_': '_', '$': '$', '{': '{', '}': '}', ';': ' ',
                        '!': ''}.get(nxt, '')
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

    @staticmethod
    def env_end(s, j, env):
        """matching \\end{env} (같은 환경이 겹쳐도)"""
        depth = 1
        pat = re.compile(r'\\(begin|end)\{' + re.escape(env) + r'\}')
        for m in pat.finditer(s, j):
            depth += 1 if m.group(1) == 'begin' else -1
            if depth == 0:
                return m.start()
        raise ValueError(f'\\end{{{env}}} 없음')

    def item_mark(self):
        if not self._lists:
            return '•'
        kind, k = self._lists[-1]
        self._lists[-1] = (kind, k + 1)
        return '•' if kind == 'itemize' else f'{k + 1}.'

    def environment(self, env, inner):
        if env == 'tikzpicture':
            if self.figs is None:
                self.problems.append('그림(TikZ)을 옮기려면 figs 가 필요')
                return ''
            return '\n' + self.figs.add('\\begin{tikzpicture}' + inner + '\\end{tikzpicture}') + '\n'
        if env == 'center':
            return '\n[[center]]\n' + self.block(inner) + '\n[[/center]]\n'
        if env in ('itemize', 'enumerate'):
            self._lists.append((env, 0))
            body = self.text(inner)
            self._lists.pop()
            return '\n' + body + '\n'
        if env in ('tabular', 'tabular*', 'array'):
            return '\n' + self.table(inner) + '\n'
        if env in ('minipage', 'flushleft', 'flushright', 'raggedright', 'small', 'footnotesize', 'multicols', 'multicols*'):
            inner = re.sub(r'^\s*(\[[^\]]*\])*\s*(\{[^{}]*\})?', '', inner, count=1) if env in ('minipage', 'multicols', 'multicols*') else inner
            return '\n' + self.text(inner) + '\n'
        if env in ('aligned', 'align', 'align*', 'gathered', 'cases', 'equation', 'equation*'):
            return '\n$$' + self.mathed('\\begin{%s}%s\\end{%s}' % (env.rstrip('*') if env.startswith('align') else env, inner, env.rstrip('*') if env.startswith('align') else env)) + '$$\n'
        self.problems.append(f'모르는 환경 {env}')
        return '\n' + self.text(inner) + '\n'

    def table(self, inner):
        """tabular → 앱 표 (| a | b |). 첫 줄 아래 \\hline 이 있으면 머리글."""
        k = skip_ws(inner, 0)
        if k < len(inner) and inner[k] == '{':  # column spec
            _, k = group_at(inner, k)
        body = inner[k:]
        # 칸 안의 환경(표 속 표, aligned …)은 잠시 감춰 두고 & · \\\\ 로 나눈다
        hidden = []

        def hide(text):
            out, i = '', 0
            while True:
                m = re.compile(r'\\begin\{([^}]*)\}').search(text, i)
                if not m:
                    return out + text[i:]
                end = self.env_end(text, m.end(), m.group(1)) + len('\\end{' + m.group(1) + '}')
                hidden.append(text[m.start():end])
                out += text[i:m.start()] + f'\x00{len(hidden) - 1}\x00'
                i = end

        def show(text):
            return re.sub('\x00(\\d+)\x00', lambda m: hidden[int(m.group(1))], text)

        body = hide(body)
        rows, cur, depth, i = [], '', 0, 0
        while i < len(body):
            c = body[i]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
            if depth == 0 and body.startswith('\\\\', i):
                rows.append(cur)
                cur = ''
                i += 2
                continue
            cur += c
            i += 1
        rows.append(cur)
        lines, header = [], False
        for r_i, r in enumerate(rows):
            raw = r
            r = r.replace('\\hline', '').strip()
            if not r:
                continue
            cells, cur, depth = [], '', 0
            for c in r:
                if c == '{':
                    depth += 1
                elif c == '}':
                    depth -= 1
                if c == '&' and depth == 0 and not cur.endswith('\\'):
                    cells.append(cur)
                    cur = ''
                else:
                    cur += c
            cells.append(cur)
            cells = [re.sub(r'\\multicolumn\s*\{\d+\}\s*\{[^}]*\}', '', x) for x in cells]
            texts = [self.text(show(x)).replace('\n', ' ').replace('|', '｜').strip() for x in cells]
            lines.append('| ' + ' | '.join(texts) + ' |')
            if len(lines) == 1 and r_i + 1 < len(rows) and rows[r_i + 1].lstrip().startswith('\\hline') and len(rows) > 3:
                header = True
        if header and len(lines) > 1:
            lines.insert(1, '|' + '---|' * lines[0].count(' | ') + '---|')
        return '\n'.join(lines)

    def block(self, inner):
        """상자·가운데 블록 안: 문단마다 빈 줄을 두어 바깥 문단 정리에서 합쳐지지 않게."""
        return '\n\n'.join(self.text(inner).strip().split('\n'))

    @staticmethod
    def paragraphs(buf):
        """빈 줄 = 문단, 문단 안의 줄바꿈 = 띄어쓰기 (TeX 처럼). 블록 표지·표·목록은 제 줄에."""
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
            if line.startswith(('$$', '[[', '@@FIG', '|')):
                flush()
                out_lines.append(line)
                continue
            if re.match(r'^(•|\d+\.) ', line):  # 목록 항목은 새 줄에서 시작
                flush()
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
    raw_tex = open(os.path.join(texdir, texs[0]), encoding='utf-8').read()
    preamble = raw_tex[:raw_tex.index('\\begin{document}')]
    tex = strip_comments(raw_tex)
    title = re.sub(r'\s*문항.*$', '', meta.get('교재명', os.path.basename(folder))).strip()
    series = meta.get('시리즈', '').split('(')[0].strip() or title.split()[0]
    num = re.search(r'(\d+)\s*회차', title)
    book_id = slug(series) + (f'-{int(num.group(1)):02d}' if num else '')

    figs = Figures(preamble, os.path.join(outdir, '_figs', book_id))
    # 머리표 색: \\TagBox* 정의의 \\colorbox{이름} → \\definecolor 의 RGB
    colors = {'black': '#000000', 'white': '#FFFFFF'}
    for m in re.finditer(r'\\definecolor\{(\w+)\}\{RGB\}\{(\d+),\s*(\d+),\s*(\d+)\}', preamble):
        colors[m.group(1)] = '#' + ''.join(f'{int(v):02X}' for v in m.groups()[1:])
    tag_colors = {}
    for m in re.finditer(r'\\newcommand\{\\(TagBox[A-Z]?)\}\[2\]\{[^\n]*?\\colorbox\{(\w+)\}', preamble):
        tag_colors[m.group(1)] = colors.get(m.group(2), '#000000')
    conv = Conv(figs)
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
        tm = re.search(r'\\(TagBox[A-Z]?)\s*\{', cell)
        label, label_src, label_color = '', '', None
        if tm:
            (label, label_src), j = args(cell, tm.end() - 1, 2)
            label_color = tag_colors.get(tm.group(1))
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
        if label_color and label_color != '#000000':
            p['labelColor'] = label_color
        src = r.get('출처', '').strip() or conv.text(label_src).strip()
        if src:
            p['source'] = src
        course['problems'].append(p)
        all_ids.append(p['id'])
    # 그림: 원문 TeX 로 한꺼번에 조판해서 SVG 로 바꿔 넣는다
    svgs = figs.compile()
    report['figures'] = len(svgs)

    def put(t):
        return re.sub(r'@@FIG(\d+)@@', lambda m: '[[svg]]' + svgs[int(m.group(1))] + '[[/svg]]', t)

    for c in courses.values():
        for p in c['problems']:
            p['stem'] = put(p['stem'])
            p['solution'] = put(p['solution'])
        c['units'] = list(dict.fromkeys(p['unit'] for p in c['problems']))
    stage = meta.get('커리큘럼 단계', 'N제').strip()
    main = max(courses.values(), key=lambda c: len(c['problems']))['subjectId']
    wb = {
        'id': book_id, 'title': title, 'course': main,
        'stage': stage if stage in ('개념', '유형', '기출', 'N제', '모의고사') else 'N제',
        # 고르기 화면의 범위 칩: 과목 묶음 (같은 시리즈끼리 같은 칩), 자세한 범위는 설명에
        'scope': '·'.join(x.strip() for x in re.split(r'[,，]', meta.get('과목', '')) if x.strip()),
        'level': '심화' if stage == 'N제' else '기본',
        'publisher': meta.get('만든 곳', ''), 'series': series,
        'desc': ' — '.join(x for x in (meta.get('시리즈', ''), meta.get('범위', '').replace(' / ', ' · ')) if x),
        'problems': all_ids,
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
.cols{display:flex;gap:14px;align-items:flex-start}.tb{border-collapse:collapse;font-size:14px}.tb td{border:1px solid #1B2A4A;padding:2px 10px;text-align:center}
"""


def make_preview(bundle, outdir):
    """앱과 같은 표기로 HTML 을 만들어 Chromium 으로 그린다 (확인용)."""
    import html as H
    from playwright.sync_api import sync_playwright

    def render(src):
        out = []
        table = []

        def flush_table():
            if table:
                rows = [r for r in table if not re.match(r'^\|[-|: ]+\|$', r)]
                out.append('<table class="tb">' + ''.join(
                    '<tr>' + ''.join('<td>' + H.escape(c.strip()) + '</td>' for c in r.strip().strip('|').split('|')) + '</tr>'
                    for r in rows) + '</table>')
                table.clear()

        for line in src.split('\n'):
            if line.startswith('|'):
                table.append(line)
                continue
            flush_table()
            if line.startswith('[[cols'):
                ws = [int(x) for x in re.findall(r':(\d+)', line)] or [1, 1]
                out.append(f'<div class="cols"><div style="flex:{ws[0]}">')
                out.append(f'<!--{ws[1] if len(ws) > 1 else 1}-->')
            elif line == '[[col]]':
                out.append('</div><div style="flex:1;display:flex;justify-content:flex-end">')
            elif line == '[[/cols]]':
                out.append('</div></div>')
            elif line == '[[box]]':
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
        flush_table()
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
        only = [x for x in os.environ.get('PREVIEW_ONLY', '').split(',') if x]
        for c in bundle['courses']:
            for p in c['problems']:
                if only and not any(x in p['id'] for x in only):
                    continue
                el = page.query_selector('#' + p['id'])
                fn = os.path.join(pdir, p['id'] + '.png')
                el.screenshot(path=fn)
                shots.append(fn)
        b.close()
    return len(shots)


def collect(out, files):
    """여러 교재 파일을 한 파일로 (앱에서 한 번에 넣기): {format:'pulinote-collection', books:[…]}"""
    books = [json.loads(gzip.decompress(open(f, 'rb').read())) for f in files]
    raw = json.dumps({'format': 'pulinote-collection', 'version': 1, 'books': books}, ensure_ascii=False,
                     separators=(',', ':')).encode('utf-8')
    with open(out, 'wb') as f:
        f.write(gzip.compress(raw, 9))
    return {'file': out, 'books': [b['id'] for b in books], 'bytes': os.path.getsize(out)}


if __name__ == '__main__':
    if sys.argv[1:2] == ['collect']:
        # python3 tools/tex_book.py collect <출력.pulinote> <교재1.pulinote> <교재2.pulinote> …
        print(json.dumps(collect(sys.argv[2], sys.argv[3:]), ensure_ascii=False, indent=1))
        sys.exit(0)
    a = [x for x in sys.argv[1:] if not x.startswith('--')]
    print(json.dumps(build(a[0], a[1], preview='--preview' in sys.argv), ensure_ascii=False, indent=1))
