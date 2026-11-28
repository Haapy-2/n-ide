import Foundation

/// Menu commands whose shortcuts can be changed in Settings, and their defaults (keep in sync with the DESIGN.md ch.7 table).
/// When adding a menu command, add one line here and read it in the menu with `ShortcutSettings.shortcut(_:)`.
enum ShortcutCommand: String, CaseIterable, Identifiable {
  case newProject, openOther, switchProject, saveNow
  /// Snapshot on save. Used only when enabled in Settings; meanwhile the save-now / take-snapshot fields lock.
  case saveWithSnapshot
  case takeSnapshot, showSnapshots
  case searchProject
  /// Select next occurrence (⌘D, PLAN ch.16). Works only when the editor has keyboard focus.
  case selectNextOccurrence
  case newEpisode, previousEpisode, nextEpisode, renameEpisode, trashEpisode, episodeGoal
  /// Episode groups. No default shortcut.
  case groupEpisodes, ungroupEpisodes

  var id: Self { self }

  /// Menu item name. The menu uses this name too.
  var title: String {
    switch self {
    case .newProject: "새 작품…"
    case .openOther: "다른 위치에서 열기…"
    case .switchProject: "작품 전환…"
    case .saveNow: "지금 저장"
    case .saveWithSnapshot: "저장하면서 스냅샷 찍기"
    case .takeSnapshot: "스냅샷 찍기"
    case .showSnapshots: "스냅샷 보기…"
    case .searchProject: "작품 전체 검색"
    case .selectNextOccurrence: "같은 말 하나 더 고르기"
    case .newEpisode: "새 회차"
    case .previousEpisode: "이전 회차"
    case .nextEpisode: "다음 회차"
    case .renameEpisode: "이름 변경…"
    case .trashEpisode: "휴지통으로 이동…"
    case .episodeGoal: "목표 글자 수…"
    case .groupEpisodes: "묶기…"
    case .ungroupEpisodes: "묶음 풀기"
    }
  }

  var category: Category {
    switch self {
    case .newProject, .openOther, .switchProject, .saveNow, .saveWithSnapshot: .file
    case .takeSnapshot, .showSnapshots: .snapshot
    case .searchProject, .selectNextOccurrence: .edit
    case .newEpisode, .previousEpisode, .nextEpisode, .renameEpisode, .trashEpisode, .episodeGoal, .groupEpisodes, .ungroupEpisodes: .episode
    }
  }

  var defaultCombo: KeyCombo? {
    switch self {
    case .newProject: KeyCombo("n", [.command, .shift])
    case .openOther: KeyCombo("o", [.command])
    case .switchProject: KeyCombo("o", [.command, .shift])
    case .saveNow: KeyCombo("s", [.command])
    // Same ⌘S as save now. The two are never active at once, so they don't clash (ShortcutSettings.isActive).
    case .saveWithSnapshot: KeyCombo("s", [.command])
    // ⌥⌘S clashes with the system "Show Sidebar", so ⌃⌘S
    case .takeSnapshot: KeyCombo("s", [.command, .control])
    case .showSnapshots: KeyCombo("s", [.command, .shift])
    case .searchProject: KeyCombo("f", [.command, .shift])
    case .selectNextOccurrence: KeyCombo("d", [.command])
    case .newEpisode: KeyCombo("n", [.command])
    case .previousEpisode: KeyCombo(.upArrow, [.command, .option])
    case .nextEpisode: KeyCombo(.downArrow, [.command, .option])
    case .renameEpisode: KeyCombo("r", [.command, .shift])
    case .trashEpisode: KeyCombo(.delete, [.command, .option])
    case .episodeGoal, .groupEpisodes, .ungroupEpisodes: nil
    }
  }

  enum Category: CaseIterable {
    case file, edit, snapshot, episode

    var title: String {
      switch self {
      case .file: "파일"
      case .edit: "편집"
      case .snapshot: "스냅샷"
      case .episode: "회차"
      }
    }

    var commands: [ShortcutCommand] { ShortcutCommand.allCases.filter { $0.category == self } }
  }
}
