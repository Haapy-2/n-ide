import Foundation

/// File modification time and size. Used as a cheap first pass at detecting external changes (PLAN ch.5 "external change detection").
public struct FileStamp: Equatable, Sendable {
  public let modified: Date
  public let size: Int

  public init(modified: Date, size: Int) {
    self.modified = modified
    self.size = size
  }

  /// nil if the file is missing or its info can't be read.
  public init?(of url: URL) {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
      let modified = attributes[.modificationDate] as? Date,
      let size = attributes[.size] as? Int
    else { return nil }
    self.init(modified: modified, size: size)
  }
}

/// Disk state when the app last read or wrote the episode file. The next check compares against it.
public struct DiskVersion: Equatable, Sendable {
  /// nil means time/size can't be trusted, so the next check compares contents directly.
  public let stamp: FileStamp?
  public let text: String

  public init(stamp: FileStamp?, text: String) {
    self.stamp = stamp
    self.text = text
  }
}

/// Result of an external-change check.
public enum DiskCheck: Equatable, Sendable {
  /// Content unchanged. If only the time changed (a save with identical content), returns a state with the new time.
  case unchanged(DiskVersion)
  /// Content changed outside the app.
  case changed(DiskVersion)
  case missing
}

/// Result of a write that checks for external changes.
public enum EpisodeWriteResult: Equatable, Sendable {
  case written(DiskVersion)
  /// Not written because it changed outside the app. Holds the current disk state.
  case conflict(DiskVersion)
}

extension ProjectStore {
  /// Read an episode body together with the file state at that moment.
  public func readEpisodeVersion(_ id: EpisodeID) throws -> DiskVersion {
    let url = layout.episodeFile(id)
    // Time is read first, content after. If someone edits in between we get "old time + new content",
    // so the next check sees a different time and compares contents again, never missing the change (the reverse order could miss it).
    let stamp = FileStamp(of: url)
    return DiskVersion(stamp: stamp, text: try readText(at: url))
  }

  /// Check whether the episode file changed outside the app since `known`.
  /// If time and size match, the file isn't read. Otherwise contents are compared; identical contents (another app merely re-saved) count as unchanged.
  public func checkEpisode(_ id: EpisodeID, against known: DiskVersion) throws -> DiskCheck {
    let url = layout.episodeFile(id)
    guard let stamp = FileStamp(of: url) else { return .missing }
    if let knownStamp = known.stamp, knownStamp == stamp { return .unchanged(known) }
    let current = DiskVersion(stamp: stamp, text: try readText(at: url))
    return current.text == known.text ? .unchanged(current) : .changed(current)
  }

  /// Pre-save check + write. If changed outside the app since `known`, don't write and return `.conflict`.
  /// If `known` is nil or the file vanished, just write (restoring a vanished body from the app's content is safer).
  public func writeEpisode(_ text: String, id: EpisodeID, ifUnchangedSince known: DiskVersion?) throws
    -> EpisodeWriteResult
  {
    if let known, case .changed(let disk) = try checkEpisode(id, against: known) {
      return .conflict(disk)
    }
    let data = Data(text.utf8)
    let url = layout.episodeFile(id)
    try AtomicFile.write(data, to: url)
    var stamp = FileStamp(of: url)
    // If another app wrote again right before reading the time after our write, the size may differ. Then don't trust the time; compare contents next time.
    if stamp?.size != data.count { stamp = nil }
    return .written(DiskVersion(stamp: stamp, text: text))
  }
}
