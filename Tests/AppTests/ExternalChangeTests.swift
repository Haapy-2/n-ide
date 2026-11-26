import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

/// 외부 변경 처리. 다른 편집기에서 고친 원고도, 앱에서 쓰던 원고도 잃지 않는지 본다.
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

  /// 다른 편집기가 저장한 것처럼 쓴다. 수정 시각이 같은 값으로 찍히지 않게 1초 뒤로 맞춘다.
  private func externalWrite(_ text: String) throws {
    let url = store.layout.episodeFile(episode)
    let before = FileStamp(of: url)?.modified ?? Date()
    try Data(text.utf8).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: before.addingTimeInterval(1)], ofItemAtPath: url.path(percentEncoded: false))
  }

  /// 앱 쪽 스냅샷을 다 남겨 물을 준비가 될 때까지 기다린다.
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

  // MARK: - 충돌을 고르지 않은 채 끌 때 (PLAN 미결정 27)

  /// 앱 쪽 글이 충돌 스냅샷에 그대로 있으면 "저장 못 한 원고"가 아니다: 다시 시도·내보내기 대상에서 빠지고 따로 센다.
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

  /// 끄면서 한 저장이 외부 변경을 막 찾은 경우(⌘Q를 자동 저장 1초 안에 누름): 마무리가 충돌 스냅샷까지 기다려,
  /// 종료 판단이 "내보낼 원고"가 아니라 "지켜진 충돌"로 본다.
  func testConflictFoundWhileFinishingIsKeptBeforeQuitDecision() async throws {
    type(" 앱에서 쓴 문장")
    try externalWrite("다른 편집기에서 고친 문장")

    await autosaver.finish()

    XCTAssertEqual(autosaver.conflictsKeptInSnapshots, 1)
    XCTAssertFalse(autosaver.hasUnprotectedChanges)
    XCTAssertEqual(try store.readEpisode(episode), "다른 편집기에서 고친 문장", "바깥 글을 덮지 않는다")
  }

  /// 충돌 뒤에 더 쓴 글은 스냅샷에 없으므로 지켜야 할 원고다.
  func testTypingAfterConflictIsUnprotected() async throws {
    type(" 앱에서 쓴 문장")
    try externalWrite("다른 편집기에서 고친 문장")
    await autosaver.checkExternalChange()
    _ = try await readyConflict()

    type(" 더 쓴 문장")

    XCTAssertTrue(autosaver.hasUnprotectedChanges)
    XCTAssertEqual(autosaver.conflictsKeptInSnapshots, 0)
  }

  /// 충돌 스냅샷마저 남기지 못했으면 앱 쪽 글은 메모리에만 있다. 내보내기를 권해야 하고, 백업이 있다고 말하면 안 된다.
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

  /// 충돌 스냅샷을 남기지 못한 채 "바깥 내용"을 고르면 앱 쪽 글이 어디에도 남지 않는다. 그때는 바꾸지 않는다.
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

    // 스냅샷을 남길 수 있게 되면 다시 고를 수 있고, 앱 쪽 글은 스냅샷에 남는다.
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: snapshots.path(percentEncoded: false))
    await autosaver.useDiskVersion(episode)

    XCTAssertNil(autosaver.conflicts[episode])
    XCTAssertEqual(textView.string, "다른 편집기에서 고친 문장")
    XCTAssertEqual(try conflictSnapshotTexts(), ["첫 문장 앱에서 쓴 문장"])
  }

  /// 충돌 스냅샷 뒤에 더 친 글도 "바깥 내용"으로 바꾸기 전에 스냅샷으로 남긴다.
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

  /// "이 앱의 내용"을 고를 때 덮을 바깥 내용을 스냅샷으로 남기지 못하면 덮지 않는다.
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

  /// 여러 커서 중이면 "앱 쪽 변경 있음"으로 본다(16장 X4): 조용히 다시 읽어 커서들을 버리지 않고 묻는다.
  func testMultiCursorCountsAsAppChange() async throws {
    textView.multiCursor = MultiCursorSession(cursor: try XCTUnwrap(MultiCursor(
      ranges: [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)], wholeWord: false)))
    try externalWrite("다른 편집기에서 고친 문장")

    await autosaver.checkExternalChange()

    XCTAssertNotNil(autosaver.conflicts[episode], "묻는다")
    XCTAssertEqual(textView.string, "첫 문장", "묻기 전에는 화면 본문을 바꾸지 않는다")
    XCTAssertEqual(textView.multiCursorRanges?.count, 2)
  }

  /// 바깥 내용으로 갈아 끼울 때, 표시된 글자 없이 이어 가던 입력기에도 그 글자를 놓으라고 알린다.
  /// 알리지 않으면 입력기가 옛 본문의 자리를 `replacementRange`로 고쳐 쓴다.
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
