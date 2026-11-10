# NovelEditor

한국어 웹소설을 쓰기 위한 macOS 네이티브 집필 에디터. 회차마다 `.md` 파일 하나로 저장하고,
빠른 입력과 깨지지 않는 한글 조합, 잃어버리지 않는 원고를 가장 중요하게 여긴다.

> 현재 상태: **계획 단계** (앱 코드 없음). 진행 상황은 [docs/PROGRESS.md](docs/PROGRESS.md) 참고 (1단계부터 생김).

## 빌드와 실행

필요한 것: macOS 27 이상, Xcode 27.2 이상.

| 하고 싶은 일 | 명령 |
|---|---|
| 빌드 | `Scripts/build.sh` |
| 빌드하고 앱 실행 | `Scripts/run.sh` |
| 테스트 전체 | `Scripts/test.sh` |
| 성능 측정 표 | `Scripts/perf.sh` |

Xcode에서 쓰려면 `NovelEditor.xcodeproj`를 열고 실행 버튼(⌘R)을 누른다.
(스크립트와 Xcode 프로젝트는 1단계에서 생긴다.)

## 폴더 지도

```
README.md            지금 이 파일
CLAUDE.md            Claude Code가 세션마다 읽는 핵심 규칙
NovelEditor.xcodeproj  Xcode 프로젝트 (1단계)
App/                 앱 소스: 화면(SwiftUI)과 편집기(AppKit)
  Resources/         글꼴, 아이콘, 색 에셋
Packages/NovelCore/  공통 로직 패키지(모델, 저장, 검색, 글자 수, 스냅샷)와 테스트
Tests/               앱 쪽 테스트, 성능 테스트
Scripts/             build.sh, run.sh, test.sh, perf.sh
docs/                모든 문서
build/               빌드 산출물과 임시 파일 (git 제외, 지워도 됨)
```

## 문서

- [docs/SPEC.md](docs/SPEC.md): 요구사항 원문
- [docs/PLAN.md](docs/PLAN.md): 단계별 계획, 세부 기준, 미결정 사항
- [docs/DESIGN.md](docs/DESIGN.md): 디자인 값과 결정
- docs/PROGRESS.md: 진행 상황과 성능 측정 (1단계부터)
