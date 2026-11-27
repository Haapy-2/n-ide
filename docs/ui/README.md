# 화면 모음 (UI 스크린샷)

UI·UX 개선 작업에서 지금 모습을 비교하려고 남긴 실제 앱 화면이다. 2026-11-27, Debug 빌드, 창 1100×760, 검증용 더미 작품(실제 원고 아님)으로 찍었다. 다크·라이트는 설정 › 일반 › 테마로 바꿔 찍었고 macOS 자체는 다크였다. 메뉴는 화면 일부를 잘라 찍어서 크기가 다르다. 창만 잡는 백그라운드 캡처로 찍어서 macOS 유리 재질(확인 창 바탕 등)은 실제 화면과 다르게 나온다. 그래서 라이트 테마 확인 창(`dialogs/dialog-*-light`)은 실제 화면에서 다시 찍었다(창 크기 그대로 1100×761). 다크 확인 창과 메뉴·툴바 묶음·알림의 유리 바탕은 창 캡처라 실제와 조금 다를 수 있다.

대표 화면은 [README](../../README.md#화면)에 있다. 다시 찍을 때는 같은 이름으로 덮어써서 git 이력으로 전후를 비교한다.

## 목차

- [작업 공간](#작업-공간)
- [사이드바](#사이드바)
- [메뉴](#메뉴)
- [확인 창과 시트](#확인-창과-시트)
- [작품 전체 검색](#작품-전체-검색)
- [스냅샷](#스냅샷)
- [설정 창](#설정-창)
- [작품 선택 창](#작품-선택-창)
- [찍으며 본 UI·UX 문제](#찍으며-본-uiux-문제)
- [찍지 못한 화면](#찍지-못한-화면)

## 작업 공간

| 화면 | 다크 | 라이트 |
|---|---|---|
| 기본 화면: 회차 목록(회차별 글자 수)과 본문 | <img src="workspace/workspace-dark.jpg" width="360" alt="기본 화면: 회차 목록(회차별 글자 수)과 본문 (dark)"> | <img src="workspace/workspace-light.jpg" width="360" alt="기본 화면: 회차 목록(회차별 글자 수)과 본문 (light)"> |
| 다른 앱을 보고 있을 때(창 단추가 회색) | <img src="workspace/workspace-inactive-dark.jpg" width="360" alt="다른 앱을 보고 있을 때(창 단추가 회색) (dark)"> | – |
| 입력하면 아래에 상태 줄(글자 수·공백 제외·목표 진행 원)이 뜸 | <img src="workspace/statusbar-dark.jpg" width="360" alt="입력하면 아래에 상태 줄(글자 수·공백 제외·목표 진행 원)이 뜸 (dark)"> | <img src="workspace/statusbar-light.jpg" width="360" alt="입력하면 아래에 상태 줄(글자 수·공백 제외·목표 진행 원)이 뜸 (light)"> |
| 스냅샷으로 되돌린 뒤 상태 줄: "03:36:30 버전으로 되돌렸어요 · 취소" | <img src="workspace/statusbar-restored-dark.jpg" width="360" alt="스냅샷으로 되돌린 뒤 상태 줄: "03:36:30 버전으로 되돌렸어요 · 취소" (dark)"> | – |
| 스냅샷 찍은 뒤 오른쪽 위 알림: "스냅샷을 찍었어요 · 메모 달기" | <img src="workspace/toast-snapshot-dark.jpg" width="360" alt="스냅샷 찍은 뒤 오른쪽 위 알림: "스냅샷을 찍었어요 · 메모 달기" (dark)"> | <img src="workspace/toast-snapshot-light.jpg" width="360" alt="스냅샷 찍은 뒤 오른쪽 위 알림: "스냅샷을 찍었어요 · 메모 달기" (light)"> |
| 사이드바를 가린 화면 | <img src="workspace/workspace-sidebar-hidden-dark.jpg" width="360" alt="사이드바를 가린 화면 (dark)"> | <img src="workspace/workspace-sidebar-hidden-light.jpg" width="360" alt="사이드바를 가린 화면 (light)"> |
| 새로 만든 빈 회차("제목 없음", 0자) | <img src="workspace/episode-empty-dark.jpg" width="360" alt="새로 만든 빈 회차("제목 없음", 0자) (dark)"> | <img src="workspace/episode-empty-light.jpg" width="360" alt="새로 만든 빈 회차("제목 없음", 0자) (light)"> |
| 회차가 하나도 없을 때: "첫 회차를 추가해 주세요." | <img src="workspace/project-empty-dark.jpg" width="360" alt="회차가 하나도 없을 때: "첫 회차를 추가해 주세요." (dark)"> | <img src="workspace/project-empty-light.jpg" width="360" alt="회차가 하나도 없을 때: "첫 회차를 추가해 주세요." (light)"> |
| 같은 말 하나 더 고르기(⌘D)로 세 곳을 고른 모습 | <img src="workspace/editor-multicursor-dark.jpg" width="360" alt="같은 말 하나 더 고르기(⌘D)로 세 곳을 고른 모습 (dark)"> | – |
| 줄 번호를 켠 본문, 고른 낱말 색 | <img src="workspace/editor-line-numbers-dark.jpg" width="360" alt="줄 번호를 켠 본문, 고른 낱말 색 (dark)"> | – |

## 사이드바

| 화면 | 다크 | 라이트 |
|---|---|---|
| 회차 묶음("1부 · 첫눈")을 편 모습 | <img src="sidebar/sidebar-group-open-dark.jpg" width="360" alt="회차 묶음("1부 · 첫눈")을 편 모습 (dark)"> | <img src="sidebar/sidebar-group-open-light.jpg" width="360" alt="회차 묶음("1부 · 첫눈")을 편 모습 (light)"> |
| 묶음을 접은 모습 | <img src="sidebar/sidebar-group-closed-dark.jpg" width="360" alt="묶음을 접은 모습 (dark)"> | – |
| ⌘클릭으로 회차 두 개를 고른 모습 | – | <img src="sidebar/sidebar-group-multiselect-light.jpg" width="360" alt="⌘클릭으로 회차 두 개를 고른 모습 (light)"> |
| 마우스를 올린 줄(3화)이 옅게 칠해짐 | <img src="sidebar/sidebar-hover-dark.jpg" width="360" alt="마우스를 올린 줄(3화)이 옅게 칠해짐 (dark)"> | – |

## 메뉴

| 화면 | 다크 | 라이트 |
|---|---|---|
| NovelEditor 메뉴 | <img src="menus/menu-app-dark.jpg" width="360" alt="NovelEditor 메뉴 (dark)"> | – |
| 파일 메뉴 | <img src="menus/menu-file-dark.jpg" width="360" alt="파일 메뉴 (dark)"> | <img src="menus/menu-file-light.jpg" width="360" alt="파일 메뉴 (light)"> |
| 편집 메뉴 | <img src="menus/menu-edit-dark.jpg" width="360" alt="편집 메뉴 (dark)"> | <img src="menus/menu-edit-light.jpg" width="360" alt="편집 메뉴 (light)"> |
| 보기 메뉴(시스템 항목만) | <img src="menus/menu-view-dark.jpg" width="360" alt="보기 메뉴(시스템 항목만) (dark)"> | – |
| 회차 메뉴 | <img src="menus/menu-episode-dark.jpg" width="360" alt="회차 메뉴 (dark)"> | <img src="menus/menu-episode-light.jpg" width="360" alt="회차 메뉴 (light)"> |
| 회차 줄 우클릭 메뉴 | <img src="menus/menu-episode-context-dark.jpg" width="360" alt="회차 줄 우클릭 메뉴 (dark)"> | <img src="menus/menu-episode-context-light.jpg" width="360" alt="회차 줄 우클릭 메뉴 (light)"> |
| 우클릭 › 묶음에 넣기 하위 메뉴 | <img src="menus/menu-episode-context-group-dark.jpg" width="360" alt="우클릭 › 묶음에 넣기 하위 메뉴 (dark)"> | – |
| 회차 두 개를 골랐을 때 우클릭 메뉴("2개 회차 …") | <img src="menus/menu-multi-select-context-dark.jpg" width="360" alt="회차 두 개를 골랐을 때 우클릭 메뉴("2개 회차 …") (dark)"> | – |
| 묶음 제목 줄 우클릭 메뉴 | <img src="menus/menu-group-context-dark.jpg" width="360" alt="묶음 제목 줄 우클릭 메뉴 (dark)"> | – |

## 확인 창과 시트

> 라이트 확인 창은 모두 실제 화면에서 찍었다. 다크 확인 창은 창 캡처라 유리 바탕이 실제보다 어둡고 평평하게 보일 수 있다.

| 화면 | 다크 | 라이트 |
|---|---|---|
| 회차 이름 | <img src="dialogs/dialog-rename-dark.jpg" width="360" alt="회차 이름 (dark)"> | <img src="dialogs/dialog-rename-light.jpg" width="360" alt="회차 이름 (light)"> |
| 목표 글자 수 | <img src="dialogs/dialog-goal-dark.jpg" width="360" alt="목표 글자 수 (dark)"> | <img src="dialogs/dialog-goal-light.jpg" width="360" alt="목표 글자 수 (light)"> |
| 휴지통으로 옮길까요? | <img src="dialogs/dialog-trash-dark.jpg" width="360" alt="휴지통으로 옮길까요? (dark)"> | <img src="dialogs/dialog-trash-light.jpg" width="360" alt="휴지통으로 옮길까요? (light)"> |
| 묶기(묶음 이름) | <img src="dialogs/dialog-group-dark.jpg" width="360" alt="묶기(묶음 이름) (dark)"> | <img src="dialogs/dialog-group-light.jpg" width="360" alt="묶기(묶음 이름) (light)"> |
| 회차 두 개를 골랐을 때 묶기 | – | <img src="dialogs/dialog-group-multi-light.jpg" width="360" alt="회차 두 개를 골랐을 때 묶기 (light)"> |
| 스냅샷 메모 | <img src="dialogs/dialog-snapshot-memo-dark.jpg" width="360" alt="스냅샷 메모 (dark)"> | – |
| 사이드바에서 ⌘Z: "묶기"를 되돌릴까요? | <img src="dialogs/dialog-sidebar-undo-dark.jpg" width="360" alt="사이드바에서 ⌘Z: "묶기"를 되돌릴까요? (dark)"> | – |
| 전체 바꾸기 확인 | <img src="dialogs/dialog-replace-all-dark.jpg" width="360" alt="전체 바꾸기 확인 (dark)"> | <img src="dialogs/dialog-replace-all-light.jpg" width="360" alt="전체 바꾸기 확인 (light)"> |
| 여러 회차 이름 변경: 글자 바꾸기(빈 상태) | <img src="dialogs/sheet-batch-rename-dark.jpg" width="360" alt="여러 회차 이름 변경: 글자 바꾸기(빈 상태) (dark)"> | – |
| 글자 바꾸기 미리 보기(화 → 회) | <img src="dialogs/sheet-batch-rename-preview-dark.jpg" width="360" alt="글자 바꾸기 미리 보기(화 → 회) (dark)"> | – |
| 앞·뒤에 붙이기 | <img src="dialogs/sheet-batch-rename-affix-dark.jpg" width="360" alt="앞·뒤에 붙이기 (dark)"> | – |
| 새 이름 + 번호 | <img src="dialogs/sheet-batch-rename-number-dark.jpg" width="360" alt="새 이름 + 번호 (dark)"> | – |

## 작품 전체 검색

| 화면 | 다크 | 라이트 |
|---|---|---|
| 검색 패널을 막 연 모습 | <img src="search/search-empty-dark.jpg" width="360" alt="검색 패널을 막 연 모습 (dark)"> | – |
| 찾은 곳이 없을 때 | <img src="search/search-no-results-dark.jpg" width="360" alt="찾은 곳이 없을 때 (dark)"> | – |
| 회차별 결과("3개 회차에서 5곳") | <img src="search/search-results-dark.jpg" width="360" alt="회차별 결과("3개 회차에서 5곳") (dark)"> | – |
| 바꿀 말을 넣은 미리 보기(지운 말 줄 긋기 + 새 말) | <img src="search/search-replace-preview-dark.jpg" width="360" alt="바꿀 말을 넣은 미리 보기(지운 말 줄 긋기 + 새 말) (dark)"> | <img src="search/search-replace-preview-light.jpg" width="360" alt="바꿀 말을 넣은 미리 보기(지운 말 줄 긋기 + 새 말) (light)"> |
| 모두 바꾼 뒤: 바꾼 회차 목록과 알림("바꾼 곳 보기 · 되돌리기") | <img src="search/search-replaced-dark.jpg" width="360" alt="모두 바꾼 뒤: 바꾼 회차 목록과 알림("바꾼 곳 보기 · 되돌리기") (dark)"> | – |
| 전체 바꾸기 되돌리기 창(회차 고르기 + 지금/되돌린 뒤 비교) | <img src="search/sheet-revert-replace-dark.jpg" width="360" alt="전체 바꾸기 되돌리기 창(회차 고르기 + 지금/되돌린 뒤 비교) (dark)"> | <img src="search/sheet-revert-replace-light.jpg" width="360" alt="전체 바꾸기 되돌리기 창(회차 고르기 + 지금/되돌린 뒤 비교) (light)"> |

## 스냅샷

| 화면 | 다크 | 라이트 |
|---|---|---|
| 과거↔현재 두 칸 비교, 더한 문단은 초록 | <img src="snapshots/snapshot-diff-dark.jpg" width="360" alt="과거↔현재 두 칸 비교, 더한 문단은 초록 (dark)"> | <img src="snapshots/snapshot-diff-light.jpg" width="360" alt="과거↔현재 두 칸 비교, 더한 문단은 초록 (light)"> |
| 낱말 단위 비교(떨렸다 → 흔들렸다), 지운 줄은 빨강 빗금 | <img src="snapshots/snapshot-diff-words-dark.jpg" width="360" alt="낱말 단위 비교(떨렸다 → 흔들렸다), 지운 줄은 빨강 빗금 (dark)"> | <img src="snapshots/snapshot-diff-words-light.jpg" width="360" alt="낱말 단위 비교(떨렸다 → 흔들렸다), 지운 줄은 빨강 빗금 (light)"> |
| 스냅샷 종류 표시(직접·바꾼 뒤·바꾸기 전·여러 커서 전)와 메모 줄 | <img src="snapshots/snapshot-kinds-dark.jpg" width="360" alt="스냅샷 종류 표시(직접·바꾼 뒤·바꾸기 전·여러 커서 전)와 메모 줄 (dark)"> | <img src="snapshots/snapshot-kinds-light.jpg" width="360" alt="스냅샷 종류 표시(직접·바꾼 뒤·바꾸기 전·여러 커서 전)와 메모 줄 (light)"> |

## 설정 창

| 화면 | 다크 | 라이트 |
|---|---|---|
| 일반(위): 테마, 목표, 스냅샷 | <img src="settings/settings-general-top-dark.jpg" width="360" alt="일반(위): 테마, 목표, 스냅샷 (dark)"> | <img src="settings/settings-general-top-light.jpg" width="360" alt="일반(위): 테마, 목표, 스냅샷 (light)"> |
| 일반(아래): 되돌리기 확인 창, 알림 유지 시간 | <img src="settings/settings-general-bottom-dark.jpg" width="360" alt="일반(아래): 되돌리기 확인 창, 알림 유지 시간 (dark)"> | <img src="settings/settings-general-bottom-light.jpg" width="360" alt="일반(아래): 되돌리기 확인 창, 알림 유지 시간 (light)"> |
| 편집기(위): 미리 보기, 글꼴·크기·간격·폭, 줄 번호, 여러 커서 | <img src="settings/settings-editor-top-dark.jpg" width="360" alt="편집기(위): 미리 보기, 글꼴·크기·간격·폭, 줄 번호, 여러 커서 (dark)"> | <img src="settings/settings-editor-top-light.jpg" width="360" alt="편집기(위): 미리 보기, 글꼴·크기·간격·폭, 줄 번호, 여러 커서 (light)"> |
| 편집기(아래): 상태 줄 | <img src="settings/settings-editor-bottom-dark.jpg" width="360" alt="편집기(아래): 상태 줄 (dark)"> | <img src="settings/settings-editor-bottom-light.jpg" width="360" alt="편집기(아래): 상태 줄 (light)"> |
| 커서: 미리 보기, 두께·높이, 모드별 색 | <img src="settings/settings-cursor-dark.jpg" width="360" alt="커서: 미리 보기, 두께·높이, 모드별 색 (dark)"> | <img src="settings/settings-cursor-light.jpg" width="360" alt="커서: 미리 보기, 두께·높이, 모드별 색 (light)"> |
| 사이드바 | <img src="settings/settings-sidebar-dark.jpg" width="360" alt="사이드바 (dark)"> | <img src="settings/settings-sidebar-light.jpg" width="360" alt="사이드바 (light)"> |
| 단축키(위): 파일·편집·스냅샷 | <img src="settings/settings-shortcuts-top-dark.jpg" width="360" alt="단축키(위): 파일·편집·스냅샷 (dark)"> | <img src="settings/settings-shortcuts-top-light.jpg" width="360" alt="단축키(위): 파일·편집·스냅샷 (light)"> |
| 단축키(가운데) | <img src="settings/settings-shortcuts-middle-dark.jpg" width="360" alt="단축키(가운데) (dark)"> | <img src="settings/settings-shortcuts-middle-light.jpg" width="360" alt="단축키(가운데) (light)"> |
| 단축키(아래): 회차, 모두 기본값으로 | <img src="settings/settings-shortcuts-bottom-dark.jpg" width="360" alt="단축키(아래): 회차, 모두 기본값으로 (dark)"> | <img src="settings/settings-shortcuts-bottom-light.jpg" width="360" alt="단축키(아래): 회차, 모두 기본값으로 (light)"> |
| 단축키 칸을 눌러 "키를 누르세요" 기다리는 상태 | <img src="settings/settings-shortcut-recording-dark.jpg" width="360" alt="단축키 칸을 눌러 "키를 누르세요" 기다리는 상태 (dark)"> | – |

## 작품 선택 창

| 화면 | 다크 | 라이트 |
|---|---|---|
| 최근 작품, 새 작품, 다른 위치에서 열기 | <img src="picker/picker-dark.jpg" width="360" alt="최근 작품, 새 작품, 다른 위치에서 열기 (dark)"> | <img src="picker/picker-light.jpg" width="360" alt="최근 작품, 새 작품, 다른 위치에서 열기 (light)"> |

## 찍으며 본 UI·UX 문제

고치지 않고 기록만 했다. 무엇을 고칠지는 정해서 PLAN에 올린다. 처음 적은 "라이트 테마 확인 창이 어둡게 뜬다"는 실제 화면에서는 밝게 떠서 뺐다(캡처 방식 탓).

| # | 본 것 | 어디서 |
|---|---|---|
| 1 | (고침: 직접 그린 회색 칸) 전체 바꾸기 되돌리기 창에서 고른 줄의 회차 번호와 "N곳" 글자가 배경과 거의 같은 색이다(라이트에서 더 심함, 실제 화면에서 다시 확인 필요) | [search/sheet-revert-replace-*](#작품-전체-검색) |
| 2 | (고침: 설정 표에 사이드바 ⌘⌫ 안내 줄) 휴지통 단축키가 회차 메뉴에는 ⌘⌫, 설정 › 단축키 표와 기본값 코드에는 ⌥⌘⌫로 서로 다르다. 메뉴는 사이드바에 초점이 있을 때만 ⌘⌫로 바뀌는 의도된 동작이었다 | menus/menu-episode-*, settings/settings-shortcuts-bottom-* |
| 3 | (고침: `EpisodeLabel`·`KoreanParticle`) 휴지통 확인 제목이 "1화 '1화'을(를)"처럼 번호와 이름이 같으면 겹치고, 조사가 "을(를)"·"(으)로"로 나온다. 스냅샷 판 제목·검색 패널·되돌리기 창의 "1화 1화"도 같은 문제 | dialogs/dialog-trash-*, dialogs/dialog-replace-all-* |
| 4 | (고침: 메뉴 이름에 "지금 회차(N화)만"·"이 회차만") 회차 두 개를 골랐을 때 회차 메뉴의 "묶기"는 고른 회차 모두, "휴지통으로 이동"은 지금 회차 하나에만 적용된다 | dialogs/dialog-group-multi-light, dialogs/dialog-trash-light |
| 5 | (고침: 되돌리기·다시 바꾸기·스냅샷으로 되돌린 뒤 바꾼 결과를 지우고 다시 찾음) 스냅샷으로 되돌린 뒤에도 검색 패널이 "5곳을 바꿨어요" 결과를 그대로 보여 준다 | workspace/statusbar-restored-dark |
| 6 | (고침: accent 테두리·글자) 단축키 칸이 "키를 누르세요"로 기다리는 상태가 평소 칸과 거의 같아 보인다 | settings/settings-shortcut-recording-dark |
| 7 | (고침: "첫 문장을 써 주세요.") 빈 회차 본문에 안내 글이 없다(작품이 비었을 때는 "첫 회차를 추가해 주세요"가 있음) | workspace/episode-empty-* |
| 8 | (원인 못 찾음, PLAN 18장 1번) 사이드바를 가리면 본문이 커서 쪽으로 스크롤되어 첫 문단이 화면 밖으로 나간 적이 있다(1화, 커서가 끝에 있을 때) | workspace/workspace-sidebar-hidden-light |
| 9 | (고침: 빈 줄 번호 기준선, 설정 "빈 줄에도 번호 달기") 줄 번호가 문단 사이 빈 줄에도 붙고, 빈 줄 번호가 글자 줄 번호보다 위로 떠 보인다 | workspace/editor-line-numbers-dark |
| 10 | (고침: 일반 판으로 합침) 설정 › 사이드바 판은 항목이 두 개뿐이라 아래가 비어 있다 | settings/settings-sidebar-* |
| 11 | (고침: 스위치를 오른쪽 단축키 칸 옆으로) 설정 › 단축키의 "저장하면서 스냅샷 찍기"만 스위치가 왼쪽에 있다(다른 줄은 오른쪽) | settings/settings-shortcuts-top-* |
| 12 | (고침: 창 탭 끄고 사이드바 가리기·줄 번호 보이기) 보기 메뉴에는 시스템이 넣은 탭 항목(탭 막대 보기 등)만 있다 | menus/menu-view-dark |
| 13 | (고침: 메뉴는 작품 순서대로, 접힌 묶음은 펼침) 회차 메뉴 "이전 회차"가 접힌 묶음 바로 뒤 회차(2화)에서 흐리다. 접힌 묶음 건너뛰기가 의도인지 확인 필요 | menus/menu-episode-dark |

## 찍지 못한 화면

| 화면 | 까닭 |
|---|---|
| 저장 실패 팝오버, 비상 백업 되살리기, 외부 변경 충돌 창, 종료 때 저장 기다림 경고 | 실제로 실패·충돌이 나야 뜬다 |
| 노트 나란히 보기 | 검증 작품에 노트가 없어 열리지 않았다 |
| 스냅샷 "이 스냅샷을 지킬까요?" | 이름 변경 스냅샷의 메모를 고칠 때만 뜬다 |
| 툴팁(마우스를 올리면 뜨는 설명) | 이번에는 시도하지 않았다(마우스를 한동안 올려 두어야 뜸) |
| 라이트: 여러 커서 | 조작이 두 번 실패해 멈췄다(본문에 초점이 가지 않음) |
| 라이트: 스냅샷 메모 창, 사이드바 ⌘Z 확인 창, NovelEditor·보기 메뉴, 마우스 올림, 묶음 접힘, 여러 회차 이름 변경, 검색 빈 상태·결과 없음 | 같은 종류의 라이트 화면(다른 확인 창·메뉴·사이드바·검색)이 있어 줄였다 |
