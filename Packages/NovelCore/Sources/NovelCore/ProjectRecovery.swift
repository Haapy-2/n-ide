import Foundation

/// 작품을 열 때 `project.json`이 어떻게 읽혔는지.
public enum ProjectRecovery: Equatable, Sendable {
  /// 정상으로 읽었다.
  case none
  /// `project.json`이 깨졌거나 없어서 `project.json.bak`으로 복구했다.
  case fromBackup
  /// 백업도 쓸 수 없어서 `episodes/`, `notes/` 폴더의 파일로 목록을 다시 만들었다.
  /// 회차 순서와 제목은 되살릴 수 없어서 파일 생성 시각 순서, 빈 제목이 된다.
  case rebuiltFromFiles
}

extension ProjectStore {
  /// 작품을 연다. `project.json`이 깨졌으면 백업 → 본문 파일 순으로 복구하고 복구한 내용을 다시 저장한다.
  ///
  /// 어떤 경우에도 본문 파일은 지우거나 고치지 않는다. 깨진 `project.json`도 지우지 않고
  /// `project.json.broken-<시각>`으로 이름을 바꿔 남긴다.
  /// 더 새 형식 버전이면 복구하지 않고 열기를 거부한다(새 앱이 만든 정보를 망가뜨리지 않기 위해).
  public func open() throws -> (project: ProjectFile, recovery: ProjectRecovery) {
    do {
      return (try loadProject(), .none)
    } catch ProjectError.corruptProjectFile, ProjectError.missingProjectFile {
      // 아래에서 복구한다.
    }

    if let backup = try backupProject() {
      try setAsideBrokenProjectFile()
      try saveProject(backup)
      return (backup, .fromBackup)
    }

    // episodes/ 폴더도 없으면 작품 폴더가 아닌 것으로 보고, 엉뚱한 폴더에 파일을 만들지 않는다.
    guard FileManager.default.fileExists(atPath: layout.episodesFolder.path(percentEncoded: false)) else {
      throw ProjectError.missingProjectFile(layout.projectFile)
    }
    let rebuilt = try rebuildFromFiles()
    try setAsideBrokenProjectFile()
    try saveProject(rebuilt)
    return (rebuilt, .rebuiltFromFiles)
  }

  /// 백업이 쓸 만하면 돌려준다. 더 새 형식이면 오류를 그대로 던진다.
  private func backupProject() throws -> ProjectFile? {
    do {
      return try Self.decodeProject(at: layout.projectBackupFile)
    } catch ProjectError.corruptProjectFile, ProjectError.missingProjectFile {
      return nil
    }
  }

  /// 깨진 `project.json`을 지우지 않고 옆으로 치워 둔다. 없으면 아무것도 하지 않는다.
  private func setAsideBrokenProjectFile() throws {
    let fileManager = FileManager.default
    let broken = layout.projectFile
    guard fileManager.fileExists(atPath: broken.path(percentEncoded: false)) else { return }
    let stamp = Int(Date().timeIntervalSince1970)
    let aside = layout.root.appending(path: "project.json.broken-\(stamp)", directoryHint: .notDirectory)
    try fileManager.moveItem(at: broken, to: aside)
  }

  /// `episodes/`, `notes/` 폴더의 `.md` 파일로 목록을 다시 만든다. 파일 내용은 읽지 않는다.
  private func rebuildFromFiles() throws -> ProjectFile {
    let title = layout.root.deletingPathExtension().lastPathComponent
    var project = ProjectFile(title: title)
    project.episodes = try markdownFileIDs(in: layout.episodesFolder).map {
      EpisodeMeta(id: EpisodeID(rawValue: $0), title: "", goal: project.settings.defaultEpisodeGoal)
    }
    project.notes = try markdownFileIDs(in: layout.notesFolder).map {
      NoteMeta(id: NoteID(rawValue: $0), title: "")
    }
    return project
  }

  /// 폴더 안 `.md` 파일의 이름(=ID)을 만든 시각 순서로. 폴더가 없으면 빈 목록.
  private func markdownFileIDs(in folder: URL) throws -> [String] {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: folder.path(percentEncoded: false)) else { return [] }
    let files = try fileManager.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension == "md" }
    let dated = files.map { url in
      (url, (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
    }
    return dated
      .sorted { $0.1 == $1.1 ? $0.0.lastPathComponent < $1.0.lastPathComponent : $0.1 < $1.1 }
      .map { $0.0.deletingPathExtension().lastPathComponent }
  }
}
