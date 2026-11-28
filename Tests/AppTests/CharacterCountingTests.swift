import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

@MainActor
final class CharacterCountingTests: XCTestCase {
  private var folder: URL!
  private var store: ProjectStore!

  override func setUp() async throws {
    let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    folder = repo.appending(path: "build/tmp/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    store = try ProjectStore.create(at: folder.appending(path: "작품.novel"), title: "x")
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func makeModel() throws -> ProjectModel {
    ProjectModel(
      project: try store.loadProject(), store: store, queue: SaveQueue(retryDelays: [.milliseconds(5)]),
      autosaveDelay: .milliseconds(20), countDelay: .milliseconds(20), countSaveDelay: .milliseconds(50))
  }

  /// Opened in the same order as EpisodeEditorPane.
  private func open(_ id: EpisodeID, in model: ProjectModel, textView: ManuscriptTextView? = nil) throws -> ManuscriptTextView {
    let textView = textView ?? ManuscriptTextView.make()
    model.counter.attach(textView)
    let text = try store.readEpisode(id)
    model.counter.begin(episode: id, text: text, known: model.episode(id)?.characterCount)
    textView.replaceAllText(with: text)
    return textView
  }

  private func type(_ text: String, in textView: ManuscriptTextView) {
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
  }

  private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(2)) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
      guard ContinuousClock.now < deadline else { return XCTFail("시간 안에 조건이 맞지 않음") }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  func testCountsOnOpenAndAfterTypingPause() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()
    try store.writeEpisode("그는 검을", id: id)
    let textView = try open(id, in: model)

    try await waitUntil { model.counter.current == CharacterCount(withSpaces: 5, withoutSpaces: 4) }
    type(" 들었다.", in: textView)
    try await waitUntil { model.counter.current == CharacterCount(withSpaces: 10, withoutSpaces: 8) }
    XCTAssertEqual(model.episode(id)?.characterCount, CharacterCount(withSpaces: 10, withoutSpaces: 8))
  }

  /// If the next episode's body fails to open, the previous episode's count is cleared (left next to the error text it would look like this episode's).
  func testClearDropsPreviousEpisodeCount() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()
    try store.writeEpisode("그는 검을", id: id)
    _ = try open(id, in: model)
    try await waitUntil { model.counter.current != nil }

    model.counter.clear()

    XCTAssertNil(model.counter.current)
  }

  /// Counting during composition doesn't break it, and the composing character counts as one.
  func testCountingDuringCompositionKeepsMarkedText() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()
    let textView = try open(id, in: model)
    textView.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))

    try await waitUntil { model.counter.current?.withSpaces == 1 }
    XCTAssertTrue(textView.hasMarkedText(), "센 뒤에도 조합 중이어야 한다")
    XCTAssertEqual(textView.markedRange().length, 1)
  }

  func testSwitchingRightAfterTypingCountsLeftEpisode() async throws {
    let model = try makeModel()
    let first = try await model.addEpisode()
    let second = try await model.addEpisode()
    try store.writeEpisode("둘째 회차", id: second)
    let textView = try open(first, in: model)
    type("방금 쓴 문장", in: textView)

    _ = try open(second, in: model, textView: textView)

    try await waitUntil { model.episode(first)?.characterCount?.withSpaces == 7 }
    try await waitUntil { model.counter.current?.withSpaces == 5 }
    XCTAssertEqual(model.episode(second)?.characterCount?.withSpaces, 5)
  }

  /// Recounts when the body is reloaded from an outside change.
  func testReloadRecounts() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()
    let textView = try open(id, in: model)
    try await waitUntil { model.counter.current == .zero }

    textView.reloadText(with: "바깥에서 쓴 글")

    try await waitUntil { model.counter.current == CharacterCount(withSpaces: 8, withoutSpaces: 6) }
  }

  func testCountIsSavedToProjectFileLater() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()

    model.recordCount(CharacterCount(withSpaces: 12, withoutSpaces: 10), for: id)
    XCTAssertNil(try store.loadProject().episodes[0].characterCount, "바로 쓰지 않는다")

    try await waitUntil { (try? self.store.loadProject().episodes[0].characterCount) == CharacterCount(withSpaces: 12, withoutSpaces: 10) }
  }

  func testSaveCountsNowWritesPendingCount() async throws {
    let model = ProjectModel(
      project: try store.loadProject(), store: store, queue: SaveQueue(), countSaveDelay: .seconds(60))
    let id = try await model.addEpisode()
    model.recordCount(CharacterCount(withSpaces: 3, withoutSpaces: 3), for: id)

    await model.saveCountsNow()

    XCTAssertEqual(try store.loadProject().episodes[0].characterCount?.withSpaces, 3)
  }

  func testUndoRenameKeepsLatestCount() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()
    let undo = UndoManager()
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    await model.renameEpisodes([id: "새 제목"], reason: .single, undoManager: undo)
    undo.endUndoGrouping()
    model.recordCount(CharacterCount(withSpaces: 100, withoutSpaces: 90), for: id)

    undo.undo()
    try await Task.sleep(for: .milliseconds(100))

    XCTAssertEqual(model.episode(id)?.title, "")
    XCTAssertEqual(model.episode(id)?.characterCount?.withSpaces, 100)
  }

  func testSetGoalSavesAndUndoes() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()
    let undo = UndoManager()
    undo.groupsByEvent = false

    undo.beginUndoGrouping()
    await model.setGoal(id, to: 7_000, undoManager: undo)
    undo.endUndoGrouping()
    XCTAssertEqual(try store.loadProject().episodes[0].goal, 7_000)
    await model.setGoal(id, to: 0)
    XCTAssertEqual(model.episode(id)?.goal, 7_000, "0 이하는 받지 않는다")

    undo.undo()
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(model.episode(id)?.goal, 5_000)
    XCTAssertEqual(try store.loadProject().episodes[0].goal, 5_000)
  }

  func testDisplayText() {
    let count = CharacterCount(withSpaces: 1_204, withoutSpaces: 987)
    XCTAssertEqual(CharacterCountDisplay.both.text(for: count), "1,204자 · 공백 제외 987자")
    XCTAssertEqual(CharacterCountDisplay.withSpaces.text(for: count), "1,204자")
    XCTAssertEqual(CharacterCountDisplay.withoutSpaces.text(for: count), "공백 제외 987자")
  }

  // MARK: - Hiding the status bar

  /// When "hide while typing" is chosen.
  private func typingHidingFade(hideAfter: Duration, showAfter: Duration) -> StatusBarFade {
    let fade = StatusBarFade(hideAfter: hideAfter, showAfter: showAfter)
    fade.hidesWhileTyping = true
    fade.hidesWhenIdle = false
    return fade
  }

  private func typeFor(_ duration: Duration, _ fade: StatusBarFade) async throws {
    let start = ContinuousClock.now
    while ContinuousClock.now - start < duration {
      fade.noteInput()
      try await Task.sleep(for: .milliseconds(50))
    }
  }

  func testFadeHidesWhileTypingAndShowsAfterPause() async throws {
    let fade = typingHidingFade(hideAfter: .milliseconds(100), showAfter: .milliseconds(150))
    try await typeFor(.milliseconds(300), fade)
    XCTAssertTrue(fade.isHidden, "계속 치면 숨는다")

    try await waitUntil { !fade.isHidden }
  }

  func testFadeStaysVisibleForShortTyping() async throws {
    let fade = typingHidingFade(hideAfter: .milliseconds(200), showAfter: .milliseconds(50))
    fade.noteInput()
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertFalse(fade.isHidden, "1초 안에 멈추면 숨지 않는다")
  }

  func testMouseMoveShowsStatusBar() async throws {
    let fade = typingHidingFade(hideAfter: .milliseconds(20), showAfter: .seconds(10))
    fade.noteInput()
    try await Task.sleep(for: .milliseconds(30))
    fade.noteInput()
    try await waitUntil { fade.isHidden }

    fade.show()

    XCTAssertFalse(fade.isHidden)
  }

  /// Default: stays visible while typing, hides a while after stopping (instead of 10 s). Moving the mouse shows it.
  func testDefaultStaysVisibleWhileTypingAndHidesWhenIdle() async throws {
    let fade = StatusBarFade(hideAfter: .milliseconds(50), showAfter: .milliseconds(50), idleAfter: .milliseconds(400))
    fade.reconsider()
    try await typeFor(.milliseconds(300), fade)
    XCTAssertFalse(fade.isHidden, "기본은 치는 동안 계속 보인다")

    try await waitUntil { fade.isHidden }
    fade.show()
    XCTAssertFalse(fade.isHidden)
    try await waitUntil { fade.isHidden }
  }

  func testIdleHidingCanBeTurnedOff() async throws {
    let fade = StatusBarFade(idleAfter: .milliseconds(50))
    fade.hidesWhenIdle = false
    fade.reconsider()
    fade.noteInput()
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertFalse(fade.isHidden)
  }

  /// With refresh set to "live" (0), counting happens without waiting while typing.
  func testRealtimeCountingUpdatesWhileTyping() async throws {
    let model = try makeModel()
    model.counter.interval = .zero
    let id = try await model.addEpisode()
    let textView = try open(id, in: model)
    try await waitUntil { model.counter.current == CharacterCount(withSpaces: 0, withoutSpaces: 0) }

    for (index, letter) in ["가", "나", "다"].enumerated() {
      type(letter, in: textView)
      try await waitUntil({ model.counter.current?.withSpaces == index + 1 }, timeout: .milliseconds(200))
    }
  }
}
