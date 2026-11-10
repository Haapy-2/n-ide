import SwiftUI

@main
struct NovelEditorApp: App {
  var body: some Scene {
    // 앱을 열면 작품 선택 창이 먼저 뜬다. 작업 공간 창은 4단계에서 붙인다.
    Window("작품 선택", id: "project-picker") {
      ProjectPickerView()
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
  }
}
