#!/bin/bash
# 디자인 스냅샷: 각 화면을 라이트/다크로 그려 docs/design-snapshots/에 PNG로 저장한다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
TEST_RUNNER_NOVEL_SNAPSHOTS=1 xb snapshots "디자인 스냅샷" -scheme NovelEditor -destination "platform=macOS" \
  test -only-testing:AppTests/DesignSnapshotTests
ls "$ROOT/docs/design-snapshots" | sed 's/^/  /'
