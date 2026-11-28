---
name: wrap-up
description: Finish a NovelEditor work step — test, measure, clean up, write the day's work log and PROGRESS, commit once, then stop and report. Use at the end of every step/fix/experiment (CLAUDE.md "Workflow"), when the user says 마무리/커밋/정리해줘, or before stopping on a usage-limit warning.
---

# Wrap up a step

All files you write here (log, PROGRESS, commit message) are in **Korean**. Keep each step's output short; scripts already print one-line summaries (full logs in `build/logs/`).

## 1. See what changed

`git status --short` and `git diff --stat`. Decide the kind:
- **code** — anything in `App/`, `Packages/NovelCore/`, `Tests/`
- **docs/scripts only** — `docs/`, `Scripts/`, `.claude/`, `README.md`, `CLAUDE.md`

## 2. Verify

- code: `Scripts/test.sh` (runs the comment check, NovelCore + app tests, iOS build of NovelCore). On failure: fix, don't delete tests or lower targets. Same approach failing twice → change approach or ask.
- code touching the keystroke path, saving, search, snapshots, episode switching, sidebar, launch: also `Scripts/perf.sh`. Any miss → report cause and options and **stop** (CLAUDE.md).
- docs/scripts only: `Scripts/check-comments.sh` if scripts changed; otherwise nothing. Say in the report that tests were skipped and why.
- Never run two builds/tests at once (8GB machine).

## 3. Clean up

No empty folders, backup copies, leftover experiment code, debug prints. `build/` is disposable and git-ignored. If folder structure changed, update the folder map in both `README.md` and `CLAUDE.md` in this same commit.

## 4. Work log — `docs/log/log<YY-MM-DD>.md`

1. First run `Scripts/fill-log-hashes.sh`: it replaces earlier `(대기)` headings with their commit hash, so those fixes ride along in this commit (no separate hash commit).
2. Create today's file if missing, first line `# YYYY-MM-DD 작업 기록`.
3. Append one entry. Heading ends with ` (대기)` — the hash is filled by the next run of step 4.1:

```markdown
## <무엇을 했나, 한 줄> (대기)

- **이유**: 왜 했나(사용자 말은 따옴표로)
- **근거**: 무엇을 보고 정했나(SPEC·PLAN 장, 측정값, 조사 결과)
- **결과**: 무엇이 바뀌었나, 테스트·측정 수치
- **에러**: 빌드·테스트 실패, 효과 없던 시도(지우지 않는다)
- **수정**: 어떻게 고쳤나
```

Drop lines that don't apply. Don't repeat what PROGRESS says.

## 5. PROGRESS and friends

- `docs/PROGRESS.md`: rewrite "지금 하는 일" / "다음 할 일" so a fresh session can continue from them alone; update "지금 상태" lines that changed; fix "알려진 문제" (remove fixed items). Add one row at the top of "최근 끝낸 일" and move the 6th-oldest row to the top of "날짜별" in `docs/HISTORY.md`. Keep PROGRESS small — it is read every session.
- Finished a stage → add a row to "끝난 단계" in `docs/HISTORY.md`.
- Ran perf.sh → add a dated note to `docs/perf-history.md` (update its table only if values changed) and the one-line summary in PROGRESS "지금 상태".
- User hand-checks to do → `docs/checklist-manual.md`.

## 6. Commit (once)

```bash
git add -A && git commit -m "<한국어 한 줄: 무엇을 왜>" -m "Co-Authored-By: <attribution line from the system reminder>"
```

Branch is `main`. Never push without approval; no force push.

## 7. End of the day

When the user ends the session or the day, if `Scripts/fill-log-hashes.sh` would still fill something (the last entry's `(대기)`), run it and commit once: `작업 기록 해시 채움`.

## 8. Stop and report (Korean)

Short: what changed, test/perf one-liners (or why skipped), commit hash, what's next. Explain any new Swift concept in one or two sentences. Then wait.
