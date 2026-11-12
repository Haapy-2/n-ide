import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

/// 글자 수 세기(편집기 → 회차 목록 → project.json), 목표 글자 수, 상태 줄 흐려짐.
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

  /// 편집기를 만들고 회차를 연다(EpisodeEditorPane이 하는 순서대로).
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

  /// 조합 중에 세어도 조합이 끊기지 않고, 조합 중인 글자도 한 글자로 센다.
  func testCountingDuringCompositionKeepsMarkedText() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()
    let textView = try open(id, in: model)
    textView.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))

    try await waitUntil { model.counter.current?.withSpaces == 1 }
    XCTAssertTrue(textView.hasMarkedText(), "센 뒤에도 조합 중이어야 한다")
    XCTAssertEqual(textView.markedRange().length, 1)
  }

  /// 입력 직후(아직 세기 전) 다른 회차로 옮겨도 떠난 회차의 마지막 글자 수가 남는다.
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

  /// 앱 밖에서 바뀐 본문으로 다시 읽어도(8단계) 다시 센다.
  func testReloadRecounts() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()
    let textView = try open(id, in: model)
    try await waitUntil { model.counter.current == .zero }

    textView.reloadText(with: "바깥에서 쓴 글")

    try await waitUntil { model.counter.current == CharacterCount(withSpaces: 8, withoutSpaces: 6) }
  }

  /// 글자 수는 project.json에 묶어서(조금 뒤에) 저장한다.
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

  /// 이름 변경을 되돌려도 그사이 센 글자 수는 옛 값으로 돌아가지 않는다.
  func testUndoRenameKeepsLatestCount() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()
    let undo = UndoManager()
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    await model.rename(id, to: "새 제목", undoManager: undo)
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

  // MARK: - 상태 줄 흐려짐

  func testFadeHidesWhileTypingAndShowsAfterPause() async throws {
    let fade = StatusBarFade(hideAfter: .milliseconds(100), showAfter: .milliseconds(150))
    let start = ContinuousClock.now
    // 50ms마다 입력을 300ms 동안 이어 간다.
    while ContinuousClock.now - start < .milliseconds(300) {
      fade.noteInput()
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertTrue(fade.isHidden, "계속 치면 숨는다")

    try await waitUntil { !fade.isHidden }
  }

  func testFadeStaysVisibleForShortTyping() async throws {
    let fade = StatusBarFade(hideAfter: .milliseconds(200), showAfter: .milliseconds(50))
    fade.noteInput()
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertFalse(fade.isHidden, "1초 안에 멈추면 숨지 않는다")
  }

  func testMouseMoveShowsStatusBar() async throws {
    let fade = StatusBarFade(hideAfter: .milliseconds(20), showAfter: .seconds(10))
    fade.noteInput()
    try await Task.sleep(for: .milliseconds(30))
    fade.noteInput()
    try await waitUntil { fade.isHidden }

    fade.show()

    XCTAssertFalse(fade.isHidden)
  }
}
