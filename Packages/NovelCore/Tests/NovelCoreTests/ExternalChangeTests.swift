import Foundation
import Testing
@testable import NovelCore

/// External-change checks and conflict snapshots. A wrong decision would overwrite a manuscript edited in another editor, so check thoroughly.
struct ExternalChangeTests {
  private func makeStore(_ folder: TestFolder) throws -> (ProjectStore, EpisodeID) {
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let id = EpisodeID.make()
    try store.writeEpisode("처음 본문", id: id)
    return (store, id)
  }

  /// Write as another editor would save. Shift the time by 1 s so it isn't stamped with the same value.
  private func externalWrite(_ text: String, store: ProjectStore, id: EpisodeID, secondsLater: TimeInterval = 1) throws {
    let url = store.layout.episodeFile(id)
    let before = FileStamp(of: url)?.modified ?? Date()
    try Data(text.utf8).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: before.addingTimeInterval(secondsLater)], ofItemAtPath: url.path(percentEncoded: false))
  }

  @Test func untouchedFileIsUnchanged() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let known = try store.readEpisodeVersion(id)

    #expect(try store.checkEpisode(id, against: known) == .unchanged(known))
  }

  @Test func externalEditIsDetected() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let known = try store.readEpisodeVersion(id)

    try externalWrite("다른 편집기에서 고침", store: store, id: id)

    guard case .changed(let disk) = try store.checkEpisode(id, against: known) else {
      Issue.record("바뀐 것으로 보여야 한다")
      return
    }
    #expect(disk.text == "다른 편집기에서 고침")
  }

  /// Changes of equal size aren't missed (different times trigger a content comparison).
  @Test func sameSizeEditIsDetected() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let known = try store.readEpisodeVersion(id)

    try externalWrite("나중 본문", store: store, id: id)

    #expect(FileStamp(of: store.layout.episodeFile(id))?.size == known.stamp?.size)
    guard case .changed = try store.checkEpisode(id, against: known) else {
      Issue.record("크기가 같아도 바뀐 것으로 보여야 한다")
      return
    }
  }

  /// Same content with only the time changed (another app re-saved as is) is not a change. The new time is remembered.
  @Test func touchWithoutContentChangeIsUnchanged() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let known = try store.readEpisodeVersion(id)

    try externalWrite("처음 본문", store: store, id: id)

    let result = try store.checkEpisode(id, against: known)
    guard case .unchanged(let refreshed) = result else {
      Issue.record("내용이 같으면 바뀌지 않은 것이다: \(result)")
      return
    }
    #expect(refreshed.stamp != known.stamp)
    #expect(refreshed.text == "처음 본문")
  }

  @Test func deletedFileIsMissing() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let known = try store.readEpisodeVersion(id)

    try FileManager.default.removeItem(at: store.layout.episodeFile(id))

    #expect(try store.checkEpisode(id, against: known) == .missing)
  }

  // MARK: - Pre-save check

  @Test func writeSucceedsWhenUnchanged() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let known = try store.readEpisodeVersion(id)

    let result = try store.writeEpisode("앱에서 고침", id: id, ifUnchangedSince: known)

    guard case .written(let version) = result else {
      Issue.record("써야 한다: \(result)")
      return
    }
    #expect(try store.readEpisode(id) == "앱에서 고침")
    // Rechecking against the just-written state reports no change (the app's own save isn't seen as an external change).
    #expect(try store.checkEpisode(id, against: version) == .unchanged(version))
  }

  @Test func writeRefusesToOverwriteExternalEdit() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let known = try store.readEpisodeVersion(id)
    try externalWrite("다른 편집기에서 고침", store: store, id: id)

    let result = try store.writeEpisode("앱에서 고침", id: id, ifUnchangedSince: known)

    guard case .conflict(let disk) = result else {
      Issue.record("덮어쓰면 안 된다: \(result)")
      return
    }
    #expect(disk.text == "다른 편집기에서 고침")
    #expect(try store.readEpisode(id) == "다른 편집기에서 고침", "디스크의 외부 변경이 그대로 남아야 한다")
  }

  /// When the user chooses "keep app content", rewrite against the current disk state and overwrite.
  @Test func writeAfterChoosingAppVersionOverwrites() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let known = try store.readEpisodeVersion(id)
    try externalWrite("다른 편집기에서 고침", store: store, id: id)
    guard case .conflict(let disk) = try store.writeEpisode("앱에서 고침", id: id, ifUnchangedSince: known) else {
      Issue.record("충돌이어야 한다")
      return
    }

    guard case .written = try store.writeEpisode("앱에서 고침", id: id, ifUnchangedSince: disk) else {
      Issue.record("이번에는 써야 한다")
      return
    }
    #expect(try store.readEpisode(id) == "앱에서 고침")
  }

  @Test func writeRecreatesDeletedFile() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let known = try store.readEpisodeVersion(id)
    try FileManager.default.removeItem(at: store.layout.episodeFile(id))

    guard case .written = try store.writeEpisode("되살림", id: id, ifUnchangedSince: known) else {
      Issue.record("없어진 파일은 앱 내용으로 되살린다")
      return
    }
    #expect(try store.readEpisode(id) == "되살림")
  }

  // MARK: - Conflict snapshots

  @Test func conflictSnapshotKeepsAppText() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    var parts = DateComponents()
    (parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second) = (2026, 11, 11, 9, 45, 12)
    let date = Snapshot.utcCalendar.date(from: parts)!

    let first = try #require(try store.writeSnapshot("앱 쪽 본문", episode: id, kind: .conflict, at: date)).url
    let second = try #require(try store.writeSnapshot("앱 쪽 본문 2", episode: id, kind: .conflict, at: date)).url

    #expect(first.lastPathComponent == "20261111-094512Z-conflict.md")
    #expect(second.lastPathComponent == "20261111-094512Z-conflict-2.md", "같은 초에 또 찍어도 앞 것을 덮어쓰지 않는다")
    #expect(try String(contentsOf: first, encoding: .utf8) == "앱 쪽 본문")
    #expect(try String(contentsOf: second, encoding: .utf8) == "앱 쪽 본문 2")
    #expect(try store.readEpisode(id) == "처음 본문", "본문 파일은 건드리지 않는다")
  }
}
