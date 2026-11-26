import Foundation
import NovelCore
import XCTest
@testable import NovelEditor

/// 작품을 열 때 지난번에 쓰지 못한 원고(비상 백업)를 묻고 되살리기.
@MainActor
final class EmergencyBackupRecoveryTests: XCTestCase {
  private var folder: URL!

  override func setUp() async throws {
    let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    folder = repo.appending(path: "build/tmp/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: folder)
  }

  /// 내보내기를 골랐다가 폴더 창을 닫으면 아무것도 고르지 않은 것이라 다시 묻는다.
  /// 백업을 그대로 두고 열면, 그 회차를 새로 저장한 뒤에도 다음에 열 때 옛 글로 되살리자고 한다.
  func testCancelledExportAsksAgain() async throws {
    let root = folder.appending(path: "작품.novel")
    let store = try ProjectStore.create(at: root, title: "작품")
    var project = try store.loadProject()
    let episode = EpisodeMeta(title: "1화", goal: 5_000)
    project.episodes = [episode]
    try store.saveProject(project)
    try store.writeEpisode("파일 글", id: episode.id)
    let backup = EmergencyBackup(folder: folder.appending(path: "Backups"))
    try backup.write("백업 글", episode: episode.id, episodeTitle: "1화", projectTitle: "작품")

    var choices: [SystemDialogs.BackupChoice] = [.export, .restore]
    var asked = 0
    _ = await EmergencyBackupRecovery.run(
      backup, project: project, root: root,
      ask: { _ in
        asked += 1
        return choices.removeFirst()
      },
      export: { _ in false })

    XCTAssertEqual(asked, 2, "폴더 창을 닫았으면 다시 묻는다")
    XCTAssertEqual(try store.readEpisode(episode.id), "백업 글")
    XCTAssertTrue(backup.entries(for: [episode.id]).isEmpty)
  }
}
