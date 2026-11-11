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

# 앱 쪽: 편집기 키 입력과 회차 전환 (릴리스 빌드, 테스트에서 앱 내부를 쓰려고 testability만 켠다)
TEST_RUNNER_NOVEL_PERF_PROJECT="$DUMMY" xb perf-app "앱 성능 측정(릴리스)" -scheme NovelEditor -configuration Release \
  -destination "platform=macOS" ENABLE_TESTABILITY=YES test -only-testing:AppTests/EditorPerformanceTests >/dev/null \
  || { echo "✗ 앱 성능 측정 실패 · build/logs/perf-app.log"; exit 1; }

# 앱 실행 시간: 6번 실행하고 첫 번째는 참고값으로만 쓴다(SPEC 8장: 한 번 실행한 적 있는 상태 기준).
xb perf-release-build "릴리스 빌드" -scheme NovelEditor -configuration Release build >/dev/null
APP="$DERIVED/Build/Products/Release/NovelEditor.app/Contents/MacOS/NovelEditor"
# 한 번이 10초를 넘기면 멈춘 것으로 보고 끄고 다음으로 넘어간다(전에는 멈추면 perf.sh가 끝나지 않았다). 멈춘 횟수는 표 아래에 적는다.
: >"$LOGS/perf-launch.log"
for _ in 1 2 3 4 5 6; do
  NOVEL_PERF_OPEN="$DUMMY" NOVEL_PERF_LAUNCH=1 "$APP" >"$LOGS/perf-launch-run.log" 2>/dev/null &
  pid=$!
  for _ in $(seq 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    echo "NOVEL_PERF launch_hung" >>"$LOGS/perf-launch.log"
  fi
  wait "$pid" 2>/dev/null || true
  grep NOVEL_PERF "$LOGS/perf-launch-run.log" >>"$LOGS/perf-launch.log" || true
done
rm -f "$LOGS/perf-launch-run.log"

# 대기 메모리: 5,000자 회차를 연 채로 30초 둔 뒤 실제 사용량(phys_footprint).
# 창 크기는 앱이 1100×760으로 고정한다(LaunchProbe.windowContentSize). 그래픽 버퍼가 창 넓이에 비례하기 때문.
NOVEL_PERF_OPEN="$DUMMY" "$APP" >/dev/null 2>&1 &
pid=$!
sleep 30
footprint -p "$pid" >"$LOGS/perf-memory.log" 2>&1 || true
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

# 측정값에서 중앙값·최솟값·최댓값(키 입력은 p95)을 뽑아 표로 만든다.
python3 - "$log" "$LOGS/perf-app.log" "$LOGS/perf-launch.log" "$LOGS/perf-memory.log" <<'PY'
import re, statistics, sys
core, app, launch, memory = [open(p, encoding="utf-8", errors="replace").read() for p in sys.argv[1:5]]
rows = []
def row(label, values, goal, unit="ms", stat="중앙값"):
    if not values:
        rows.append(f"| {label} | 측정 실패 | | | {goal}{unit} 이내 | 확인 필요 |"); return
    if stat == "p95":
        ordered = sorted(values); main = ordered[min(len(ordered) - 1, int(len(ordered) * 0.95))]
    else:
        main = statistics.median(values)
    ok = "통과" if main <= goal else "미달"
    rows.append(f"| {label} | {stat} {main:.1f}{unit} | {min(values):.1f}{unit} | {max(values):.1f}{unit} | {goal}{unit} 이내 | {ok} |")

m = re.search(r"testOpen500EpisodeProject\]' measured \[Clock Monotonic Time, s\].*?values: \[([^\]]+)\]", core)
row("500회차 작품 열기 (파일 읽기)", [float(v) * 1000 for v in m.group(1).split(",")] if m else [], 300)
def perf(name, text):
    m = re.search(rf"NOVEL_PERF {name} ([0-9.,]+)", text)
    return [float(v) for v in m.group(1).split(",")] if m else []
row("키 입력 1,000번 (5,000자 회차)", perf("keystroke_ms", app), 16, stat="p95")
row("회차 전환 (처음 여는 5,000자 회차)", perf("switch_ms", app), 50)
runs = [float(v) for v in re.findall(r"launch_ms ([0-9.]+)", launch)]
hung = launch.count("launch_hung")
row("앱 실행 → 입력 가능 (첫 실행 제외 5회)", runs[1:], 500)
m = re.search(r"phys_footprint:\s*([0-9.]+)\s*(KB|MB|GB)", memory) or re.search(r"Footprint:\s*([0-9.]+)\s*(KB|MB|GB)", memory)
if m:
    mb = float(m.group(1)) * {"KB": 1 / 1024, "MB": 1, "GB": 1024}[m.group(2)]
    rows.append(f"| 대기 메모리 (5,000자 회차, 30초 뒤) | {mb:.1f}MB | | | 100MB 이내 | {'통과' if mb <= 100 else '미달'} |")
else:
    rows.append("| 대기 메모리 | 측정 실패 | | | 100MB 이내 | 확인 필요 |")

print("| 항목 | 기준값 | 최솟값 | 최댓값 | 목표 | 결과 |")
print("|---|---|---|---|---|---|")
print("\n".join(rows))
if runs: print(f"\n참고: 첫 실행 {runs[0]:.1f}ms")
if hung: print(f"주의: 실행 6번 중 {hung}번이 10초 안에 입력 가능 상태가 되지 않아 껐음")
PY
