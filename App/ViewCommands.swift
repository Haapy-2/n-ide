import SwiftUI

/// 보기 메뉴: 사이드바 가리기·보기(⌥⌘S), 줄 번호 보이기. 창 탭 항목은 AppDelegate에서 끈다.
/// 시스템 사이드바 메뉴(`SidebarCommands`)는 ⌃⌘S를 써서 스냅샷 찍기와 겹치므로 직접 만든다.
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
