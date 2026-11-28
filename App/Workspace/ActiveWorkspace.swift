import Foundation
import Observation

/// Project of the most recently front workspace window. The Settings window belongs to no project window, so
/// this is used to show per-project values (new-episode goal).
/// When Settings comes to the front the workspace goes back but the value stays. Cleared only when the workspace window closes.
@MainActor
@Observable
final class ActiveWorkspace {
  static let shared = ActiveWorkspace()

  private(set) var model: ProjectModel?
  /// That window's undo history. Goals changed in Settings go into the same history so ⌘Z in the workspace can revert them.
  @ObservationIgnored private(set) weak var undoManager: UndoManager?

  func activate(_ model: ProjectModel, undoManager: UndoManager?) {
    if self.model !== model { self.model = model }
    self.undoManager = undoManager
  }

  func deactivate(_ model: ProjectModel) {
    guard self.model === model else { return }
    self.model = nil
    undoManager = nil
  }
}
