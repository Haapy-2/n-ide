import Foundation

/// 작품 폴더 안의 파일 위치. 경로는 밖에서 받은 작품 폴더 URL 하나로만 정해진다.
///
/// ```
/// 내작품.novel/
///   project.json
///   episodes/<회차ID>.md
///   notes/<노트ID>.md
///   snapshots/<회차ID>/<시각>.md
/// ```
public struct ProjectLayout: Sendable {
  public let root: URL

  public init(root: URL) { self.root = root }

  public var projectFile: URL { root.appending(path: "project.json", directoryHint: .notDirectory) }
  public var episodesFolder: URL { root.appending(path: "episodes", directoryHint: .isDirectory) }
  public var notesFolder: URL { root.appending(path: "notes", directoryHint: .isDirectory) }
  public var snapshotsFolder: URL { root.appending(path: "snapshots", directoryHint: .isDirectory) }

  public func episodeFile(_ id: EpisodeID) -> URL {
    episodesFolder.appending(path: "\(id.rawValue).md", directoryHint: .notDirectory)
  }

  public func noteFile(_ id: NoteID) -> URL {
    notesFolder.appending(path: "\(id.rawValue).md", directoryHint: .notDirectory)
  }
}
