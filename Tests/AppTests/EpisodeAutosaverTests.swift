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

  func testNoBackupWhenSavingSucceeds() async throws {
    let backup = EmergencyBackup(folder: folder.appending(path: "Backups"))
    autosaver.backup = backup
    type(" 잘 저장됨")
    await autosaver.flush()
    await autosaver.waitForBackups()
    XCTAssertFalse(FileManager.default.fileExists(atPath: backup.folder.path(percentEncoded: false)))
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

    guard case .failed = autosaver.status else { return XCTFail("실패 상태여야 한다: \(autosaver.status)") }
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

  /// 한글 조합 중에 저장해도 조합이 끊기지 않는다(텍스트 저장소를 읽기만 한다).
  func testSavingDuringCompositionKeepsMarkedText() async throws {
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    textView.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    autosaver.textDidChange()

    await autosaver.flush()

    XCTAssertTrue(textView.hasMarkedText(), "저장 뒤에도 조합 중이어야 한다")
    XCTAssertEqual(textView.markedRange().length, 1)
  }

  /// 회차를 떠나면 저장을 기다리지 않고 바로 돌아오지만, 곧바로 다시 열어도 방금 쓴 본문이 보인다.
  func testQuickReturnShowsLatestTextBeforeSaveFinishes() async throws {
    type(" 방금 쓴 문장")

    autosaver.leaveEpisode()

    XCTAssertEqual(autosaver.pendingText(for: episode), "첫 문장 방금 쓴 문장")
    await autosaver.flush()
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 방금 쓴 문장")
    XCTAssertNil(autosaver.pendingText(for: episode))
  }

  /// 떠난 회차의 본문 기준을 계속 들고 있지 않는다(훑어본 회차만큼 메모리가 늘지 않게). 저장이 끝난 뒤에 놓는다.
  func testReleasesBaselineAfterLeaving() async throws {
    let version = try store.readEpisodeVersion(episode)
    autosaver.begin(episode: episode, version: version)
    type(" 떠나기 전")
    autosaver.leaveEpisode()
    XCTAssertTrue(autosaver.holdsBaseline(for: episode), "저장이 끝나기 전에는 외부 변경 확인에 필요하다")

    await autosaver.flush()
    XCTAssertFalse(autosaver.holdsBaseline(for: episode))
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 떠나기 전")

    // 다시 열어 고치면 평소처럼 저장된다.
    let again = try store.readEpisodeVersion(episode)
    textView.replaceAllText(with: again.text)
    autosaver.begin(episode: episode, version: again)
    type(" 다시")
    await autosaver.flush()
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 떠나기 전 다시")
  }

  /// 저장에 실패해 메모리에 남은 회차는 떠나도 기준을 놓지 않는다(다시 저장할 때 외부 변경을 확인해야 한다).
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

  /// 저장이 실패한 뒤 더 새 본문을 쓰는 중에 돌아오면, 옛 실패 본문이 아니라 더 새 본문을 보여 준다.
  /// 옛 본문을 보여 주면 이어 쓴 글이 그사이 쓴 글("둘")을 덮어 조용히 사라진다.
  func testQuickReturnAfterFailedSaveShowsNewestText() async throws {
    let episodes = store.layout.episodesFolder.path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: episodes)
    type(" 하나")
    await autosaver.flush()
    XCTAssertEqual(autosaver.pendingText(for: episode), "첫 문장 하나", "실패한 본문은 메모리에")

    // 디스크가 돌아온 뒤 더 쓰고 떠난다. 새 저장은 시작만 했고 아직 안 끝났다.
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: episodes)
    type(" 둘")
    autosaver.leaveEpisode()

    // 바로 돌아와 이어 쓴다(회차 전환과 같은 순서).
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

  /// 창이 비활성화되거나 닫힐 때는 본문을 그 자리에서 복사해 저장을 시작한다.
  /// `Task` 안으로 미루면 창 닫기 처리가 끝난 뒤에 돌아, 그사이 편집기가 사라지면 마지막 입력을 못 읽는다.
  func testStartSaveCopiesTextRightAway() async throws {
    type(" 닫기 직전")

    autosaver.startSave()

    XCTAssertEqual(autosaver.pendingText(for: episode), "첫 문장 닫기 직전", "기다리기 전에 이미 복사돼 있다")
    await autosaver.flush()
    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 닫기 직전")
  }

  // MARK: - 다른 회차의 저장 실패

  /// 이 회차 파일 자리에 비어 있지 않은 폴더를 둬서, 이 회차 저장만 실패하게 한다(폴더 권한을 막으면 모든 회차가 실패한다).
  private func blockSaves(of id: EpisodeID) throws -> URL {
    let file = store.layout.episodeFile(id)
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    try Data().write(to: file.appending(path: "막음"))
    return file
  }

  /// 첫 회차 저장을 실패시킨 채 둘째 회차로 옮긴다. 첫 회차 본문은 메모리에만 있다.
  private func failFirstThenOpenSecond() async throws -> (blocked: URL, second: EpisodeID) {
    let second = EpisodeID.make()
    try store.writeEpisode("둘째 회차", id: second)
    let blocked = try blockSaves(of: episode)
    type(" 못 쓴 문장")
    await autosaver.flush()
    guard case .failed = autosaver.status else { throw XCTSkip("저장 실패를 만들지 못했다: \(autosaver.status)") }
    autosaver.leaveEpisode()
    // 떠날 때 시작한 저장(역시 실패)이 다 끝나길 기다린다. 안 기다리면 그 재시도가 막힘이 풀린 뒤 성공해 버려 이 상황이 재현되지 않는다.
    await autosaver.flush()
    textView.replaceAllText(with: "둘째 회차")
    autosaver.begin(episode: second)
    return (blocked, second)
  }

  /// 창 닫기·휴지통·⌘S의 `flush`는 열린 회차만이 아니라 저장에 실패해 메모리에 남은 다른 회차도 다시 저장한다.
  /// 열린 회차만 저장하면 다른 회차 본문은 창을 닫을 때 조용히 사라진다.
  func testFlushRetriesFailedSaveOfAnotherEpisode() async throws {
    let (blocked, _) = try await failFirstThenOpenSecond()
    try FileManager.default.removeItem(at: blocked)

    await autosaver.flush()

    XCTAssertEqual(try store.readEpisode(episode), "첫 문장 못 쓴 문장")
    XCTAssertFalse(autosaver.hasUnsavedChanges)
    XCTAssertEqual(autosaver.status, .idle)
  }

  /// 다른 회차가 저장되어도 앞 회차의 실패 표시는 남는다("저장 중"에 멈춰 실패가 가려지면 안 된다).
  func testFailureStaysVisibleWhileAnotherEpisodeSaves() async throws {
    let (_, second) = try await failFirstThenOpenSecond()
    type(" 둘째에 쓴 문장")

    await autosaver.flush()

    XCTAssertEqual(try store.readEpisode(second), "둘째 회차 둘째에 쓴 문장")
    guard case .failed = autosaver.status else { return XCTFail("첫 회차 실패가 보여야 한다: \(autosaver.status)") }
    XCTAssertTrue(autosaver.hasUnsavedChanges)
  }

  /// 끝내 저장하지 못한 원고를 다른 곳으로 내보낼 수 있게 제목과 본문을 내준다. 내보낸 뒤에는 남은 일이 없다.
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
