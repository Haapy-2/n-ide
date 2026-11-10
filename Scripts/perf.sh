#!/bin/bash
# 성능 측정: 더미 작품(500회차 × 5,000자)을 만들고 릴리스 빌드로 재서 표로 보여준다. 결과는 build/logs/perf.log
set -euo pipefail
source "$(dirname "$0")/lib.sh"
DUMMY="$ROOT/build/perf/더미 500화.novel"
SPM=(--package-path "$ROOT/Packages/NovelCore" --scratch-path "$ROOT/build/spm")

if [ ! -d "$DUMMY" ]; then
  swift run -c release "${SPM[@]}" make-dummy-novel "$DUMMY" >"$LOGS/perf-dummy.log" 2>&1 \
    || { echo "✗ 더미 작품 생성 실패 · build/logs/perf-dummy.log"; exit 1; }
fi

log="$LOGS/perf.log"
if ! NOVEL_PERF_PROJECT="$DUMMY" swift test -c release "${SPM[@]}" --filter NovelCorePerformanceTests >"$log" 2>&1; then
  echo "✗ 성능 측정 실패 · 전체 로그 build/logs/perf.log"
  grep -E "error:|failed" "$log" | head -20
  exit 1
fi

# XCTest가 남긴 측정값(7회)에서 중앙값·최솟값·최댓값을 뽑아 표로 만든다.
python3 - "$log" <<'PY'
import re, statistics, sys
names = {"testOpen500EpisodeProject": ("500회차 작품 열기 (project.json + 첫 회차 본문, NovelCore)", 300)}
print("| 항목 | 중앙값 | 최솟값 | 최댓값 | 목표 | 결과 |")
print("|---|---|---|---|---|---|")
for line in open(sys.argv[1], encoding="utf-8"):
    m = re.search(r"(test\w+)\]' measured \[Clock Monotonic Time, s\].*?values: \[([^\]]+)\]", line)
    if not m: continue
    label, goal = names.get(m.group(1), (m.group(1), None))
    ms = [float(v) * 1000 for v in m.group(2).split(",")]
    med = statistics.median(ms)
    ok = "" if goal is None else ("통과" if med <= goal else "미달")
    print(f"| {label} | {med:.1f}ms | {min(ms):.1f}ms | {max(ms):.1f}ms | {goal}ms 이내 | {ok} |")
PY
