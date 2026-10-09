#!/usr/bin/env python3
"""
평문 교재 → 앱 문항 묶음 (.pulinote)  — TeX 원본이 없는 자료용 (인적성·NCS·국어 지문형 등).

  python3 tools/text_book.py <교재 폴더> <출력 폴더>
  python3 tools/text_book.py check <교재 폴더>          (변환하지 않고 흠만 본다)

교재 폴더:
  정보.txt            머리말 (- 키: 값)
  문항.txt            문항·지문 본문  (여러 개로 나눠도 됨: 문항*.txt)
  그림/*.svg          선택 — 문항에서 [그림: 이름.svg] 로 부른다

문항.txt 짜임새 — `#문항 <번호>` / `#지문 <번호>` 로 토막을 나눈다.

    #지문 P1
    제목: 데이터 압축
    [본문]
    첫 문단…

    #문항 언어-01
    영역: 언어이해
    유형: 주제 찾기
    형식: 객관식
    정답: 3
    난이도: 3
    지문: P1
    [문제]
    다음 글의 주제로 가장 적절한 것은?
    [선택지]
    1. …
    [해설]
    …

본문 표기법은 docs/problem-schema.md 와 같다 ($수식$, **굵게**, __밑줄__, | 표 |, • 목록).
교재 내용은 저작물이므로 출력은 저장소에 넣지 않는다.
"""

import gzip
import hashlib
import json
import os
import re
import sys

# 과목·영역 이름 → 앱 과목(course): (id, 이름, 색, 교과군)
# assets/problems/*.json 의 subjectId·색과 같아야 한다 (같으면 한 과목으로 합쳐진다).
APT = ('apt', '인적성', '#0E7C86', 'apt')
COURSES = {
    # 인적성·NCS
    '인적성': APT, '언어': APT, '수리': APT, '자료해석': APT, '추리': APT,
    '도식': APT, '공간': APT, '지각': APT, '상식': APT,
    'NCS': ('ncs', 'NCS', '#0E7C86', 'apt'),
    # 교과 (앱에 이미 있는 과목과 같은 id)
    '지구과학Ⅰ': ('earth1', '지구과학Ⅰ', '#169C6B', 'sci'),
    '지구과학1': ('earth1', '지구과학Ⅰ', '#169C6B', 'sci'),
    '지구과학': ('earth1', '지구과학Ⅰ', '#169C6B', 'sci'),
    '물리학Ⅰ': ('phy1', '물리학Ⅰ', '#2F6BFF', 'sci'),
    '물리학1': ('phy1', '물리학Ⅰ', '#2F6BFF', 'sci'),
    '물리학Ⅱ': ('phy2', '물리학Ⅱ', '#1D4ED8', 'sci'),
    '물리학2': ('phy2', '물리학Ⅱ', '#1D4ED8', 'sci'),
    '통합과학': ('integ', '통합과학', '#0EA5E9', 'sci'),
    '수학': ('math', '고등수학', '#E0703B', 'math'),
    '수학Ⅰ': ('math', '고등수학', '#E0703B', 'math'),
    '수학Ⅱ': ('math', '고등수학', '#E0703B', 'math'),
    '확률과 통계': ('math', '고등수학', '#E0703B', 'math'),
    '미적분': ('math', '고등수학', '#E0703B', 'math'),
    '기하': ('math', '고등수학', '#E0703B', 'math'),
}
EMATH1 = ('emath1', '공업수학1', '#6D4AFF', 'univ')
EMATH2 = ('emath2', '공업수학2', '#5B3FD6', 'univ')
CALC1 = ('calc1', '미분적분학1', '#C2410C', 'univ')
CALC2 = ('calc2', '미분적분학2', '#9A3412', 'univ')
COURSES.update({
    '공업수학1': EMATH1, '공업수학Ⅰ': EMATH1, '공업수학 1': EMATH1,
    '공업수학2': EMATH2, '공업수학Ⅱ': EMATH2, '공업수학 2': EMATH2,
    '미분적분학1': CALC1, '미분적분학Ⅰ': CALC1, '미분적분학 1': CALC1,
    '미분적분학2': CALC2, '미분적분학Ⅱ': CALC2, '미분적분학 2': CALC2,
    # 예전 이름도 같은 과목으로 받는다
    '미적분학1': CALC1, '미적분학Ⅰ': CALC1, '미적분학 1': CALC1,
    '미적분학2': CALC2, '미적분학Ⅱ': CALC2, '미적분학 2': CALC2,
})
DEFAULT_COURSE = APT

# 교과군별 기본 대상 학년 (정보.txt 에 '대상 학년' 이 없을 때)
DEFAULT_GRADES = {'apt': ['취준'], 'univ': ['한양대'], 'sci': ['고2', '고3', 'N수'], 'math': ['고1', '고2', '고3', 'N수'],
                  'kor': ['고1', '고2', '고3', 'N수'], 'eng': ['고1', '고2', '고3', 'N수'], 'soc': ['고1', '고2', '고3', 'N수']}

# 목록에 없는 과목 이름(국어·영어·화학·한국사·중등 …)은 이름으로 교과군을 짐작해 새 과목으로 만든다.
GROUP_HINTS = (
    ('kor', ('국어', '문학', '독서', '화법', '작문', '언어와 매체', '비문학')),
    ('eng', ('영어', '영문', 'English', 'TOEIC', '토익')),
    ('math', ('수학', '대수', '기하', '미적', '확률', '통계')),
    ('sci', ('물리', '화학', '생명', '지구', '과학', '생물')),
    ('soc', ('사회', '역사', '한국사', '세계사', '지리', '윤리', '경제', '정치', '법')),
)
GENERIC_COLORS = ('#C2410C', '#7C3AED', '#0F766E', '#BE185D', '#4D7C0F', '#B45309', '#1D4ED8', '#9D174D')


def generic_course(name):
    group = next((g for g, keys in GROUP_HINTS if any(k in name for k in keys)), 'univ')
    color = GENERIC_COLORS[int(hashlib.md5(name.encode()).hexdigest(), 16) % len(GENERIC_COLORS)]
    return (stable_slug(name), name, color, group)

STAGES = ('개념', '유형', '기출', 'N제', '모의고사')
CONCEPT_KINDS = ('개념', '실전개념', '공식 정리')
SECTIONS = ('문제', '선택지', '해설', '본문', '보기')
CIRCLED = '①②③④⑤⑥⑦⑧⑨'
# <보기> 항목 머리 (ㄱ. ㄴ. ㄷ. / 가. 나. / (가) (나))
BOX_HEAD = re.compile(r'^\s*(?:\(?\s*([ㄱ-ㅎ가-힣])\s*[.)]|\(\s*([ㄱ-ㅎ가-힣])\s*\))\s*(.*)$')


def read_info(path):
    """정보.txt 머리말 (- 키: 값). 표가 있으면 무시한다 (문항.txt 가 참이다)."""
    meta = {}
    if not os.path.exists(path):
        return meta
    for raw in open(path, encoding='utf-8'):
        m = re.match(r'^-\s*([^:：]+)[:：]\s*(.*)$', raw.rstrip('\n'))
        if m:
            meta[m.group(1).strip()] = m.group(2).strip()
    return meta


def parse_blocks(text):
    """문항.txt → [{'kind': '문항'|'지문'|'개념', 'no': …, 'head': {…}, 'body': {구역: 글}}]"""
    out = []
    cur = None
    sec = None
    for raw in text.splitlines():
        line = raw.rstrip()
        m = re.match(r'^#\s*(문항|지문|개념)\s+(\S.*)$', line)
        if m:
            cur = {'kind': m.group(1), 'no': m.group(2).strip(), 'head': {}, 'body': {}}
            out.append(cur)
            sec = None
            continue
        if cur is None:
            continue
        m = re.match(r'^\[\s*([^\]]+?)\s*\]\s*$', line)
        if m and m.group(1) in SECTIONS:
            sec = m.group(1)
            cur['body'].setdefault(sec, [])
            continue
        if sec is None:
            m = re.match(r'^([^:：\[]{1,12})[:：]\s*(.*)$', line)
            if m:
                cur['head'][m.group(1).strip()] = m.group(2).strip()
            continue
        cur['body'][sec].append(line)
    for b in out:
        b['body'] = {k: '\n'.join(v).strip('\n') for k, v in b['body'].items()}
    return out


def clean(text, figs, problems, where):
    """빈 줄을 문단으로 남기고 [그림: …] 을 SVG 로 바꾼다."""
    def fig(m):
        name = m.group(1).strip()
        path = figs.get(name) or figs.get(name + '.svg')
        if not path:
            problems.append(f'{where}: 그림 "{name}" 을 찾지 못했어요')
            return '[그림 없음]'
        svg = open(path, encoding='utf-8').read().strip()
        svg = re.sub(r'<\?xml.*?\?>', '', svg, flags=re.S).strip()
        return '[[svg]]' + svg + '[[/svg]]'

    s = re.sub(r'\[\s*그림\s*[:：]\s*([^\]]+)\]', fig, text)
    s = re.sub(r'\n{3,}', '\n\n', s)
    return s.strip()


def split_choices(text, problems, where):
    """선택지 글 → ['첫 선택지', …] (번호·동그라미 번호를 떼어 낸다)."""
    items, cur = [], None
    for line in text.splitlines():
        m = re.match(r'^\s*(?:\(?(\d)\)|(\d)\.|([' + CIRCLED + r']))\s*(.*)$', line)
        if m:
            if cur is not None:
                items.append('\n'.join(cur).strip())
            cur = [m.group(4)]
        elif cur is not None:
            cur.append(line)
        elif line.strip():
            problems.append(f'{where}: 선택지 번호가 없는 줄 — {line.strip()[:20]}')
    if cur is not None:
        items.append('\n'.join(cur).strip())
    return [c for c in items if c]


def split_box(text):
    """<보기> 글 → ['ㄱ. …', 'ㄴ. …'] (머리 글자는 그대로 남긴다 — 선택지가 그 글자를 가리킨다)."""
    items, cur = [], None
    for line in text.splitlines():
        if BOX_HEAD.match(line):
            if cur is not None:
                items.append('\n'.join(cur).strip())
            cur = [line.strip()]
        elif cur is not None:
            cur.append(line)
        elif line.strip():
            cur = [line.strip()]
    if cur is not None:
        items.append('\n'.join(cur).strip())
    return [c for c in items if c]


def course_of(*keys, generic=()):
    """과목 → 영역 → 정보.txt 과목 순으로 먼저 맞는 과목을 쓴다.

    이름의 앞머리만 본다 ('해양 지각' 이 인적성 '지각' 으로 가지 않게).
    목록에 하나도 없으면 generic 이름(과목 칸) 중 첫 번째로 새 과목을 만든다.
    """
    for key in keys:
        key = (key or '').strip()
        if not key:
            continue
        # 긴 이름을 먼저 본다 ('미분적분학1' 이 고등 '미적분' 으로 가지 않게)
        for name, c in sorted(COURSES.items(), key=lambda kv: -len(kv[0])):
            if key == name or key.startswith(name):
                return c
    for name in generic:
        name = (name or '').strip()
        if name:
            return generic_course(name)
    return DEFAULT_COURSE


# 흔한 한글 낱말 → 영문 (id 를 사람이 읽을 수 있게). 긴 낱말을 먼저 둔다.
WORDS = (
    ('공업수학', 'emath'), ('미분적분학', 'calc'), ('미적분학', 'calc'),
    # 영역·과목
    ('자료해석', 'data'), ('언어이해', 'lang'), ('공간지각', 'sp'), ('창의수리', 'cre'),
    ('언어추리', 'lrea'), ('수리추론', 'nrea'), ('수열추리', 'srea'), ('디지털역량', 'digi'),
    ('지구과학', 'earth'), ('통합과학', 'integ'), ('물리학', 'phy'), ('확률과 통계', 'prob'),
    ('한국사', 'hist'), ('언어', 'lang'), ('수리', 'num'), ('수열', 'seq'), ('자료', 'data'),
    ('추리', 'rea'), ('추론', 'rea'), ('도식', 'dia'), ('도형', 'fig'), ('공간', 'sp'),
    ('지각', 'per'), ('상식', 'gen'), ('인적성', 'apt'), ('이해', 'comp'),
    ('고체 지구', 'solid'), ('고체', 'solid'), ('대기와 해양', 'air'), ('대기', 'air'),
    ('해양', 'sea'), ('우주', 'space'), ('지구', 'earth'), ('수학', 'math'), ('과학', 'sci'),
    # 교재 종류·목차
    ('모의고사', 'mock'), ('유형', 'type'), ('연습', 'prac'), ('실전', 'real'), ('훈련', 'drill'),
    ('수업', 'cls'), ('숙제', 'hw'), ('기출', 'gc'), ('변형', 'var'), ('심화', 'adv'),
    ('예제', 'ex'), ('오답', 'wrong'), ('보기', 'ex'),
)


def slug(s):
    for a, b in WORDS:
        s = s.replace(a, b)
    return re.sub(r'[^0-9A-Za-z]+', '-', s).strip('-').lower() or 'book'


def stable_slug(text):
    """이름 → id 토막. 한글이 영문으로 옮겨지지 못해 떨어져 나가면 (그래서 다른 이름과
    구별되지 않으면) 짧은 지문을 붙인다. 같은 이름은 늘 같은 토막이 된다."""
    mapped = text
    for a, b in WORDS:
        mapped = mapped.replace(a, b)
    base = slug(text)
    if base == 'book' or re.search(r'[가-힣]', mapped):
        base = f'{base}-{hashlib.md5(text.encode()).hexdigest()[:4]}'
    return base


def item_slug(no, used):
    """문항번호 → id 꼬리 (겹치면 지문을 붙여 가른다)."""
    base = stable_slug(no)
    if base in used:
        base = f'{base}-{hashlib.md5(no.encode()).hexdigest()[:4]}'
    used.add(base)
    return base


def build(folder, outdir=None):
    meta = read_info(os.path.join(folder, '정보.txt'))
    srcs = sorted(f for f in os.listdir(folder) if f.startswith('문항') and f.endswith('.txt'))
    if not srcs:
        raise SystemExit(f'{folder} 안에 문항.txt 가 없어요')
    blocks = []
    for f in srcs:
        blocks += parse_blocks(open(os.path.join(folder, f), encoding='utf-8').read())

    figdir = os.path.join(folder, '그림')
    figs = {}
    if os.path.isdir(figdir):
        for f in os.listdir(figdir):
            if f.lower().endswith('.svg'):
                figs[f] = figs[os.path.splitext(f)[0]] = os.path.join(figdir, f)

    title = re.sub(r'\s*문항.*$', '', meta.get('교재명', os.path.basename(folder))).strip()
    series = meta.get('시리즈', '').split('(')[0].strip() or title.split()[0]
    num = re.search(r'(\d+)\s*회(?:차)?', title)
    # id: 시리즈 + 꼬리 (회차 번호, 없으면 교재명에서 시리즈를 뺀 나머지).
    # 교재명이 시리즈로 시작하지 않으면 교재명만 쓴다 (이름이 겹쳐 쌓이지 않게).
    if title.startswith(series):
        rest = title[len(series):].strip()
        head = stable_slug(series)
    else:
        rest = ''
        head = stable_slug(title)
    if num:
        tail = f'-{int(num.group(1)):02d}'
    else:
        tail = f'-{stable_slug(rest)}' if rest else ''
    book_id = head + tail
    book_course = course_of(meta.get('과목', ''), generic=[meta.get('과목', '')])
    grades = [g.strip() for g in re.split(r'[,，·/]', meta.get('대상 학년', '')) if g.strip()] \
        or DEFAULT_GRADES.get(book_course[3], ['고2', '고3', 'N수'])

    problems = []
    passages, items, concept_blocks = [], [], []
    seen = set()
    for b in blocks:
        if b['no'] in seen:
            problems.append(f'{b["kind"]} {b["no"]}: 번호가 겹쳐요')
        seen.add(b['no'])
        if b['kind'] == '개념':
            concept_blocks.append(b)
        else:
            (passages if b['kind'] == '지문' else items).append(b)

    used = set()
    pass_json = []
    for b in passages:
        body = clean(b['body'].get('본문', ''), figs, problems, f'지문 {b["no"]}')
        if not body:
            problems.append(f'지문 {b["no"]}: [본문] 이 비어 있어요')
        p = {'id': f'{book_id}-p-{item_slug(b["no"], used)}', 'title': b['head'].get('제목', ''), 'body': body}
        if b['head'].get('출처'):
            p['source'] = b['head']['출처']
        pass_json.append(p)
    pass_ids = {b['no']: p['id'] for b, p in zip(passages, pass_json)}

    courses, all_ids = {}, []
    for b in items:
        where = f'문항 {b["no"]}'
        head, body = b['head'], b['body']
        area = head.get('영역', '')
        stem = clean(body.get('문제', ''), figs, problems, where)
        if not stem:
            problems.append(f'{where}: [문제] 가 비어 있어요')
        answer = head.get('정답', '').strip()
        if not answer:
            problems.append(f'{where}: 정답이 비어 있어요 (앱 채점에 꼭 필요해요)')
        kind = head.get('형식', '').strip()
        choices = split_choices(body.get('선택지', ''), problems, where) if body.get('선택지') else []
        box = split_box(clean(body.get('보기', ''), figs, problems, where)) if body.get('보기') else []
        is_choice = kind.startswith('객관') or (not kind and len(choices) >= 2)
        if is_choice and len(choices) < 2:
            problems.append(f'{where}: 객관식인데 선택지가 {len(choices)}개예요')
        if is_choice and answer and not re.fullmatch(r'[1-9]', answer):
            problems.append(f'{where}: 객관식 정답은 번호(1~5)로 적어 주세요 — 지금 "{answer}"')
        if is_choice and answer.isdigit() and choices and int(answer) > len(choices):
            problems.append(f'{where}: 정답 {answer}번인데 선택지는 {len(choices)}개예요')
        try:
            diff = max(1, min(5, int(re.sub(r'[^0-9]', '', head.get('난이도', '3')) or 3)))
        except ValueError:
            diff = 3
        cid, cname, color, group = course_of(head.get('과목', ''), area, meta.get('과목', ''),
                                            generic=[head.get('과목', ''), meta.get('과목', '')])
        course = courses.setdefault(cid, {
            'subject': cname, 'subjectId': cid, 'color': color, 'group': group,
            'level': 'mid' if grades and all(g.startswith('중') for g in grades) else 'high',
            'grades': grades, 'track': meta.get('시험', '').strip() or ('공통' if group == 'apt' else '수능'),
            'passages': [], 'problems': []})
        p = {
            'id': f'{book_id}-{item_slug(b["no"], used)}',
            'unit': area or cname,
            'topic': head.get('유형', ''),
            'section': head.get('목차', '') or area or '',
            'difficulty': diff,
            'type': 'choice' if is_choice else 'short',
            'stem': stem,
            'answer': answer,
            'solution': clean(body.get('해설', ''), figs, problems, where),
            'tags': [title],
        }
        if choices:
            p['choices'] = choices
        if box:
            p['boxItems'] = box
        if head.get('지문'):
            pid = pass_ids.get(head['지문'])
            if pid:
                p['passageId'] = pid
            else:
                problems.append(f'{where}: 지문 "{head["지문"]}" 을 찾지 못했어요')
        for key, field in (('머리표', 'label'), ('출처', 'source'), ('단위', 'answerUnit'), ('힌트', 'hint')):
            if head.get(key):
                p[field] = head[key]
        if head.get('배점'):
            try:
                p['points'] = int(re.sub(r'[^0-9]', '', head['배점']))
            except ValueError:
                pass
        course['problems'].append(p)
        all_ids.append(p['id'])

    # 개념 페이지 (#개념) — 과목은 문항과 같은 방식으로 고른다
    concept_ids = []
    for b in concept_blocks:
        where = f'개념 {b["no"]}'
        head = b['head']
        text = clean(b['body'].get('본문', ''), figs, problems, where)
        if not text:
            problems.append(f'{where}: [본문] 이 비어 있어요')
        kind = head.get('종류', '개념').strip() or '개념'
        if kind not in CONCEPT_KINDS:
            problems.append(f'{where}: 종류는 {" · ".join(CONCEPT_KINDS)} 중에서 골라 주세요 — 지금 "{kind}"')
            kind = '개념'
        area = head.get('영역', '')
        cid, cname, color, group = course_of(head.get('과목', ''), area, meta.get('과목', ''),
                                             generic=[head.get('과목', ''), meta.get('과목', '')])
        course = courses.setdefault(cid, {
            'subject': cname, 'subjectId': cid, 'color': color, 'group': group,
            'level': 'mid' if grades and all(g.startswith('중') for g in grades) else 'high',
            'grades': grades, 'track': meta.get('시험', '').strip() or ('공통' if group == 'apt' else '수능'),
            'passages': [], 'problems': []})
        c = {
            'id': f'{book_id}-c-{item_slug(b["no"], used)}',
            'title': head.get('제목', '').strip(),
            'kind': kind,
            'unit': area or cname,
            'topic': head.get('유형', ''),
            'section': head.get('목차', '') or '',
            'body': text,
        }
        if not c['title']:
            problems.append(f'{where}: 제목이 비어 있어요')
        links = [x.strip() for x in re.split(r'[,，/]', head.get('연결', '')) if x.strip()]
        if links:
            c['links'] = links
        if head.get('출처'):
            c['source'] = head['출처']
        course.setdefault('concepts', []).append(c)
        concept_ids.append(c['id'])

    for c in courses.values():
        c['units'] = list(dict.fromkeys(p['unit'] for p in c['problems']))
    if courses and pass_json:
        main_course = max(courses.values(), key=lambda c: len(c['problems']))
        main_course['passages'] = pass_json
    stage = meta.get('커리큘럼 단계', '모의고사').strip()
    main = max(courses.values(), key=lambda c: len(c['problems']))['subjectId'] if courses else 'apt'
    wb = {
        'id': book_id, 'title': title, 'course': main,
        'stage': stage if stage in STAGES else '모의고사',
        'scope': '·'.join(x.strip() for x in re.split(r'[,，/]', meta.get('범위', '')) if x.strip()),
        'level': meta.get('수준', '기본').strip() or '기본',
        'publisher': meta.get('만든 곳', ''), 'series': series,
        'desc': ' — '.join(x for x in (meta.get('시리즈', ''), meta.get('범위', '').replace(' / ', ' · ')) if x),
        'problems': all_ids,
    }
    if concept_ids:
        wb['concepts'] = concept_ids
    bundle = {'format': 'pulinote-bundle', 'version': 1, 'id': book_id, 'title': title,
              'courses': list(courses.values()), 'workbooks': [wb]}
    report = {'book': title, 'id': book_id, 'problems': len(all_ids), 'passages': len(pass_json),
              'concepts': len(concept_ids),
              'choice': sum(1 for c in courses.values() for p in c['problems'] if p['type'] == 'choice'),
              'box': sum(1 for c in courses.values() for p in c['problems'] if p.get('boxItems')),
              'figures': len(set(figs.values())), 'issues': problems}
    want = meta.get('문항 수', '').strip()
    if want.isdigit() and int(want) != len(all_ids):
        report['issues'].append(f'정보.txt 는 {want}문항인데 문항.txt 에는 {len(all_ids)}개예요')
    if outdir:
        os.makedirs(outdir, exist_ok=True)
        raw = json.dumps(bundle, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        path = os.path.join(outdir, f'{book_id}.pulinote')
        with open(path, 'wb') as f:
            f.write(gzip.compress(raw, 9))
        with open(os.path.join(outdir, f'{book_id}.json'), 'w', encoding='utf-8') as f:
            json.dump(bundle, f, ensure_ascii=False, indent=1)
        report['file'] = path
        report['bytes'] = os.path.getsize(path)
    return report


SELFTEST_INFO = """- 교재명: 보기 교재 01회차
- 시리즈: 보기 교재
- 과목: 인적성
- 커리큘럼 단계: 모의고사
- 범위: 언어이해 / 자료해석
- 대상 학년: 취준
- 문항 수: 3
"""

SELFTEST_ITEMS = """#지문 P1
제목: 보기 지문

[본문]
첫 문단.

**굵은** 글이 있는 둘째 문단.

#문항 언어-01
영역: 언어이해
유형: 주제 찾기
형식: 객관식
정답: 2
난이도: 3
지문: P1
머리표: 유형 연습

[문제]
위 글의 주제로 알맞은 것은?

[선택지]
1. 첫째
2. 둘째
3. 셋째
4. 넷째
5. 다섯째

[해설]
둘째 문단에 있다.

#문항 자료-01
영역: 자료해석
형식: 객관식
정답: 1
배점: 2

[문제]
표에 대한 설명으로 옳은 것은?

| 구분 | 갑 | 을 |
|---|---|---|
| 값 | 30 | 45 |

[선택지]
1) 을이 크다
2) 갑이 크다

[해설]
$45 > 30$

#문항 추리-01
영역: 추리
형식: 단답형
정답: 7
단위: 개

[문제]
[그림: 보기.svg] 빈칸에 들어갈 수는?

[해설]
앞의 두 수를 더한다.
"""

SELFTEST_SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"></svg>'

SELFTEST_SCI_INFO = """- 교재명: 보기 과학 01회차
- 시리즈: 보기 과학
- 과목: 지구과학Ⅰ
- 커리큘럼 단계: 유형
- 범위: 고체 지구 / 대기와 해양
- 문항 수: 2
"""

SELFTEST_SCI_ITEMS = """#개념 C1
제목: 판 구조론 핵심
종류: 실전개념
영역: 고체 지구
유형: 판 구조론
목차: 수업문항
연결: 판 구조론, 맨틀 대류

[본문]
판의 경계는 세 가지이다.

$$v = f\\lambda$$

#문항 고체-01
영역: 고체 지구
유형: 판 구조론
형식: 객관식
정답: 3
난이도: 2
힌트: 순서대로 발전하였다.

[문제]
옳은 것만을 <보기>에서 있는 대로 고른 것은?

[보기]
ㄱ. 첫째 것은 옳다.
ㄴ. 둘째 것은 틀리다.
ㄷ. 셋째 것은 옳다.

[선택지]
1. ㄱ
2. ㄴ
3. ㄱ, ㄷ
4. ㄴ, ㄷ
5. ㄱ, ㄴ, ㄷ

[해설]
ㄴ 만 틀리다.

#문항 해양 지각-01
영역: 대기와 해양
형식: 단답형
정답: 35
단위: psu

[문제]
표층 염분을 구하시오.

[해설]
표에서 읽는다.
"""


def selftest():
    """스스로 만든 보기 교재로 변환기가 제대로 도는지 본다 (CI)."""
    import tempfile
    fails = []

    def eq(got, want, what):
        if got != want:
            fails.append(f'{what}: {got!r} ≠ {want!r}')

    with tempfile.TemporaryDirectory() as tmp:
        folder = os.path.join(tmp, '보기 교재 01회차')
        os.makedirs(os.path.join(folder, '그림'))
        for name, body in (('정보.txt', SELFTEST_INFO), ('문항.txt', SELFTEST_ITEMS),
                           (os.path.join('그림', '보기.svg'), SELFTEST_SVG)):
            with open(os.path.join(folder, name), 'w', encoding='utf-8') as f:
                f.write(body)
        out = os.path.join(tmp, 'out')
        rep = build(folder, out)
        eq(rep['issues'], [], '흠 없이 변환')
        eq(rep['problems'], 3, '문항 수')
        eq(rep['passages'], 1, '지문 수')
        eq(rep['choice'], 2, '객관식 수')
        with gzip.open(rep['file']) as f:
            bundle = json.loads(f.read().decode('utf-8'))
        eq(bundle['format'], 'pulinote-bundle', '묶음 형식')
        c = bundle['courses'][0]
        eq(c['group'], 'apt', '교과군')
        eq(c['grades'], ['취준'], '대상 학년')
        eq(c['units'], ['언어이해', '자료해석', '추리'], '영역 목록')
        eq([p['id'] for p in c['passages']], [rep['id'] + '-p-p1'], '지문 id')
        ps = {p['id'].rsplit('-', 2)[-2] + '-' + p['id'].rsplit('-', 1)[-1]: p for p in c['problems']}
        eq(sorted(ps), ['data-01', 'lang-01', 'rea-01'], '문항 id')
        lang = ps['lang-01']
        eq(lang['type'], 'choice', '객관식')
        eq(lang['answer'], '2', '정답')
        eq(len(lang['choices']), 5, '선택지 5개')
        eq(lang['choices'][1], '둘째', '선택지 글 (번호는 떼어 낸다)')
        eq(lang['passageId'], rep['id'] + '-p-p1', '지문 연결')
        eq(lang['label'], '유형 연습', '머리표')
        eq(lang['section'], '언어이해', '목차')
        data = ps['data-01']
        eq(data['points'], 2, '배점')
        assert '| 구분 | 갑 | 을 |' in data['stem'], '표가 그대로 남아야 한다'
        rea = ps['rea-01']
        eq(rea['type'], 'short', '단답형')
        eq(rea['answerUnit'], '개', '단위')
        assert rea['stem'].startswith('[[svg]]<svg'), '그림이 들어가야 한다'
        eq(bundle['workbooks'][0]['stage'], '모의고사', '커리큘럼 단계')
        eq(bundle['workbooks'][0]['scope'], '언어이해·자료해석', '범위 칩')

        # 흠을 일부러 넣어 보고 잡아내는지 본다
        with open(os.path.join(folder, '문항.txt'), 'w', encoding='utf-8') as f:
            f.write('#문항 A-01\n영역: 추리\n형식: 객관식\n정답: 9\n지문: 없음\n[문제]\n가\n[선택지]\n1. 가\n')
        bad = build(folder)
        want = ['객관식인데 선택지가 1개', '정답 9번인데 선택지는 1개', '지문 "없음" 을 찾지 못했',
                '3문항인데 문항.txt 에는 1개']
        for w in want:
            if not any(w in i for i in bad['issues']):
                fails.append(f'흠을 못 잡았어요: {w} — {bad["issues"]}')
    # 과학 교재 (보기 ㄱㄴㄷ 합답형 · 교과 과목 고르기)
    with tempfile.TemporaryDirectory() as tmp:
        folder = os.path.join(tmp, '보기 과학 01회차')
        os.makedirs(folder)
        for name, body in (('정보.txt', SELFTEST_SCI_INFO), ('문항.txt', SELFTEST_SCI_ITEMS)):
            with open(os.path.join(folder, name), 'w', encoding='utf-8') as f:
                f.write(body)
        rep = build(folder, os.path.join(tmp, 'out'))
        eq(rep['issues'], [], '과학 교재도 흠 없이 변환')
        eq(rep['box'], 1, '보기 합답형 수')
        eq(rep['concepts'], 1, '개념 수')
        with gzip.open(rep['file']) as f:
            sci_bundle = json.loads(f.read().decode('utf-8'))
        c = sci_bundle['courses'][0]
        wbs0 = sci_bundle['workbooks'][0]
        eq(c['subjectId'], 'earth1', '앱에 있는 지구과학Ⅰ 과목으로 들어간다')
        eq(c['group'], 'sci', '교과군')
        eq(c['grades'], ['고2', '고3', 'N수'], '대상 학년 (안 적으면 과학 기본값)')
        eq(c['track'], '수능', '시험')
        eq(c['units'], ['고체 지구', '대기와 해양'], '단원 순서')
        ps = {p['id']: p for p in c['problems']}
        solid = ps[rep['id'] + '-solid-01']
        eq(len(solid['boxItems']), 3, '보기 세 줄')
        eq(solid['boxItems'][1], 'ㄴ. 둘째 것은 틀리다.', '보기 머리 글자는 남긴다')
        eq(len(solid['choices']), 5, '선택지 5개')
        eq(solid['choices'][2], 'ㄱ, ㄷ', '합답형 선택지')
        eq(solid['answer'], '3', '정답은 번호')
        eq(solid['hint'], '순서대로 발전하였다.', '힌트')
        cn = c['concepts'][0]
        eq((cn['kind'], cn['title'], cn['section'], cn['links']), ('실전개념', '판 구조론 핵심', '수업문항', ['판 구조론', '맨틀 대류']), '개념 페이지')
        assert '$$v = f' in cn['body'], '개념 본문 수식 줄'
        eq(wbs0['concepts'], [cn['id']], '교재에 개념 id 목록')
        assert '<보기>' in solid['stem'], '문제 글은 그대로'
        # 한글이 떨어져 나가는 번호도 서로 갈린다 ('해양 지각-01' → sea-per-01 은 안 된다)
        sea = [i for i in ps if i.endswith('-01') and 'solid' not in i]
        eq(len(sea), 1, '둘째 문항 id')

    # 목록에 없는 과목 (국어·중등 수학 …) → 이름으로 새 과목을 만든다
    with tempfile.TemporaryDirectory() as tmp:
        folder = os.path.join(tmp, '보기 국어 01회차')
        os.makedirs(folder)
        with open(os.path.join(folder, '정보.txt'), 'w', encoding='utf-8') as f:
            f.write('- 교재명: 보기 국어 01회차\n- 과목: 국어\n- 대상 학년: 중3\n')
        with open(os.path.join(folder, '문항.txt'), 'w', encoding='utf-8') as f:
            f.write('#문항 1\n영역: 문학\n형식: 단답형\n정답: 3\n[문제]\n가\n[해설]\n나\n')
        rep = build(folder, os.path.join(tmp, 'out'))
        eq(rep['issues'], [], '국어 교재도 흠 없이 변환')
        with gzip.open(rep['file']) as f:
            c = json.loads(f.read().decode('utf-8'))['courses'][0]
        eq((c['subject'], c['group'], c['level'], c['grades']), ('국어', 'kor', 'mid', ['중3']), '새 과목 (교과군·중등)')

    print('\n'.join(fails) if fails else 'text_book selftest ok (인적성 3문항 · 지문 1 / 과학 2문항 · 보기 1)')
    return 1 if fails else 0


if __name__ == '__main__':
    a = sys.argv[1:]
    if a and a[0] == 'selftest':
        sys.exit(selftest())
    if a and a[0] == 'check':
        print(json.dumps(build(a[1]), ensure_ascii=False, indent=1))
    elif len(a) >= 2:
        print(json.dumps(build(a[0], a[1]), ensure_ascii=False, indent=1))
    else:
        print(__doc__)
        sys.exit(2)
