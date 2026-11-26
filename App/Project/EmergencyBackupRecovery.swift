import Foundation
import NovelCore

/// 작품을 열 때 지난번에 작품 폴더에 쓰지 못한 원고(비상 백업)가 있으면 묻고 되살린다(PLAN 17장 1번).
/// 회차를 화면에 띄우기 전에 파일을 고쳐 두므로, 편집기는 되살린 글을 처음부터 읽는다.
@MainActor
enum EmergencyBackupRecovery {
  nonisolated static let snapshotMemo = "비상 백업에서 되살리기 전"

  /// 되살린 회차의 글자 수를 고친 작품 정보를 돌려준다. 백업이 없으면 그대로.
  static func run(
    _ backup: EmergencyBackup, project: ProjectFile, root: URL,
    ask: @MainActor ([String]) -> SystemDialogs.BackupChoice = SystemDialogs.offerBackupRestore(episodeNames:),
    export: @MainActor ([(title: String, text: String)]) -> Bool = SystemDialogs.exportUnsaved
  ) async -> ProjectFile {
    let ids = Set(project.episodes.map(\.id))
    let store = ProjectStore(root: root)
    // 파일에 이미 같은 글이 있으면(저장은 됐는데 백업을 못 지움) 묻지 않고 지운다.
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
        // 폴더 창을 닫았으면 아무것도 고르지 않은 것이라 다시 묻는다. 백업을 남긴 채 열면 그 회차를 새로 저장한 뒤에도
        // 다음에 열 때 옛 글로 되살리자고 한다.
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

  /// 지우지 않고 시스템 휴지통으로 옮긴다(되돌릴 수 있게).
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
    let title = project.episodes[index].title
    return "\(index + 1)화 \(title.isEmpty ? "제목 없음" : title)"
  }
}
