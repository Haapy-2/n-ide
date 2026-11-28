import Foundation
import Testing
@testable import NovelCore

/// Manuscripts that couldn't be saved to the project folder are kept outside it and restored on the next open.
struct EmergencyBackupTests {
  @Test func writesAndFindsOnlyThisProjectsEpisodes() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let backup = EmergencyBackup(folder: folder.url.appending(path: "Backups"))
    let mine = EpisodeID.make()
    let other = EpisodeID.make()
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    try backup.write("살릴 원고", episode: mine, episodeTitle: "1화", projectTitle: "작품", at: date)
    try backup.write("다른 작품", episode: other, episodeTitle: "x", projectTitle: "y")

    let found = backup.entries(for: [mine])
    #expect(found == [.init(episodeID: mine, text: "살릴 원고", episodeTitle: "1화", projectTitle: "작품", savedAt: date)])
  }

  @Test func missingFolderMeansNoBackups() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    #expect(EmergencyBackup(folder: folder.url.appending(path: "없음")).entries(for: [EpisodeID.make()]).isEmpty)
  }

  @Test func keepsTextEvenWithoutInfoFile() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let backup = EmergencyBackup(folder: folder.url)
    let id = EpisodeID.make()
    try backup.write("본문", episode: id, episodeTitle: "1화", projectTitle: "작품")
    try FileManager.default.removeItem(at: folder.url.appending(path: "\(id.rawValue).json"))

    let found = backup.entries(for: [id])
    #expect(found.map(\.text) == ["본문"])
    #expect(found.first?.savedAt == nil)
  }

  @Test func removeDeletesBothFilesAndIgnoresMissing() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let backup = EmergencyBackup(folder: folder.url)
    let id = EpisodeID.make()
    try backup.write("본문", episode: id, episodeTitle: "", projectTitle: "")

    try backup.remove(id)
    try backup.remove(id)

    #expect(try folder.fileNames(in: folder.url).isEmpty)
  }

  @Test func restoreKeepsCurrentFileAsSnapshotThenWrites() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "작품")
    let id = EpisodeID.make()
    try store.writeEpisode("디스크의 옛 글", id: id)
    let backup = EmergencyBackup(folder: folder.url.appending(path: "Backups"))
    try backup.write("저장 못 한 새 글", episode: id, episodeTitle: "1화", projectTitle: "작품")
    let entry = try #require(backup.entries(for: [id]).first)

    #expect(try backup.restore(entry, into: store, memo: "비상 백업에서 되살리기 전"))

    #expect(try store.readEpisode(id) == "저장 못 한 새 글")
    let snapshot = try #require(try store.snapshots(of: id).last)
    #expect(snapshot.kind == .restore)
    #expect(try store.readSnapshot(snapshot) == "디스크의 옛 글")
    #expect(store.readMemo(snapshot) == "비상 백업에서 되살리기 전")
    #expect(backup.entries(for: [id]).isEmpty)
  }

  @Test func restoreSkipsWhenFileAlreadyHasTheText() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "작품")
    let id = EpisodeID.make()
    try store.writeEpisode("같은 글", id: id)
    let backup = EmergencyBackup(folder: folder.url.appending(path: "Backups"))
    try backup.write("같은 글", episode: id, episodeTitle: "", projectTitle: "")

    #expect(try !backup.restore(try #require(backup.entries(for: [id]).first), into: store, memo: ""))

    #expect(try store.snapshots(of: id).isEmpty)
    #expect(backup.entries(for: [id]).isEmpty)
  }

  @Test func restoreRecreatesMissingEpisodeFile() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "작품")
    let id = EpisodeID.make()
    let backup = EmergencyBackup(folder: folder.url.appending(path: "Backups"))
    try backup.write("파일이 없어진 회차", episode: id, episodeTitle: "", projectTitle: "")

    #expect(try backup.restore(try #require(backup.entries(for: [id]).first), into: store, memo: ""))

    #expect(try store.readEpisode(id) == "파일이 없어진 회차")
    #expect(try store.snapshots(of: id).isEmpty)
  }

  /// If the current file can't be read (not UTF-8 etc.), don't overwrite without a `복원 전` snapshot. Overwriting would lose that file's content entirely.
  @Test func restoreRefusesWhenCurrentFileCannotBeRead() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "작품")
    let id = EpisodeID.make()
    let unreadable = Data([0xFF, 0xFE, 0x00, 0xD8])
    try unreadable.write(to: store.layout.episodeFile(id))
    let backup = EmergencyBackup(folder: folder.url.appending(path: "Backups"))
    try backup.write("백업 글", episode: id, episodeTitle: "", projectTitle: "")

    #expect(throws: (any Error).self) {
      try backup.restore(try #require(backup.entries(for: [id]).first), into: store, memo: "")
    }

    #expect(try Data(contentsOf: store.layout.episodeFile(id)) == unreadable)
    #expect(backup.entries(for: [id]).map(\.text) == ["백업 글"], "되살리지 못했으니 백업은 그대로")
  }
}
