#!/bin/bash
# 검증 도우미: 실제 앱을 사용자처럼 조작하기 전후의 준비와 정리.
#   verify.sh launch            빌드 → 사용자 설정 백업 → 새 검증 작품 생성 → 그 작품을 바로 연 앱 실행
#   verify.sh doctor            이 인스턴스를 조작해도 되는지 읽기만 하며 점검
#   verify.sh evidence <이름>   검증 작품의 디스크 상태(본문 .md, project.json)를 증거 폴더로 복사
#   verify.sh cleanup           우리가 띄운 앱만 끄고, 사용자 설정을 되돌리고, 검증 작품을 지운다(증거는 남김)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
VERIFY="$ROOT/build/verify"
RUN="$VERIFY/run"                       # 이번 실행의 임시 상태(정리 때 지움)
EVIDENCE="$VERIFY/evidence"             # 증거(정리 때 지우지 않음)
PROJECT="$RUN/검증 작품.novel"
APP="$ROOT/build/DerivedData/Build/Products/Debug/NovelEditor.app"
BIN="$APP/Contents/MacOS/NovelEditor"
DOMAIN="com.haapy2.NovelEditor"
BACKUP="$VERIFY/defaults-backup.plist"  # 사용자의 실제 설정. 정리 때 되돌린 뒤 지운다
NO_DOMAIN="$VERIFY/defaults-was-empty"
PIDFILE="$RUN/app.pid"

ours_alive() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

launch() {
  if pgrep -x NovelEditor >/dev/null; then
    echo "✗ NovelEditor가 이미 켜져 있습니다(사용자 것이거나 지난 검증의 잔여). 설정이 섞이니 조작하지 않습니다."
    echo "  지난 검증 잔여라면 verify.sh cleanup, 사용자 것이라면 사용자에게 꺼 달라고 요청하세요."
    exit 1
  fi
  # 지난 실행이 정리 없이 끝났으면 백업이 이미 있다. 그 백업이 진짜 원본이므로 덮어쓰지 않는다.
  if [ ! -f "$BACKUP" ] && [ ! -f "$NO_DOMAIN" ]; then
    mkdir -p "$VERIFY"
    if defaults export "$DOMAIN" "$BACKUP" 2>/dev/null; then :; else rm -f "$BACKUP"; touch "$NO_DOMAIN"; fi
  fi
  "$ROOT/Scripts/build.sh"
  rm -rf "$RUN"; mkdir -p "$RUN" "$EVIDENCE"
  # 3회차, 긴 회차 0개, 300자: 빠르게 열리고 내용을 대화로 읽을 필요가 없을 만큼 작다
  swift run -c release --package-path "$ROOT/Packages/NovelCore" --scratch-path "$ROOT/build/spm" \
    make-dummy-novel "$PROJECT" 3 0 300 >"$RUN/dummy.log" 2>&1 \
    || { echo "✗ 검증 작품 생성 실패 · $RUN/dummy.log"; exit 1; }
  # NOVEL_PERF_OPEN: 작품 선택 창을 건너뛰고 이 작품을 바로 연다(App/Perf/LaunchProbe.swift)
  # 창 복원을 끈다: perf.sh 등이 연 다른 작품(더미 500화) 창이 macOS 창 복원으로 대신 뜬 일이 있다(2026-11-20).
  NOVEL_PERF_OPEN="$PROJECT" nohup "$BIN" -ApplePersistenceIgnoreState YES >"$RUN/app.log" 2>&1 &
  echo $! >"$PIDFILE"
  for _ in $(seq 1 20); do
    sleep 0.5
    ours_alive || { echo "✗ 앱이 바로 꺼졌습니다 · $RUN/app.log"; exit 1; }
  done
  echo "✓ 실행됨 pid $(cat "$PIDFILE") · 작품 $PROJECT"
  echo "  준비 확인: app_screenshot으로 작업 공간 창(사이드바에 회차 3개, 본문)이 보이는지 본다"
}

doctor() {
  local ok=1
  if ours_alive; then echo "✓ 우리가 띄운 앱 pid $(cat "$PIDFILE") 살아 있음"
  else echo "✗ 우리가 띄운 앱이 없음 → verify.sh launch"; ok=0; fi
  local others; others=$(pgrep -x NovelEditor | grep -vx "$(cat "$PIDFILE" 2>/dev/null || echo none)" || true)
  [ -z "$others" ] || { echo "✗ 다른 NovelEditor 인스턴스 있음(pid $others) → 조작 대상이 헷갈림"; ok=0; }
  if ours_alive; then
    local exe; exe=$(ps -o comm= -p "$(cat "$PIDFILE")")
    [ "$exe" = "$BIN" ] && echo "✓ 실행 파일이 이 저장소 빌드" || { echo "✗ 실행 파일이 다름: $exe"; ok=0; }
  fi
  local newer; newer=$(find "$ROOT/App" -newer "$BIN" -type f 2>/dev/null | head -1)
  [ -z "$newer" ] && echo "✓ 빌드가 App/ 소스보다 최신" || { echo "✗ 빌드 뒤에 바뀐 소스 있음($newer) → cleanup 후 launch"; ok=0; }
  [ -d "$PROJECT" ] && echo "✓ 검증 작품 있음" || { echo "✗ 검증 작품 없음"; ok=0; }
  [ -f "$BACKUP" ] || [ -f "$NO_DOMAIN" ] && echo "✓ 사용자 설정 백업 있음" || { echo "✗ 사용자 설정 백업 없음"; ok=0; }
  [ $ok = 1 ] && echo "→ 조작해도 됨" || { echo "→ 조작하지 말 것"; exit 1; }
}

evidence() {
  local name="${1:?증거 이름을 주세요(예: autosave)}"
  local dest; dest="$EVIDENCE/$(date +%Y%m%d-%H%M%S)-$name"
  mkdir -p "$dest"
  cp -R "$PROJECT/episodes" "$PROJECT/project.json" "$dest/"
  echo "✓ 증거 저장 $dest"
}

cleanup() {
  if ours_alive; then
    local pid; pid=$(cat "$PIDFILE")
    kill "$pid"   # 이름이 아니라 우리가 띄운 pid만
    for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid"
  fi
  if [ -f "$BACKUP" ]; then defaults delete "$DOMAIN" 2>/dev/null || true; defaults import "$DOMAIN" "$BACKUP" && rm -f "$BACKUP"
  elif [ -f "$NO_DOMAIN" ]; then defaults delete "$DOMAIN" 2>/dev/null || true; rm -f "$NO_DOMAIN"; fi
  rm -rf "$RUN"
  echo "✓ 정리 끝 · 증거는 $EVIDENCE 에 남아 있음"
}

case "${1:-}" in
  launch) launch ;;
  doctor) doctor ;;
  evidence) evidence "${2:-}" ;;
  cleanup) cleanup ;;
  *) sed -n '2,6p' "$0"; exit 1 ;;
esac
