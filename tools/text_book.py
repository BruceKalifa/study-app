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

# 영역 이름 → 앱 과목(course): (id, 이름, 색, 교과군)
COURSES = {
    '인적성': ('apt', '인적성', '#0E7C86', 'apt'),
    '언어': ('apt', '인적성', '#0E7C86', 'apt'),
    '수리': ('apt', '인적성', '#0E7C86', 'apt'),
    '자료해석': ('apt', '인적성', '#0E7C86', 'apt'),
    '추리': ('apt', '인적성', '#0E7C86', 'apt'),
    '도식': ('apt', '인적성', '#0E7C86', 'apt'),
    '공간': ('apt', '인적성', '#0E7C86', 'apt'),
    '지각': ('apt', '인적성', '#0E7C86', 'apt'),
    '상식': ('apt', '인적성', '#0E7C86', 'apt'),
    'NCS': ('ncs', 'NCS', '#0E7C86', 'apt'),
}
DEFAULT_COURSE = ('apt', '인적성', '#0E7C86', 'apt')

STAGES = ('개념', '유형', '기출', 'N제', '모의고사')
SECTIONS = ('문제', '선택지', '해설', '본문', '보기')
CIRCLED = '①②③④⑤⑥⑦⑧⑨'


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
    """문항.txt → [{'kind': '문항'|'지문', 'no': …, 'head': {…}, 'body': {구역: 글}}]"""
    out = []
    cur = None
    sec = None
    for raw in text.splitlines():
        line = raw.rstrip()
        m = re.match(r'^#\s*(문항|지문)\s+(\S.*)$', line)
        if m:
            cur = {'kind': m.group(1), 'no': m.group(2).strip(), 'head': {}, 'body': {}}
            out.append(cur)
            sec = None
            continue
        if cur is None:
            continue
        m = re.match(r'^\[\s*([^\]]+?)\s*\]\s*$', line)
        if m and m.group(1) in SECTIONS:
            sec = '문제' if m.group(1) == '보기' else m.group(1)
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


def course_of(area, fallback):
    for name, c in COURSES.items():
        if area.startswith(name) or name in area:
            return c
    for name, c in COURSES.items():
        if fallback.startswith(name):
            return c
    return DEFAULT_COURSE


def slug(s):
    for a, b in (('자료해석', 'data'), ('언어이해', 'lang'), ('언어', 'lang'), ('수리', 'num'),
                 ('자료', 'data'), ('추리', 'rea'), ('도식', 'dia'), ('도형', 'fig'), ('공간', 'sp'),
                 ('지각', 'per'), ('상식', 'gen'), ('인적성', 'apt'), ('모의고사', 'mock')):
        s = s.replace(a, b)
    return re.sub(r'[^0-9A-Za-z]+', '-', s).strip('-').lower() or 'book'


def item_slug(no, used):
    """문항번호 → id 꼬리. 한글이 떨어져 나가 겹치면 짧은 지문을 붙여 가른다."""
    base = slug(no)
    if base == 'book' or base in used:
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
    num = re.search(r'(\d+)\s*회차', title)
    head = slug(series)
    if head == 'book':  # 한글만 있는 이름 — 교재마다 다른 꼬리를 붙여 겹치지 않게
        head = 'book-' + hashlib.md5(series.encode()).hexdigest()[:4]
    book_id = head + (f'-{int(num.group(1)):02d}' if num else '')
    grades = [g.strip() for g in re.split(r'[,，·/]', meta.get('대상 학년', '취준')) if g.strip()]

    problems = []
    passages, items = [], []
    seen = set()
    for b in blocks:
        if b['no'] in seen:
            problems.append(f'{b["kind"]} {b["no"]}: 번호가 겹쳐요')
        seen.add(b['no'])
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
        cid, cname, color, group = course_of(area, meta.get('과목', ''))
        course = courses.setdefault(cid, {
            'subject': cname, 'subjectId': cid, 'color': color, 'group': group, 'level': 'high',
            'grades': grades, 'track': meta.get('시험', '').strip() or '공통',
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
    bundle = {'format': 'pulinote-bundle', 'version': 1, 'id': book_id, 'title': title,
              'courses': list(courses.values()), 'workbooks': [wb]}
    report = {'book': title, 'id': book_id, 'problems': len(all_ids), 'passages': len(pass_json),
              'choice': sum(1 for c in courses.values() for p in c['problems'] if p['type'] == 'choice'),
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
        eq([p['id'] for p in c['passages']], ['book-316d-01-p-p1'], '지문 id')
        ps = {p['id'].rsplit('-', 2)[-2] + '-' + p['id'].rsplit('-', 1)[-1]: p for p in c['problems']}
        eq(sorted(ps), ['data-01', 'lang-01', 'rea-01'], '문항 id')
        lang = ps['lang-01']
        eq(lang['type'], 'choice', '객관식')
        eq(lang['answer'], '2', '정답')
        eq(len(lang['choices']), 5, '선택지 5개')
        eq(lang['choices'][1], '둘째', '선택지 글 (번호는 떼어 낸다)')
        eq(lang['passageId'], 'book-316d-01-p-p1', '지문 연결')
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
    print('\n'.join(fails) if fails else f'text_book selftest ok ({3} 문항 · 1 지문)')
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
