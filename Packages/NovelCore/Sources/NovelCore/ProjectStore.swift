import Foundation

/// 작품 폴더 하나를 읽고 쓴다. 모든 쓰기는 원자적이다.
/// 메서드는 모두 동기 함수라서, 앱은 메인 스레드가 아닌 곳에서 부른다.
public struct ProjectStore: Sendable {
  public let layout: ProjectLayout

  public init(root: URL) {
    layout = ProjectLayout(root: root)
  }

  // MARK: - 작품

  /// 새 작품 폴더를 만든다. 같은 이름의 폴더가 있으면 건드리지 않고 실패한다.
  @discardableResult
  public static func create(at root: URL, title: String) throws -> ProjectStore {
    let fileManager = FileManager.default
    guard !fileManager.fileExists(atPath: root.path(percentEncoded: false)) else {
      throw ProjectError.alreadyExists(root)
    }
    let store = ProjectStore(root: root)
    for folder in [store.layout.episodesFolder, store.layout.notesFolder, store.layout.snapshotsFolder] {
      try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    try store.saveProject(ProjectFile(title: title))
    return store
  }

  /// `project.json`을 엄격하게 읽는다. 깨졌으면 복구하지 않고 오류를 던진다. 작품을 열 때는 `open()`을 쓴다.
  public func loadProject() throws -> ProjectFile {
    try Self.decodeProject(at: layout.projectFile)
  }

  /// 저장하기 전에 지금 파일이 정상이면 `project.json.bak`으로 남긴다. 깨진 파일로 백업을 덮어쓰지 않는다.
  public func saveProject(_ project: ProjectFile) throws {
    let current = layout.projectFile
    if let data = FileManager.default.contents(atPath: current.path(percentEncoded: false)),
      (try? Self.decodeProject(data: data, url: current)) != nil
    {
      try AtomicFile.write(data, to: layout.projectBackupFile)
    }
    let encoder = JSONEncoder()
    // 사람이 텍스트 편집기로 열어도 읽기 쉽게 들여쓰고, 키 순서를 고정해 git 비교도 깔끔하게 한다.
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try AtomicFile.write(try encoder.encode(project), to: current)
  }

  static func decodeProject(at url: URL) throws -> ProjectFile {
    guard let data = FileManager.default.contents(atPath: url.path(percentEncoded: false)) else {
      throw ProjectError.missingProjectFile(url)
    }
    return try decodeProject(data: data, url: url)
  }

  static func decodeProject(data: Data, url: URL) throws -> ProjectFile {
    // 버전부터 확인한다. 더 새 형식이면 전체를 해석하기 전에 거부해야 엉뚱한 오류가 나지 않는다.
    guard let header = try? JSONDecoder().decode(VersionHeader.self, from: data) else {
      throw ProjectError.corruptProjectFile(url)
    }
    guard header.schemaVersion <= ProjectFormat.currentSchemaVersion else {
      throw ProjectError.newerSchemaVersion(
        found: header.schemaVersion, supported: ProjectFormat.currentSchemaVersion)
    }
    guard let project = try? JSONDecoder().decode(ProjectFile.self, from: data) else {
      throw ProjectError.corruptProjectFile(url)
    }
    return project
  }

  // MARK: - 회차와 노트 본문

  public func readEpisode(_ id: EpisodeID) throws -> String {
    try readText(at: layout.episodeFile(id))
  }

  public func writeEpisode(_ text: String, id: EpisodeID) throws {
    try AtomicFile.write(Data(text.utf8), to: layout.episodeFile(id))
  }

  public func readNote(_ id: NoteID) throws -> String {
    try readText(at: layout.noteFile(id))
  }

  public func writeNote(_ text: String, id: NoteID) throws {
    try AtomicFile.write(Data(text.utf8), to: layout.noteFile(id))
  }

  /// 본문은 UTF-8 그대로 읽는다. 다른 편집기가 붙인 BOM만 떼고, 줄바꿈 등 나머지는 손대지 않는다.
  private func readText(at url: URL) throws -> String {
    guard var data = FileManager.default.contents(atPath: url.path(percentEncoded: false)) else {
      throw ProjectError.missingTextFile(url)
    }
    if data.starts(with: [0xEF, 0xBB, 0xBF]) {
      data.removeFirst(3)
    }
    guard let text = String(data: data, encoding: .utf8) else {
      throw ProjectError.notUTF8(url)
    }
    return text
  }

  private struct VersionHeader: Decodable {
    let schemaVersion: Int
  }
}
