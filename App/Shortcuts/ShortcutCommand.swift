import Foundation

/// 설정에서 단축키를 바꿀 수 있는 메뉴 명령과 기본 단축키 (DESIGN.md 7장 표와 같게 둔다).
/// 새 메뉴 명령을 만들면 여기에 한 줄 더하고 메뉴에서 `ShortcutSettings.shortcut(_:)`로 읽는다.
enum ShortcutCommand: String, CaseIterable, Identifiable {
  case newProject, openOther, switchProject, saveNow
  /// 저장하면서 스냅샷 찍기(2026-11-18 사용자 요청). 설정에서 켰을 때만 쓰이고, 그동안 지금 저장·스냅샷 찍기 칸은 잠긴다.
  case saveWithSnapshot
  case takeSnapshot, showSnapshots
  /// 작품 전체 검색(12단계)
  case searchProject
  case newEpisode, previousEpisode, nextEpisode, renameEpisode, trashEpisode, episodeGoal

  var id: Self { self }

  /// 메뉴 항목 이름. 메뉴도 이 이름을 쓴다.
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
    case .newProject, .openOther, .switchProject, .saveNow, .saveWithSnapshot: .file
    case .takeSnapshot, .showSnapshots: .snapshot
    case .searchProject: .edit
    case .newEpisode, .previousEpisode, .nextEpisode, .renameEpisode, .trashEpisode, .episodeGoal: .episode
    }
  }

  var defaultCombo: KeyCombo? {
    switch self {
    case .newProject: KeyCombo("n", [.command, .shift])
    case .openOther: KeyCombo("o", [.command])
    case .switchProject: KeyCombo("o", [.command, .shift])
    case .saveNow: KeyCombo("s", [.command])
    // 지금 저장과 같은 ⌘S. 둘은 동시에 쓰이지 않아서 겹치지 않는다(ShortcutSettings.isActive).
    case .saveWithSnapshot: KeyCombo("s", [.command])
    // ⌥⌘S는 시스템 "사이드바 보기"와 겹쳐 ⌃⌘S로(2026-11-17 사용자 결정)
    case .takeSnapshot: KeyCombo("s", [.command, .control])
    case .showSnapshots: KeyCombo("s", [.command, .shift])
    case .searchProject: KeyCombo("f", [.command, .shift])
    case .newEpisode: KeyCombo("n", [.command])
    case .previousEpisode: KeyCombo(.upArrow, [.command, .option])
    case .nextEpisode: KeyCombo(.downArrow, [.command, .option])
    case .renameEpisode: KeyCombo("r", [.command, .shift])
    case .trashEpisode: KeyCombo(.delete, [.command, .option])
    case .episodeGoal: nil
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
