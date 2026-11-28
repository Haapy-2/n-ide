import SwiftUI

/// Command the episode menu sends to the current front workspace window. nil for impossible commands (dimmed in the menu).
struct WorkspaceActions {
  var addEpisode: () -> Void
  var renameSelected: (() -> Void)?
  var trashSelected: (() -> Void)?
  /// Trash menu title while multiple episodes are selected ("지금 회차(3화)만 휴지통으로 이동…"). nil normally.
  var trashTitle: String? = nil
  var setGoalSelected: (() -> Void)?
  var selectPrevious: (() -> Void)?
  var selectNext: (() -> Void)?
  /// Save now without waiting (⌘S). Just moves up what autosave already does.
  var saveNow: (() -> Void)?
  /// Save then snapshot (replaces save now when enabled in Settings → Shortcuts). The snapshot is skipped if the text equals the last snapshot.
  var saveWithSnapshot: (() -> Void)?
  var takeSnapshot: (() -> Void)?
  var showSnapshots: (() -> Void)?
  /// Open the project search panel in place of the sidebar (⇧⌘F). If already open, focus its input field.
  var showSearch: (() -> Void)?
  /// Open the revert sheet for the most recent replace all. nil if there's nothing to revert.
  var revertReplace: (() -> Void)?
  /// Group the selected episodes (or the current one). A name prompt appears.
  var groupMarked: (() -> Void)?
  /// Ungroup the group containing the current episode. nil if not in a group.
  var ungroupSelected: (() -> Void)?
  /// View menu hide/show sidebar (⌥⌘S)
  var toggleSidebar: (() -> Void)? = nil
  var isSidebarVisible = true
}

extension FocusedValues {
  @Entry var workspaceActions: WorkspaceActions?
  /// Whether the sidebar (episode list) has keyboard focus. The episode menu uses it to change shortcuts.
  @Entry var episodeSidebarFocused: Bool?
}
