# 진행 상황

마지막 갱신: 2026-11-10 · 단계 계획은 [PLAN.md](PLAN.md)

## 지금 하는 일

4단계(작품 선택 창과 사이드바, 성능 도구) 완료, 사용자 확인 대기 중.

## 다음 할 일

5단계 편집기와 한글 입력 (PLAN.md 4장).
- `App/Editor/`에 `NSTextView`(TextKit 1 명시) 래퍼(`NSViewRepresentable`). 본문의 원본은 텍스트 저장소, SwiftUI에는 넘기지 않는다.
- DESIGN.md 3장 편집 영역 값(본문 폭 680pt, 줄 높이 고정, 문단 간격, 위 72pt, 아래 = 보이는 높이의 절반).
- `WorkspaceView`의 `// 편집기 자리 (5단계)`에 붙인다. 선택한 회차만 `ProjectStore.readEpisode`로 백그라운드에서 읽는다. 회차 전환 시 실행 취소 기록 비우기.
- `docs/checklist-hangul.md` 작성. 성능: 키 입력 p95, 회차 전환, 앱 실행, 대기 메모리 측정 추가(앱 쪽 성능 테스트는 `Tests/` 아래 새 타깃).

## 끝난 단계

| 단계 | 날짜 | 내용 |
|---|---|---|
| 0. 계획 | 2026-11-10 | SPEC, PLAN, DESIGN 승인 |
| 1. 앱 뼈대 | 2026-11-10 | Xcode 프로젝트, NovelCore 패키지, 스크립트, 색 토큰, Pretendard, 작품 선택 창(빈 상태), 작업 공간 틀, 디자인 스냅샷 |
| 2. NovelCore 저장 기본 | 2026-11-10 | 모델(작품·회차·노트·고유 ID), `project.json`(schemaVersion, 상위 버전 거부), 원자적 쓰기(임시 파일 → fsync → rename), 회차·노트 본문 UTF-8 읽기·쓰기, 테스트 22개 |
| 3. 저장 순서와 복구 | 2026-11-10 | 저장 줄(`SaveQueue` actor, 변경 번호로 옛 저장 차단, 0.5·1·2초 재시도), `project.json.bak`, 열 때 복구(백업 → 본문 파일로 재구성, 깨진 파일은 `project.json.broken-<시각>`으로 보존), 테스트 38개 |
| 4. 작품 선택 창과 사이드바, 성능 도구 | 2026-11-10 | `.novel` 문서 패키지 등록, 작품 선택 창(최근 작품, 새 작품, 다른 위치에서 열기, Finder 두 번 클릭), 작업 공간 창(백그라운드 열기·복구 알림), 사이드바 회차 목록, 파일 메뉴, `make-dummy-novel`, `Scripts/perf.sh` |

## 알려진 문제

- 디자인 스냅샷은 창을 화면 밖에서 그려 뜨는 방식이라 **사이드바(유리 패널과 그 안의 회차 목록)가 통째로 하얗게 찍힌다**. 사이드바는 실제 앱이나 Xcode 미리보기로 확인한다. 자동으로 찍으려면 화면 기록 권한이 필요해서 보류.
- 사용자 보고(2026-11-10): Xcode 미리보기에서 사이드바를 여닫기를 반복하면 끊기는 느낌. 미리보기는 Debug + 미리보기 오버헤드라 실제 앱과 다르다. 4단계에서 실제 앱(Release)으로 확인하고, 끊기면 `backgroundExtensionEffect`(종이색을 사이드바 아래로 늘려 그리는 효과, `App/Workspace/WorkspaceView.swift`)를 1순위로 의심해 켜고 끈 상태를 비교 측정한다.

## 최근 성능 측정

2026-11-10, M2 8GB, 릴리스 빌드, 7회. 더미: 500회차(앞 10화 5,000자, 나머지 300자).

| 항목 | 중앙값 | 최솟값 | 최댓값 | 목표 | 결과 |
|---|---|---|---|---|---|
| 500회차 작품 열기 (project.json + 첫 회차 본문, NovelCore) | 1.0ms | 1.0ms | 1.1ms | 300ms 이내 | 통과 |

- 지금 재는 것은 파일 읽기까지다. "사이드바와 본문이 화면에 보일 때까지"는 편집기가 생기는 5단계부터 앱 쪽에서 잰다.

## 빌드 시간 참고 (Debug)

| 항목 | 시간 |
|---|---|
| 처음 빌드 | 약 6초 |
| 테스트 전체 (`Scripts/test.sh`) | 약 15초 |

## NovelCore 파일 지도

| 파일 | 역할 |
|---|---|
| `ProjectFormat.swift` | 확장자, 현재 형식 버전 |
| `Identifiers.swift` | 회차·노트 고유 ID |
| `ProjectFile.swift` | `project.json` 내용(작품, 회차 목록, 노트 목록, 작품별 설정) |
| `ProjectLayout.swift` | 작품 폴더 안 파일 위치 |
| `ProjectStore.swift` | 작품 만들기, `project.json`·본문 읽기·쓰기, 저장 때 백업 |
| `ProjectRecovery.swift` | 작품 열기(`open()`)와 복구 |
| `SaveQueue.swift` | 저장 줄: 순서 보장, 옛 저장 차단, 재시도 |
| `../MakeDummyNovel/main.swift` | 성능용 더미 작품 생성기 |
| `AtomicFile.swift` | 원자적 쓰기 |
| `ProjectError.swift` | 오류 종류 |
