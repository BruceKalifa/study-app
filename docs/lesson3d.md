# 3D 모션그래픽 수업 만들기 (Solvit3D)

솔빗 앱의 개념 페이지에서 **돌려 보고, 단계별로 넘기고, 재생되는 3D 수업**을 열 수 있어요.
수업은 선생님이 외부에서(예: AI 도구와 함께) **HTML 파일 하나**로 만들고, 교재 폴더에 넣어 변환·업로드합니다.
앱은 3D 엔진(three.js)과 조작 화면(단계 이동·재생·슬라이더·자막)을 이미 갖고 있어서, 수업 파일에는 **장면 내용만** 적으면 돼요.

## 한눈에

```
교재 폴더/
├─ 정보.txt
├─ 문항.txt          ← #개념 블록에  3D수업: 이중적분.html  한 줄
└─ 3D수업/
   └─ 이중적분.html  ← Solvit3D.lesson({ … }) 이 들어 있는 HTML 파일
```

`문항.txt` 예:

```
#개념 L1
제목: 이중적분과 부피
종류: 개념
영역: 다변수 적분
목차: 3D 수업
연결: 이중적분

[본문]
(선택) 3D 수업 아래쪽에는 글이 따로 보이지 않아요. 본문은 비워도 돼요.
```

머리에 `3D수업: 파일이름.html` 을 적으면 그 개념은 **필기 종이 대신 3D 수업**으로 열려요 (목차에는 `3D` 표시가 붙어요).
파일은 교재 폴더 또는 그 안의 `3D수업` 폴더에 두세요.

변환·검사:

```
python3 tools/text_book.py check <교재 폴더>          # 흠만 알려 줌 (파일 없음 · 인터넷 주소 · 크기 …)
python3 tools/text_book.py <교재 폴더> <출력 폴더>     # .pulinote 만들기
python3 tools/lesson3d_check.py 이중적분.html          # (선택) 브라우저로 실제 그려 보고 단계별 그림 저장
```

## 수업 파일 규칙

1. **HTML 파일 하나**. 안에 `<script>Solvit3D.lesson({ … })</script>` 가 있어야 해요.
2. **외부 파일·라이브러리·인터넷 주소 금지** (CDN, 이미지 URL, 웹폰트 …). 앱이 막아 둬서 어차피 안 불러져요.
   글자는 `s.label('x² + y²', 위치)` 로 3D 안에 쓰거나 자막(`caption`)에 적습니다. 수식은 **유니코드 문자**로 (x² ∂f/∂x ∫ ∑ √ π θ ≤ ≥ → ⃗).
3. `fetch`, `XMLHttpRequest`, `localStorage`, `window.open`, `<iframe>`, `<link>`, `import` 쓰지 않기.
4. 크기는 **400KB 이하**. 큰 숫자표를 넣지 말고 수식으로 그리세요.
5. 개발자 미리보기용으로 `<script src="solvit3d-runtime.js"></script>` 한 줄을 `<head>` 에 둬도 돼요 (앱이 자기 것으로 바꿔 끼워요).
6. **좌표는 z가 위쪽**(수학 교과서와 같은 오른손 좌표계): x 오른쪽, y 안쪽, z 위.

## 수업 구조

```js
Solvit3D.lesson({
  title: '수업 제목',                    // 위쪽에 표시
  background: '#F7F5EF',                 // (선택) 배경색
  camera: { position: [7, -9, 6], target: [0, 0, 1] },   // 처음 시점

  setup(s) {                             // (선택) 모든 단계에 남는 물체 (축·격자 …)
    s.axes({ size: 3 });
    s.grid({ size: 6 });
  },

  steps: [                               // 단계들 — 아래 "다음" 버튼/슬라이더로 넘김
    {
      title: '1. 단계 제목',
      caption: '자막 글. 줄바꿈은 \n',    // 화면 아래 카드
      camera: { position: [...], target: [...] },   // (선택) 이 단계에서 카메라가 부드럽게 이동
      build(s) { /* 이 단계의 물체를 만든다 */ },
      animate(s, p, t) { /* (선택) 움직임 — p: 0~1 진행도, t: 초 */ },
      duration: 6,                       // (선택) animate 길이(초), 기본 5
      loop: false,                       // (선택) true 면 계속 반복
      autoplay: true,                    // (선택) false 면 재생을 눌러야 움직임
      startAt: 0.5,                      // (선택) 처음부터 이 진행도에서 멈춰 시작
    },
  ],
});
```

- 단계가 바뀔 때마다 앞 단계 물체는 지워지고 `build` 가 다시 불려요. `setup` 물체만 남아요.
- `build`/`animate` 안에서 `this` 는 그 단계 객체예요. **단계 사이에 값을 넘기려면 `s.v`** (단계마다 새로 비워지는 보관함)를 쓰세요:
  `build` 에서 `s.v.ball = s.sphere(...)`, `animate` 에서 `s.v.ball.position.set(...)`.
- `animate` 가 있으면 화면 아래에 재생·일시정지가 생기고, 슬라이더를 끌면 `p` 가 바뀌어 **그 순간의 장면**이 그려져요.
  그래서 `animate` 는 **p 만으로 장면이 결정되게** 쓰세요 (이전 프레임에 기대지 않기).
- 자막을 움직임에 맞춰 바꾸고 싶으면 `animate` 안에서 `s.setCaption('제목', '글')`.

## 도우미 (`s.…`)

색은 `'#4f7cff'` 같은 CSS 색 문자열. 좌표는 `[x, y, z]`.

| 호출 | 설명 |
|---|---|
| `s.axes({size, names, negative, ticks})` | x·y·z 축 화살표와 눈금 |
| `s.grid({size, z})` | xy 평면 격자 |
| `s.point(pos, {r, color, label})` | 점 (라벨 선택) |
| `s.sphere(pos, r, {color, opacity, wire})` | 구 |
| `s.box(center, [dx,dy,dz], {color, opacity})` | 직육면체 (기둥·막대) |
| `s.cylinder(a, b, r, {color, opacity, open})` | a→b 원기둥 |
| `s.cone(apex, base, r, {color, opacity})` | 원뿔 (꼭짓점, 밑면 중심) |
| `s.arrow(from, to, {color, width, label})` | 벡터 화살표. 반환값 `.set(from, to)` 로 움직임 |
| `s.line([p0, p1, …], {color, opacity})` | 꺾은선 |
| `s.curve(t => [x,y,z], {t:[t0,t1], n, radius, color})` | 매개변수 곡선. `.progress(p)` 처음 p만 그리기, `.at(p)` 점, `.tangentAt(p)` 접선 |
| `s.surface((x,y) => z, {x:[a,b], y:[c,d], n, color, heightColor:[낮은색,높은색], opacity, wire})` | 곡면 z=f(x,y) |
| `s.paramSurface((u,v) => [x,y,z], {u:[..], v:[..], n, color, opacity})` | 매개변수 곡면 (구·토러스·회전체) |
| `s.plane(point, normal, {size, color, opacity})` | 평면 (점과 법선) |
| `s.vectorField((x,y,z) => [vx,vy,vz], {x,y,z,n,scale,color})` | 벡터장 |
| `s.label('텍스트', pos, {color, size, bg})` | 항상 화면을 향하는 글자 (여러 줄은 `\n`) |
| `s.light(pos, intensity)` | 점광원 추가 (기본 조명은 이미 있어요) |
| `s.camTo({position, target}, 초)` | 카메라를 부드럽게 옮김 |
| `s.THREE`, `s.scene`, `s.add(obj)` | three.js(r147)를 직접 쓰고 싶을 때 (물체는 `s.add(...)` 로 넣어야 단계가 바뀔 때 지워져요) |
| `s.lerp`, `s.clamp`, `s.ease(t)`, `s.TAU` | 계산 도우미 |

학생 조작: 한 손가락 드래그 = 회전, 두 손가락 = 확대·이동, 위쪽 "자동회전", "시점 처음으로", 아래쪽 이전·재생·슬라이더·다음.

## 만들 때 요령

- 한 단계에는 **한 가지 생각**만. 보통 4~8단계.
- 단계 첫 장면은 가만히 보여 주고(`animate` 없음), 설명이 필요한 부분만 `animate` 로 움직이세요.
- 자막은 짧게(2~3줄). 수식은 유니코드로: `∬ f(x,y) dA = ∫₀¹ ∫₀¹ (x+y) dy dx`.
- 색: 대상은 파랑 `#4f7cff`, 강조는 주황 `#E0703B`, 영역은 초록 `#2F9E6E`, 경고·정답 표시는 빨강 `#B42318`.
- 화면 안 큰 물체가 카메라를 가리지 않게 `camera.position` 은 물체에서 6~12 정도 떨어뜨리세요.
- 오류가 나면 수업 화면 위쪽에 빨간 줄로 메시지가 보여요 (그 단계만 비고 나머지는 계속 돼요).

## 예시

`docs/lesson3d/3D수업_샘플_이중적분.html` — 곡면 → 영역 → 기둥으로 쪼개기(재생) → 극한 → 부피 확인의 5단계 수업.
`docs/lesson3d/3D수업_양식.html` — 빈 양식. 복사해서 시작하세요.
