import Foundation

/// Reads and writes one project folder. All writes are atomic.
/// All methods are synchronous, so the app calls them off the main thread.
public struct ProjectStore: Sendable {
  public let layout: ProjectLayout

  public init(root: URL) {
    layout = ProjectLayout(root: root)
  }

  // MARK: - Project

  /// Create a new project folder. If a folder with the same name exists, fail without touching it.
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

  /// Read `project.json` strictly. If broken, throw without recovering. Use `open()` when opening a project.
  public func loadProject() throws -> ProjectFile {
    try Self.decodeProject(at: layout.projectFile)
  }

  /// Before saving, keep the current file as `project.json.bak` if it's valid. A broken file never overwrites the backup.
  /// The backup is a bonus, so the real save proceeds even if it fails. Stopping the real save on a backup failure would lose the changed episode list entirely.
  public func saveProject(_ project: ProjectFile) throws {
    let current = layout.projectFile
    if let data = FileManager.default.contents(atPath: current.path(percentEncoded: false)),
      (try? Self.decodeProject(data: data, url: current)) != nil
    {
      try? AtomicFile.write(data, to: layout.projectBackupFile)
    }
    let encoder = JSONEncoder()
    // Indented for readability in a text editor, with fixed key order for clean git diffs.
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
    // Check the version first. A newer format must be rejected before decoding everything, to avoid misleading errors.
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

  // MARK: - Episode and note bodies

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

  /// Bodies are read as UTF-8 as is. Only a BOM added by other editors is stripped; newlines and everything else are untouched.
  func readText(at url: URL) throws -> String {
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
