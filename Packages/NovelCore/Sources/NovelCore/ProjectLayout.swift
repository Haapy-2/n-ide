import Foundation

/// File locations inside the project folder. Paths derive solely from the project folder URL passed in.
///
/// ```
/// 내작품.novel/
///   project.json
///   project.json.bak
///   episodes/<episodeID>.md
///   notes/<noteID>.md
///   snapshots/<episodeID>/<time>-<kind>.md (+ memo in .memo)
/// ```
public struct ProjectLayout: Sendable {
  public let root: URL

  public init(root: URL) { self.root = root }

  public var projectFile: URL { root.appending(path: "project.json", directoryHint: .notDirectory) }
  /// Last good copy. Recover from here when `project.json` is broken.
  public var projectBackupFile: URL { root.appending(path: "project.json.bak", directoryHint: .notDirectory) }
  public var episodesFolder: URL { root.appending(path: "episodes", directoryHint: .isDirectory) }
  public var notesFolder: URL { root.appending(path: "notes", directoryHint: .isDirectory) }
  public var snapshotsFolder: URL { root.appending(path: "snapshots", directoryHint: .isDirectory) }
  public var imagesFolder: URL { root.appending(path: "images", directoryHint: .isDirectory) }

  /// File of an image line's `.project` source. The name comes from `ImageLine` (no `/`, `..`), so it stays inside `images/`.
  public func imageFile(named fileName: String) -> URL {
    imagesFolder.appending(path: fileName, directoryHint: .notDirectory)
  }

  public func episodeFile(_ id: EpisodeID) -> URL {
    episodesFolder.appending(path: "\(id.rawValue).md", directoryHint: .notDirectory)
  }

  public func snapshotFolder(_ id: EpisodeID) -> URL {
    snapshotsFolder.appending(path: id.rawValue, directoryHint: .isDirectory)
  }

  public func noteFile(_ id: NoteID) -> URL {
    notesFolder.appending(path: "\(id.rawValue).md", directoryHint: .notDirectory)
  }
}
