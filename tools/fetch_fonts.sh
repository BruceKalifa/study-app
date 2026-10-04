#!/usr/bin/env bash
# Pretendard (UI) and 나눔명조 (exam paper), both SIL Open Font License 1.1.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p assets/fonts
if [ ! -f assets/fonts/Pretendard-Regular.otf ]; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/p.zip" https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip
  unzip -q "$tmp/p.zip" -d "$tmp/p"
  for w in Regular Medium SemiBold Bold ExtraBold; do
    f=$(find "$tmp/p" -name "Pretendard-$w.otf" | head -1)
    cp "$f" assets/fonts/
  done
fi
for w in Regular Bold; do
  f=assets/fonts/NanumMyeongjo-$w.ttf
  [ -f "$f" ] || curl -fsSL -o "$f" "https://raw.githubusercontent.com/google/fonts/main/ofl/nanummyeongjo/NanumMyeongjo-$w.ttf"
done
ls -la assets/fonts
