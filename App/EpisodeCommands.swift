import SwiftUI

/// Episode menu (DESIGN.md ch.7). Everything dims when there's no front workspace window.
/// Shortcuts read the values changed in Settings → Shortcuts (defaults in `ShortcutCommand`).
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

      // Group several episodes selected with ⌘-click / ⇧-click in the sidebar (PLAN ch.8 option B).
      Button(ShortcutCommand.groupEpisodes.title) { actions?.groupMarked?() }
        .keyboardShortcut(shortcuts.shortcut(.groupEpisodes))
        .disabled(actions?.groupMarked == nil)
      Button(ShortcutCommand.ungroupEpisodes.title) { actions?.ungroupSelected?() }
        .keyboardShortcut(shortcuts.shortcut(.ungroupEpisodes))
        .disabled(actions?.ungroupSelected == nil)
    }
  }

  /// With defaults: ⌘⌫ when the sidebar has focus, ⌥⌘⌫ when the editor does.
  /// In the editor ⌘⌫ means "delete to line start", so the menu must not intercept it there. If the user changed it, that combo applies everywhere.
  private func trashShortcut(_ shortcuts: ShortcutSettings) -> KeyboardShortcut? {
    if !shortcuts.isCustomized(.trashEpisode), sidebarFocused == true {
      return KeyboardShortcut(.delete, modifiers: [.command])
    }
    return shortcuts.shortcut(.trashEpisode)
  }
}
