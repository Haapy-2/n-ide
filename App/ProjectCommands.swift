import SwiftUI

/// File menu: new project, open elsewhere, switch project, save now, take/view snapshots (DESIGN.md ch.7).
/// Shortcuts read the values changed in Settings → Shortcuts (defaults in `ShortcutCommand`).
struct ProjectCommands: Commands {
  @FocusedValue(\.workspaceActions) private var actions
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow

  var body: some Commands {
    let shortcuts = ShortcutStore.shared.settings
    // Remove the system default "New Window" (⌘N) and replace with project-level commands. ⌘N is used by "New Episode".
    CommandGroup(replacing: .newItem) {
      Button(ShortcutCommand.newProject.title) {
        Task { await launcher.createNew() }
      }
      .keyboardShortcut(shortcuts.shortcut(.newProject))

      Button(ShortcutCommand.openOther.title) { launcher.openExisting() }
        .keyboardShortcut(shortcuts.shortcut(.openOther))

      Button(ShortcutCommand.switchProject.title) { openWindow(id: AppScene.picker) }
        .keyboardShortcut(shortcuts.shortcut(.switchProject))

      // Save and snapshot live in this group too. In a non-document app the system save group (.saveItem) is empty, so
      // items added with CommandGroup(after: .saveItem) never appear in the menu.
      Divider()
      // With "snapshot on save" on, the same item saves and snapshots with that key.
      Button(ShortcutCommand.saveNow.title) {
        if shortcuts.savesWithSnapshot { actions?.saveWithSnapshot?() } else { actions?.saveNow?() }
      }
      .keyboardShortcut(shortcuts.saveMenuShortcut)
      .disabled(actions?.saveNow == nil)
      Button(ShortcutCommand.takeSnapshot.title) { actions?.takeSnapshot?() }
        .keyboardShortcut(shortcuts.shortcut(.takeSnapshot))
        .disabled(actions?.takeSnapshot == nil)
      Button(ShortcutCommand.showSnapshots.title) { actions?.showSnapshots?() }
        .keyboardShortcut(shortcuts.shortcut(.showSnapshots))
        .disabled(actions?.showSnapshots == nil)
    }
  }

  private var launcher: ProjectLauncher {
    ProjectLauncher(openWindow: openWindow, dismissWindow: dismissWindow)
  }
}
