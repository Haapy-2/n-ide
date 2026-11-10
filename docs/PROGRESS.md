# 진행 상황

마지막 갱신: 2026-11-10 · 단계 계획은 [PLAN.md](PLAN.md)

## 지금 하는 일

3단계(저장 순서와 복구) 완료, 사용자 확인 대기 중.

## 다음 할 일

4단계 작품 선택 창과 사이드바, 성능 도구 (PLAN.md 4장).
- `App/Info.plist`에 `.novel`을 문서 패키지 형식으로 등록(UTExportedTypeDeclarations, CFBundleDocumentTypes). Finder 두 번 클릭 → 그 작품 바로 열기.
- `App/Picker/ProjectPickerView.swift`: 최근 작품 목록(UserDefaults에 경로 저장, 없어진 경로는 조용히 빼기), 새 작품(저장 창, 처음 위치 ~/Documents, 마지막 위치 기억), 다른 위치에서 열기.
- 작업 공간 창: `WindowGroup(for: URL.self)`로 작품마다 창. `ProjectStore.open()`을 백그라운드에서 부르고, 복구했으면 한 줄로 알림.
- 사이드바 회차 목록(번호, 제목, 글자 수 자리).
- `make-dummy-novel` 실행 도구(NovelCore 패키지 안, 500회차 × 5,000자를 build/perf/에), `Scripts/perf.sh`, "500회차 열기" 측정.
- 사이드바 여닫기 끊김을 실제 앱(Release)에서 확인 (알려진 문제 참고).

## 끝난 단계

| 단계 | 날짜 | 내용 |
|---|---|---|
| 0. 계획 | 2026-11-10 | SPEC, PLAN, DESIGN 승인 |
| 1. 앱 뼈대 | 2026-11-10 | Xcode 프로젝트, NovelCore 패키지, 스크립트, 색 토큰, Pretendard, 작품 선택 창(빈 상태), 작업 공간 틀, 디자인 스냅샷 |
| 2. NovelCore 저장 기본 | 2026-11-10 | 모델(작품·회차·노트·고유 ID), `project.json`(schemaVersion, 상위 버전 거부), 원자적 쓰기(임시 파일 → fsync → rename), 회차·노트 본문 UTF-8 읽기·쓰기, 테스트 22개 |
| 3. 저장 순서와 복구 | 2026-11-10 | 저장 줄(`SaveQueue` actor, 변경 번호로 옛 저장 차단, 0.5·1·2초 재시도), `project.json.bak`, 열 때 복구(백업 → 본문 파일로 재구성, 깨진 파일은 `project.json.broken-<시각>`으로 보존), 테스트 38개 |

## 알려진 문제

- 디자인 스냅샷은 창을 화면 밖에서 그려 뜨는 방식이라 **리퀴드 글래스 사이드바가 하얗게 찍힌다**(유리는 화면 합성 단계에서 그려지기 때문). 사이드바 모양은 4단계부터 실제 앱에서 확인한다.
- 작품 선택 창의 버튼은 4단계 전까지 눌리지 않는다(비활성).
- 사용자 보고(2026-11-10): Xcode 미리보기에서 사이드바를 여닫기를 반복하면 끊기는 느낌. 미리보기는 Debug + 미리보기 오버헤드라 실제 앱과 다르다. 4단계에서 실제 앱(Release)으로 확인하고, 끊기면 `backgroundExtensionEffect`(종이색을 사이드바 아래로 늘려 그리는 효과, `App/Workspace/WorkspaceView.swift`)를 1순위로 의심해 켜고 끈 상태를 비교 측정한다.

## 최근 성능 측정

아직 없음. 측정 도구는 4단계에서 만든다.

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
| `AtomicFile.swift` | 원자적 쓰기 |
| `ProjectError.swift` | 오류 종류 |
