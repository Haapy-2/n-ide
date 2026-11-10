# 진행 상황

마지막 갱신: 2026-11-10 · 단계 계획은 [PLAN.md](PLAN.md)

## 지금 하는 일

2단계(NovelCore 저장 기본) 완료, 사용자 확인 대기 중.

## 다음 할 일

3단계 저장 순서와 복구 (PLAN.md 4장).
- `Packages/NovelCore/Sources/NovelCore/`에 회차별 저장 줄(actor, 한 번에 하나씩)과 변경 번호를 만든다. 낮은 번호의 저장이 높은 번호를 덮지 못하게.
- `ProjectStore.saveProject`가 직전 정상본을 `project.json.bak`으로 남기게 하고, `loadProject`가 깨진 경우 백업 → `episodes/` 파일로 목록 재구성 순서로 복구하게 한다(지금은 `ProjectError.corruptProjectFile`을 던지기만 함).
- 저장 실패 재시도(0.5초, 1초, 2초).
- 늦게 끝난 옛 저장 재현 테스트, 복구 테스트.

## 끝난 단계

| 단계 | 날짜 | 내용 |
|---|---|---|
| 0. 계획 | 2026-11-10 | SPEC, PLAN, DESIGN 승인 |
| 1. 앱 뼈대 | 2026-11-10 | Xcode 프로젝트, NovelCore 패키지, 스크립트, 색 토큰, Pretendard, 작품 선택 창(빈 상태), 작업 공간 틀, 디자인 스냅샷 |
| 2. NovelCore 저장 기본 | 2026-11-10 | 모델(작품·회차·노트·고유 ID), `project.json`(schemaVersion, 상위 버전 거부), 원자적 쓰기(임시 파일 → fsync → rename), 회차·노트 본문 UTF-8 읽기·쓰기, 테스트 22개 |

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
| `ProjectStore.swift` | 작품 만들기, `project.json`·본문 읽기·쓰기 |
| `AtomicFile.swift` | 원자적 쓰기 |
| `ProjectError.swift` | 오류 종류 |
