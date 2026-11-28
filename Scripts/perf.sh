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
  -destination "platform=macOS" ENABLE_TESTABILITY=YES test -only-testing:AppTests/EditorPerformanceTests -only-testing:AppTests/MemoryGrowthTests >/dev/null \
  || { echo "✗ 앱 성능 측정 실패 · build/logs/perf-app.log"; exit 1; }

# 앱 실행 시간: 6번 실행하고 첫 번째는 참고값으로만 쓴다(SPEC 8장: 한 번 실행한 적 있는 상태 기준).
xb perf-release-build "릴리스 빌드" -scheme NovelEditor -configuration Release build >/dev/null
APP="$DERIVED/Build/Products/Release/NovelEditor.app/Contents/MacOS/NovelEditor"
# 한 번이 10초를 넘기면 멈춘 것으로 보고 끄고 다음으로 넘어간다(전에는 멈추면 perf.sh가 끝나지 않았다). 멈춘 횟수는 표 아래에 적는다.
: >"$LOGS/perf-launch.log"
for _ in 1 2 3 4 5 6; do
  NOVEL_PERF_OPEN="$DUMMY" NOVEL_PERF_LAUNCH=1 NOVEL_PERF_MEASURE=1 "$APP" >"$LOGS/perf-launch-run.log" 2>/dev/null &
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
# macOS 창 복원을 끈다: 지난번에 열려 있던 창이 함께 뜨면 값이 77 ↔ 89MB로 흔들렸다.
NOVEL_PERF_OPEN="$DUMMY" NOVEL_PERF_MEASURE=1 "$APP" -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &
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
row("키 입력 300번 (10만 자 회차, 글자 수 실시간)", perf("keystroke_realtime_100k_ms", app), 16, stat="p95")
row("키 입력 300번 (10만 자 회차 끝, 줄 번호 켬, 30번에 한 번 엔터)", perf("keystroke_line_numbers_100k_ms", app), 16, stat="p95")
row("키 입력 300번 (10만 자, 커서 100개, 화면 그리기까지)", perf("multi_cursor_100_keystroke_ms", app), 16, stat="p95")
row("회차 전환 (처음 여는 5,000자 회차)", perf("switch_ms", app), 50)
# 그림 회차(PLAN 19장 6번, 결정 41): 같은 측정에서 그림 없는 같은 본문과 비교한다.
row("그림 회차 키 입력 1,000번 (5,000자 + 그림 10장)", perf("image_keystroke_ms", app), 8, stat="p95")
def p95(values):
    ordered = sorted(values); return ordered[min(len(ordered) - 1, int(len(ordered) * 0.95))]
def extra(label, a, b, goal, use_p95):
    if not a or not b:
        rows.append(f"| {label} | 측정 실패 | | | {goal}ms 이내 | 확인 필요 |"); return
    stat = p95 if use_p95 else statistics.median
    d = stat(a) - stat(b)
    rows.append(f"| {label} | {'p95' if use_p95 else '중앙값'} +{d:.2f}ms | | | +{goal}ms 이내 | {'통과' if d <= goal else '미달'} |")
extra("　그림 없는 같은 본문보다 키 입력이 느려진 정도", perf("image_keystroke_ms", app), perf("image_keystroke_plain_ms", app), 1, True)
extra("그림 회차 전환 (그림 10장, 그림 없는 같은 본문 대비)", perf("image_switch_ms", app), perf("image_switch_plain_ms", app), 5, False)
# 타이핑 중 0.2초마다: 글자 수 하나가 바뀌어 작업 공간(사이드바 500회차 포함)이 다시 그려질 때까지. 한 프레임 기준.
row("글자 수 바뀜 → 화면 갱신 (사이드바 500회차)", perf("sidebar_count_ms", app), 16, stat="p95")
# 설정 창 슬라이더를 끌 때 본문에 새 모양 입히기. SPEC에 목표가 없어 한 프레임(16ms)을 기준으로 둔다.
row("설정 바꿔 모양 다시 입히기 (5,000자)", perf("style_5k_ms", app), 16)
row("설정 바꿔 모양 다시 입히기 (10만 자)", perf("style_100k_ms", app), 16)
# 글자 수 전체 계산(메인 스레드 밖). SPEC에 목표가 없어 입력 멈춤 뒤 한 프레임(16ms)을 기준으로 둔다.
row("글자 수 전체 계산 (5,000자)", perf("count_5k_ms", core), 16)
row("글자 수 전체 계산 (10만 자, 편집기 문자열)", perf("count_100k_bridged_ms", core), 16)
# 스냅샷 찍기(메인 스레드 밖): 50개 찬 회차에 비교 → 쓰기 → 정리. SPEC에 목표가 없어 회차 전환 목표(50ms)를 기준으로 둔다.
row("스냅샷 찍기 (5,000자, 50개 찬 회차)", perf("snapshot_5k_ms", core), 50)
row("스냅샷 찍기 (10만 자, 50개 찬 회차)", perf("snapshot_100k_ms", core), 50)
# 비교(메인 스레드 밖): 스냅샷을 누르면 바로 보여야 해서 100ms를 기준으로 둔다(SPEC에 목표 없음).
row("비교 (5,000자, 문단 30% 고침)", perf("diff_5k_ms", core), 100)
row("비교 (10만 자, 문단 30% 고침)", perf("diff_100k_ms", core), 100)
row("비교 (10만 자, 겹치는 문단 없음)", perf("diff_100k_unrelated_ms", core), 100)
# 작품 전체 검색(12단계, 메인 스레드 밖): 없는 문구로 500회차를 모두 읽고 찾기. SPEC 8장 목표 0.5초.
row("작품 전체 검색 500회차 (처음)", perf("search_500_first_ms", core), 500)
row("작품 전체 검색 500회차 (두 번째부터)", perf("search_500_ms", core), 500)
row("찾기만 500회차 × 5,000자 (파일 읽기 빼고)", perf("search_500x5k_ms", core), 500)
# 스냅샷 판 열기(11g): 목록·메모 50개 읽기 + 가장 최근 것과 비교까지. 비교와 같은 100ms 기준.
row("스냅샷 판 열기 → 비교 보임 (5,000자, 50개)", perf("panel_open_5k_ms", app), 100)
row("스냅샷 판 열기 → 비교 보임 (10만 자, 50개)", perf("panel_open_100k_ms", app), 100)
# 전체 바꾸기(13단계, 미결정 20): 더미 사본에서 "그는" 있는 회차 모두, 회차마다 스냅샷 두 개 + 본문 쓰기.
row("전체 바꾸기 500화 중 \"그는\" 있는 회차 모두", perf("replace_all_500_ms", app), 2000)
# 되돌리기(PLAN 14장 5번): 창을 열 때 회차마다 다시 감지(스냅샷·본문 읽기 + 비교), 모두 되돌리기(회차마다 되돌리기 전 스냅샷 + 본문 쓰기).
# 목표는 SPEC에 없어 검색(500ms)·바꾸기(2초)와 같게 잡았다(PLAN 미결정 26).
row("되돌리기 창 열기 500화 (다시 감지)", perf("revert_detect_500_ms", app), 500)
row("모두 되돌리기 500화", perf("revert_all_500_ms", app), 2000)
row("여러 회차 이름 변경 500화 (스냅샷까지)", perf("batch_rename_500_ms", app), 2000)
# 그동안 메인 스레드가 가장 오래 막힌 시간. 누른 뒤 화면이 멈추지 않는지 본다(판 열기와 같은 100ms).
row("여러 회차 이름 변경 500화 중 화면 멈춤", perf("batch_rename_500_main_gap_ms", app), 100)
# 스냅샷으로 되돌리기: 본문 통째 바꾸기(메인 스레드). 회차 전환과 같은 50ms 기준.
row("되돌리기 본문 바꾸기 (10만 자)", perf("restore_100k_ms", app), 50)
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
full = perf("multi_cursor_100_keystroke_full_layout_ms", app)
if full:
    ordered = sorted(full)
    print(f"\n참고: 커서 100개 키 입력을 본문 전체 레이아웃까지 재면 p95 {ordered[min(len(ordered) - 1, int(len(ordered) * 0.95))]:.1f}ms (앱은 이 몫을 뒤에서 나눠 한다)")
if runs: print(f"\n참고: 첫 실행 {runs[0]:.1f}ms")
if hung: print(f"주의: 실행 6번 중 {hung}번이 10초 안에 입력 가능 상태가 되지 않아 껐음")
# 회차 전환 메모리(MemoryGrowthTests): footprint/malloc 사용량(MB). 쌓이는지는 malloc 쪽으로 본다(목표 없음, 참고값).
m = re.search(r"NOVEL_PERF memory_switch (.+)", app)
if m: print(f"회차 전환 메모리 (footprint/malloc MB, 500회차 3바퀴 → 10만 자 회차 3번 열고 닫기): {m.group(1).strip()}")
PY
