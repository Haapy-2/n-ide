import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

/// 스냅샷 찍는 때 (11b): 떠날 때, 자동(간격), 직접, 설정.
@MainActor
final class SnapshotTimingTests: XCTestCase {
  private var folder: URL!
  private var store: ProjectStore!
  private var episode: EpisodeID!
  private var textView: ManuscriptTextView!
  private var autosaver: EpisodeAutosaver!

  override func setUp() async throws {
    let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    folder = repo.appending(path: "build/tmp/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    store = try ProjectStore.create(at: folder.appending(path: "작품.novel"), title: "x")
    episode = EpisodeID.make()
    try store.writeEpisode("첫 문장", id: episode)

    textView = ManuscriptTextView.make()
    textView.replaceAllText(with: "첫 문장")
    autosaver = EpisodeAutosaver(
      store: store, queue: SaveQueue(retryDelays: [.milliseconds(5)]), delay: .milliseconds(50))
    autosaver.attach(textView)
    autosaver.begin(episode: episode)
  }

  override func tearDown() async throws {
    autosaver.snapshots.settings.autoEnabled = false
    try? FileManager.default.removeItem(at: folder)
  }

  private func type(_ text: String) {
    textView.insertText(text, replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
    autosaver.textDidChange()
  }

  private func snapshots() throws -> [Snapshot] { try store.snapshots(of: episode) }

  // MARK: - 설정

  func testDefaultsAndClamping() {
    let defaults = EpisodeSnapshotter.Settings()
    XCTAssertTrue(defaults.autoEnabled)
    XCTAssertEqual(defaults.interval, .seconds(30 * 60))
    XCTAssertEqual(defaults.retention, 50)

    let odd = EpisodeSnapshotter.Settings(minutes: 7, retention: 999)
    XCTAssertEqual(odd.interval, .seconds(30 * 60), "고를 수 없는 간격은 기본값으로")
    XCTAssertEqual(odd.retention, 100)
    XCTAssertEqual(EpisodeSnapshotter.Settings(retention: 3).retention, 10)
    XCTAssertEqual(EpisodeSnapshotter.Settings(retention: 47).retention, 40, "10 단위로 맞춘다")
  }

  // MARK: - 떠날 때

  func testLeaveAfterEditingTakesSnapshot() async throws {
    type(" 둘째")
    autosaver.leaveEpisode()
    await autosaver.snapshots.waitForWrites()

    let taken = try snapshots()
    XCTAssertEqual(taken.map(\.kind), [.leave])
    XCTAssertEqual(try store.readSnapshot(taken[0]), "첫 문장 둘째")
  }

  func testLeaveWithoutEditingTakesNothing() async throws {
    autosaver.leaveEpisode()
    await autosaver.snapshots.waitForWrites()
    XCTAssertTrue(try snapshots().isEmpty, "훑어보기만 한 회차는 찍지 않는다")
  }

  func testLeaveStillWorksWhenAutoIsOff() async throws {
    autosaver.snapshots.settings.autoEnabled = false
    type(" 둘째")
    await autosaver.finish()
    XCTAssertEqual(try snapshots().map(\.kind), [.leave], "자동을 꺼도 떠날 때는 찍는다")
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 둘째", "창을 닫을 때 저장도 끝낸다")
    XCTAssertFalse(autosaver.hasWorkBeforeQuit)
  }

  // MARK: - 자동

  func testAutoTickOnlyWhenEdited() async throws {
    autosaver.snapshots.autoTick()
    await autosaver.snapshots.waitForWrites()
    XCTAssertTrue(try snapshots().isEmpty)

    type(" 둘째")
    autosaver.snapshots.autoTick()
    autosaver.snapshots.autoTick()
    await autosaver.snapshots.waitForWrites()
    XCTAssertEqual(try snapshots().map(\.kind), [.auto], "그사이 고친 것이 없으면 다시 찍지 않는다")
  }

  func testAutoOffTakesNothing() async throws {
    autosaver.snapshots.settings.autoEnabled = false
    type(" 둘째")
    autosaver.snapshots.autoTick()
    await autosaver.snapshots.waitForWrites()
    XCTAssertTrue(try snapshots().isEmpty)
  }

  /// 간격을 바꾸면 새 간격으로 타이머를 다시 건다(시험용으로 아주 짧게).
  func testTimerUsesNewInterval() async throws {
    var settings = autosaver.snapshots.settings
    settings.interval = .milliseconds(50)
    autosaver.snapshots.settings = settings
    type(" 둘째")

    try await Task.sleep(for: .milliseconds(400))
    await autosaver.snapshots.waitForWrites()
    XCTAssertEqual(try snapshots().map(\.kind), [.auto])
  }

  func testRetentionPrunesAutoButKeepsManual() async throws {
    _ = try await autosaver.takeManualSnapshot()
    autosaver.snapshots.settings = EpisodeSnapshotter.Settings(retention: 10)
    for index in 0..<12 {
      type(" \(index)")
      autosaver.snapshots.autoTick()
    }
    await autosaver.snapshots.waitForWrites()

    let taken = try snapshots()
    XCTAssertEqual(taken.filter { $0.kind == .auto }.count, 10)
    XCTAssertEqual(taken.filter { $0.kind == .manual }.count, 1)
  }

  // MARK: - 직접

  func testManualSavesFirstAndAlwaysTakes() async throws {
    type(" 둘째")
    let first = try await autosaver.takeManualSnapshot()
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 둘째", "저장을 먼저 끝낸다")
    let second = try await autosaver.takeManualSnapshot()

    XCTAssertNotNil(first)
    XCTAssertNotNil(second, "내용이 같아도 직접 찍기는 찍는다")
    XCTAssertEqual(try snapshots().map(\.kind), [.manual, .manual])

    autosaver.leaveEpisode()
    await autosaver.snapshots.waitForWrites()
    XCTAssertEqual(try snapshots().count, 2, "직접 찍은 뒤 고치지 않았으면 떠날 때 찍지 않는다")
  }
}
