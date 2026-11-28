import Foundation

/// How `project.json` was read when opening the project.
public enum ProjectRecovery: Equatable, Sendable {
  /// Read normally.
  case none
  /// `project.json` was broken or missing, so it was recovered from `project.json.bak`.
  case fromBackup
  /// The backup was unusable too, so the list was rebuilt from files in `episodes/` and `notes/`.
  /// Episode order and titles can't be recovered, so they're ordered by file creation time with empty titles.
  case rebuiltFromFiles
}

extension ProjectStore {
  /// Open a project. If `project.json` is broken, recover from the backup, then from body files, and save the recovered content.
  ///
  /// Body files are never deleted or modified. The broken `project.json` isn't deleted either;
  /// it's renamed to `project.json.broken-<time>` and kept.
  /// For a newer format version, refuse to open without recovering (so info made by a newer app isn't destroyed).
  public func open() throws -> (project: ProjectFile, recovery: ProjectRecovery) {
    do {
      return (try loadProject(), .none)
    } catch ProjectError.corruptProjectFile, ProjectError.missingProjectFile {
      // Recover below.
    }

    if let backup = try backupProject() {
      try setAsideBrokenProjectFile()
      try saveProject(backup)
      return (backup, .fromBackup)
    }

    // Without an episodes/ folder it isn't a project folder, so don't create files in some unrelated folder.
    guard FileManager.default.fileExists(atPath: layout.episodesFolder.path(percentEncoded: false)) else {
      throw ProjectError.missingProjectFile(layout.projectFile)
    }
    let rebuilt = try rebuildFromFiles()
    try setAsideBrokenProjectFile()
    try saveProject(rebuilt)
    return (rebuilt, .rebuiltFromFiles)
  }

  /// Return the backup if usable. For a newer format, rethrow the error.
  private func backupProject() throws -> ProjectFile? {
    do {
      return try Self.decodeProject(at: layout.projectBackupFile)
    } catch ProjectError.corruptProjectFile, ProjectError.missingProjectFile {
      return nil
    }
  }

  /// Move a broken `project.json` aside instead of deleting it. No-op if absent.
  private func setAsideBrokenProjectFile() throws {
    let fileManager = FileManager.default
    let broken = layout.projectFile
    guard fileManager.fileExists(atPath: broken.path(percentEncoded: false)) else { return }
    let stamp = Int(Date().timeIntervalSince1970)
    var aside = layout.root.appending(path: "project.json.broken-\(stamp)", directoryHint: .notDirectory)
    // Even moving twice in the same second (opening in quick succession), number it so the earlier one isn't overwritten and opening doesn't fail on a name clash.
    var number = 2
    while fileManager.fileExists(atPath: aside.path(percentEncoded: false)) {
      aside = layout.root.appending(path: "project.json.broken-\(stamp)-\(number)", directoryHint: .notDirectory)
      number += 1
    }
    try fileManager.moveItem(at: broken, to: aside)
  }

  /// Rebuild the list from `.md` files in `episodes/` and `notes/`. File contents aren't read.
  private func rebuildFromFiles() throws -> ProjectFile {
    let title = layout.root.deletingPathExtension().lastPathComponent
    var project = ProjectFile(title: title)
    project.episodes = try markdownFiles(in: layout.episodesFolder).map {
      EpisodeMeta(id: EpisodeID(rawValue: $0.id), title: "", goal: project.settings.defaultEpisodeGoal)
    }
    project.notes = try markdownFiles(in: layout.notesFolder).map {
      NoteMeta(id: NoteID(rawValue: $0.id), title: "")
    }
    return project
  }

  /// Episode files in `episodes/` missing from the list (`listed`), by creation time. Only names and sizes are checked; contents aren't read.
  /// A list restored from backup lacks episodes created after the backup, so those manuscripts appear gone. This finds them.
  /// Empty files are excluded: they're traces of the app quitting mid-creation (empty body → list save), with no text to recover.
  public func unlistedEpisodes(excluding listed: Set<EpisodeID>) throws -> [EpisodeID] {
    try markdownFiles(in: layout.episodesFolder)
      .filter { $0.size > 0 }
      .map { EpisodeID(rawValue: $0.id) }
      .filter { !listed.contains($0) }
  }

  /// Names (= IDs) and sizes of `.md` files in the folder, by creation time. Empty list if the folder is missing.
  private func markdownFiles(in folder: URL) throws -> [(id: String, size: Int)] {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: folder.path(percentEncoded: false)) else { return [] }
    let files = try fileManager.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension == "md" }
    let described = files.map { url in
      let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
      return (url: url, created: values?.creationDate ?? .distantPast, size: values?.fileSize ?? 0)
    }
    return described
      .sorted { $0.created == $1.created ? $0.url.lastPathComponent < $1.url.lastPathComponent : $0.created < $1.created }
      .map { ($0.url.deletingPathExtension().lastPathComponent, $0.size) }
  }
}
