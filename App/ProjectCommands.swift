import SwiftUI

/// 파일 메뉴: 새 작품, 다른 위치에서 열기, 작품 전환, 스냅샷 찍기·보기 (DESIGN.md 7장).
struct ProjectCommands: Commands {
  @FocusedValue(\.workspaceActions) private var actions
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow

  var body: some Commands {
    // 시스템 기본 "새 윈도우"(⌘N)는 빼고 작품 단위 명령으로 바꾼다. ⌘N은 나중에 "새 회차"가 쓴다.
    CommandGroup(replacing: .newItem) {
      Button("새 작품…") {
        Task { await launcher.createNew() }
      }
      .keyboardShortcut("n", modifiers: [.command, .shift])

      Button("다른 위치에서 열기…") { launcher.openExisting() }
        .keyboardShortcut("o")

      Button("작품 전환…") { openWindow(id: AppScene.picker) }
        .keyboardShortcut("o", modifiers: [.command, .shift])
    }
    CommandGroup(after: .saveItem) {
      Button("스냅샷 찍기") { actions?.takeSnapshot?() }
        .keyboardShortcut("s", modifiers: [.command, .option])
        .disabled(actions?.takeSnapshot == nil)
      Button("스냅샷 보기…") { actions?.showSnapshots?() }
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .disabled(actions?.showSnapshots == nil)
    }
  }

  private var launcher: ProjectLauncher {
    ProjectLauncher(openWindow: openWindow, dismissWindow: dismissWindow)
  }
}
