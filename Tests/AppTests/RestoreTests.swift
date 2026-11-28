import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

/// Restore from snapshot (PLAN ch.10 #6). First and foremost checks that the current text is never lost.
@MainActor
final class RestoreTests: XCTestCase {
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
    try store.writeEpisode("지금 글", id: episode)

    let version = try store.readEpisodeVersion(episode)
    textView = ManuscriptTextView.make()
    textView.replaceAllText(with: version.text)
    autosaver = EpisodeAutosaver(
      store: store, queue: SaveQueue(retryDelays: [.milliseconds(5)]), delay: .milliseconds(50))
    autosaver.attach(textView)
    autosaver.begin(episode: episode, version: version)
  }

  override func tearDown() async throws {
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: store.layout.snapshotFolder(episode).path(percentEncoded: false))
    try? FileManager.default.removeItem(at: folder)
  }

  private func restore(to text: String) async throws -> Bool {
    try await autosaver.restore(episode, to: text, memo: "11월 12일 14:23:05 버전으로 되돌림", notice: "14:23:05 버전으로 되돌렸어요")
  }

  func testRestoreReplacesTextAndUndoReturnsInOneStep() async throws {
    let restored = try await restore(to: "옛 글\n둘째 문단")
    XCTAssertTrue(restored)
    XCTAssertEqual(textView.string, "옛 글\n둘째 문단")
    XCTAssertEqual(autosaver.restoreNotice, "14:23:05 버전으로 되돌렸어요")

    textView.undo(nil)
    XCTAssertEqual(textView.string, "지금 글", "⌘Z 한 번이면 되돌리기 전으로")
    textView.redo(nil)
    XCTAssertEqual(textView.string, "옛 글\n둘째 문단")
  }

  func testLeavesRestoreSnapshotWithMemoBeforeReplacing() async throws {
    _ = try await restore(to: "옛 글")
    let snapshots = try store.snapshots(of: episode)
    XCTAssertEqual(snapshots.map(\.kind), [.restore])
    XCTAssertEqual(try store.readSnapshot(snapshots[0]), "지금 글")
    XCTAssertEqual(store.readMemo(snapshots[0]), "11월 12일 14:23:05 버전으로 되돌림")
  }

  func testRestoredTextIsSavedByAutosave() async throws {
    _ = try await restore(to: "옛 글")
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(try store.readEpisode(episode), "옛 글")
  }

  func testCancelFromStatusBarUndoesAndSaves() async throws {
    _ = try await restore(to: "옛 글")
    autosaver.undoRestore()
    XCTAssertEqual(textView.string, "지금 글")
    XCTAssertNil(autosaver.restoreNotice)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(try store.readEpisode(episode), "지금 글")
  }

  func testNoticeDisappearsOnNextEditAndOnLeaving() async throws {
    _ = try await restore(to: "옛 글")
    autosaver.textDidChange()
    XCTAssertNil(autosaver.restoreNotice)

    _ = try await restore(to: "또 옛 글")
    XCTAssertNotNil(autosaver.restoreNotice)
    autosaver.leaveEpisode()
    XCTAssertNil(autosaver.restoreNotice)
  }

  func testSameTextDoesNothing() async throws {
    let restored = try await restore(to: "지금 글")
    XCTAssertFalse(restored)
    XCTAssertTrue(try store.snapshots(of: episode).isEmpty)
    XCTAssertNil(autosaver.restoreNotice)
  }

  func testFailedRestoreSnapshotKeepsCurrentText() async throws {
    let snapshotFolder = store.layout.snapshotFolder(episode)
    try FileManager.default.createDirectory(at: snapshotFolder, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: snapshotFolder.path(percentEncoded: false))

    do {
      _ = try await restore(to: "옛 글")
      XCTFail("쓸 수 없으면 오류여야 한다")
    } catch {}
    XCTAssertEqual(textView.string, "지금 글")
    XCTAssertNil(autosaver.restoreNotice)
  }

  /// Restoring again to the pre-restore snapshot leaves another pre-restore, so both directions are recorded.
  func testRestoringFromRestoreSnapshotRecordsBothWays() async throws {
    _ = try await restore(to: "옛 글")
    let before = try XCTUnwrap(try store.snapshots(of: episode).last)
    autosaver.textDidChange()
    try await Task.sleep(for: .milliseconds(1_100))  // Same second would only add -2, but make time order explicit

    _ = try await restore(to: try store.readSnapshot(before))
    XCTAssertEqual(textView.string, "지금 글")
    let snapshots = try store.snapshots(of: episode)
    XCTAssertEqual(snapshots.map(\.kind), [.restore, .restore])
    XCTAssertEqual(try store.readSnapshot(snapshots[1]), "옛 글")
  }

  func testBlockedWhileConflictIsOpen() async throws {
    // A file changed outside while app edits are unsaved creates a conflict. Shift the modification time by 1 s so it isn't stamped the same.
    textView.insertText(" 더", replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
    autosaver.textDidChange()
    let url = store.layout.episodeFile(episode)
    let before = FileStamp(of: url)?.modified ?? Date()
    try Data("바깥 글".utf8).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: before.addingTimeInterval(1)], ofItemAtPath: url.path(percentEncoded: false))
    await autosaver.checkExternalChange()
    XCTAssertNotNil(autosaver.conflicts[episode])

    do {
      _ = try await restore(to: "옛 글")
      XCTFail("충돌 중에는 막아야 한다")
    } catch EpisodeAutosaver.RestoreError.conflict {
    }
    XCTAssertEqual(textView.string, "지금 글 더")
  }

  func testRestoreDuringCompositionFinishesItFirst() async throws {
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    textView.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    XCTAssertTrue(textView.hasMarkedText())
    XCTAssertTrue(textView.replaceAllUndoably(with: "옛 글", actionName: "되돌리기"))
    XCTAssertFalse(textView.hasMarkedText())
    XCTAssertEqual(textView.string, "옛 글")
  }
}
