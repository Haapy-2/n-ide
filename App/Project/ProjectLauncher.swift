import NovelCore
import SwiftUI

/// Shared flow for creating and opening projects. Used by both the picker and the File menu.
struct ProjectLauncher {
  let openWindow: OpenWindowAction
  let dismissWindow: DismissWindowAction

  /// Ask for a location, create the new project folder, then open it.
  func createNew() async {
    guard let url = SystemDialogs.askNewProjectLocation() else { return }
    let title = url.deletingPathExtension().lastPathComponent
    do {
      // File writes off the main thread.
      try await Task.detached { _ = try ProjectStore.create(at: url, title: title) }.value
      open(url)
    } catch let error as ProjectError {
      SystemDialogs.showError("새 작품을 만들지 못했어요", message: error.userMessage)
    } catch {
      SystemDialogs.showError("새 작품을 만들지 못했어요", message: error.localizedDescription)
    }
  }

  func openExisting() {
    if let url = SystemDialogs.askExistingProject() { open(url) }
  }

  /// Open the workspace window and close the picker. If the same project is already open, that window comes to the front.
  func open(_ url: URL) {
    openWindow(value: Self.windowValue(for: url))
    dismissWindow(id: AppScene.picker)
  }

  /// URL used as the window value. Normalized so the same project folder gives the same value wherever it's opened from (recents, open panel, Finder).
  /// A trailing `/` or a different alias path would be a different value, opening one project in two windows that save the same files separately.
  static func windowValue(for url: URL) -> URL {
    // Paths through aliases (symbolic links) are resolved to the real folder too. Nonexistent paths are left as is.
    var path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    while path.count > 1, path.hasSuffix("/") { path.removeLast() }
    return URL(filePath: path, directoryHint: .isDirectory)
  }
}

enum AppScene {
  static let picker = "project-picker"
}
