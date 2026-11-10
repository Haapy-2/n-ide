# 스크립트 공통 부분: 경로와 xcodebuild 실행 방식. 직접 실행하지 않고 다른 스크립트가 불러 쓴다.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"
LOGS="$ROOT/build/logs"
mkdir -p "$LOGS"

# xb <로그 이름> <설명> <xcodebuild 인자...>
# 성공하면 한 줄 요약, 실패하면 오류 부분만 보여준다. 전체 로그는 build/logs/<로그 이름>.log
xb() {
  local name="$1" label="$2"; shift 2
  local log="$LOGS/$name.log" result="$LOGS/$name.xcresult" start=$SECONDS
  rm -rf "$result"  # 결과 묶음도 홈 폴더 임시 위치가 아니라 build/ 안에 남긴다
  if xcodebuild -project "$ROOT/NovelEditor.xcodeproj" -derivedDataPath "$DERIVED" -resultBundlePath "$result" "$@" >"$log" 2>&1; then
    echo "✓ $label 성공 ($((SECONDS - start))초) · 로그 build/logs/$name.log"
  else
    echo "✗ $label 실패 · 전체 로그 build/logs/$name.log"
    grep -E "error:|: failed|FAILED|✘|recorded an issue|Fatal error" "$log" | sort -u | head -30
    return 1
  fi
}
