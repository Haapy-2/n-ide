#!/bin/bash
# 작업 기록(docs/log/)의 "## 제목 (대기)"를 그 제목을 처음 넣은 커밋의 짧은 해시로 바꾼다.
# 해시는 커밋한 뒤에야 생기므로, 기록에는 (대기)로 쓰고 하루 마무리 때 이것을 돌려 한 번만 커밋한다.
# 아직 커밋하지 않은 제목은 그대로 둔다. 바꾼 개수를 출력하고, 커밋은 하지 않는다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
filled=0; left=0
for f in docs/log/log*.md; do
  while IFS= read -r line; do
    hash=$(git log --reverse --format=%h -S"$line" -- "$f" | head -1)
    if [ -z "$hash" ]; then left=$((left + 1)); continue; fi
    new="${line% (대기)} ($hash)"
    LINE="$line" NEW="$new" perl -0pi -e 's/^\Q$ENV{LINE}\E$/$ENV{NEW}/m' "$f"
    filled=$((filled + 1))
  done < <(grep -E '^## .* \(대기\)$' "$f" || true)
done
msg="✓ 작업 기록 해시 $filled개 채움"
[ "$left" -gt 0 ] && msg="$msg · 아직 커밋 안 된 제목 $left개"
echo "$msg"
