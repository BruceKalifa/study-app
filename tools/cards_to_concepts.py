#!/usr/bin/env python3
"""'개념 읽기 카드'(정답이 "다 읽었습니다" 인 가짜 객관식 문제)로 만든 교재를 진짜 개념 페이지(concepts)로 바꾼다.

사용:  python3 tools/cards_to_concepts.py 입력.pulinote 출력.pulinote

- label 이 '개념' 이고 보기가 "다 읽었습니다 / 다시 읽겠습니다" 인 문항 → 개념 페이지 (본문 = 문제 글에서 첫 줄 제목을 뺀 것)
- 개념의 목차(section) = 그 단원 이름, 문제의 목차(section) = '' → 교재가 단원별로 묶이고 개념이 각 단원 맨 앞에 나온다
- 개념의 연결(links) = 같은 단원 문제들의 유형 → 개념 페이지의 "이 개념 문제 풀기" 가 그 단원 문제를 연다
"""
import gzip, json, re, sys

KINDS = ('개념', '실전개념', '공식 정리')
HEAD = re.compile(r'^\s*\*\*(.+?)\*\*\s*\n+', re.S)


def is_card(p):
    ch = p.get('choices') or []
    return p.get('label') == '개념' and p.get('type') == 'choice' and any('읽' in str(c) for c in ch)


def convert_bundle(b):
    n = 0
    for c in b['courses']:
        cards = [p for p in c['problems'] if is_card(p)]
        if not cards:
            continue
        rest = [p for p in c['problems'] if not is_card(p)]
        topics = {}
        for p in rest:
            topics.setdefault(p['unit'], [])
            if p.get('topic') and p['topic'] not in topics[p['unit']]:
                topics[p['unit']].append(p['topic'])
            p['section'] = ''
        concepts = c.setdefault('concepts', [])
        for p in cards:
            stem = p['stem']
            m = HEAD.match(stem)
            kind, title = '개념', p.get('topic', '')
            if m:
                parts = [x.strip() for x in m.group(1).split(' · ', 1)]
                if len(parts) == 2:
                    kind = parts[0] if parts[0] in KINDS else '개념'
                    title = parts[1]
                stem = stem[m.end():]
            cn = {'id': p['id'], 'title': title, 'kind': kind, 'unit': p['unit'], 'topic': p.get('topic', ''),
                  'section': p['unit'], 'body': stem.strip()}
            if topics.get(p['unit']):
                cn['links'] = list(topics[p['unit']])
            concepts.append(cn)
            n += 1
        ids = {p['id'] for p in cards}
        c['problems'] = rest
        c['units'] = list(dict.fromkeys(p['unit'] for p in rest))
        for w in b['workbooks']:
            if w['course'] == c['subjectId']:
                w['problems'] = [i for i in w['problems'] if i not in ids]
                w['concepts'] = [x['id'] for x in concepts]
    return n


def main(src, dst):
    o = json.loads(gzip.decompress(open(src, 'rb').read()))
    books = o['books'] if o.get('format') == 'pulinote-collection' else [o]
    n = sum(convert_bundle(b) for b in books)
    open(dst, 'wb').write(gzip.compress(json.dumps(o, ensure_ascii=False, separators=(',', ':')).encode()))
    print(f'개념 페이지 {n}개로 바꿨어요 → {dst}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
