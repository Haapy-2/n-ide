import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

/// Autosave. Directly tied to manuscript loss, so failure cases are checked too.
@MainActor
final class EpisodeAutosaverTests: XCTestCase {
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
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.layout.episodesFolder.path(percentEncoded: false))
    try? FileManager.default.removeItem(at: folder)
  }

  private func type(_ text: String) {
    textView.insertText(text, replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
    autosaver.textDidChange()
  }

  /// Quit right after inserting a picture mid-composition: quit ends composition, waits for the line, and saves it.
  func testQuitWaitsForAPictureAndSavesItsLine() async throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = textView
    textView.project = store.layout
    let observer = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView, queue: nil) {
      [autosaver] _ in MainActor.assumeIsolated { autosaver?.textDidChange() }
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    textView.insertImages([.data(rep.representation(using: .png, properties: [:])!)])
    textView.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    XCTAssertTrue(autosaver.hasWorkBeforeQuit)

    await autosaver.finish()

    let saved = try store.readEpisode(episode)
    XCTAssertTrue(saved.hasPrefix("첫 문장ㅎ"), saved)
    XCTAssertTrue(saved.contains("\n![](../images/"), saved)
    XCTAssertFalse(autosaver.hasWorkBeforeQuit)
  }

  func testSavesAfterTypingPauses() async throws {
    type(" 둘째 문장")
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장", "입력 직후에는 아직 저장하지 않는다")

    try await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 둘째 문장")
    XCTAssertFalse(autosaver.hasUnsavedChanges)
  }

  func testSavesWhileTypingWithoutPause() async throws {
    autosaver = EpisodeAutosaver(
      store: store, queue: SaveQueue(retryDelays: [.milliseconds(5)]),
      delay: .milliseconds(150), maxWait: .milliseconds(300))
    autosaver.attach(textView)
    autosaver.begin(episode: episode)

    for _ in 0..<25 {
      type("가")
      try await Task.sleep(for: .milliseconds(30))
    }

    let saved = try store.readEpisode(episode)
    XCTAssertNotEqual(saved, "첫 문장", "쉬지 않고 쳐도 최대 대기 시간이 지나면 저장한다")
    XCTAssertTrue(textView.string.hasPrefix(saved))
  }

  func testFailedSaveIsBackedUpOutsideProjectUntilSaved() async throws {
    let backup = EmergencyBackup(folder: folder.appending(path: "Backups"))
    autosaver.backup = backup
    autosaver.projectTitle = { "작품" }
    autosaver.episodeTitle = { _ in "1화" }
    let episodes = store.layout.episodesFolder.path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: episodes)
    type(" 지켜야 할 문장")

    await autosaver.flush()
    await autosaver.waitForBackups()

    let saved = backup.entries(for: [episode])
    XCTAssertEqual(saved.map(\.text), ["첫 문장 지켜야 할 문장"], "작품 폴더에 못 쓴 원고는 밖에 따로 둔다")
    XCTAssertEqual(saved.first?.episodeTitle, "1화")
    XCTAssertEqual(saved.first?.projectTitle, "작품")

    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: episodes)
    await autosaver.flush()
    await autosaver.waitForBackups()

    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 지켜야 할 문장")
    XCTAssertTrue(backup.entries(for: [episode]).isEmpty, "저장되면 백업을 지운다")
  }

  /// If even the backup couldn't be written, it must not say "백업해 두었어요" (quit notice, status bar). Backed up only once actually written.
  func testBackupThatFailsToWriteIsNotReportedAsBackedUp() async throws {
    let backupFolder = folder.appending(path: "Backups")
    try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: backupFolder.path(percentEncoded: false))
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: backupFolder.path(percentEncoded: false))
    }
    autosaver.backup = EmergencyBackup(folder: backupFolder)
    let episodes = store.layout.episodesFolder.path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: episodes)
    type(" 지켜야 할 문장")

    await autosaver.flush()
    await autosaver.waitForBackups()

    XCTAssertFalse(autosaver.unprotectedAreBackedUp, "백업을 못 썼으면 종료 안내가 내보내기를 권해야 한다")
    guard case .failed(let failure) = autosaver.status else { return XCTFail("실패 상태여야 한다: \(autosaver.status)") }
    XCTAssertFalse(failure.isBackedUp, "상태 줄도 백업해 두었다고 하지 않는다")

    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: backupFolder.path(percentEncoded: false))
    await autosaver.flush()
    await autosaver.waitForBackups()

    XCTAssertTrue(autosaver.unprotectedAreBackedUp, "다시 시도해 백업이 써지면 백업됐다고 본다")
    guard case .failed(let again) = autosaver.status else { return XCTFail("실패 상태여야 한다: \(autosaver.status)") }
    XCTAssertTrue(again.isBackedUp)
  }

  func testNoBackupWhenSavingSucceeds() async throws {
    let backup = EmergencyBackup(folder: folder.appending(path: "Backups"))
    autosaver.backup = backup
    type(" 잘 저장됨")
    await autosaver.flush()
    await autosaver.waitForBackups()
    XCTAssertFalse(FileManager.default.fileExists(atPath: backup.folder.path(percentEncoded: false)))
  }

  func testPendingManuscriptsIncludeUnsavedEditorText() async throws {
    autosaver.episodeTitle = { _ in "1화" }
    XCTAssertTrue(autosaver.pendingManuscripts().isEmpty)
    type(" 아직 저장 전")
    XCTAssertEqual(autosaver.pendingManuscripts().map(\.text), ["첫 문장 아직 저장 전"])
    XCTAssertEqual(autosaver.pendingManuscripts().map(\.title), ["1화"])
    await autosaver.flush()
    XCTAssertTrue(autosaver.pendingManuscripts().isEmpty, "저장이 끝나면 내보낼 것이 없다")
  }

  func testFlushSavesImmediately() async throws {
    type(" 바로 저장")
    await autosaver.flush()
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 바로 저장")
  }

  func testNothingIsWrittenWithoutChanges() async throws {
    try FileManager.default.removeItem(at: store.layout.episodeFile(episode))
    await autosaver.flush()
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.layout.episodeFile(episode).path(percentEncoded: false)))
  }

  func testFailedSaveKeepsTextInMemoryAndRecovers() async throws {
    let episodes = store.layout.episodesFolder.path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: episodes)
    type(" 지켜야 할 문장")

    await autosaver.flush()

    guard case .failed(let failure) = autosaver.status else { return XCTFail("실패 상태여야 한다: \(autosaver.status)") }
    XCTAssertEqual(failure.label, "쓸 권한 없음", "까닭에 맞는 짧은 안내")
    XCTAssertTrue(failure.detail.contains("권한"))
    XCTAssertTrue(autosaver.hasUnsavedChanges)
    XCTAssertEqual(autosaver.pendingText(for: episode), "첫 문장 지켜야 할 문장")
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장", "실패해도 원래 파일은 그대로")

    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: episodes)
    await autosaver.flush()

    XCTAssertEqual(autosaver.status, .idle)
    XCTAssertFalse(autosaver.hasUnsavedChanges)
    XCTAssertNil(autosaver.pendingText(for: episode))
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 지켜야 할 문장")
  }

  /// Saving during Hangul composition doesn't break it (text storage is only read).
  /// Without a restore notice, typing doesn't touch the notice value. Touching it would redraw the status bar on every keystroke.
  func testTypingWithoutRestoreNoticeLeavesNoticeObserversAlone() {
    nonisolated(unsafe) var notified = false
    withObservationTracking {
      _ = autosaver.restoreNotice
    } onChange: {
      notified = true
    }

    type("가")

    XCTAssertFalse(notified)
  }

  func testSavingDuringCompositionKeepsMarkedText() async throws {
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    textView.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    autosaver.textDidChange()

    await autosaver.flush()

    XCTAssertTrue(textView.hasMarkedText(), "저장 뒤에도 조합 중이어야 한다")
    XCTAssertEqual(textView.markedRange().length, 1)
  }

  /// Leaving an episode returns immediately without waiting for the save, yet reopening right away still shows the just-written body.
  func testQuickReturnShowsLatestTextBeforeSaveFinishes() async throws {
    type(" 방금 쓴 문장")

    autosaver.leaveEpisode()

    XCTAssertEqual(autosaver.pendingText(for: episode), "첫 문장 방금 쓴 문장")
    await autosaver.flush()
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 방금 쓴 문장")
    XCTAssertNil(autosaver.pendingText(for: episode))
  }

  /// The left episode's body baseline isn't held on to (so memory doesn't grow with browsed episodes). Released after the save finishes.
  func testReleasesBaselineAfterLeaving() async throws {
    let version = try store.readEpisodeVersion(episode)
    autosaver.begin(episode: episode, version: version)
    type(" 떠나기 전")
    autosaver.leaveEpisode()
    XCTAssertTrue(autosaver.holdsBaseline(for: episode), "저장이 끝나기 전에는 외부 변경 확인에 필요하다")

    await autosaver.flush()
    XCTAssertFalse(autosaver.holdsBaseline(for: episode))
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 떠나기 전")

    // Reopening and editing saves as usual.
    let again = try store.readEpisodeVersion(episode)
    textView.replaceAllText(with: again.text)
    autosaver.begin(episode: episode, version: again)
    type(" 다시")
    await autosaver.flush()
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 떠나기 전 다시")
  }

  /// An episode left in memory after a failed save keeps its baseline even when left (external changes must be checked when re-saving).
  func testKeepsBaselineWhileUnsaved() async throws {
    let version = try store.readEpisodeVersion(episode)
    autosaver.begin(episode: episode, version: version)
    let episodes = store.layout.episodesFolder.path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: episodes)
    type(" 못 쓴 문장")
    autosaver.leaveEpisode()
    await autosaver.flush()

    XCTAssertTrue(autosaver.holdsBaseline(for: episode))
    XCTAssertEqual(autosaver.pendingText(for: episode), "첫 문장 못 쓴 문장")
  }

  /// Returning while a newer body is being written after a failed save shows the newer body, not the old failed one.
  /// Showing the old body would let continued typing overwrite what was written in between ("둘"), silently losing it.
  func testQuickReturnAfterFailedSaveShowsNewestText() async throws {
    let episodes = store.layout.episodesFolder.path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: episodes)
    type(" 하나")
    await autosaver.flush()
    XCTAssertEqual(autosaver.pendingText(for: episode), "첫 문장 하나", "실패한 본문은 메모리에")

    // After the disk comes back, write more and leave. The new save has only started and isn't finished.
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: episodes)
    type(" 둘")
    autosaver.leaveEpisode()

    // Come right back and keep writing (same order as an episode switch).
    let back = try XCTUnwrap(autosaver.pendingText(for: episode))
    XCTAssertEqual(back, "첫 문장 하나 둘")
    textView.replaceAllText(with: back)
    autosaver.begin(episode: episode)
    type(" 셋")
    await autosaver.flush()

    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 하나 둘 셋")
    XCTAssertFalse(autosaver.hasUnsavedChanges)
    XCTAssertEqual(autosaver.status, .idle)
  }

  /// On window deactivation or close, the body is copied in place and saving starts.
  /// Deferring into a `Task` would run after window-close handling; if the editor vanished meanwhile, the last input couldn't be read.
  func testStartSaveCopiesTextRightAway() async throws {
    type(" 닫기 직전")

    autosaver.startSave()

    XCTAssertEqual(autosaver.pendingText(for: episode), "첫 문장 닫기 직전", "기다리기 전에 이미 복사돼 있다")
    await autosaver.flush()
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 닫기 직전")
  }

  // MARK: - Save failure in another episode

  /// Put a non-empty folder where this episode's file goes so only this episode's save fails (blocking folder permissions would fail every episode).
  private func blockSaves(of id: EpisodeID) throws -> URL {
    let file = store.layout.episodeFile(id)
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    try Data().write(to: file.appending(path: "막음"))
    return file
  }

  /// Move to the second episode with the first episode's save failing. The first body exists only in memory.
  private func failFirstThenOpenSecond() async throws -> (blocked: URL, second: EpisodeID) {
    let second = EpisodeID.make()
    try store.writeEpisode("둘째 회차", id: second)
    let blocked = try blockSaves(of: episode)
    type(" 못 쓴 문장")
    await autosaver.flush()
    guard case .failed = autosaver.status else { throw XCTSkip("저장 실패를 만들지 못했다: \(autosaver.status)") }
    autosaver.leaveEpisode()
    // Wait for the save started on leave (also failing) to finish. Otherwise its retry succeeds after unblocking and the situation isn't reproduced.
    await autosaver.flush()
    textView.replaceAllText(with: "둘째 회차")
    autosaver.begin(episode: second)
    return (blocked, second)
  }

  /// `flush` from window close, trash and ⌘S re-saves not only the open episode but also other episodes left in memory after failed saves.
  /// Saving only the open episode would silently lose other episodes' bodies when the window closes.
  func testFlushRetriesFailedSaveOfAnotherEpisode() async throws {
    let (blocked, _) = try await failFirstThenOpenSecond()
    try FileManager.default.removeItem(at: blocked)

    await autosaver.flush()

    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 못 쓴 문장")
    XCTAssertFalse(autosaver.hasUnsavedChanges)
    XCTAssertEqual(autosaver.status, .idle)
  }

  /// Even when another episode saves, the earlier episode's failure indicator remains (it must not hide behind a stuck "saving").
  func testFailureStaysVisibleWhileAnotherEpisodeSaves() async throws {
    let (_, second) = try await failFirstThenOpenSecond()
    type(" 둘째에 쓴 문장")

    await autosaver.flush()

    XCTAssertEqual(try store.readEpisode(second), "둘째 회차 둘째에 쓴 문장")
    guard case .failed = autosaver.status else { return XCTFail("첫 회차 실패가 보여야 한다: \(autosaver.status)") }
    XCTAssertTrue(autosaver.hasUnsavedChanges)
  }

  /// Hands over titles and bodies so manuscripts that ultimately couldn't be saved can be exported elsewhere. Nothing remains after export.
  func testUnsavedManuscriptsCanBeRescued() async throws {
    _ = try await failFirstThenOpenSecond()
    autosaver.episodeTitle = { [episode] id in id == episode ? "1화" : "?" }

    let rescued = autosaver.unsavedManuscripts()

    XCTAssertEqual(rescued.map(\.title), ["1화"])
    XCTAssertEqual(rescued.map(\.text), ["첫 문장 못 쓴 문장"])
    autosaver.markRescued()
    XCTAssertFalse(autosaver.hasUnsavedChanges)
  }
}
