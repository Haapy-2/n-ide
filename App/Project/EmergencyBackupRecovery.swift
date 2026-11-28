import Foundation
import NovelCore

/// When opening a project, if manuscripts that couldn't be written to the project folder last time exist (emergency backup), ask and restore them (PLAN ch.17 #1).
/// Files are fixed before the episode is shown, so the editor reads the restored text from the start.
@MainActor
enum EmergencyBackupRecovery {
  nonisolated static let snapshotMemo = "비상 백업에서 되살리기 전"

  /// Returns project info with corrected counts for restored episodes. Unchanged if there's no backup.
  static func run(
    _ backup: EmergencyBackup, project: ProjectFile, root: URL,
    ask: @MainActor ([String]) -> SystemDialogs.BackupChoice = SystemDialogs.offerBackupRestore(episodeNames:),
    export: @MainActor ([(title: String, text: String)]) -> Bool = SystemDialogs.exportUnsaved
  ) async -> ProjectFile {
    let ids = Set(project.episodes.map(\.id))
    let store = ProjectStore(root: root)
    // If the file already has the same text (saved, but the backup wasn't deleted), delete it without asking.
    let entries = await Task.detached(priority: .userInitiated) {
      backup.entries(for: ids).filter { entry in
        guard (try? store.readEpisode(entry.episodeID)) == entry.text else { return true }
        try? backup.remove(entry.episodeID)
        return false
      }
    }.value
    guard !entries.isEmpty else { return project }

    let names = entries.map { name(of: $0, in: project) }
    while true {
      switch ask(names) {
      case .restore:
        return await restore(entries, backup: backup, store: store, project: project)
      case .export:
        let manuscripts = zip(entries, names).map { (title: $1, text: $0.text) }
        // Closing the folder dialog means nothing was chosen, so ask again. Opening with the backup left would, even after that episode is saved anew,
        // offer to restore the old text on the next open.
        guard export(manuscripts) else { continue }
        trash(entries, backup: backup)
        return project
      case .discard:
        trash(entries, backup: backup)
        return project
      }
    }
  }

  private static func restore(
    _ entries: [EmergencyBackup.Entry], backup: EmergencyBackup, store: ProjectStore, project: ProjectFile
  ) async -> ProjectFile {
    let outcomes = await Task.detached(priority: .userInitiated) {
      entries.map { entry in (entry, Result { try backup.restore(entry, into: store, memo: snapshotMemo) }) }
    }.value
    var project = project
    var failed: [String] = []
    for (entry, outcome) in outcomes {
      switch outcome {
      case .success:
        if let index = project.episodes.firstIndex(where: { $0.id == entry.episodeID }) {
          project.episodes[index].characterCount = CharacterCount(counting: entry.text)
        }
      case .failure(let error):
        failed.append("\(name(of: entry, in: project)): \((error as? ProjectError)?.userMessage ?? error.localizedDescription)")
      }
    }
    if !failed.isEmpty {
      SystemDialogs.showError(
        "원고를 되살리지 못했어요",
        message: failed.joined(separator: "\n") + "\n백업은 그대로 두었어요. 다음에 열 때 다시 물어요.")
    }
    return project
  }

  /// Moved to the system Trash instead of deleted (so it can be undone).
  private static func trash(_ entries: [EmergencyBackup.Entry], backup: EmergencyBackup) {
    for entry in entries {
      for url in backup.files(of: entry.episodeID) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
      }
    }
  }

  private static func name(of entry: EmergencyBackup.Entry, in project: ProjectFile) -> String {
    guard let index = project.episodes.firstIndex(where: { $0.id == entry.episodeID }) else {
      return entry.episodeTitle.isEmpty ? "제목 없음" : entry.episodeTitle
    }
    return EpisodeLabel.text(number: index + 1, title: project.episodes[index].title)
  }
}
