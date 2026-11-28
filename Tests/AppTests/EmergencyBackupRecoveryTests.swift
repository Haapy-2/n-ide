import Foundation
import NovelCore
import XCTest
@testable import NovelEditor

/// On project open, ask about and restore manuscripts that couldn't be written last time (emergency backup).
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

  /// Choosing export and then closing the folder dialog means nothing was chosen, so ask again.
  /// Opening with the backup left in place would, even after that episode is saved anew, offer to restore the old text next time.
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
