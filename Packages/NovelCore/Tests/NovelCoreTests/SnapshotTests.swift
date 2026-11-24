import Foundation
import Testing
@testable import NovelCore

/// 스냅샷 저장·목록·메모·정리. 정리는 실제로 파일을 지우므로 "지우면 안 되는 것"을 가장 꼼꼼히 본다.
struct SnapshotTests {
  private func makeStore(_ folder: TestFolder) throws -> (ProjectStore, EpisodeID) {
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let id = EpisodeID.make()
    try store.writeEpisode("본문", id: id)
    return (store, id)
  }

  private func time(_ seconds: Int) -> Date {
    var parts = DateComponents()
    (parts.year, parts.month, parts.day, parts.hour) = (2026, 11, 11, 9)
    return Calendar(identifier: .gregorian).date(from: parts)!.addingTimeInterval(TimeInterval(seconds))
  }

  private func names(_ store: ProjectStore, _ id: EpisodeID) throws -> [String] {
    try store.snapshots(of: id).map(\.id)
  }

  // MARK: - 찍기와 목록

  @Test func writesNamedFileAndReadsBack() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)

    let snapshot = try #require(try store.writeSnapshot("한글 본문 😀", episode: id, kind: .manual, at: time(65)))

    #expect(snapshot.id == "20261111-090105-manual.md")
    #expect(snapshot.kind == .manual)
    #expect(snapshot.date == time(65))
    #expect(try store.readSnapshot(snapshot) == "한글 본문 😀")
    #expect(try store.readEpisode(id) == "본문", "본문 파일은 건드리지 않는다")
  }

  @Test func emptyWhenNoFolder() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    #expect(try store.snapshots(of: id).isEmpty)
  }

  @Test func listIsTimeOrderAndSameSecondGetsNumber() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)

    try store.writeSnapshot("c", episode: id, kind: .auto, at: time(20))
    try store.writeSnapshot("a", episode: id, kind: .leave, at: time(5))
    try store.writeSnapshot("b1", episode: id, kind: .auto, at: time(10))
    try store.writeSnapshot("b2", episode: id, kind: .auto, at: time(10))
    try store.writeSnapshot("b3", episode: id, kind: .auto, at: time(10))

    #expect(try names(store, id) == [
      "20261111-090005-leave.md",
      "20261111-090010-auto.md",
      "20261111-090010-auto-2.md",
      "20261111-090010-auto-3.md",
      "20261111-090020-auto.md",
    ])
    let texts = try store.snapshots(of: id).map { try store.readSnapshot($0) }
    #expect(texts == ["a", "b1", "b2", "b3", "c"], "같은 초에 또 찍어도 앞 것을 덮지 않는다")
  }

  @Test func ignoresUnknownFiles() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    try store.writeSnapshot("x", episode: id, kind: .auto, at: time(0))
    let snapshotFolder = store.layout.snapshotFolder(id)
    for name in [
      "메모.txt", "20261111-090000-odd.md", "2026-auto.md", "20261111-090000-auto-1.md",
      ".20261111-090000-auto.md.tmp", "20261111-0900xx-auto.md", "README.md",
      "20261311-090000-auto.md", "20261111-256000-auto.md",
    ] {
      try Data("?".utf8).write(to: snapshotFolder.appending(path: name))
    }

    #expect(try names(store, id) == ["20261111-090000-auto.md"])
  }

  @Test func skipsWhenSameAsLatest() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)

    #expect(try store.writeSnapshot("가", episode: id, kind: .leave, at: time(0), skipIfSameAsLatest: true) != nil,
      "처음에는 비교할 것이 없어 찍는다")
    #expect(try store.writeSnapshot("가", episode: id, kind: .auto, at: time(1), skipIfSameAsLatest: true) == nil)
    #expect(try store.writeSnapshot("가나", episode: id, kind: .auto, at: time(2), skipIfSameAsLatest: true) != nil)
    #expect(try store.writeSnapshot("가", episode: id, kind: .auto, at: time(3), skipIfSameAsLatest: true) != nil,
      "가장 최근 것과만 비교한다")
    #expect(try store.writeSnapshot("가", episode: id, kind: .manual, at: time(4)) != nil, "직접 찍기는 같아도 찍는다")
    #expect(try store.snapshots(of: id).count == 4)
  }

  // MARK: - 메모

  @Test func memoIsSeparateFile() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)

    let snapshot = try #require(
      try store.writeSnapshot("본문 그대로", episode: id, kind: .manual, memo: "  고백 장면 전\n", at: time(0)))

    #expect(store.readMemo(snapshot) == "고백 장면 전", "앞뒤 공백은 다듬는다")
    #expect(try store.readSnapshot(snapshot) == "본문 그대로", "메모가 본문에 섞이지 않는다")
    #expect(try folder.fileNames(in: store.layout.snapshotFolder(id))
      == ["20261111-090000-manual.md", "20261111-090000-manual.memo"])
    #expect(try names(store, id) == ["20261111-090000-manual.md"], "메모 파일은 목록에 따로 잡히지 않는다")
  }

  @Test func memoEditAndClear() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let snapshot = try #require(try store.writeSnapshot("본문", episode: id, kind: .manual, memo: "  ", at: time(0)))

    #expect(store.readMemo(snapshot) == nil, "빈 메모는 파일을 만들지 않는다")
    try store.writeMemo("처음", for: snapshot)
    try store.writeMemo("고친 메모", for: snapshot)
    #expect(store.readMemo(snapshot) == "고친 메모")
    try store.writeMemo("", for: snapshot)
    #expect(store.readMemo(snapshot) == nil)
    #expect(try store.readSnapshot(snapshot) == "본문", "메모를 지워도 스냅샷은 남는다")
  }

  // MARK: - 정리

  @Test func pruneRemovesOldestAutoAndLeaveOnly() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    // 자동·떠날 때 12개 사이사이에 지우면 안 되는 종류를 끼워 둔다.
    let keepKinds: [SnapshotKind] = [.manual, .restore, .conflict, .external]
    for index in 0..<12 {
      try store.writeSnapshot("\(index)", episode: id, kind: index.isMultiple(of: 2) ? .auto : .leave, at: time(index * 10))
      if index < keepKinds.count {
        try store.writeSnapshot("keep", episode: id, kind: keepKinds[index], at: time(index * 10 + 1))
      }
    }
    try Data("?".utf8).write(to: store.layout.snapshotFolder(id).appending(path: "모르는 파일.md"))

    let removed = try store.pruneSnapshots(of: id, keeping: 10)

    #expect(removed.map(\.id) == ["20261111-090000-auto.md", "20261111-090010-leave.md"], "오래된 것부터")
    let left = try store.snapshots(of: id)
    #expect(left.filter(\.kind.isPrunable).count == 10)
    #expect(Set(left.filter { !$0.kind.isPrunable }.map(\.kind)) == Set(keepKinds), "다른 종류는 하나도 안 지운다")
    #expect(try folder.fileNames(in: store.layout.snapshotFolder(id)).contains("모르는 파일.md"))
    #expect(try store.readEpisode(id) == "본문")
    #expect(try store.pruneSnapshots(of: id, keeping: 10).isEmpty, "넘치지 않으면 아무것도 안 지운다")
  }

  @Test func pruneFollowsLimitChanges() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    for index in 0..<120 {
      try store.writeSnapshot("\(index)", episode: id, kind: .auto, at: time(index))
    }

    try store.pruneSnapshots(of: id, keeping: 100)
    #expect(try store.snapshots(of: id).count == 100)
    try store.pruneSnapshots(of: id, keeping: 10)
    let left = try store.snapshots(of: id)
    #expect(left.count == 10)
    #expect(try left.map { try store.readSnapshot($0) } == (110..<120).map(String.init), "가장 새 것만 남는다")
  }

  @Test func pruneNeverEmptiesWithBadLimit() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    for index in 0..<3 { try store.writeSnapshot("\(index)", episode: id, kind: .leave, at: time(index)) }

    try store.pruneSnapshots(of: id, keeping: 0)
    #expect(try names(store, id) == ["20261111-090002-leave.md"])
  }

  @Test func pruneKeepsSnapshotsWithMemo() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let kept = try #require(try store.writeSnapshot("옛", episode: id, kind: .auto, memo: "남길 것", at: time(0)))
    try store.writeSnapshot("가운데", episode: id, kind: .leave, at: time(1))
    let later = try #require(try store.writeSnapshot("뒤", episode: id, kind: .auto, at: time(2)))
    try store.writeSnapshot("새", episode: id, kind: .auto, at: time(3))
    // 나중에 메모를 단 것도 지킨다.
    try store.writeMemo("이것도", for: later)

    let removed = try store.pruneSnapshots(of: id, keeping: 1)

    #expect(removed.map(\.id) == ["20261111-090001-leave.md"], "메모 단 것은 세지도 지우지도 않는다")
    #expect(try folder.fileNames(in: store.layout.snapshotFolder(id)) == [
      "20261111-090000-auto.md", "20261111-090000-auto.memo",
      "20261111-090002-auto.md", "20261111-090002-auto.memo", "20261111-090003-auto.md",
    ])
    #expect(store.readMemo(kept) == "남길 것")
  }

  @Test func renameCountsAndGoesEvenWithMemoUnlessKept() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let oldest = try #require(
      try store.writeSnapshot("본문", episode: id, kind: .rename, memo: "'1화' → '프롤로그'", title: "1화", at: time(0)))
    let kept = try #require(
      try store.writeSnapshot("본문", episode: id, kind: .rename, memo: "남길 것", title: "프롤로그", at: time(1)))
    try store.keep(kept)
    try store.writeSnapshot("고침", episode: id, kind: .auto, at: time(2))
    try store.writeSnapshot("본문", episode: id, kind: .rename, memo: "새 것", title: "", at: time(3))

    #expect(store.readTitle(oldest) == "1화")
    let removed = try store.pruneSnapshots(of: id, keeping: 2)

    #expect(removed.map(\.id) == [oldest.id], "메모가 있어도 이름 변경은 보관 개수에 세고 지운다")
    #expect(try folder.fileNames(in: store.layout.snapshotFolder(id)) == [
      "20261111-090001-rename.keep", "20261111-090001-rename.md", "20261111-090001-rename.memo",
      "20261111-090001-rename.title", "20261111-090002-auto.md",
      "20261111-090003-rename.md", "20261111-090003-rename.memo", "20261111-090003-rename.title",
    ], "지운 것은 메모·제목 파일까지 함께, 지킨 것은 그대로")
    #expect(try store.snapshots(of: id).last.map { store.readTitle($0) } == "", "빈 제목도 남긴다")
    #expect(store.isKept(kept))
  }

  /// 같은 초에 여러 개 찍다가 앞 번호가 정리돼도, 다음 것은 빈 번호가 아니라 뒤 번호를 받아 가장 새 것으로 남는다.
  @Test func sameSecondNeverReusesPrunedNumber() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    for index in 0..<3 { try store.writeSnapshot("\(index)", episode: id, kind: .rename, at: time(0)) }
    try store.pruneSnapshots(of: id, keeping: 1)
    #expect(try names(store, id) == ["20261111-090000-rename-3.md"])

    try store.writeSnapshot("새", episode: id, kind: .rename, at: time(0))
    try store.pruneSnapshots(of: id, keeping: 1)

    #expect(try store.snapshots(of: id).map { try store.readSnapshot($0) } == ["새"])
  }

  @Test func memoKeepsOnlyNonRenameKinds() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let auto = try #require(try store.writeSnapshot("가", episode: id, kind: .auto, memo: "메모", at: time(0)))
    let rename = try #require(try store.writeSnapshot("가", episode: id, kind: .rename, memo: "메모", at: time(1)))
    #expect(store.isKept(auto))
    #expect(!store.isKept(rename))
    try store.keep(auto)
    try store.writeMemo("", for: auto)
    #expect(!store.isKept(auto), "이름 변경이 아닌 것은 메모만 본다")
  }

  @Test func pruneLeavesOtherEpisodesAlone() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let other = EpisodeID.make()
    for index in 0..<3 {
      try store.writeSnapshot("\(index)", episode: id, kind: .auto, at: time(index))
      try store.writeSnapshot("\(index)", episode: other, kind: .auto, at: time(index))
    }

    try store.pruneSnapshots(of: id, keeping: 1)
    #expect(try store.snapshots(of: other).count == 3)
  }

  @Test func nameKeepsFixedWidthAndLocalTime() throws {
    var parts = DateComponents()
    (parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second) = (2027, 1, 2, 3, 4, 5)
    let date = Calendar(identifier: .gregorian).date(from: parts)!
    #expect(Snapshot.stamp(for: date) == "20270102-030405", "한 자리 수도 0을 채워 이름순이 시간순이 되게")
  }

  // MARK: - 덮지 않기, 지우면 안 되는 것

  @Test func neverOverwritesExistingName() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let snapshotFolder = store.layout.snapshotFolder(id)
    try FileManager.default.createDirectory(at: snapshotFolder, withIntermediateDirectories: true)
    // 다른 곳이 먼저 같은 이름(과 그다음 번호)을 써 둔 경우
    try Data("먼저 1".utf8).write(to: snapshotFolder.appending(path: "20261111-090000-auto.md"))
    try Data("먼저 2".utf8).write(to: snapshotFolder.appending(path: "20261111-090000-auto-2.md"))

    let snapshot = try #require(try store.writeSnapshot("새것", episode: id, kind: .auto, at: time(0)))

    #expect(snapshot.id == "20261111-090000-auto-3.md")
    #expect(try String(contentsOf: snapshotFolder.appending(path: "20261111-090000-auto.md"), encoding: .utf8) == "먼저 1")
    #expect(try String(contentsOf: snapshotFolder.appending(path: "20261111-090000-auto-2.md"), encoding: .utf8) == "먼저 2")
    #expect(try !folder.fileNames(in: snapshotFolder).contains { $0.hasSuffix(".tmp") }, "임시 파일이 남지 않는다")
  }

  @Test func atomicWriteWithoutReplacingLeavesExistingFile() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let url = folder.url.appending(path: "있는 파일.md")
    try Data("원래".utf8).write(to: url)

    #expect(throws: AtomicFile.AlreadyExists.self) { try AtomicFile.write(Data("새것".utf8), to: url, replacing: false) }
    #expect(try String(contentsOf: url, encoding: .utf8) == "원래")
    #expect(try folder.fileNames(in: folder.url) == ["있는 파일.md"])
  }

  @Test func pruneNeverTouchesFoldersOrLinks() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, id) = try makeStore(folder)
    let snapshotFolder = store.layout.snapshotFolder(id)
    try FileManager.default.createDirectory(at: snapshotFolder, withIntermediateDirectories: true)
    // 이름만 스냅샷처럼 생긴 폴더(안에 파일)와, 본문 파일을 가리키는 바로가기
    let fakeFolder = snapshotFolder.appending(path: "20261111-085900-auto.md")
    try FileManager.default.createDirectory(at: fakeFolder, withIntermediateDirectories: true)
    try Data("안의 파일".utf8).write(to: fakeFolder.appending(path: "중요.txt"))
    try FileManager.default.createSymbolicLink(
      at: snapshotFolder.appending(path: "20261111-085901-auto.md"), withDestinationURL: store.layout.episodeFile(id))
    for index in 0..<3 { try store.writeSnapshot("\(index)", episode: id, kind: .auto, at: time(index)) }

    #expect(try store.snapshots(of: id).count == 3, "폴더와 바로가기는 목록에 없다")
    try store.pruneSnapshots(of: id, keeping: 1)

    #expect(FileManager.default.fileExists(atPath: fakeFolder.appending(path: "중요.txt").path(percentEncoded: false)))
    #expect(try store.readEpisode(id) == "본문", "바로가기가 가리키는 본문은 그대로")
    #expect(try store.snapshots(of: id).map(\.id) == ["20261111-090002-auto.md"])
  }
}
