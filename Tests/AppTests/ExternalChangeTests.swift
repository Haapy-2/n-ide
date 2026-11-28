import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

/// External change handling. Checks that neither a manuscript edited in another editor nor the one being written in the app is lost.
@MainActor
final class ExternalChangeTests: XCTestCase {
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

    let version = try store.readEpisodeVersion(episode)
    textView = ManuscriptTextView.make()
    textView.replaceAllText(with: version.text)
    autosaver = EpisodeAutosaver(
      store: store, queue: SaveQueue(retryDelays: [.milliseconds(5)]), delay: .seconds(60))
    autosaver.attach(textView)
    autosaver.begin(episode: episode, version: version)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func type(_ text: String) {
    textView.insertText(text, replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
    autosaver.textDidChange()
  }

  /// Write as another editor would save. Shift the modification time by 1 s so it isn't stamped with the same value.
  private func externalWrite(_ text: String) throws {
    let url = store.layout.episodeFile(episode)
    let before = FileStamp(of: url)?.modified ?? Date()
    try Data(text.utf8).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: before.addingTimeInterval(1)], ofItemAtPath: url.path(percentEncoded: false))
  }

  /// Wait until the app-side snapshot is fully kept and it's ready to ask.
  private func readyConflict() async throws -> EpisodeAutosaver.Conflict {
    for _ in 0..<200 {
      if let conflict = autosaver.conflicts[episode], conflict.isReady { return conflict }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw XCTSkip("충돌이 준비되지 않음")
  }

  private func snapshotFiles() throws -> [String] {
    let folder = store.layout.snapshotFolder(episode).path(percentEncoded: false)
    guard FileManager.default.fileExists(atPath: folder) else { return [] }
    return try FileManager.default.contentsOfDirectory(atPath: folder).sorted()
  }

  func testReloadsQuietlyWhenAppHasNoChanges() async throws {
    try externalWrite("다른 편집기에서 고친 문장")

    await autosaver.checkExternalChange()

    XCTAssertEqual(textView.string, "다른 편집기에서 고친 문장")
    XCTAssertTrue(autosaver.conflicts.isEmpty, "앱 쪽 변경이 없으면 묻지 않는다")
    XCTAssertFalse(autosaver.hasUnsavedChanges)
    XCTAssertEqual(try snapshotFiles(), [], "앱 쪽에 잃을 내용이 없으니 스냅샷도 필요 없다")
  }

  /// While the snapshot panel is open, external content isn't loaded (the panel's "current" is the body at open time, so the diff would go wrong).
  /// Checked once and loaded when the panel closes.
  func testSnapshotPanelHoldsExternalChangeUntilClosed() async throws {
    let panel = try XCTUnwrap(autosaver.beginPanel())
    try externalWrite("판이 열린 동안 바깥에서 고친 문장")

    await autosaver.checkExternalChange()
    XCTAssertEqual(textView.string, "첫 문장")

    autosaver.endPanel(hadFocus: panel.hadFocus)
    for _ in 0..<200 where textView.string == "첫 문장" { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(textView.string, "판이 열린 동안 바깥에서 고친 문장")
  }

  func testOwnSaveIsNotMistakenForExternalChange() async throws {
    type(" 둘째 문장")
    await autosaver.flush()

    await autosaver.checkExternalChange()

    XCTAssertTrue(autosaver.conflicts.isEmpty)
    XCTAssertEqual(textView.string, "첫 문장 둘째 문장")
  }

  func testBothChangedOnActivationAsksAndKeepsAppTextInSnapshot() async throws {
    type(" 앱에서 쓴 문장")
    try externalWrite("다른 편집기에서 고친 문장")

    await autosaver.checkExternalChange()
    let conflict = try await readyConflict()

    XCTAssertEqual(conflict.disk.text, "다른 편집기에서 고친 문장")
    let snapshot = try XCTUnwrap(conflict.snapshot)
    XCTAssertTrue(snapshot.lastPathComponent.hasSuffix("-conflict.md"))
    XCTAssertEqual(try String(contentsOf: snapshot, encoding: .utf8), "첫 문장 앱에서 쓴 문장")
    XCTAssertEqual(textView.string, "첫 문장 앱에서 쓴 문장", "묻기 전에는 화면 본문을 바꾸지 않는다")
    XCTAssertEqual(try store.readEpisode(episode), "다른 편집기에서 고친 문장", "묻기 전에는 덮어쓰지 않는다")
    XCTAssertTrue(autosaver.hasUnsavedChanges, "고를 때까지 종료하면 경고가 떠야 한다")
  }

  // MARK: - Quitting with an unresolved conflict (PLAN open question 27)

  /// If the app-side text is intact in the conflict snapshot, it isn't an "unsaved manuscript": excluded from retry/export and counted separately.
  func testConflictKeptInSnapshotIsNotUnprotected() async throws {
    type(" 앱에서 쓴 문장")
    try externalWrite("다른 편집기에서 고친 문장")
    await autosaver.checkExternalChange()
    _ = try await readyConflict()

    XCTAssertTrue(autosaver.hasWorkBeforeQuit, "종료 때 알려야 한다")
    XCTAssertFalse(autosaver.hasUnprotectedChanges)
    XCTAssertEqual(autosaver.conflictsKeptInSnapshots, 1)
    XCTAssertTrue(autosaver.unsavedManuscripts().isEmpty, "내보낼 원고가 아니다")
  }

  /// When the save during quit just found an external change (⌘Q within 1 s of autosave): finishing waits for the conflict snapshot,
  /// so the quit decision sees a "preserved conflict" rather than "a manuscript to export".
  func testConflictFoundWhileFinishingIsKeptBeforeQuitDecision() async throws {
    type(" 앱에서 쓴 문장")
    try externalWrite("다른 편집기에서 고친 문장")

    await autosaver.finish()

    XCTAssertEqual(autosaver.conflictsKeptInSnapshots, 1)
    XCTAssertFalse(autosaver.hasUnprotectedChanges)
    XCTAssertEqual(try store.readEpisode(episode), "다른 편집기에서 고친 문장", "바깥 글을 덮지 않는다")
  }

  /// Text written after the conflict isn't in the snapshot, so it's a manuscript to protect.
  func testTypingAfterConflictIsUnprotected() async throws {
    type(" 앱에서 쓴 문장")
    try externalWrite("다른 편집기에서 고친 문장")
    await autosaver.checkExternalChange()
    _ = try await readyConflict()

    type(" 더 쓴 문장")

    XCTAssertTrue(autosaver.hasUnprotectedChanges)
    XCTAssertEqual(autosaver.conflictsKeptInSnapshots, 0)
  }

  /// If even the conflict snapshot couldn't be kept, the app-side text is only in memory. Export must be offered, and it must not claim a backup exists.
  func testConflictWithoutSnapshotIsUnprotectedAndNotBackedUp() async throws {
    let snapshots = store.layout.snapshotFolder(episode)
    try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: snapshots.path(percentEncoded: false))
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: snapshots.path(percentEncoded: false))
    }
    type(" 앱에서 쓴 문장")
    try externalWrite("다른 편집기에서 고친 문장")
    await autosaver.checkExternalChange()
    let conflict = try await readyConflict()

    XCTAssertNil(conflict.snapshot)
    XCTAssertTrue(autosaver.hasUnprotectedChanges)
    XCTAssertEqual(autosaver.unsavedManuscripts().map(\.text), ["첫 문장 앱에서 쓴 문장"])
    XCTAssertFalse(autosaver.unprotectedAreBackedUp)
  }

  /// Choosing "external content" without a conflict snapshot would leave the app-side text nowhere. Then nothing changes.
  func testChoosingDiskVersionWithoutAppSnapshotKeepsAppText() async throws {
    let snapshots = store.layout.snapshotFolder(episode)
    try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: snapshots.path(percentEncoded: false))
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: snapshots.path(percentEncoded: false))
    }
    type(" 앱에서 쓴 문장")
    try externalWrite("다른 편집기에서 고친 문장")
    await autosaver.checkExternalChange()
    let conflict = try await readyConflict()
    XCTAssertNil(conflict.snapshot)

    await autosaver.useDiskVersion(episode)

    XCTAssertNotNil(autosaver.conflicts[episode], "고르기를 막고 충돌을 그대로 둔다")
    XCTAssertEqual(autosaver.conflicts[episode]?.unkept, .app, "묻는 창이 바꾸지 않은 까닭을 보인다")
    XCTAssertEqual(textView.string, "첫 문장 앱에서 쓴 문장")
    XCTAssertEqual(autosaver.unsavedManuscripts().map(\.text), ["첫 문장 앱에서 쓴 문장"], "내보낼 원고로 남는다")

    // Once snapshots can be kept, it can be chosen again, and the app-side text stays in a snapshot.
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: snapshots.path(percentEncoded: false))
    await autosaver.useDiskVersion(episode)

    XCTAssertNil(autosaver.conflicts[episode])
    XCTAssertEqual(textView.string, "다른 편집기에서 고친 문장")
    XCTAssertEqual(try conflictSnapshotTexts(), ["첫 문장 앱에서 쓴 문장"])
  }

  /// Text typed after the conflict snapshot is also snapshotted before switching to "external content".
  func testChoosingDiskVersionKeepsTextTypedAfterConflictSnapshot() async throws {
    type(" 앱에서 쓴 문장")
    try externalWrite("다른 편집기에서 고친 문장")
    await autosaver.checkExternalChange()
    _ = try await readyConflict()
    type(" 더 쓴 문장")

    await autosaver.useDiskVersion(episode)

    XCTAssertEqual(textView.string, "다른 편집기에서 고친 문장")
    XCTAssertTrue(try conflictSnapshotTexts().contains("첫 문장 앱에서 쓴 문장 더 쓴 문장"), "버린 쪽의 마지막 글이 스냅샷에 있다")
  }

  /// When choosing "this app's content", if the external content to overwrite can't be snapshotted, don't overwrite.
  func testChoosingAppVersionWithoutExternalSnapshotDoesNotOverwrite() async throws {
    type(" 앱에서 쓴 문장")
    try externalWrite("다른 편집기에서 고친 문장")
    await autosaver.flush()
    _ = try await readyConflict()
    let snapshots = store.layout.snapshotFolder(episode).path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: snapshots)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: snapshots) }

    await autosaver.keepAppVersion(episode)
    await autosaver.flush()

    XCTAssertEqual(try store.readEpisode(episode), "다른 편집기에서 고친 문장", "바깥 내용을 남기지 못했으니 덮지 않는다")
    XCTAssertNotNil(autosaver.conflicts[episode], "충돌을 그대로 둔다")
    XCTAssertEqual(autosaver.conflicts[episode]?.unkept, .disk)
    XCTAssertEqual(textView.string, "첫 문장 앱에서 쓴 문장")
  }

  private func conflictSnapshotTexts() throws -> [String] {
    try snapshotFiles().filter { $0.contains("-conflict") && $0.hasSuffix(".md") }.map {
      try String(contentsOf: store.layout.snapshotFolder(episode).appending(path: $0), encoding: .utf8)
    }
  }

  func testSaveRightBeforeWritingDetectsExternalChange() async throws {
    type(" 앱에서 쓴 문장")
    try externalWrite("다른 편집기에서 고친 문장")

    await autosaver.flush()

    XCTAssertEqual(try store.readEpisode(episode), "다른 편집기에서 고친 문장", "저장 직전 확인으로 덮어쓰지 않는다")
    let conflict = try await readyConflict()
    XCTAssertEqual(try String(contentsOf: XCTUnwrap(conflict.snapshot), encoding: .utf8), "첫 문장 앱에서 쓴 문장")
  }

  func testChoosingAppVersionOverwritesAndKeepsExternalInSnapshot() async throws {
    type(" 앱에서 쓴 문장")
    try externalWrite("다른 편집기에서 고친 문장")
    await autosaver.flush()
    _ = try await readyConflict()

    await autosaver.keepAppVersion(episode)
    await autosaver.flush()

    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 앱에서 쓴 문장")
    XCTAssertTrue(autosaver.conflicts.isEmpty)
    XCTAssertFalse(autosaver.hasUnsavedChanges)
    let external = try XCTUnwrap(try snapshotFiles().first { $0.hasSuffix("-external.md") })
    let externalURL = store.layout.snapshotFolder(episode).appending(path: external)
    XCTAssertEqual(try String(contentsOf: externalURL, encoding: .utf8), "다른 편집기에서 고친 문장", "덮어쓴 바깥 내용도 남는다")
  }

  func testChoosingDiskVersionReloadsAndStopsSaving() async throws {
    type(" 앱에서 쓴 문장")
    try externalWrite("다른 편집기에서 고친 문장")
    await autosaver.flush()
    _ = try await readyConflict()

    await autosaver.useDiskVersion(episode)
    await autosaver.flush()

    XCTAssertEqual(textView.string, "다른 편집기에서 고친 문장")
    XCTAssertEqual(try store.readEpisode(episode), "다른 편집기에서 고친 문장")
    XCTAssertTrue(autosaver.conflicts.isEmpty)
    XCTAssertFalse(autosaver.hasUnsavedChanges)
    XCTAssertEqual(try snapshotFiles().filter { $0.hasSuffix("-conflict.md") }.count, 1, "앱 쪽 본문은 스냅샷에 남아 있다")
  }

  func testTypingAfterChoosingDiskVersionSavesNormally() async throws {
    type(" 앱에서 쓴 문장")
    try externalWrite("다른 편집기에서 고친 문장")
    await autosaver.flush()
    _ = try await readyConflict()
    await autosaver.useDiskVersion(episode)

    type(" 이어 쓰기")
    await autosaver.flush()

    XCTAssertEqual(try store.readEpisode(episode), "다른 편집기에서 고친 문장 이어 쓰기")
    XCTAssertTrue(autosaver.conflicts.isEmpty)
  }

  /// During multi-cursor, treat it as "app-side changes" (ch.16 X4): ask instead of silently reloading and dropping the cursors.
  func testMultiCursorCountsAsAppChange() async throws {
    textView.multiCursor = MultiCursorSession(cursor: try XCTUnwrap(MultiCursor(
      ranges: [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)], wholeWord: false)))
    try externalWrite("다른 편집기에서 고친 문장")

    await autosaver.checkExternalChange()

    XCTAssertNotNil(autosaver.conflicts[episode], "묻는다")
    XCTAssertEqual(textView.string, "첫 문장", "묻기 전에는 화면 본문을 바꾸지 않는다")
    XCTAssertEqual(textView.multiCursorRanges?.count, 2)
  }

  /// When swapping in external content, also tell an IME continuing without displayed text to let go of that character.
  /// Otherwise the IME rewrites the old body's spot via `replacementRange`.
  func testReloadTellsInputMethodToForgetCharacterInProgress() throws {
    let method = try XCTUnwrap(class_getInstanceMethod(NSTextInputContext.self, #selector(NSTextInputContext.discardMarkedText)))
    let original = method_getImplementation(method)
    typealias Discard = @convention(c) (NSTextInputContext, Selector) -> Void
    nonisolated(unsafe) var discarded = 0
    let counting: @convention(block) (NSTextInputContext) -> Void = { context in
      discarded += 1
      unsafeBitCast(original, to: Discard.self)(context, #selector(NSTextInputContext.discardMarkedText))
    }
    method_setImplementation(method, imp_implementationWithBlock(counting))
    defer { method_setImplementation(method, original) }
    XCTAssertNotNil(textView.inputContext)

    textView.setSelectedRange(NSRange(location: 0, length: 0))
    textView.insertText("ㄱ", replacementRange: NSRange(location: NSNotFound, length: 0))
    XCTAssertFalse(textView.hasMarkedText())
    discarded = 0
    textView.reloadText(with: "바깥에서 쓴 글")
    XCTAssertEqual(discarded, 1, "외부 변경 불러오기")

    textView.insertText("ㄱ", replacementRange: NSRange(location: NSNotFound, length: 0))
    discarded = 0
    textView.replaceAllText(with: "다른 회차")
    XCTAssertEqual(discarded, 1, "회차 전환")
  }

  func testDeletedFileIsRecreatedFromApp() async throws {
    try FileManager.default.removeItem(at: store.layout.episodeFile(episode))

    await autosaver.checkExternalChange()
    await autosaver.flush()

    XCTAssertEqual(try store.readEpisode(episode), "첫 문장")
  }
}
