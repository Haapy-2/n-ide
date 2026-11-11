import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

/// 외부 변경 처리 (8단계). 다른 편집기에서 고친 원고도, 앱에서 쓰던 원고도 잃지 않는지 본다.
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

    autosaver.useDiskVersion(episode)
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
    autosaver.useDiskVersion(episode)

    type(" 이어 쓰기")
    await autosaver.flush()

    XCTAssertEqual(try store.readEpisode(episode), "다른 편집기에서 고친 문장 이어 쓰기")
    XCTAssertTrue(autosaver.conflicts.isEmpty)
  }

  func testDeletedFileIsRecreatedFromApp() async throws {
    try FileManager.default.removeItem(at: store.layout.episodeFile(episode))

    await autosaver.checkExternalChange()
    await autosaver.flush()

    XCTAssertEqual(try store.readEpisode(episode), "첫 문장")
  }
}
