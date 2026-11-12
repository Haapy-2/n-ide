import SwiftUI

@main
struct NovelEditorApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    // 앱을 열면 작품 선택 창이 먼저 뜬다. Finder에서 .novel을 두 번 클릭한 경우도 이 창이 받아서 작품을 연다.
    Window("작품 선택", id: AppScene.picker) {
      ProjectPickerView()
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .handlesExternalEvents(matching: ["*"])
    .commands {
      ProjectCommands()
      EpisodeCommands()
    }

    // 작품마다 작업 공간 창 하나. 창의 값은 작품 폴더 URL이다.
    WindowGroup(for: URL.self) { $url in
      if let url {
        WorkspaceWindow(url: url)
      }
    }
    .defaultSize(width: 1100, height: 760)
    // 바깥에서 들어온 파일 열기 요청으로 빈 작업 공간 창이 생기지 않게 한다.
    .handlesExternalEvents(matching: [])

    // 앱 메뉴의 "설정…"(⌘,)
    Settings {
      SettingsView()
    }
    // 내용의 최소 크기까지만 줄어들고, 그보다 크게는 마음대로 늘릴 수 있다.
    .windowResizability(.contentMinSize)
  }
}
