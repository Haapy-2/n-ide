import SwiftUI

/// 편집 메뉴의 "작품 전체 검색"(⇧⌘F, DESIGN 7장)과 "전체 바꾸기 되돌리기…"(PLAN 14장 5번). 앞에 있는 작업 공간 창이 없으면 흐리게 보인다.
struct SearchCommands: Commands {
  @FocusedValue(\.workspaceActions) private var actions

  var body: some Commands {
    CommandGroup(after: .textEditing) {
      Divider()
      Button(ShortcutCommand.searchProject.title) { actions?.showSearch?() }
        .keyboardShortcut(ShortcutStore.shared.settings.shortcut(.searchProject))
        .disabled(actions?.showSearch == nil)
      Button("전체 바꾸기 되돌리기…") { actions?.revertReplace?() }
        .disabled(actions?.revertReplace == nil)
    }
  }
}
