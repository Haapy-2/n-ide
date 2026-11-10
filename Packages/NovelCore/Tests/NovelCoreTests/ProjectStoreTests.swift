import Foundation
import Testing
@testable import NovelCore

struct ProjectStoreTests {
  // MARK: - 작품 만들기

  @Test func createMakesFolderStructure() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let root = folder.url.appending(path: "달빛 아래 검.novel")

    try ProjectStore.create(at: root, title: "달빛 아래 검")

    #expect(try folder.fileNames(in: root) == ["episodes", "notes", "project.json", "snapshots"])
  }

  @Test func createRefusesExistingFolder() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let root = folder.url.appending(path: "작품.novel")
    let store = try ProjectStore.create(at: root, title: "원래 작품")

    #expect(throws: ProjectError.alreadyExists(root)) {
      try ProjectStore.create(at: root, title: "덮어쓰면 안 됨")
    }
    #expect(try store.loadProject().title == "원래 작품")
  }

  // MARK: - project.json

  @Test func projectRoundTrip() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "회귀한 검성")
    var project = try store.loadProject()
    project.episodes = [
      EpisodeMeta(title: "1화 귀환", goal: 5_000),
      EpisodeMeta(title: "", goal: 4_500),
    ]
    project.notes = [NoteMeta(title: "주인공 설정")]
    project.settings.defaultEpisodeGoal = 4_500

    try store.saveProject(project)

    #expect(try store.loadProject() == project)
  }

  @Test func projectJSONIsReadableText() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "한글 제목")

    let json = try String(contentsOf: store.layout.projectFile, encoding: .utf8)

    // 다른 편집기로 열어도 읽을 수 있어야 한다: 한글이 \u 이스케이프 없이 그대로, 줄바꿈 들여쓰기.
    #expect(json.contains("\"title\" : \"한글 제목\""))
    #expect(json.contains("\"schemaVersion\" : 1"))
    #expect(json.contains("\n"))
  }

  @Test func newerSchemaVersionIsRejectedAndFileUntouched() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let future = #"{ "schemaVersion" : 99, "title" : "미래 앱이 만든 작품", "새필드" : true }"#
    try Data(future.utf8).write(to: store.layout.projectFile)

    #expect(throws: ProjectError.newerSchemaVersion(found: 99, supported: 1)) {
      try store.loadProject()
    }
    #expect(try String(contentsOf: store.layout.projectFile, encoding: .utf8) == future)
  }

  @Test func corruptProjectFileIsReported() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    try Data("{ 반쯤 쓰인".utf8).write(to: store.layout.projectFile)

    #expect(throws: ProjectError.corruptProjectFile(store.layout.projectFile)) {
      try store.loadProject()
    }
  }

  @Test func missingSchemaVersionIsCorrupt() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    try Data(#"{ "title" : "버전 없음" }"#.utf8).write(to: store.layout.projectFile)

    #expect(throws: ProjectError.corruptProjectFile(store.layout.projectFile)) {
      try store.loadProject()
    }
  }

  @Test func missingProjectFileIsReported() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = ProjectStore(root: folder.url.appending(path: "없는작품.novel"))

    #expect(throws: ProjectError.missingProjectFile(store.layout.projectFile)) {
      try store.loadProject()
    }
  }

  // MARK: - 본문

  @Test func episodeRoundTripKeepsTextExactly() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let id = EpisodeID.make()
    // 한글, 이모지, 조합형 문자, 빈 줄, 다른 편집기가 넣었을 CRLF까지 그대로 보존되어야 한다.
    let text = String(repeating: "가나다라마바사 ", count: 700)
      + "\n\n\"대사\" — 🗡️ e\u{301}\r\n마지막 줄"

    try store.writeEpisode(text, id: id)

    #expect(try store.readEpisode(id) == text)
  }

  @Test func episodeIsStoredAsPlainUTF8WithoutBOM() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let id = EpisodeID.make()

    try store.writeEpisode("첫 줄\n둘째 줄", id: id)

    let bytes = try Data(contentsOf: store.layout.episodeFile(id))
    #expect(bytes == Data("첫 줄\n둘째 줄".utf8))
  }

  @Test func episodeFileNameIsItsIDAndSurvivesRename() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    var project = try store.loadProject()
    let episode = EpisodeMeta(title: "옛 제목", goal: 5_000)
    project.episodes.append(episode)
    try store.saveProject(project)
    try store.writeEpisode("본문", id: episode.id)

    project.episodes[0].title = "새 제목"
    try store.saveProject(project)

    #expect(try folder.fileNames(in: store.layout.episodesFolder) == ["\(episode.id.rawValue).md"])
    #expect(try store.readEpisode(episode.id) == "본문")
  }

  @Test func readingStripsBOMAddedByOtherEditors() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let id = EpisodeID.make()
    try (Data([0xEF, 0xBB, 0xBF]) + Data("본문".utf8)).write(to: store.layout.episodeFile(id))

    #expect(try store.readEpisode(id) == "본문")
  }

  @Test func nonUTF8EpisodeIsReportedNotGuessed() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let id = EpisodeID.make()
    try Data([0xB0, 0xA1, 0xFF, 0xFE]).write(to: store.layout.episodeFile(id))  // EUC-KR 등 다른 인코딩 흉내

    #expect(throws: ProjectError.notUTF8(store.layout.episodeFile(id))) {
      try store.readEpisode(id)
    }
  }

  @Test func missingEpisodeFileIsReportedNotTreatedAsEmpty() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let id = EpisodeID.make()

    #expect(throws: ProjectError.missingTextFile(store.layout.episodeFile(id))) {
      try store.readEpisode(id)
    }
  }

  @Test func noteRoundTrip() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let id = NoteID.make()

    try store.writeNote("이름: 한서윤\n나이: 19", id: id)

    #expect(try store.readNote(id) == "이름: 한서윤\n나이: 19")
  }
}
