import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

/// 자동 저장. 원고 유실과 바로 이어지므로 실패 경우까지 확인한다.
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

  func testSavesAfterTypingPauses() async throws {
    type(" 둘째 문장")
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장", "입력 직후에는 아직 저장하지 않는다")

    try await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 둘째 문장")
    XCTAssertFalse(autosaver.hasUnsavedChanges)
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

  /// 저장이 계속 실패하면 원고를 메모리에 들고 있고, 다시 쓸 수 있게 되면 저장한다.
  func testFailedSaveKeepsTextInMemoryAndRecovers() async throws {
    let episodes = store.layout.episodesFolder.path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: episodes)
    type(" 지켜야 할 문장")

    await autosaver.flush()

    guard case .failed = autosaver.status else { return XCTFail("실패 상태여야 한다: \(autosaver.status)") }
    XCTAssertTrue(autosaver.hasUnsavedChanges)
    XCTAssertEqual(autosaver.unsavedText(for: episode), "첫 문장 지켜야 할 문장")
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장", "실패해도 원래 파일은 그대로")

    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: episodes)
    await autosaver.flush()

    XCTAssertEqual(autosaver.status, .idle)
    XCTAssertFalse(autosaver.hasUnsavedChanges)
    XCTAssertNil(autosaver.unsavedText(for: episode))
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 지켜야 할 문장")
  }

  /// 한글 조합 중에 저장해도 조합이 끊기지 않는다(텍스트 저장소를 읽기만 한다).
  func testSavingDuringCompositionKeepsMarkedText() async throws {
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    textView.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    autosaver.textDidChange()

    await autosaver.flush()

    XCTAssertTrue(textView.hasMarkedText(), "저장 뒤에도 조합 중이어야 한다")
    XCTAssertEqual(textView.markedRange().length, 1)
  }
}
