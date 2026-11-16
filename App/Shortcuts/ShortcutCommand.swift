import Foundation

/// 설정에서 단축키를 바꿀 수 있는 메뉴 명령과 기본 단축키 (DESIGN.md 7장 표와 같게 둔다).
/// 새 메뉴 명령을 만들면 여기에 한 줄 더하고 메뉴에서 `ShortcutSettings.shortcut(_:)`로 읽는다.
enum ShortcutCommand: String, CaseIterable, Identifiable {
  case newProject, openOther, switchProject, saveNow
  case takeSnapshot, showSnapshots
  case newEpisode, previousEpisode, nextEpisode, renameEpisode, trashEpisode, episodeGoal

  var id: Self { self }

  /// 메뉴 항목 이름. 메뉴도 이 이름을 쓴다.
  var title: String {
    switch self {
    case .newProject: "새 작품…"
    case .openOther: "다른 위치에서 열기…"
    case .switchProject: "작품 전환…"
    case .saveNow: "지금 저장"
    case .takeSnapshot: "스냅샷 찍기"
    case .showSnapshots: "스냅샷 보기…"
    case .newEpisode: "새 회차"
    case .previousEpisode: "이전 회차"
    case .nextEpisode: "다음 회차"
    case .renameEpisode: "이름 변경…"
    case .trashEpisode: "휴지통으로 이동…"
    case .episodeGoal: "목표 글자 수…"
    }
  }

  var category: Category {
    switch self {
    case .newProject, .openOther, .switchProject, .saveNow: .file
    case .takeSnapshot, .showSnapshots: .snapshot
    case .newEpisode, .previousEpisode, .nextEpisode, .renameEpisode, .trashEpisode, .episodeGoal: .episode
    }
  }

  var defaultCombo: KeyCombo? {
    switch self {
    case .newProject: KeyCombo("n", [.command, .shift])
    case .openOther: KeyCombo("o", [.command])
    case .switchProject: KeyCombo("o", [.command, .shift])
    case .saveNow: KeyCombo("s", [.command])
    // ⌥⌘S는 시스템 "사이드바 보기"와 겹쳐 ⌃⌘S로(2026-11-17 사용자 결정)
    case .takeSnapshot: KeyCombo("s", [.command, .control])
    case .showSnapshots: KeyCombo("s", [.command, .shift])
    case .newEpisode: KeyCombo("n", [.command])
    case .previousEpisode: KeyCombo(.upArrow, [.command, .option])
    case .nextEpisode: KeyCombo(.downArrow, [.command, .option])
    case .renameEpisode: KeyCombo("r", [.command, .shift])
    case .trashEpisode: KeyCombo(.delete, [.command, .option])
    case .episodeGoal: nil
    }
  }

  enum Category: CaseIterable {
    case file, snapshot, episode

    var title: String {
      switch self {
      case .file: "파일"
      case .snapshot: "스냅샷"
      case .episode: "회차"
      }
    }

    var commands: [ShortcutCommand] { ShortcutCommand.allCases.filter { $0.category == self } }
  }
}
