# CLAUDE.md

macOS용 한국어 웹소설 집필 에디터(앱 이름 임시: `NovelEditor`). 사용자는 Swift 초보인 대학생이고, 대화·문서·보고는 모두 한국어로 한다.
세부 사양은 여기에 복사하지 말고 `docs/`를 본다.

## 세션 시작할 때

1. 이 파일과 `docs/PROGRESS.md`를 먼저 읽는다. 저장소 전체를 훑지 않는다.
2. 그 작업에 필요한 파일만, 필요한 부분만 읽는다.
3. 시작할 때와 중간중간 `docs/PROGRESS.md`의 "지금 하는 일", "다음 할 일"을 새 세션이 이어갈 수 있을 만큼 구체적으로 갱신한다.

## 우선순위 (충돌하면 위를 택하고 사용자에게 알린다)

1. 사용자가 보기 편하고 관리하기 편할 것
2. 최적화: 빠르고 가볍고, 한글 입력이 절대 깨지지 않을 것
3. 깔끔한 디자인 ("잘 만든 종이 원고", `docs/DESIGN.md`)
4. 탄탄한 기능 (개수보다 확실한 동작)

## 폴더 지도

```
README.md, CLAUDE.md   루트에는 이 둘과 아래 항목만. 새 루트 항목은 허락 받고 추가
NovelEditor.xcodeproj  Xcode 프로젝트
App/                   앱 소스 (Picker/ 작품 선택 창, Workspace/ 작업 공간, Editor/ 원고 편집기(AppKit), Project/ 작품 열기·만들기·최근 목록, Theme/ 색 토큰, Perf/ 측정용 갈고리). Resources/ = Fonts/, Colors.xcassets
Packages/NovelCore/    Foundation만 쓰는 공통 로직 패키지 + 단위 테스트 + 성능 테스트 + make-dummy-novel(더미 작품 생성기)
Tests/AppTests/        앱 테스트, 디자인 스냅샷 (성능 테스트는 Tests/ 아래 따로)
Scripts/               build.sh, run.sh, test.sh, snapshots.sh, perf.sh, lib.sh(공통)
docs/                  SPEC, PLAN, DESIGN, PROGRESS, 체크리스트, design-snapshots/
build/                 빌드 산출물·임시 파일·더미 작품·로그 (git 제외, 통째로 지워도 됨)
```

구조가 바뀌면 같은 커밋에서 `README.md`와 이 파일의 폴더 지도를 고친다.

## 명령

- `Scripts/build.sh` 빌드 / `Scripts/run.sh` 빌드 후 실행 / `Scripts/test.sh` 테스트 / `Scripts/snapshots.sh` 디자인 스냅샷 / `Scripts/perf.sh` 성능 표
- NovelCore 테스트는 `swift test --scratch-path build/spm`, 앱 테스트는 `xcodebuild`(스킴 NovelEditor). test.sh가 둘 다 돌린다
- 스크립트는 성공하면 한 줄 요약, 실패하면 오류 부분만 출력한다. 전체 로그는 `build/logs/`.
- 직접 `xcodebuild`를 쓸 때는 항상 `-derivedDataPath build/DerivedData`와 `-resultBundlePath build/logs/…`.
- Xcode 프로젝트는 폴더 동기화 그룹이라 `App/`, `Tests/AppTests/`에 파일을 넣으면 자동 포함된다. 프로젝트 파일을 고칠 일은 빌드 설정뿐
- 메모리 8GB 기기다. 빌드나 테스트를 동시에 여러 개 돌리지 않는다. 하위 에이전트·병렬 작업은 꼭 필요할 때만.

## 기술 결정 (확정, 바꾸려면 근거와 함께 먼저 제안)

- Swift, SwiftUI(창·사이드바·설정), 편집기는 `NSTextView`(TextKit 1 명시) + `NSViewRepresentable`
- 저장은 일반 파일: 회차마다 `.md`, 작품 정보는 `project.json`. DB 없음, 외부 라이브러리 없음(Pretendard 글꼴만 예외)
- `NovelCore`는 Foundation만 import. AppKit/SwiftUI 금지, macOS 전용 API 금지, 경로는 밖에서 받는다 (나중에 iOS에서 재사용)
- AppKit 코드는 편집기 관련 파일 안에만 둔다. 예외: `App/Project/SystemDialogs.swift`(저장·열기 창, Finder, 경고 창), `App/AppDelegate.swift`(종료 전 저장 대기). 둘 다 SwiftUI에 대응하는 것이 없음

## 코드 규칙

- 들여쓰기 스페이스 2칸. 파일 하나에 역할 하나. 필요 없는 추상화나 미리 만드는 기능 금지
- 주석은 "왜"가 필요한 곳에만, 한국어로
- 색 값은 `App/Resources/Colors.xcassets`에만, 코드는 `App/Theme/ColorTokens.swift`의 이름(`Color.paper` 등)만 쓴다
- 앱 이름은 빌드 설정 `PRODUCT_NAME` 한 곳. 코드는 `AppInfo.name`으로 읽는다
- 앱 타깃은 기본 격리가 MainActor(Swift 6). NovelCore는 기본 격리 없음
- 테스트: NovelCore는 Swift Testing(`@Test`), 앱 쪽은 XCTest
- 보고할 때 새로 등장한 Swift 개념은 한두 문장으로 설명

## 꼭 지킬 것

- 원고 유실이 가장 심각한 버그다. 모든 쓰기는 원자적으로, 저장 순서 보장, 본문 파일은 절대 지우지 않는다. 저장 코드 테스트를 가장 꼼꼼히
- 한글 조합 중(`hasMarkedText`)에는 텍스트 저장소 수정, 선택 영역 변경, 뷰 재생성을 하지 않는다. `updateNSView`에서 텍스트를 다시 넣지 않는다
- `NSTextView`의 텍스트 저장소가 본문의 원본이다. 키 입력마다 본문 전체를 복사하거나 SwiftUI 상태로 흘리지 않는다
- 작품을 열 때 `project.json`만 읽고, 본문은 선택한 회차만 읽는다. 저장·검색·글자 수·스냅샷은 메인 스레드를 막지 않는다
- 성능은 감이 아니라 측정으로 (`docs/SPEC.md` 8장). 목표 미달이면 숨기지 말고 원인·대안을 보고하고 멈춘다
- 더미 작품은 앞 10화만 5,000자, 나머지는 300자(사용자 요청). 더미·생성 파일 내용을 대화로 읽지 않는다(토큰 절약)

## 하면 안 되는 것

- 이 폴더 밖에 파일 만들기 (Xcode 자체 캐시만 예외). 실제 원고(`.novel`)를 저장소에 넣기
- 새 도구(Homebrew 등) 허락 없이 설치하기. 추가 요금 드는 방식으로 넘어가기
- 원격 저장소를 묻지 않고 만들거나 연결하기. 강제 푸시, 히스토리 다시 쓰기. 브랜치는 `main` 하나
- 비밀번호·토큰·개인 정보 커밋
- 테스트를 지우거나 목표 수치를 낮춰서 통과시키기
- 빈 폴더, 백업 사본, 실험 잔여 코드 남기기
- 같은 방법을 두 번 넘게 반복하기 (두 번 실패하면 접근을 바꾸거나 묻는다)

## 작업 흐름

- 단계마다: 빌드 → 테스트 → 성능 측정 → 정리 → `docs/PROGRESS.md` 갱신 → 커밋 → 멈추고 보고. 승인 후 푸시
- 커밋은 작게 자주, 메시지는 한국어 한 줄(무엇을 왜)
- 한도 경고가 보이면 새 작업을 시작하지 말고 마무리·커밋·PROGRESS 갱신 후 멈춘다
- 정해지지 않은 결정은 임의로 정하지 말고 `docs/PLAN.md`의 "미결정 사항"에 적고 묻는다

## 문서 위치

- 요구사항 원문: `docs/SPEC.md`
- 단계 계획, 세부 기준, 미결정 사항: `docs/PLAN.md`
- 색·글꼴·레이아웃 값: `docs/DESIGN.md`
- 진행 상황, 성능 측정 표: `docs/PROGRESS.md`
- 한글 입력 손 확인 체크리스트: `docs/checklist-hangul.md` (편집기 단계에서 생성)
