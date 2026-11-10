#!/bin/bash
# 테스트: NovelCore 단위 테스트, 앱 테스트를 돌리고, NovelCore가 iOS에서도 빌드되는지 확인한다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log="$LOGS/core-test.log"
if swift test --package-path "$ROOT/Packages/NovelCore" --scratch-path "$ROOT/build/spm" >"$log" 2>&1; then
  echo "✓ NovelCore 테스트 성공 · $(grep -hoE "Test run with [0-9]+ tests?( in [0-9]+ suites?)? passed" "$log" | tail -1)"
else
  echo "✗ NovelCore 테스트 실패 · 전체 로그 build/logs/core-test.log"
  grep -E "error:|✘|recorded an issue" "$log" | head -30
  exit 1
fi

xb test "앱 테스트" -scheme NovelEditor -destination "platform=macOS" test
grep -hoE "Executed [0-9]+ tests?, with [0-9]+ tests? skipped and [0-9]+ failures?|Executed [0-9]+ tests?, with [0-9]+ failures?" "$LOGS/test.log" | tail -1 | sed 's/^/  /'
xb ios-core "NovelCore iOS 빌드 확인" -scheme NovelCore -destination "generic/platform=iOS" build
