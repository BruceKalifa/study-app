# flutter_math_fork (풀이노트 patched copy)

Copy of [flutter_math_fork](https://github.com/simpleclub-extended/flutter_math_fork) 0.7.4
(commit 75a6f61, Apache-2.0, see LICENSE) with two small changes, used through `dependency_overrides`:

- `lib/src/render/symbols/make_symbol.dart`: glyphs fall back to `NotoSerifKR` / `NanumMyeongjo`
  so Korean inside `\text{…}` renders in the body serif instead of the system font.
- `lib/src/ast/tex_break.dart`: a part that ends with a relation or binary operator gets an empty
  ord appended, so the space after the operator survives line breaking (`a = 3`, `p + q`).
