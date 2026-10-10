# PDF 교재를 앱에 (고화질 이미지 개념 교재)

TeX 원문이 있으면 `tools/tex_book.py` 로 글·수식·그림을 다시 조판하고(선명, 용량 작음),
**PDF 밖에 없는 자료**는 `tools/pdf_book.py` 로 쪽마다 고화질 이미지로 싣는다.

```
python3 tools/pdf_book.py 교재.pdf 출력.pulinote --title "교재 이름" --course 물리학1 --pages 3-60
python3 tools/pdf_book.py 교재.pdf 출력.pulinote --title "…" --course 물리학1 --toc 목차.txt
```

- 앱에서는 쪽 이미지가 종이 너비에 맞게 펼쳐지고, 그 위에 펜으로 필기한다 (개념 페이지와 같다. 필기는 개념마다 자동 저장).
- 가로 2000px WebP (쪽당 100~250KB). 태블릿에서 두 배로 확대해도 선명하다. `--width`·`--quality` 로 조절.
- 목차 파일: 한 줄에 `제목 | 시작쪽-끝쪽 | 단원(선택) | 종류(선택)`. 없으면 `--per N` 쪽씩 묶는다.
- 풀이·정답이 인쇄돼 있어 먼저 보이면 안 되는 곳은 `--mask 쪽:x0,y0,x1,y1` (쪽 크기에 대한 0~1 비율)로 흰색으로 가린다.
- 서버는 파일 하나 40MB 까지 받는다. 크면 `--pages` 로 나눠 여러 교재로 만든다.
- 데이터: 개념(`concepts[]`)의 `images` 에 `data:image/webp;base64,…` 목록. `images` 가 있으면 본문 대신 그림을 보여 주고 `body` 는 그림 아래에 덧붙는다.
- 직접 풀 예시 문제는 이미지 안에 두지 않는다 — 진짜 문제로 따로 올리고 개념의 `links` 로 잇는다.
