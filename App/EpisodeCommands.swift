import SwiftUI

/// 회차 메뉴 (DESIGN.md 7장). 앞에 있는 작업 공간 창이 없으면 모두 흐리게 보인다.
/// 단축키는 설정 → 단축키에서 바꾼 값을 읽는다(`ShortcutCommand`에 기본값).
struct EpisodeCommands: Commands {
  @FocusedValue(\.workspaceActions) private var actions
  @FocusedValue(\.episodeSidebarFocused) private var sidebarFocused

  var body: some Commands {
    let shortcuts = ShortcutStore.shared.settings
    CommandMenu("회차") {
      Button(ShortcutCommand.newEpisode.title) { actions?.addEpisode() }
        .keyboardShortcut(shortcuts.shortcut(.newEpisode))
        .disabled(actions == nil)

      Divider()

      Button(ShortcutCommand.previousEpisode.title) { actions?.selectPrevious?() }
        .keyboardShortcut(shortcuts.shortcut(.previousEpisode))
        .disabled(actions?.selectPrevious == nil)
      Button(ShortcutCommand.nextEpisode.title) { actions?.selectNext?() }
        .keyboardShortcut(shortcuts.shortcut(.nextEpisode))
        .disabled(actions?.selectNext == nil)

      Divider()

      Button(ShortcutCommand.renameEpisode.title) { actions?.renameSelected?() }
        .keyboardShortcut(shortcuts.shortcut(.renameEpisode))
        .disabled(actions?.renameSelected == nil)
      Button(actions?.trashTitle ?? ShortcutCommand.trashEpisode.title) { actions?.trashSelected?() }
        .keyboardShortcut(trashShortcut(shortcuts))
        .disabled(actions?.trashSelected == nil)

      Divider()

      Button(ShortcutCommand.episodeGoal.title) { actions?.setGoalSelected?() }
        .keyboardShortcut(shortcuts.shortcut(.episodeGoal))
        .disabled(actions?.setGoalSelected == nil)

      Divider()

      // 사이드바에서 ⌘클릭·⇧클릭으로 여러 회차를 고른 뒤 묶는다(PLAN 8장 B안).
      Button(ShortcutCommand.groupEpisodes.title) { actions?.groupMarked?() }
        .keyboardShortcut(shortcuts.shortcut(.groupEpisodes))
        .disabled(actions?.groupMarked == nil)
      Button(ShortcutCommand.ungroupEpisodes.title) { actions?.ungroupSelected?() }
        .keyboardShortcut(shortcuts.shortcut(.ungroupEpisodes))
        .disabled(actions?.ungroupSelected == nil)
    }
  }

  /// 기본값일 때: 사이드바에 초점이 있으면 ⌘⌫, 편집기에 있으면 ⌥⌘⌫.
  /// 편집기의 ⌘⌫는 "줄 앞까지 지우기"라서 그때는 메뉴가 가로채면 안 된다. 사용자가 바꿨으면 어디서나 그 조합.
  private func trashShortcut(_ shortcuts: ShortcutSettings) -> KeyboardShortcut? {
    if !shortcuts.isCustomized(.trashEpisode), sidebarFocused == true {
      return KeyboardShortcut(.delete, modifiers: [.command])
    }
    return shortcuts.shortcut(.trashEpisode)
  }
}
