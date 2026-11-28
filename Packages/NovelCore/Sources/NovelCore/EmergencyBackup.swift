import Foundation

/// Manuscripts that couldn't be saved to the project folder are kept in a separate folder outside it. Restored on next open even if the app crashed.
/// Outside the project so whatever broke the project folder (permissions, full disk, locked sync folder) doesn't block the backup.
/// Folder layout: `<episodeID>.md` (body as is, fine for humans to open) and `<episodeID>.json` (title, time).
/// Keyed by episode ID, so it survives moving the project folder in Finder.
public struct EmergencyBackup: Sendable {
  public struct Entry: Equatable, Sendable {
    public let episodeID: EpisodeID
    public let text: String
    public let episodeTitle: String
    public let projectTitle: String
    /// nil if the info file couldn't be read.
    public let savedAt: Date?
  }

  private struct Info: Codable {
    var episodeTitle: String
    var projectTitle: String
    var savedAt: Date
  }

  public let folder: URL

  public init(folder: URL) {
    self.folder = folder
  }

  /// Body first, then info. The body survives even if writing info fails.
  public func write(
    _ text: String, episode id: EpisodeID, episodeTitle: String, projectTitle: String, at date: Date = Date()
  ) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try AtomicFile.write(Data(text.utf8), to: textURL(id))
    let info = Info(episodeTitle: episodeTitle, projectTitle: projectTitle, savedAt: date)
    try AtomicFile.write(try Self.encoder.encode(info), to: infoURL(id))
  }

  /// Backups for these episodes. Reads the folder listing once (usually empty). Backups with unreadable bodies are skipped.
  public func entries(for ids: Set<EpisodeID>) -> [Entry] {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else {
      return []
    }
    return names.compactMap { name -> Entry? in
      guard name.hasSuffix(".md") else { return nil }
      let id = EpisodeID(rawValue: String(name.dropLast(3)))
      guard ids.contains(id),
        let data = try? Data(contentsOf: textURL(id)),
        let text = String(data: data, encoding: .utf8)
      else { return nil }
      let info = (try? Data(contentsOf: infoURL(id))).flatMap { try? Self.decoder.decode(Info.self, from: $0) }
      return Entry(
        episodeID: id, text: text, episodeTitle: info?.episodeTitle ?? "", projectTitle: info?.projectTitle ?? "",
        savedAt: info?.savedAt)
    }
    .sorted { $0.episodeID.rawValue < $1.episodeID.rawValue }
  }

  /// Delete the backup. No-op if absent. Call only after the manuscript was safely written to the project folder.
  public func remove(_ id: EpisodeID) throws {
    for url in [textURL(id), infoURL(id)] where FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
      try FileManager.default.removeItem(at: url)
    }
  }

  /// Locations of the two backup files (for moving to the trash).
  public func files(of id: EpisodeID) -> [URL] {
    [textURL(id), infoURL(id)].filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
  }

  /// Restore the backup body into the project's episode file. If the current file body differs, keep it first as a `복원 전` snapshot,
  /// so it can still be diffed or restored in the snapshot panel afterwards. The backup is deleted only after everything is written.
  /// If equal to the file (already saved), don't write; just delete the backup. True if restored.
  @discardableResult
  /// Throws if the file exists but can't be read (not UTF-8 etc.). Overwriting without a snapshot would lose that content entirely.
  public func restore(_ entry: Entry, into store: ProjectStore, memo: String) throws -> Bool {
    let file = store.layout.episodeFile(entry.episodeID).path(percentEncoded: false)
    let current = FileManager.default.fileExists(atPath: file) ? try store.readEpisode(entry.episodeID) : nil
    guard current != entry.text else {
      try remove(entry.episodeID)
      return false
    }
    if let current {
      try store.writeSnapshot(current, episode: entry.episodeID, kind: .restore, memo: memo)
    }
    try store.writeEpisode(entry.text, id: entry.episodeID)
    try remove(entry.episodeID)
    return true
  }

  private func textURL(_ id: EpisodeID) -> URL {
    folder.appending(path: "\(id.rawValue).md", directoryHint: .notDirectory)
  }

  private func infoURL(_ id: EpisodeID) -> URL {
    folder.appending(path: "\(id.rawValue).json", directoryHint: .notDirectory)
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}
