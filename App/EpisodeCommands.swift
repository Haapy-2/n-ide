import SwiftUI

/// 회차 메뉴 (DESIGN.md 7장). 앞에 있는 작업 공간 창이 없으면 모두 흐리게 보인다.
struct EpisodeCommands: Commands {
  @FocusedValue(\.workspaceActions) private var actions
  @FocusedValue(\.episodeSidebarFocused) private var sidebarFocused

  var body: some Commands {
    CommandMenu("회차") {
      Button("새 회차") { actions?.addEpisode() }
        .keyboardShortcut("n")
        .disabled(actions == nil)

      Divider()

      Button("이전 회차") { actions?.selectPrevious?() }
        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
        .disabled(actions?.selectPrevious == nil)
      Button("다음 회차") { actions?.selectNext?() }
        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        .disabled(actions?.selectNext == nil)

      Divider()

      Button("이름 변경…") { actions?.renameSelected?() }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(actions?.renameSelected == nil)
      // 사이드바에 초점이 있으면 ⌘⌫, 편집기에 있으면 ⌥⌘⌫.
      // /Users/book/Desktop/n-ide/App/EpisodeCommands.swift편집기의 ⌘⌫는 "줄 앞까지 지우기"라서 그때는 메뉴가 가로채면 안 된다.
      Button("휴지통으로 이동…") { actions?.trashSelected?() }
        .keyboardShortcut(.delete, modifiers: sidebarFocused == true ? [.command] : [.command, .option])
        .disabled(actions?.trashSelected == nil)

      Divider()

      Button("목표 글자 수…") { actions?.setGoalSelected?() }
        .disabled(actions?.setGoalSelected == nil)
    }
  }
}
