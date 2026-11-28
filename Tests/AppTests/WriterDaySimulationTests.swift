import AppKit
import NovelCore
import SwiftUI
import XCTest
@testable import NovelEditor

/// A writer's day: runs a serializing writer using the workspace (`WorkspaceView`) for a day, following a script (`Step` table).
/// Each step checks what the writer sees (editor text, caret, scroll position, keyboard focus, save state, snapshots), and after every step
/// every episode's disk body is compared against what the writer wrote. Steps carry over the previous step's state.
///
/// The test window can't become key (the app doesn't come to the front), so clicks, menus, toolbar and dialogs don't reach it. So episode selection
/// uses sidebar ↑↓, and ⌘N, renaming and sidebar actions call the `ProjectModel` functions those commands invoke.
@MainActor
final class WriterDaySimulationTests: XCTestCase {
  private var day: WriterDay!

  /// Runs as a synchronous test: AppKit manipulation happens on the main thread outside any Task, like real events, and the app's async functions
  /// are launched in separate Tasks while spinning the run loop (`WriterDay.run`). An Objective-C exception inside such a Task unwinds past the Task,
  /// leaving the main thread marked as running it, and at test end the test app dies with a Swift concurrency allocator error.
  /// So sidebar actions that create undo records must be called via `sidebar {}` (which opens a group).
  func testWriterDay() throws {
    day = try WriterDay.start()
    defer {
      day.end()
      day = nil
    }
    for step in script {
      do {
        try day.perform(step)
      } catch {
        XCTFail("[\(step.name)] 멈춤: \(error)")
        break
      }
    }
    // Known hitches don't count as failures, so they're logged.
    for line in day.knownBreaks { print("알려진 끊김 \(line)") }
  }

  // MARK: - Script

  private var script: [Step] {
    [
      Step("1. 작품 열기") { day in
        try day.openWorkspace()
      } check: { day in
        day.see(day.openEpisode, day.ep2, "지난번 마지막에 본 2화가 열린다")
        day.see(day.editor.string, day.expected[day.ep2], "편집기에 2화 본문")
        try day.waitFor("기억한 커서·화면 위치로 돌아온다") { day.isAt(day.seededPlace) }
        day.ok(day.editorHasFocus, "바로 쓸 수 있게 키보드 초점이 편집기")
      },

      Step("2. 이어 쓰기와 지금 저장") { day in
        try day.type(" 비가 다시 내렸다.", .marked)
        try day.type(" 도윤이 웃었다.", .replacing)
        try day.saveNow()
        day.see(try day.disk(day.ep2), day.editor.string, "⌘S 뒤 디스크에 지금 글")
        try day.type(" 그리고 걸었다.", .marked)
        try day.waitFor("멈추고 1초쯤 뒤 자동 저장") {
          (try? day.disk(day.ep2)) == day.editor.string && day.model.autosaver.status == .idle
        }
      } check: { day in
        day.ok(day.editorHasFocus, "치는 동안 초점은 편집기")
        day.see(day.model.autosaver.status, .idle, "저장 상태는 평소")
      },

      Step("3. 새 회차 만들고 이름 붙여 바로 쓰기") { day in
        try day.sidebar { day.newEpisode = try await day.model.addEpisode(after: day.ep2, undoManager: day.sidebarUndo) }
        day.expected[day.newEpisode] = ""
        try day.pick(day.newEpisode)
        try day.sidebar { await day.model.renameEpisodes([day.newEpisode: "새벽의 손님"], reason: .single, undoManager: day.sidebarUndo) }
        day.knownBreak("findings 1·14: 새 회차를 고르고 이름을 바꾼 뒤 키보드 초점이 편집기가 아니다(⌘N·⇧⌘R 길은 테스트 창에서 닿지 않아 사이드바 길)", fixedWhen: day.editorHasFocus)
        day.clickEditor()
        try day.type("새벽에 손님이 왔다.", .marked)
      } check: { day in
        day.see(day.openEpisode, day.newEpisode, "새 회차가 열려 있다")
        day.see(day.model.episodes.map(\.title), ["1화", "2화", "새벽의 손님", "3화"], "2화 바로 뒤에 새 이름으로")
        day.see(day.editor.string, "새벽에 손님이 왔다.", "새 회차에 쓴 글만 있다")
      },

      Step("4. 앞 회차를 봤다가 돌아오기") { day in
        let back = day.editor.viewState()
        day.marks = [try day.snapshotIDs(day.newEpisode), try day.snapshotIDs(day.ep2)]
        let left = try XCTUnwrap(day.places[day.ep2], "[\(day.stepName)] 2화를 떠날 때 자리")
        try day.pick(day.ep2)
        day.clickEditor()
        try day.waitFor("2화는 떠날 때 자리로") { day.isAt(left) }
        try day.pick(day.newEpisode)
        day.clickEditor()
        try day.waitFor("새 회차도 떠날 때 자리로") { day.isAt(back) }
      } check: { day in
        try day.run { await day.model.autosaver.snapshots.waitForWrites() }
        let left = try day.newSnapshots(day.newEpisode, since: day.marks[0])
        day.see(left.map(\.kind), [.leave], "고친 회차를 떠날 때 스냅샷 하나")
        day.see(try left.first.map(day.store.readSnapshot), day.expected[day.newEpisode], "스냅샷은 떠날 때 글")
        day.see(try day.newSnapshots(day.ep2, since: day.marks[1]).count, 0, "훑어보기만 한 회차는 스냅샷 없음")
      },

      Step("6. 작품 전체 바꾸기와 되돌리기") { day in
        let before = try day.diskBytes()
        let replace = day.makeReplace()
        replace.replacement = "서준"
        try day.run { await replace.prepare(query: "민준", caseSensitive: false) }
        let pending = try XCTUnwrap(replace.pending, "[\(day.stepName)] 바꿀 곳을 센다")
        day.see(pending.plan.count, 5, "1화 셋, 2화 둘")
        _ = try day.run { await replace.confirm(pending) }
        try day.run { await day.model.autosaver.flush() }
        for (id, text) in day.expected {
          day.see(try day.disk(id), text.replacingOccurrences(of: "민준", with: "서준"), "바꾼 뒤 디스크: \(day.title(id))")
        }
        let found = try day.run { await replace.latestUndoable() }
        let undoable = try XCTUnwrap(found, "[\(day.stepName)] 되돌릴 바꾸기")
        _ = try day.run { await replace.revert(undoable.record, Set(undoable.candidates.map(\.id))) }
        try day.run { await day.model.autosaver.flush() }
        for (id, bytes) in before {
          day.see(try day.diskData(id), bytes, "되돌리면 바꾸기 전과 바이트까지 같다: \(day.title(id))")
        }
      } check: { day in
        day.see(day.editor.string, day.expected[day.newEpisode], "열린 회차도 원문")
      },

      Step("7. ⌘D 여러 커서로 세 곳 고치기") { day in
        try day.pick(day.ep3)
        day.clickEditor()
        let original = day.editor.string
        day.marks = [try day.snapshotIDs(day.ep3)]
        let word = (original as NSString).range(of: "늑대")
        day.editor.setSelectedRange(NSRange(location: word.location + 1, length: 0))
        for _ in 0..<3 { day.key { day.editor.selectNextOccurrence(nil) } }
        day.see(day.editor.multiCursorRanges?.count, 3, "같은 말 세 곳")
        try day.type("범", .replacing)
        let edited = original.replacingOccurrences(of: "늑대", with: "범")
        day.see(day.editor.string, edited, "세 곳이 함께 바뀐다")
        try day.saveNow()
        day.see(try day.disk(day.ep3), edited, "디스크에도 세 곳")
        // ⌘Z closes the group opened by the event first. Called inside a group opened by `key`, a manager with groupsByEvent off throws.
        day.editor.undo(nil)
        day.see(day.editor.string, original, "⌘Z 한 번에 세 곳이 돌아온다")
        day.key { day.editor.doCommand(by: #selector(NSResponder.cancelOperation(_:))) }
        day.see(day.editor.multiCursorRanges, nil, "esc로 커서 하나")
        day.expected[day.ep3] = original
      } check: { day in
        try day.run { await day.model.autosaver.snapshots.waitForWrites() }
        let taken = try day.newSnapshots(day.ep3, since: day.marks[0])
        day.see(taken.map(\.kind), [.multiCursor], "'여러 커서 전' 스냅샷 하나")
        day.see(try taken.first.map(day.store.readSnapshot), day.expected[day.ep3], "여러 커서 전 글")
      },

      Step("8. 스냅샷 찍고 크게 고친 뒤 되돌리기") { day in
        let kept = try day.run { try await day.model.autosaver.takeManualSnapshot() }
        let snapshot = try XCTUnwrap(kept, "[\(day.stepName)] 직접 스냅샷")
        let original = day.editor.string
        day.marks = [try day.snapshotIDs(day.ep3)]
        day.editor.selectAll(nil)
        try day.type("전부 다시 쓴다.", .replacing)
        try day.saveNow()
        day.see(try day.disk(day.ep3), "전부 다시 쓴다.", "고쳐 쓴 글이 저장된다")

        let panel = try XCTUnwrap(day.model.autosaver.beginPanel(), "[\(day.stepName)] 스냅샷 판 열기")
        day.ok(panel.hadFocus, "판을 열 때 편집기에 초점이 있었다")
        let browser = SnapshotBrowser(
          store: day.store, episodeID: day.ep3, currentText: panel.text, currentTitle: day.title(day.ep3))
        try day.run { await browser.load() }
        browser.select(snapshot.id)
        try day.waitFor("비교가 끝난다") { browser.canRestore }
        let restored = try day.run { await browser.restoreSelected(with: day.model.autosaver) { _ in } }
        day.ok(restored, "되돌렸다")
        day.model.autosaver.endPanel(hadFocus: panel.hadFocus)
        day.see(day.editor.string, original, "본문이 스냅샷과 같다")
        day.expected[day.ep3] = original
      } check: { day in
        day.ok(day.editorHasFocus, "판을 닫으면 초점이 편집기로")
        try day.run { await day.model.autosaver.snapshots.waitForWrites() }
        let taken = try day.newSnapshots(day.ep3, since: day.marks[0])
        day.see(taken.map(\.kind), [.restore], "'복원 전' 스냅샷")
        day.see(try taken.first.map(day.store.readSnapshot), "전부 다시 쓴다.", "되돌리기 전 글이 남는다")
      },

      Step("9. 순서 바꾸기·묶기·휴지통 뒤 ⌘Z") { day in
        let order = day.model.episodes.map(\.id)
        let undo = day.sidebarUndo
        try day.sidebar { await day.model.moveEpisodes(rows: [3], before: 0, undoManager: undo) }
        day.see(day.model.episodes.map(\.title), ["3화", "1화", "2화", "새벽의 손님"], "3화를 맨 위로")
        try day.sidebar { _ = await day.model.groupEpisodes([day.ep1, day.ep2], title: "1부", undoManager: undo) }
        try day.sidebar { try await day.model.trashEpisode(day.newEpisode, undoManager: undo) }
        day.ok(!day.fileExists(day.newEpisode), "휴지통으로 간 회차 파일은 회차 폴더에 없다")
        try day.run { await day.model.finishProjectSaves() }
        try day.verifyListOnDisk()
        // Sidebar ⌘Z goes through the confirmation one press at a time. The next is pressed after the previous undo's file move finishes.
        for _ in 0..<3 {
          undo.undo()
          try day.run { await day.model.finishFileUndos() }
        }
        day.see(day.model.episodes.map(\.id), order, "⌘Z 세 번이면 처음 순서")
        day.see(day.model.project.groups, [], "묶음도 풀린다")
      } check: { day in
        day.ok(day.fileExists(day.newEpisode), "휴지통에서 돌아온다")
        day.see(day.openEpisode, day.ep3, "보던 회차 그대로")
      },

      Step("12. 다른 편집기가 회차를 고침") { day in
        day.marks = [try day.snapshotIDs(day.ep3)]
        let text = try XCTUnwrap(day.expected[day.ep3])
        let inside = (text as NSString).range(of: "3화의 40번째").location
        day.editor.setSelectedRange(NSRange(location: inside, length: 0))
        let added = "바깥에서 넣은 첫 줄.\n"
        let outside = added + text
        try day.writeOutside(outside, to: day.ep3)
        day.returnToApp()
        try day.waitFor("앱 쪽 변경이 없으면 바깥 글로") { day.editor.string == outside }
        day.expected[day.ep3] = outside
        day.knownBreak("findings 3: 바깥 글로 갈아 끼우면 커서가 숫자 자리에 남아 다른 글자 앞으로 밀린다", fixedWhen: day.editor.selectedRange().location == inside + (added as NSString).length)
        let reloaded = try day.newSnapshots(day.ep3, since: day.marks[0])
        day.knownBreak("findings 3: 말없이 불러와 그 전 글로 돌아갈 스냅샷이 없다", fixedWhen: !reloaded.isEmpty)

        day.marks = [try day.snapshotIDs(day.ep3)]
        try day.type(" 앱에서 쓴 글.", .replacing)
        let mine = day.editor.string
        try day.writeOutside(outside + "\n바깥 두 번째.", to: day.ep3)
        day.returnToApp()
        try day.waitFor("양쪽 다 바뀌면 충돌로 묻는다") { day.model.autosaver.conflicts[day.ep3]?.isReady == true }
        try day.run { await day.model.autosaver.keepAppVersion(day.ep3) }
        day.see(day.editor.string, mine, "앱 쪽을 고르면 편집기 글 그대로")
      } check: { day in
        day.see(day.model.autosaver.conflicts.isEmpty, true, "충돌을 골랐다")
        try day.run { await day.model.autosaver.snapshots.waitForWrites() }
        let kinds = try day.newSnapshots(day.ep3, since: day.marks[0]).map(\.kind)
        day.ok(kinds.contains(.conflict), "앱 쪽 글을 충돌 스냅샷으로 남긴다: \(kinds)")
        day.ok(kinds.contains(.external), "덮은 바깥 글도 남긴다: \(kinds)")
      },

      Step("13. 앱을 끄고 다시 열기") { day in
        try day.type(" 끄기 직전 문장.", .marked)
        let place = day.editor.viewState()
        day.ok(day.model.autosaver.hasWorkBeforeQuit, "끄기 전에 마칠 일이 있다")
        try day.run { await day.model.autosaver.finish() }
        day.ok(!day.model.autosaver.hasWorkBeforeQuit, "종료 전 저장 대기가 다 마친다")
        for (id, text) in day.expected { day.see(try day.disk(id), text, "끄기 전 디스크: \(day.title(id))") }
        try day.closeWorkspace()
        try day.openWorkspace()
        try day.waitFor("같은 회차·커서·화면으로 다시 열린다") { day.openEpisode == day.ep3 && day.isAt(place) }
      } check: { day in
        day.ok(day.editorHasFocus, "다시 열면 초점이 편집기")
        day.see(day.editor.string, day.expected[day.ep3], "끄기 직전 문장까지")
      },

      Step("14. 저장이 막힌 채 계속 쓰기") { day in
        try day.blockEpisodeFolder(true)
        let saved = try day.disk(day.ep3)
        try day.type(" 막힌 동안 쓴 문장.", .replacing)
        try day.saveNow()
        guard case .failed = day.model.autosaver.status else { return XCTFail("[\(day.stepName)] 저장 실패가 보인다") }
        try day.run { await day.model.autosaver.waitForBackups() }
        day.see(day.backup.entries(for: [day.ep3]).map(\.text), [day.editor.string], "작품 밖 비상 백업에 실제로 써졌다")
        day.see(try day.disk(day.ep3), saved, "디스크의 원고는 그대로(사라지지 않음)")
        try day.type(" 그래도 계속 쓴다.", .marked)
        try day.saveNow()
        try day.run { await day.model.autosaver.waitForBackups() }
        day.see(day.backup.entries(for: [day.ep3]).map(\.text), [day.editor.string], "백업도 마지막 글로")
        day.ok(day.model.autosaver.unprotectedAreBackedUp, "상태 줄은 '백업해 두었어요'")
        try day.blockEpisodeFolder(false)
        try day.saveNow()
        try day.run { await day.model.autosaver.waitForBackups() }
      } check: { day in
        day.see(try day.disk(day.ep3), day.editor.string, "권한이 돌아오면 저장된다")
        day.see(day.backup.entries(for: [day.ep3]).count, 0, "저장되면 백업을 지운다")
      },
    ]
  }
}

// MARK: - One script line

/// One script line: what the writer does (`act`) and what to check on screen and disk afterwards (`check`).
/// After each step, `WriterDay.perform` also checks every episode's disk body, the list, save state and main-thread time.
@MainActor
private struct Step {
  let name: String
  let act: (WriterDay) throws -> Void
  let check: (WriterDay) throws -> Void

  init(_ name: String, act: @escaping (WriterDay) throws -> Void, check: @escaping (WriterDay) throws -> Void) {
    self.name = name
    self.act = act
    self.check = check
  }
}

// MARK: - Writer's day state

/// State lasting all day: the project, open window, and what the writer wrote (`expected`, the answer compared against disk).
@MainActor
private final class WriterDay {
  enum Input {
    /// Displayed-text (underlined) mode: compose with `setMarkedText`, commit with `insertText`
    case marked
    /// 2-set (macOS 27) continuing composition without displayed text via "replace the previous character with this" (`replacementRange`)
    case replacing
  }

  enum Work: String {
    case key = "키 입력"
    case switchEpisode = "회차 전환"
    case saveStart = "저장 시작"
  }

  /// Fails if a single main-thread chunk takes longer than this (generous since it's a Debug build).
  static let mainThreadLimit: Duration = .milliseconds(50)

  let folder: URL
  let store: ProjectStore
  let backup: EmergencyBackup
  let ep1: EpisodeID
  let ep2: EpisodeID
  let ep3: EpisodeID
  var newEpisode: EpisodeID!
  var expected: [EpisodeID: String] = [:]
  /// Episode 2 position left "last time" for the first step
  let seededPlace: EpisodeViewState
  /// Position seen when leaving an episode via the sidebar (must be restored on return)
  var places: [EpisodeID: EpisodeViewState] = [:]
  /// Snapshot list for before/after comparison within a step
  var marks: [[String]] = []
  private(set) var model: ProjectModel!
  private(set) var window: NSWindow?
  private(set) var editor: ManuscriptTextView!
  /// Undo history for sidebar actions (the workspace receives the window's history)
  let sidebarUndo: UndoManager
  private(set) var stepName = ""
  /// Known hitches met during this day (for reporting)
  private(set) var knownBreaks: [String] = []
  private var samples: [(Work, Duration)] = []
  private var savedSettings: [String: Any] = [:]
  private let clock = ContinuousClock()
  /// Fixed so the screen is the same regardless of user settings (the test app reads the real app settings).
  private static let pinnedSettings: [String: Any] = [
    AppSettingKey.multiCursorEnabled: true, AppSettingKey.collapsedEpisodeGroups: "",
  ]

  private init(folder: URL, store: ProjectStore, ids: [EpisodeID], seededPlace: EpisodeViewState) {
    self.folder = folder
    self.store = store
    backup = EmergencyBackup(folder: folder.appending(path: "Backups"))
    ep1 = ids[0]
    ep2 = ids[1]
    ep3 = ids[2]
    self.seededPlace = seededPlace
    sidebarUndo = UndoManager()
    sidebarUndo.groupsByEvent = false
  }

  /// A serialized project (episodes 1–3, 60 paragraphs each) and the remembered position "closed while viewing episode 2 last time".
  static func start() throws -> WriterDay {
    let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let folder = repo.appending(path: "build/tmp/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder.appending(path: "휴지통"), withIntermediateDirectories: true)
    let store = try ProjectStore.create(at: folder.appending(path: "작품.novel"), title: "회귀한 검성")
    var project = try store.loadProject()
    let extras: [[Int: String]] = [
      [10: "민준은 칼을 들었다.", 20: "민준이 웃었다.", 30: "그날 민준은 돌아오지 않았다."],
      [15: "민준의 편지가 왔다.", 45: "민준은 답하지 않았다."],
      [12: "검은 늑대 한 마리.", 24: "멀리 늑대 울음이 들렸다.", 36: "다시 늑대 그림자가 보였다."],
    ]
    var texts: [EpisodeID: String] = [:]
    for (index, extra) in extras.enumerated() {
      let meta = EpisodeMeta(title: "\(index + 1)화", goal: 5_000)
      let text = (1...60).map { extra[$0] ?? "\(index + 1)화의 \($0)번째 문단. 비가 그친 골목을 천천히 걸었다." }
        .joined(separator: "\n")
      try store.writeEpisode(text, id: meta.id)
      project.episodes.append(meta)
      texts[meta.id] = text
    }
    try store.saveProject(project)
    let ids = project.episodes.map(\.id)
    let second = try XCTUnwrap(texts[ids[1]]) as NSString
    let place = EpisodeViewState(
      caret: second.range(of: "2화의 30번째").location + 5, top: second.range(of: "2화의 25번째").location,
      openedAt: Date().addingTimeInterval(-3_600))
    EpisodeViewStates.shared.record(
      EpisodeViewState(caret: 0, top: 0, openedAt: Date().addingTimeInterval(-7_200)), for: ids[0])
    EpisodeViewStates.shared.record(place, for: ids[1])

    let day = WriterDay(folder: folder, store: store, ids: ids, seededPlace: place)
    day.expected = texts
    for (key, value) in pinnedSettings {
      if let old = UserDefaults.standard.object(forKey: key) { day.savedSettings[key] = old }
      UserDefaults.standard.set(value, forKey: key)
    }
    return day
  }

  /// Permissions must be restored first so pending saves can finish and the folder can be deleted.
  func end() {
    try? blockEpisodeFolder(false)
    if let model { try? run { await model.autosaver.finish() } }
    try? closeWorkspace()
    for key in Self.pinnedSettings.keys {
      UserDefaults.standard.set(savedSettings[key], forKey: key)
    }
    try? FileManager.default.removeItem(at: folder)
  }

  // MARK: Running steps

  func perform(_ step: Step) throws {
    stepName = step.name
    samples = []
    try step.act(self)
    try step.check(self)
    try verifyManuscripts()
    for (work, elapsed) in samples where elapsed > Self.mainThreadLimit {
      XCTFail("[\(stepName)] \(work.rawValue)가 메인 스레드를 \(elapsed) 막았다(한도 \(Self.mainThreadLimit))")
    }
  }

  /// After any step: after ⌘S every episode's disk body equals what the writer wrote (nothing lost or mixed),
  /// the episode folder's files and the `project.json` list match the on-screen list, and save state is normal.
  private func verifyManuscripts() throws {
    try saveNow()
    try run { await self.model.finishProjectSaves() }
    for episode in model.episodes {
      see(try disk(episode.id), expected[episode.id], "디스크 본문: \(episode.title)")
    }
    if let open = openEpisode { see(editor.string, expected[open], "편집기 본문") }
    try verifyListOnDisk()
    see(model.autosaver.status, .idle, "저장 상태")
    see(model.autosaver.conflicts.isEmpty, true, "남은 충돌 없음")
  }

  func verifyListOnDisk() throws {
    let names = try FileManager.default.contentsOfDirectory(atPath: store.layout.episodesFolder.path(percentEncoded: false))
      .filter { $0.hasSuffix(".md") }
    see(Set(names), Set(model.episodes.map { store.layout.episodeFile($0.id).lastPathComponent }), "회차 폴더의 파일 = 목록")
    let saved = try store.loadProject()
    see(saved.episodes.map(\.id), model.episodes.map(\.id), "project.json 회차 순서")
    see(saved.episodes.map(\.title), model.episodes.map(\.title), "project.json 제목")
    see(saved.groups, model.project.groups, "project.json 묶음")
  }

  // MARK: Window

  func openWorkspace() throws {
    model = ProjectModel(
      project: try store.loadProject(), store: store, queue: SaveQueue(retryDelays: [.milliseconds(5)]),
      moveToTrash: { [folder] url in
        let destination = folder.appending(path: "휴지통/\(url.lastPathComponent)")
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
      },
      backup: backup)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled, .resizable], backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: WorkspaceView(model: model))
    window.makeKeyAndOrderFront(nil)
    self.window = window
    try waitFor("작업 공간이 뜨고 편집기가 회차를 연다") {
      self.find(ManuscriptTextView.self) != nil && self.model.autosaver.episodeID != nil
    }
    editor = find(ManuscriptTextView.self)
    // Tests have no events, so undo groups don't close by themselves. Each key is closed as one group directly (`key`).
    editor.episodeUndoManager.groupsByEvent = false
  }

  /// Close the window as if quitting. The editor receives `willTerminate` and remembers the current position.
  func closeWorkspace() throws {
    guard let window else { return }
    let open = openEpisode
    let place = editor?.viewState()
    // Notify as at quit. In tests the autorelease pool drains only when the test ends, so merely closing would tear down the editor
    // and remember the position only then.
    NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApp)
    window.contentView = nil
    window.close()
    self.window = nil
    if let open, let place {
      try waitFor("닫을 때 자리를 기억한다") { EpisodeViewStates.shared.state(for: open)?.caret == place.caret }
    }
  }

  var openEpisode: EpisodeID? { model.autosaver.episodeID }
  var editorHasFocus: Bool { window?.firstResponder === editor }
  func title(_ id: EpisodeID) -> String { model.episode(id)?.title ?? id.rawValue }

  func isAt(_ place: EpisodeViewState) -> Bool {
    let now = editor.viewState()
    return now.caret == place.caret && now.top == place.top
  }

  /// Select an episode in the sidebar: give the sidebar focus (clicking gives it focus) and move with ↑↓.
  /// Clicks don't reach the non-key test window, so the keyboard path is used. Main-thread time is measured per key until the episode changes.
  func pick(_ id: EpisodeID) throws {
    guard let window, let sidebar = find(NSTableView.self) else { return XCTFail("[\(stepName)] 사이드바가 없다") }
    if let open = openEpisode { places[open] = editor.viewState() }
    window.makeFirstResponder(sidebar)
    let ids = model.episodes.map(\.id)
    guard let target = ids.firstIndex(of: id), var index = openEpisode.flatMap(ids.firstIndex(of:)) else {
      return XCTFail("[\(stepName)] 고를 회차가 목록에 없다")
    }
    while index != target {
      let step = target > index ? 1 : -1
      let next = ids[index + step]
      // Episode switching happens on the SwiftUI update turn after the key. The run loop is spun continuously from the key until the new body loads, and timed.
      let started = clock.now
      press(arrow: step > 0 ? NSDownArrowFunctionKey : NSUpArrowFunctionKey, keyCode: step > 0 ? 125 : 126)
      while openEpisode != next, clock.now - started < .seconds(2) {
        RunLoop.main.run(mode: .default, before: Date())
      }
      samples.append((.switchEpisode, clock.now - started))
      guard openEpisode == next else { return XCTFail("[\(stepName)] ↑↓로 \(title(next))에 가지 못했다") }
      index += step
    }
    see(editor.string, expected[id], "고른 회차의 본문이 편집기에")
    knownBreak("findings 1: 사이드바에서 회차를 고르면 키보드 초점이 사이드바에 남아 바로 쓰지 못한다", fixedWhen: editorHasFocus)
  }

  /// Click the body to start writing. The caret isn't moved (to check the remembered position; a real click moves it to the clicked spot, findings 1).
  func clickEditor() {
    window?.makeFirstResponder(editor)
  }

  /// Go to another app and come back. The test window can't become key, so the window key-state notifications the workspace receives are posted directly.
  func returnToApp() {
    guard let window else { return }
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
  }

  private func press(arrow: Int, keyCode: UInt16) {
    guard let window, let scalar = UnicodeScalar(arrow) else { return }
    let characters = String(Character(scalar))
    for type in [NSEvent.EventType.keyDown, .keyUp] {
      guard
        let event = NSEvent.keyEvent(
          with: type, location: .zero, modifierFlags: [.numericPad, .function],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
          characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
      else { continue }
      window.sendEvent(event)
    }
  }

  private func find<T: NSView>(_ type: T.Type) -> T? {
    func search(_ view: NSView) -> T? { (view as? T) ?? view.subviews.lazy.compactMap(search).first }
    return window?.contentView.flatMap(search)
  }

  // MARK: Writing

  /// Type Hangul in exactly the order the IME sends (`HangulKeys`). With one caret, check the typed text went in at the caret.
  func type(_ text: String, _ input: Input) throws {
    guard let open = openEpisode else { return XCTFail("[\(stepName)] 열린 회차가 없다") }
    // The editor text points at text storage's mutable string, so copy it before typing.
    let before = NSString(string: editor.string)
    let selection = editor.selectedRange()
    let single = editor.multiCursorRanges == nil
    // In `.replacing`, keys that edit a character (update, commit) leave no undo record. The real app opens a group only when a record is made,
    // but grouping by hand leaves empty groups that ⌘Z pops alone, so this mode types one character (first key through last) as one group.
    let undo = editor.episodeUndoManager
    var letterOpen = false
    for event in HangulKeys.events(for: text) {
      guard input == .replacing else {
        key { apply(event, input) }
        continue
      }
      switch event {
      case .update, .commit: break
      case .start, .next, .literal:
        if letterOpen { undo.endUndoGrouping() }
        undo.beginUndoGrouping()
        letterOpen = true
      }
      samples.append((.key, clock.measure { apply(event, input) }))
    }
    if letterOpen { undo.endUndoGrouping() }
    if single {
      see(editor.string, before.replacingCharacters(in: selection, with: text), "친 글이 커서 자리에")
    }
    see(editor.hasMarkedText(), false, "조합이 끝났다")
    expected[open] = editor.string
  }

  private func apply(_ event: HangulKeys.Event, _ input: Input) {
    let none = NSRange(location: NSNotFound, length: 0)
    let previous = NSRange(location: editor.selectedRange().location - 1, length: 1)
    func mark(_ text: String) {
      editor.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0), replacementRange: none)
    }
    switch (event, input) {
    case (.start(let text), .marked), (.update(let text), .marked): mark(text)
    case (.next(let done, let text), .marked):
      editor.insertText(done, replacementRange: none)
      mark(text)
    case (.commit(let done), .marked): editor.insertText(done, replacementRange: none)
    case (.start(let text), .replacing): editor.insertText(text, replacementRange: none)
    case (.update(let text), .replacing): editor.insertText(text, replacementRange: previous)
    case (.next(let done, let text), .replacing):
      editor.insertText(done, replacementRange: previous)
      editor.insertText(text, replacementRange: none)
    case (.commit, .replacing): break
    case (.literal(let text), _): editor.insertText(text, replacementRange: none)
    }
  }

  /// One key: closed as one undo group, with main-thread time measured.
  func key(_ body: () -> Void) {
    let undo = editor.episodeUndoManager
    let elapsed = clock.measure {
      undo.beginUndoGrouping()
      body()
      undo.endUndoGrouping()
    }
    samples.append((.key, elapsed))
  }

  /// ⌘S (the workspace's save now): starting the save happens on the main thread immediately; completion is awaited.
  func saveNow() throws {
    samples.append((.saveStart, clock.measure { model.autosaver.startSave() }))
    try run { await self.model.autosaver.flush() }
  }

  /// One sidebar action as one undo group.
  func sidebar(_ work: @escaping @MainActor () async throws -> Void) throws {
    sidebarUndo.beginUndoGrouping()
    defer { sidebarUndo.endUndoGrouping() }
    try run(work)
  }

  /// Launch the app's async function in a separate Task and spin the main run loop until it finishes (fails if not done within 10 s).
  func run<T>(_ work: @escaping @MainActor () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    Task { @MainActor in
      do { box.result = .success(try await work()) } catch { box.result = .failure(error) }
    }
    let deadline = clock.now + .seconds(10)
    while box.result == nil, clock.now < deadline {
      RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
    }
    guard let result = box.result else { throw TimedOut(step: stepName) }
    return try result.get()
  }

  func makeReplace() -> ProjectReplace {
    let model = model!
    return ProjectReplace(
      store: store, autosaver: model.autosaver, episodeIDs: { model.episodes.map(\.id) },
      recordCount: { model.recordCount($0, for: $1) })
  }

  // MARK: Disk

  func disk(_ id: EpisodeID) throws -> String { try store.readEpisode(id) }

  func diskData(_ id: EpisodeID) throws -> Data { try Data(contentsOf: store.layout.episodeFile(id)) }

  func diskBytes() throws -> [EpisodeID: Data] {
    var bytes: [EpisodeID: Data] = [:]
    for episode in model.episodes { bytes[episode.id] = try diskData(episode.id) }
    return bytes
  }

  func fileExists(_ id: EpisodeID) -> Bool {
    FileManager.default.fileExists(atPath: store.layout.episodeFile(id).path(percentEncoded: false))
  }

  /// Another editor edits the file. Shift the modification time by 1 s so it isn't stamped the same.
  func writeOutside(_ text: String, to id: EpisodeID) throws {
    let url = store.layout.episodeFile(id)
    let before = FileStamp(of: url)?.modified ?? Date()
    try Data(text.utf8).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: before.addingTimeInterval(1)], ofItemAtPath: url.path(percentEncoded: false))
  }

  func blockEpisodeFolder(_ blocked: Bool) throws {
    try FileManager.default.setAttributes(
      [.posixPermissions: blocked ? 0o555 : 0o755], ofItemAtPath: store.layout.episodesFolder.path(percentEncoded: false))
  }

  func snapshotIDs(_ id: EpisodeID) throws -> [String] { try store.snapshots(of: id).map(\.id) }

  func newSnapshots(_ id: EpisodeID, since ids: [String]) throws -> [Snapshot] {
    try store.snapshots(of: id).filter { !ids.contains($0.id) }
  }

  // MARK: Checks

  /// When long bodies differ, show only around the first difference.
  func see<T: Equatable>(_ actual: T, _ expected: T, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
    guard actual != expected else { return }
    guard let actual = actual as? String, let expected = expected as? String else {
      return XCTAssertEqual(actual, expected, "[\(stepName)] \(what)", file: file, line: line)
    }
    let same = zip(actual, expected).prefix { $0 == $1 }.count
    func around(_ text: String) -> String {
      String(text.dropFirst(max(0, same - 15)).prefix(40)).replacingOccurrences(of: "\n", with: "⏎")
    }
    XCTFail(
      "[\(stepName)] \(what): \(same)번째 글자부터 다름. 실제 「\(around(actual))」 기대 「\(around(expected))」 (길이 \(actual.count)/\(expected.count))",
      file: file, line: line)
  }

  func ok(_ condition: Bool, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(condition, "[\(stepName)] \(what)", file: file, line: line)
  }

  /// A known flow hitch. Currently the expectation must fail (recorded quietly); once fixed and passing, it's reported as a failure.
  /// `XCTExpectFailure` isn't used: calling it in this test killed the test app at test end.
  func knownBreak(_ finding: String, fixedWhen fixed: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if fixed {
      XCTFail("[\(stepName)] 알려진 끊김이 고쳐졌다. 이 줄을 보통 확인으로 바꾼다: \(finding)", file: file, line: line)
    } else {
      knownBreaks.append("[\(stepName)] \(finding)")
    }
  }

  /// Wait until the condition holds (instead of a fixed time). Fails if not within 2 s.
  func waitFor(_ what: String, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) throws {
    let deadline = clock.now + .seconds(2)
    while !condition() {
      guard clock.now < deadline else { return XCTFail("[\(stepName)] \(what)", file: file, line: line) }
      RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
    }
  }
}

/// Result of a Task awaited while spinning the run loop
@MainActor
private final class ResultBox<T> {
  var result: Result<T, any Error>?
}

private struct TimedOut: Error, CustomStringConvertible {
  let step: String
  var description: String { "[\(step)] 10초 안에 끝나지 않았다" }
}

// MARK: - 2-set IME simulation

/// Break text into the composition steps the 2-set IME sends the editor. Types jamo keys per character, and handles a final consonant moving
/// to the next character's initial (동 + ㅠ → 도 + 유), plus compound vowels and compound finals, like the IME.
private enum HangulKeys {
  enum Event: Equatable {
    /// Start composing a new character
    case start(String)
    /// Change the composing character
    case update(String)
    /// Commit the previous character and start composing a new one (one key)
    case next(commit: String, start: String)
    /// Commit composition before a non-Hangul key or at the end
    case commit(String)
    /// A non-Hangul character
    case literal(String)
  }

  private static let initials = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
  private static let medials = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
  private static let finals: [Character?] = [nil] + Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
  private static let vowelPairs: [Character: [Character]] = [
    "ㅘ": ["ㅗ", "ㅏ"], "ㅙ": ["ㅗ", "ㅐ"], "ㅚ": ["ㅗ", "ㅣ"], "ㅝ": ["ㅜ", "ㅓ"], "ㅞ": ["ㅜ", "ㅔ"], "ㅟ": ["ㅜ", "ㅣ"],
    "ㅢ": ["ㅡ", "ㅣ"],
  ]
  private static let finalPairs: [Character: [Character]] = [
    "ㄳ": ["ㄱ", "ㅅ"], "ㄵ": ["ㄴ", "ㅈ"], "ㄶ": ["ㄴ", "ㅎ"], "ㄺ": ["ㄹ", "ㄱ"], "ㄻ": ["ㄹ", "ㅁ"], "ㄼ": ["ㄹ", "ㅂ"],
    "ㄽ": ["ㄹ", "ㅅ"], "ㄾ": ["ㄹ", "ㅌ"], "ㄿ": ["ㄹ", "ㅍ"], "ㅀ": ["ㄹ", "ㅎ"], "ㅄ": ["ㅂ", "ㅅ"],
  ]

  private struct Syllable {
    var lead: Character?
    var vowel: Character?
    var tail: Character?

    var text: String {
      guard let lead, let vowel, let l = initials.firstIndex(of: lead), let v = medials.firstIndex(of: vowel),
        let t = finals.firstIndex(of: tail), let scalar = UnicodeScalar(0xAC00 + (l * 21 + v) * 28 + t)
      else { return String(lead ?? vowel ?? " ") }
      return String(Character(scalar))
    }
  }

  static func events(for text: String) -> [Event] {
    var events: [Event] = []
    var current: Syllable?
    func startNew(_ next: Syllable, committing done: Syllable) {
      current = next
      events.append(.next(commit: done.text, start: next.text))
    }
    func feed(_ key: Character) {
      guard var syllable = current else {
        let fresh = medials.contains(key) ? Syllable(vowel: key) : Syllable(lead: key)
        current = fresh
        return events.append(.start(fresh.text))
      }
      if medials.contains(key) {
        if syllable.lead != nil, syllable.vowel == nil {
          syllable.vowel = key
        } else if syllable.tail == nil, let vowel = syllable.vowel, let pair = combined(vowel, key, in: vowelPairs) {
          syllable.vowel = pair
        } else if let tail = syllable.tail {
          var done = syllable
          let parts = finalPairs[tail]
          done.tail = parts?.first
          return startNew(Syllable(lead: parts?.last ?? tail, vowel: key), committing: done)
        } else {
          return startNew(Syllable(vowel: key), committing: syllable)
        }
      } else if syllable.lead != nil, syllable.vowel != nil, syllable.tail == nil, finals.contains(key) {
        syllable.tail = key
      } else if let tail = syllable.tail, let pair = combined(tail, key, in: finalPairs) {
        syllable.tail = pair
      } else {
        return startNew(Syllable(lead: key), committing: syllable)
      }
      current = syllable
      events.append(.update(syllable.text))
    }
    for character in text {
      if let keys = keys(of: character) {
        keys.forEach(feed)
      } else {
        if let syllable = current { events.append(.commit(syllable.text)) }
        current = nil
        events.append(.literal(String(character)))
      }
    }
    if let syllable = current { events.append(.commit(syllable.text)) }
    return events
  }

  private static func combined(_ first: Character, _ second: Character, in pairs: [Character: [Character]]) -> Character? {
    pairs.first { $0.value == [first, second] }?.key
  }

  /// Jamo keys typing one precomposed character (compound vowels/finals take two keys). nil if not a Hangul character.
  private static func keys(of character: Character) -> [Character]? {
    guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first,
      (0xAC00...0xD7A3).contains(scalar.value)
    else { return nil }
    let index = Int(scalar.value) - 0xAC00
    let vowel = medials[index / 28 % 21]
    var keys = [initials[index / (21 * 28)]] + (vowelPairs[vowel] ?? [vowel])
    if let tail = finals[index % 28] { keys += finalPairs[tail] ?? [tail] }
    return keys
  }
}
