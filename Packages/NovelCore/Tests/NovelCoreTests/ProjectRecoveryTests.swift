import Foundation
import Testing
@testable import NovelCore

/// `project.json` 보호와 복구. 어떤 경우에도 본문 파일은 지워지거나 바뀌면 안 된다.
struct ProjectRecoveryTests {
  /// 회차 3개와 본문이 있는 작품을 만든다.
  private func makeProject(in folder: TestFolder) throws -> (ProjectStore, ProjectFile) {
    let store = try ProjectStore.create(at: folder.url.appending(path: "달빛 아래 검.novel"), title: "달빛 아래 검")
    var project = try store.loadProject()
    project.episodes = (1...3).map { EpisodeMeta(title: "\($0)화", goal: 5_000) }
    try store.saveProject(project)
    for (index, episode) in project.episodes.enumerated() {
      try store.writeEpisode("\(index + 1)화 본문", id: episode.id)
    }
    return (store, project)
  }

  private func episodeBytes(_ store: ProjectStore) throws -> [String: Data] {
    let folder = store.layout.episodesFolder
    var result: [String: Data] = [:]
    for name in try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) {
      result[name] = try Data(contentsOf: folder.appending(path: name))
    }
    return result
  }

  private func breakProjectFile(_ store: ProjectStore) throws {
    try Data("{ \"schemaVersion\" : 1, \"title\" : \"반쯤".utf8).write(to: store.layout.projectFile)
  }

  // MARK: - 백업

  @Test func saveKeepsPreviousGoodVersionAsBackup() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, before) = try makeProject(in: folder)
    var after = before
    after.title = "바뀐 제목"

    try store.saveProject(after)

    let backup = try JSONDecoder().decode(
      ProjectFile.self, from: Data(contentsOf: store.layout.projectBackupFile))
    #expect(backup == before)
    #expect(try store.loadProject() == after)
  }

  @Test func brokenProjectFileNeverOverwritesBackup() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, project) = try makeProject(in: folder)
    try store.saveProject(project)  // 이제 백업 = project
    try breakProjectFile(store)

    var next = project
    next.title = "새 제목"
    try store.saveProject(next)

    let backup = try JSONDecoder().decode(
      ProjectFile.self, from: Data(contentsOf: store.layout.projectBackupFile))
    #expect(backup == project)
  }

  // MARK: - 열기와 복구

  @Test func openNormalProjectNeedsNoRecovery() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, project) = try makeProject(in: folder)

    let opened = try store.open()

    #expect(opened.project == project)
    #expect(opened.recovery == .none)
  }

  @Test func brokenProjectFileIsRestoredFromBackup() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, project) = try makeProject(in: folder)
    try store.saveProject(project)  // 백업 = project
    let bodiesBefore = try episodeBytes(store)
    try breakProjectFile(store)

    let opened = try store.open()

    #expect(opened.recovery == .fromBackup)
    #expect(opened.project == project)
    #expect(try store.loadProject() == project)  // 복구한 내용이 다시 저장됨
    #expect(try episodeBytes(store) == bodiesBefore)
    // 깨진 파일은 지우지 않고 옆에 남는다.
    let names = try folder.fileNames(in: store.layout.root)
    #expect(names.contains { $0.hasPrefix("project.json.broken-") })
  }

  @Test func withoutUsableBackupListIsRebuiltFromEpisodeFiles() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, project) = try makeProject(in: folder)
    let bodiesBefore = try episodeBytes(store)
    try breakProjectFile(store)
    try Data("백업도 깨짐".utf8).write(to: store.layout.projectBackupFile)

    let opened = try store.open()

    #expect(opened.recovery == .rebuiltFromFiles)
    #expect(opened.project.title == "달빛 아래 검")  // 폴더 이름에서
    #expect(Set(opened.project.episodes.map(\.id)) == Set(project.episodes.map(\.id)))
    #expect(opened.project.episodes.allSatisfy { $0.goal == 5_000 })
    #expect(try episodeBytes(store) == bodiesBefore)
    for episode in project.episodes {
      #expect(try store.readEpisode(episode.id).hasSuffix("화 본문"))
    }
  }

  @Test func missingProjectFileIsRebuiltWhenEpisodesExist() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, project) = try makeProject(in: folder)
    try FileManager.default.removeItem(at: store.layout.projectFile)
    try FileManager.default.removeItem(at: store.layout.projectBackupFile)

    let opened = try store.open()

    #expect(opened.recovery == .rebuiltFromFiles)
    #expect(opened.project.episodes.count == project.episodes.count)
  }

  @Test func rebuiltOrderFollowsFileCreationTime() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    // 이름 순서와 만든 순서를 일부러 반대로 한다.
    let ids = ["ccc", "bbb", "aaa"].map(EpisodeID.init(rawValue:))
    for (index, id) in ids.enumerated() {
      try store.writeEpisode("본문", id: id)
      let date = Date(timeIntervalSince1970: 1_000_000 + Double(index) * 60)
      try FileManager.default.setAttributes(
        [.creationDate: date], ofItemAtPath: store.layout.episodeFile(id).path(percentEncoded: false))
    }
    try FileManager.default.removeItem(at: store.layout.projectFile)

    let opened = try store.open()

    #expect(opened.project.episodes.map(\.id) == ids)
  }

  @Test func newerVersionIsNeverRecoveredOrRewritten() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let (store, _) = try makeProject(in: folder)
    let future = Data(#"{ "schemaVersion" : 7, "title" : "미래" }"#.utf8)
    try future.write(to: store.layout.projectFile)

    #expect(throws: ProjectError.newerSchemaVersion(found: 7, supported: 1)) {
      try store.open()
    }
    #expect(try Data(contentsOf: store.layout.projectFile) == future)
  }

  @Test func folderThatIsNotAProjectIsLeftAlone() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = ProjectStore(root: folder.url)

    #expect(throws: ProjectError.missingProjectFile(store.layout.projectFile)) {
      try store.open()
    }
    #expect(try folder.fileNames(in: folder.url).isEmpty)
  }
}
