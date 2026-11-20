#!/bin/bash
# 코드 주석에 이력(날짜, 사용자 요청·결정, "전에는")이 들어갔는지 검사한다. 이력은 docs/log/와 커밋 메시지에 둔다(CLAUDE.md 코드 규칙).
# 걸린 줄이 있으면 그 줄을 보여 주고 실패한다.
set -uo pipefail
cd "$(dirname "$0")/.."
# 작업 단계 번호("8단계", "11e")와 날짜 든 로그 경로도 이력이다. 근거는 "PLAN 10장 6번"처럼 문서 장으로 가리킨다.
pattern='20[0-9]{2}-[0-9]{2}-[0-9]{2}|사용자 (요청|결정|선택|보고|확인)|점검\)|(//+|[.)]) (전에는|예전에는)|[0-9]+단계|(^|[^0-9A-Za-z])1[0-9][a-g]([^A-Za-z]|$)|log[0-9]{2}-[0-9]{2}'
hits=$(find App Packages/NovelCore/Sources Packages/NovelCore/Tests Tests -name '*.swift' -print0 \
  | xargs -0 grep -nE '^\s*//' | grep -E "$pattern" || true)
if [ -n "$hits" ]; then
  echo "✗ 주석에 이력이 있습니다. 이유만 남기고 날짜·요청·예전 동작은 docs/log/로 옮기세요:"
  echo "$hits" | cut -c1-160
  exit 1
fi
echo "✓ 주석 검사 통과"
