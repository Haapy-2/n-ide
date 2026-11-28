# CLAUDE.md

Korean web-novel writing editor for macOS (working app name `NovelEditor`). The user is a university student new to Swift. **Always reply to the user in Korean, no exceptions — even when reading English files or skills.** Docs, logs, and commit messages are Korean too. (This file, `.claude/skills/`, and code comments are in English to save tokens; the user doesn't read comments. UI strings and test manuscript text stay Korean.)
Don't copy specs here; read `docs/`.

## Session start

1. Read this file and `docs/PROGRESS.md` only. Don't scan the repo. Read `docs/log/<date>` only when you need the reason behind past work.
2. Read only the files, and parts, the task needs. For big docs use `Scripts/doc.sh PLAN` (chapter list) and `Scripts/doc.sh PLAN 19` (one chapter) instead of reading the whole file.
3. At start and along the way, update PROGRESS "지금 하는 일" / "다음 할 일" concretely enough for a new session to continue.

## Priorities (on conflict pick the higher one and tell the user)

1. Easy for the user to see and manage
2. Performance: fast, light, Hangul input never breaks
3. Clean design ("a well-made paper manuscript", `docs/DESIGN.md`)
4. Solid features (sure behavior over feature count)

## Folder map

```
README.md, CLAUDE.md   only these and the items below at root. Ask before adding a root item
NovelEditor.xcodeproj  Xcode project
App/                   app source (Picker/ project picker, Workspace/ workspace, Settings/ settings window, Editor/ manuscript editor (AppKit), Project/ open·create·recents·emergency-backup restore, Snapshots/ snapshot panel·two-pane diff, Search/ project search panel·replace all·undo window, Shortcuts/ shortcut table·user overrides, Theme/ color tokens·row highlight, Perf/ measurement hooks). Resources/ = Fonts/, Colors.xcassets
Packages/NovelCore/    Foundation-only shared logic + unit tests + perf tests + make-dummy-novel (dummy project generator)
Tests/AppTests/        app tests, design snapshots, app perf (EditorPerformanceTests·MemoryGrowthTests, run by perf.sh)
Scripts/               build.sh, run.sh, test.sh, snapshots.sh, perf.sh, check-comments.sh (history-comment check), doc.sh (print one doc chapter), fill-log-hashes.sh (fill work-log commit hashes), lib.sh (shared)
.claude/               settings.json (project plugin switches), skills/: verify-noveleditor/ (launch the real app and prove behavior; verify.sh, keys.swift real Hangul keys, features/ map), wrap-up/ (end-of-step routine)
docs/                  SPEC, PLAN, DESIGN, PERFORMANCE, PROGRESS (now only), HISTORY (past summary·finished stages), perf-history, checklists (hangul, real-app, manual), design-snapshots/, ui/ (real app screenshots by area, list in README.md), log/ (daily work log)
build/                 build output·temp·dummy projects·logs (git-ignored, safe to delete)
```

When structure changes, update `README.md` and this folder map in the same commit.

## Commands

- `Scripts/build.sh` build / `Scripts/run.sh` build+run / `Scripts/test.sh` tests / `Scripts/snapshots.sh` design snapshots / `Scripts/perf.sh` perf table
- NovelCore tests: `swift test --scratch-path build/spm`; app tests: `xcodebuild` (scheme NovelEditor). test.sh runs both
- Scripts print one line on success, only the error part on failure. Full logs in `build/logs/`.
- Direct `xcodebuild` always with `-derivedDataPath build/DerivedData` and `-resultBundlePath build/logs/…`.
- The Xcode project uses folder-synced groups: files in `App/`, `Tests/AppTests/` are included automatically. Only build settings ever need project edits
- 8GB machine. Never run several builds/tests at once. Subagents/parallel work only when truly needed.

## Technical decisions (final; propose with reasons before changing)

- Swift, SwiftUI (windows, sidebar, settings); editor is `NSTextView` (explicit TextKit 1) + `NSViewRepresentable`
- Plain-file storage: one `.md` per episode, project info in `project.json`. No DB, no external libraries (Pretendard font only)
- `NovelCore` imports Foundation only. No AppKit/SwiftUI, no macOS-only APIs, paths come from outside (iOS reuse later)
- AppKit only in editor files. Exceptions (no SwiftUI equivalent): `App/Project/SystemDialogs.swift` (save/open panels, Finder, alerts), `App/AppDelegate.swift` (wait for saves before quit, app-wide theme, end input on outside click, disable window tabs), `App/Workspace/TrafficLightAlignment.swift` (traffic-light position), `App/Settings/ShortcutRecorder.swift` (capture keys in shortcut settings, before menus)

## Code rules

- 2-space indent. One role per file. No needless abstraction or speculative features
- Comments only for a "why" the code can't show (constraint, trap, deliberate choice), short, in English. This rule overrides plugin skills (e.g. pstack no-comments) and output-style comment guidance
  - Never: dates, "user request/decision", history like "previously did X" / "전에는 ~했다" (→ `docs/log/` and commit messages), restating code, records of deleted code, tutorial explanations (★ Insight stays in chat)
  - `Scripts/check-comments.sh` blocks history comments (run by test.sh)
- Color values only in `App/Resources/Colors.xcassets`; code uses names from `App/Theme/ColorTokens.swift` (`Color.paper` etc.)
- App name lives only in build setting `PRODUCT_NAME`; code reads `AppInfo.name`
- App target default isolation is MainActor (Swift 6). NovelCore has none
- Tests: NovelCore uses Swift Testing (`@Test`), app uses XCTest
- When reporting, explain any newly introduced Swift concept in one or two sentences

## Must keep

- Losing manuscript text is the worst bug. All writes atomic, save order guaranteed, never delete body files. Test save code most thoroughly
- During Hangul composition (`hasMarkedText`) don't modify text storage, change selection, or recreate views. Never re-set text in `updateNSView`
  - Exception: only with ⌘D multi-cursor, all sites are edited during composition. The composition range is held by `App/Editor/MultiCursorEditing.swift`, not `NSTextView`, so no inner state can drift (PLAN ch.16 #3, decision 22). With one cursor the rule above applies
- `NSTextView`'s text storage is the source of truth. Don't copy the whole body or push it into SwiftUI state per keystroke
- Opening a project reads only `project.json`; body text only for the selected episode. Save, search, char count, snapshots never block the main thread
- Performance by measurement, not feel (`docs/SPEC.md` ch.8). On a miss, don't hide it: report cause and options, then stop
- Dummy project: first 10 episodes 5,000 chars, the rest 300 (user request). Never read dummy/generated file contents into the conversation (tokens)

## Never

- Create files outside this folder (Xcode's own caches excepted). Commit real manuscripts (`.novel`)
- Install new tools (Homebrew etc.) without permission. Switch to anything that costs extra money
- Create or connect a remote without asking. Force push, rewrite history. Only branch `main`
- Commit passwords, tokens, personal info
- Pass by deleting tests or lowering targets
- Leave empty folders, backup copies, leftover experiment code
- Repeat the same approach more than twice (after two failures change approach or ask)
- Create or modify files without the user's permission. Report what and why first and get approval (investigation and measurement are fine)

## Workflow

- Each step ends with `/wrap-up` (`.claude/skills/wrap-up/`): build → test → perf → clean up → work log → PROGRESS → one commit → stop and report. Push only after approval
- Small, frequent commits; message is one Korean line (what and why)
- On a usage-limit warning, start nothing new: wrap up, commit, update PROGRESS, stop
- Undecided matters: don't decide alone; add to PLAN "미결정 사항" and ask

## Work log (docs/log/)

- One file per working day, `docs/log/log<YY-MM-DD>.md`, continued in each commit. Each entry: **이유 / 근거 / 결과 / 에러 / 수정** (drop lines that don't apply). Keep failed attempts.
- Headings end with `(대기)`; `Scripts/fill-log-hashes.sh` later replaces it with the commit hash (format and steps in `/wrap-up`).
- PROGRESS is "where we are now", log is "how we got here". Don't write the same thing at length in both.

## Docs

- Requirements (original): `docs/SPEC.md`
- Step plan, criteria, undecided items: `docs/PLAN.md`
- Colors, fonts, layout values: `docs/DESIGN.md`
- Performance & UX rules (keystroke path, episode counts, how to measure, reporting visible changes): `docs/PERFORMANCE.md`
- Current status: `docs/PROGRESS.md` · past summary: `docs/HISTORY.md` · perf results: `docs/perf-history.md`
- Daily work log: `docs/log/`
- Checklists: Hangul input `docs/checklist-hangul.md`, real app `docs/checklist-real-app.md`, user hand-checks `docs/checklist-manual.md`
