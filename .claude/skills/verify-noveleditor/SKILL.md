---
name: verify-noveleditor
description: Launch NovelEditor (macOS Korean web-novel editor) for real, drive it like a user, and prove behavior with screenshots and on-disk files. Use when an editor/episode/snapshot/settings change passes tests but must be confirmed in the real app.
---

# NovelEditor verification

Launch the real app (Debug build) on a small verification project, drive it like a user with computer-use `app_*` tools, then prove the result with the screen and the `.md` files on disk. Helper: `verify.sh` in this folder. Report to the user in Korean.

## Launch

```bash
.claude/skills/verify-noveleditor/verify.sh launch
```

- **Run outside the sandbox** (Bash with sandbox disabled) — launch, cleanup, and `keys` alike. An app launched inside the sandbox dies when the command ends, and `keys` can't reach it.
- Refuses if NovelEditor is already running. It may be the user's: never kill it, ask the user.
- What it does: backs up user defaults (`com.haapy2.NovelEditor`) to `build/verify/defaults-backup.plist` → `Scripts/build.sh` → creates `build/verify/run/검증 작품.novel` (3 episodes, ~300 chars each) → launches with `NOVEL_PERF_OPEN` so the picker is skipped. pid in `build/verify/run/app.pid`.
- Ready when: `request_access` with `com.haapy2.NovelEditor`, then `app_screenshot` shows `1화 2화 3화` in the sidebar and the body (AXTextArea) on the right.

## Doctor

```bash
.claude/skills/verify-noveleditor/verify.sh doctor
```

Read-only. Checks our pid is alive, no other NovelEditor runs, the binary is this repo's build, no `App/` source changed after the build, and the project and defaults backup exist. If it prints `→ 조작하지 말 것`, fix and rerun. Run it first whenever something looks off.

## Drive

Background computer-use tools only; never take the user's screen unless a step below says so.

- Screen/elements: `app_screenshot` (scale 0.5 is enough). Find targets by AX titles: episode rows `AXButton "1화"`, char count `AXButton "296"`, body `AXTextArea`, toolbar `"새 회차"`, `"사이드바 가리기"`, `"작품 전체 검색"`.
- Cursor at end of body: `app_click` the empty area below the last line → result says `moved to end of text`. Then `app_type`.
- Use `app_menu` for commands, not shortcuts (the user may have remapped them). Top menus: `NovelEditor 파일 편집 보기 회차 윈도우 도움말`.
  - 파일: `지금 저장`, `스냅샷 찍기`, `스냅샷 보기…`, `작품 전환…`
  - 회차: `새 회차`, `이전 회차`, `다음 회차`, `이름 변경…`, `휴지통으로 이동…`, `목표 글자 수…`
- Clicking a sidebar episode row with `app_click` does not switch episodes; use the 회차 menu.
- Background `app_drag` (finishes within ~1s) does not start a list drag. For sidebar drag-and-drop use full-screen control: press, move slowly, release.
- Per-feature paths and proof criteria: follow the map in `features/README.md`. If a feature has several entry points, don't stop after one.

## Evidence

```bash
.claude/skills/verify-noveleditor/verify.sh evidence <name>
```

Copies the project's `episodes/*.md` and `project.json` to `build/verify/evidence/<time>-<name>/`. Cleanup keeps this folder.

Proof rules:
- Use real user paths: clicks, typing, menus. No internal calls or test-only hooks (`NOVEL_PERF_OPEN` only skips the picker).
- Keep before and after: `app_screenshot` before, `app_screenshot` after, plus disk files.
- Don't trust the screen alone. Confirm saves with `grep <marker> "build/verify/run/검증 작품.novel/episodes/"*.md`. Mix an easy marker like `VERIFY01` into typed text.
- Never read body text into the conversation (CLAUDE.md: no dummy content). Use `grep -c` / `grep -o` on the marker only.
- `screencapture` fails here (no screen-recording permission). Use `app_screenshot` results as screen evidence and state what you saw.

## Cleanup

```bash
.claude/skills/verify-noveleditor/verify.sh cleanup
```

- Kills only the pid in `app.pid` (never by name). Press `파일 > 지금 저장` first so it quits without waiting on saves.
- Restores user defaults from the backup, deletes the backup and `build/verify/run/`. Keeps `build/verify/evidence/`.
- Finally `app_release`.
- Always clean up, even after a failed attempt — otherwise the next launch refuses ("already running") and user defaults stay at verification values.

## Hangul composition (real key codes)

Running the real 2-set Korean IME needs system key codes. It briefly takes the user's screen, so only when needed. Run the `osascript` activate and `keys` outside the sandbox.

On a Korean keyboard layout, computer-use `cmd+<letter>` sends key code 0 and fires the wrong shortcut (`cmd+d` arrived as ⌘A and selected all). Use `app_menu` for menu commands, and `keys` for others (e.g. ⌘D is `c2`).

1. Build the tool: `xcrun swiftc -O .claude/skills/verify-noveleditor/keys.swift -o build/verify/keys`
2. Cursor at body end (`app_click`), `request_full_control`, bring app forward: `osascript -e 'tell application id "com.haapy2.NovelEditor" to activate'`
3. Send keys: `build/verify/keys 14,4,2,11,1,49` (= "도윤 "). 2-set codes: ㄱ 15(r) ㄴ 1(s) ㄷ 14(e) ㅇ 2(d) ㅏ 40(k) ㅗ 4(h) ㅠ 11(b) space 49 ⌫ 51 return 36. ⌘Z `c6`, ⇧⌘Z `cs6`. Re-activate the app before every ⌘ key.
4. Check with `app_zoom` (background) and disk files. Then `release_full_control`.
- The IME remembers a mode per app (marked text vs. replace without marked text, PLAN ch.16 #5). If results look odd, check which mode was active first.

## Can't do

- computer-use `app_type`/`key` can't reproduce IME composition (inserts finished syllables or key code 0). Use the Hangul section above.
- Never run two instances; they share one defaults store and overwrite each other.
- Don't measure performance with this skill. Use `Scripts/perf.sh`.
