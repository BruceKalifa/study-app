#!/usr/bin/env bash
# Pretendard (SIL Open Font License 1.1) — https://github.com/orioncactus/pretendard
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p assets/fonts
if [ -f assets/fonts/Pretendard-Regular.otf ]; then echo "fonts present"; exit 0; fi
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/p.zip" https://github.com/orioncactus/pretendard/releases/download/v1.3.9/Pretendard-1.3.9.zip
unzip -q "$tmp/p.zip" -d "$tmp/p"
for w in Regular Medium SemiBold Bold ExtraBold; do
  f=$(find "$tmp/p" -name "Pretendard-$w.otf" | head -1)
  cp "$f" assets/fonts/
done
ls -la assets/fonts
