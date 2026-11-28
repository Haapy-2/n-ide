import SwiftUI

/// View menu: hide/show sidebar (⌥⌘S), show line numbers. Window tab items are disabled in AppDelegate.
/// The system sidebar menu (`SidebarCommands`) uses ⌃⌘S, clashing with take snapshot, so it's built by hand.
struct ViewCommands: Commands {
  @FocusedValue(\.workspaceActions) private var actions
  @AppStorage(AppSettingKey.showsLineNumbers) private var showsLineNumbers = false

  var body: some Commands {
    CommandGroup(before: .toolbar) {
      Button(actions?.isSidebarVisible == false ? "사이드바 보기" : "사이드바 가리기") { actions?.toggleSidebar?() }
        .keyboardShortcut("s", modifiers: [.command, .option])
        .disabled(actions?.toggleSidebar == nil)
      Toggle("줄 번호 보이기", isOn: $showsLineNumbers)
      Divider()
    }
  }
}
