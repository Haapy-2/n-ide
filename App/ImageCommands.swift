import SwiftUI

/// Edit menu "그림 넣기…" (PLAN ch.19, 14-1 ③b). Goes to the editor with keyboard focus; dims without a front workspace window.
struct ImageCommands: Commands {
  @FocusedValue(\.workspaceActions) private var actions

  var body: some Commands {
    CommandGroup(after: .pasteboard) {
      Divider()
      Button(ShortcutCommand.insertImage.title) { ManuscriptTextView.sendInsertImage() }
        .keyboardShortcut(ShortcutStore.shared.settings.shortcut(.insertImage))
        .disabled(actions == nil)
    }
  }
}
