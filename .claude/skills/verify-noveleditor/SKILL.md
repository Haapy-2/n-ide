---
name: verify-noveleditor
description: NovelEditor(macOS 한국어 웹소설 편집기)를 사용자처럼 실제로 띄워 조작하고, 화면과 디스크 파일로 동작을 증명한다. 편집기·회차·스냅샷·설정 변경이 "테스트는 통과하지만 실제 앱에서도 되는지" 확인할 때 쓴다.
---

# NovelEditor 검증

실제 앱(Debug 빌드)을 작은 검증 작품으로 띄우고, computer-use의 `app_*` 도구로 사용자처럼 조작한 뒤, 화면과 디스크의 `.md` 파일로 결과를 증명한다. 도우미는 같은 폴더의 `verify.sh`.

## 실행 (Launch)

```bash
.claude/skills/verify-noveleditor/verify.sh launch
```

- **샌드박스 밖에서 실행한다**(Bash 도구의 샌드박스 끄기). launch·cleanup·`keys` 모두. 샌드박스 안에서 띄운 앱은 명령이 끝나면 꺼지고, `keys`도 앱에 닿지 않는다.
- NovelEditor가 이미 켜져 있으면 거부한다. 사용자 것일 수 있으니 절대 끄지 말고 사용자에게 묻는다.
- 하는 일: 사용자 설정(UserDefaults `com.haapy2.NovelEditor`)을 `build/verify/defaults-backup.plist`로 백업 → `Scripts/build.sh` → `build/verify/run/검증 작품.novel`(3회차, 각 약 300자) 생성 → `NOVEL_PERF_OPEN`으로 작품 선택 창을 건너뛰고 그 작품을 바로 연 앱 실행. pid는 `build/verify/run/app.pid`.
- 준비 완료: `request_access`에 `com.haapy2.NovelEditor`를 넣고 `app_screenshot`. 사이드바에 `1화 2화 3화`, 오른쪽에 본문(AXTextArea)이 보이면 쓸 수 있다.

## 점검 (Doctor)

```bash
.claude/skills/verify-noveleditor/verify.sh doctor
```

읽기만 한다. 우리 pid가 살아 있는지, 다른 NovelEditor가 없는지, 실행 파일이 이 저장소 빌드인지, 빌드 뒤에 `App/` 소스가 바뀌지 않았는지, 검증 작품과 설정 백업이 있는지 확인한다. `→ 조작하지 말 것`이 나오면 고치고 다시 실행한다. 이상하면 언제든 먼저 이것을 돌린다.

## 조작 (Drive)

computer-use 백그라운드 도구만 쓴다. 사용자 화면을 빼앗지 않는다.

- 화면·요소: `app_screenshot`(scale 0.5면 충분). AX 요약의 제목으로 대상을 찾는다. 회차 줄은 `AXButton "1화"`, 글자 수 `AXButton "296"`, 본문 `AXTextArea`, 툴바 `"새 회차"`, `"사이드바 가리기"`, `"작품 전체 검색"`.
- 본문 끝에 커서: 본문 영역의 마지막 줄 아래 빈 곳을 `app_click` → 결과에 `moved to end of text`가 뜬다. 그 자리에서 `app_type`.
- 메뉴 명령은 단축키 대신 `app_menu`로 누른다(사용자가 단축키를 바꿨을 수 있음). 최상위 메뉴: `NovelEditor 파일 편집 보기 회차 윈도우 도움말`.
  - 파일: `지금 저장`, `스냅샷 찍기`, `스냅샷 보기…`, `작품 전환…`
  - 회차: `새 회차`, `이전 회차`, `다음 회차`, `이름 변경…`, `휴지통으로 이동…`, `목표 글자 수…`
- 기능별 경로와 증명 기준은 `features/README.md`의 지도를 따른다. 지도에 있는 진입로가 여럿이면 하나만 해 보고 끝내지 않는다.

## 증거 (Evidence)

```bash
.claude/skills/verify-noveleditor/verify.sh evidence <이름>
```

검증 작품의 `episodes/*.md`와 `project.json`을 `build/verify/evidence/<시각>-<이름>/`에 복사한다. 이 폴더는 정리 때 지우지 않는다.

증명 기준:
- 실제 사용자 경로로 한다: 클릭, 입력, 메뉴. 내부 함수 호출이나 테스트 전용 갈고리는 쓰지 않는다(`NOVEL_PERF_OPEN`은 작품 선택 창을 건너뛰는 데만 쓴다).
- 행동 전과 후를 모두 남긴다: 조작 전 `app_screenshot`, 조작 후 `app_screenshot`, 그리고 디스크 파일.
- 화면만 믿지 않는다. 저장은 `grep <표시 문구> "build/verify/run/검증 작품.novel/episodes/"*.md`로 디스크에 실제로 있는지 확인한다. 입력할 때는 `VERIFY01`처럼 찾기 쉬운 표시 문구를 섞는다.
- 본문 내용을 통째로 대화에 읽지 않는다(CLAUDE.md: 더미 내용 읽기 금지). `grep -c`나 `grep -o`로 표시 문구만 확인한다.
- `screencapture`는 이 Mac에서 화면 기록 권한이 없어 실패한다. 화면 증거는 `app_screenshot` 결과(대화에 남음)를 쓰고, 무엇을 봤는지 보고에 적는다.

## 정리 (Cleanup)

```bash
.claude/skills/verify-noveleditor/verify.sh cleanup
```

- `app.pid`에 적힌 우리 프로세스만 끈다(이름으로 끄지 않음). 끄기 전에 `파일 > 지금 저장`을 눌러 두면 저장 대기 없이 바로 꺼진다.
- 사용자 설정을 백업에서 되돌리고 백업을 지운다. `build/verify/run/`(검증 작품)을 지운다. `build/verify/evidence/`는 남는다.
- 마지막으로 `computer-use`의 `app_release`.
- 실패한 시도 뒤에도 반드시 cleanup을 돌린다. 안 그러면 다음 launch가 "이미 켜져 있음"으로 거부되고, 사용자 설정이 검증 값으로 남는다.

## 한글 조합 확인 (실제 키 코드)

두벌식 입력기를 실제로 돌리려면 키 코드를 시스템에 보내야 한다. 사용자 화면을 잠시 빼앗으므로 꼭 필요할 때만. 앱을 앞으로 가져오는 `osascript`와 `keys`는 샌드박스 밖에서 돌린다.

한글 자판에서는 컴퓨터 유스 `cmd+글자`가 키 코드 0으로 가서 엉뚱한 단축키가 된다(`cmd+d`가 ⌘A로 들어가 본문 전체가 골라짐). 메뉴에 있는 명령은 `app_menu`로, 없는 단축키는 `keys`(예: ⌘D는 `c2`)로 누른다.

1. 도구 빌드: `xcrun swiftc -O .claude/skills/verify-noveleditor/keys.swift -o build/verify/keys`
2. 본문 끝에 커서(`app_click`), `request_full_control`, 앱을 앞으로: `osascript -e 'tell application id "com.haapy2.NovelEditor" to activate'`
3. 키 보내기: `build/verify/keys 14,4,2,11,1,49`(= "도윤 "). 두벌식 키 코드: ㄱ 15(r) ㄴ 1(s) ㄷ 14(e) ㅇ 2(d) ㅏ 40(k) ㅗ 4(h) ㅠ 11(b) 공백 49 ⌫ 51 엔터 36. ⌘Z `c6`, ⇧⌘Z `cs6`. ⌘가 든 키 앞에는 매번 앱을 앞으로 다시 가져온다.
4. 확인은 `app_zoom`(백그라운드)과 디스크 파일. 끝나면 `release_full_control`.
- 입력기는 앱마다 방식(표시된 글자 없이 바꾸기 / 표시된 글자)을 기억하고 바꾼다(PLAN 16장 5번). 결과가 이상하면 어느 방식이었는지부터 본다.

## 할 수 없는 것

- 컴퓨터 유스의 `app_type`·`key`로는 한글 조합(IME)을 재현하지 못한다(완성 글자를 바로 넣거나 키 코드가 0). 아래 "한글 조합 확인"을 쓴다.
- 동시에 두 인스턴스를 띄우지 않는다. 설정 저장소가 하나라 서로 덮는다.
- 성능 수치는 이 스킬로 재지 않는다. `Scripts/perf.sh`를 쓴다.
