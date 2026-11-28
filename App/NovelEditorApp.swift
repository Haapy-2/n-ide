import SwiftUI

@main
struct NovelEditorApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    // Launching the app shows the project picker first. Double-clicking a .novel in Finder is also received by this window, which opens the project.
    Window("작품 선택", id: AppScene.picker) {
      ProjectPickerView()
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .handlesExternalEvents(matching: ["*"])
    .commands {
      ProjectCommands()
      EpisodeCommands()
      SearchCommands()
      ViewCommands()
      ImageCommands()
    }

    // One workspace window per project. The window's value is the project folder URL.
    WindowGroup(for: URL.self) { $url in
      if let url {
        WorkspaceWindow(url: url)
      }
    }
    .defaultSize(width: 1100, height: 760)
    // Prevents empty workspace windows from external file-open requests.
    .handlesExternalEvents(matching: [])

    Settings {
      SettingsView()
    }
    // Fixed window size (SettingsView.windowSize). No resize border either.
    .windowResizability(.contentSize)
  }
}
