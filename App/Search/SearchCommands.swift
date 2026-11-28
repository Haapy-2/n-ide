import SwiftUI

/// Edit menu "project search" (⇧⌘F, DESIGN ch.7), "revert replace all…" (PLAN ch.14 #5), "select next occurrence" (⌘D, ch.16).
/// Dims when there's no front workspace window.
struct SearchCommands: Commands {
  @FocusedValue(\.workspaceActions) private var actions
  @AppStorage(AppSettingKey.multiCursorEnabled) private var multiCursorEnabled = true

  var body: some Commands {
    CommandGroup(after: .textEditing) {
      Divider()
      Button(ShortcutCommand.searchProject.title) { actions?.showSearch?() }
        .keyboardShortcut(ShortcutStore.shared.settings.shortcut(.searchProject))
        .disabled(actions?.showSearch == nil)
      Button("전체 바꾸기 되돌리기…") { actions?.revertReplace?() }
        .disabled(actions?.revertReplace == nil)
      Divider()
      Button(ShortcutCommand.selectNextOccurrence.title) { ManuscriptTextView.sendSelectNextOccurrence() }
        .keyboardShortcut(ShortcutStore.shared.settings.shortcut(.selectNextOccurrence))
        .disabled(actions == nil || !multiCursorEnabled)
    }
  }
}
