import SwiftUI

/// 파일 메뉴: 새 작품, 다른 위치에서 열기, 작품 전환, 지금 저장, 스냅샷 찍기·보기 (DESIGN.md 7장).
/// 단축키는 설정 → 단축키에서 바꾼 값을 읽는다(`ShortcutCommand`에 기본값).
struct ProjectCommands: Commands {
  @FocusedValue(\.workspaceActions) private var actions
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow

  var body: some Commands {
    let shortcuts = ShortcutStore.shared.settings
    // 시스템 기본 "새 윈도우"(⌘N)는 빼고 작품 단위 명령으로 바꾼다. ⌘N은 "새 회차"가 쓴다.
    CommandGroup(replacing: .newItem) {
      Button(ShortcutCommand.newProject.title) {
        Task { await launcher.createNew() }
      }
      .keyboardShortcut(shortcuts.shortcut(.newProject))

      Button(ShortcutCommand.openOther.title) { launcher.openExisting() }
        .keyboardShortcut(shortcuts.shortcut(.openOther))

      Button(ShortcutCommand.switchProject.title) { openWindow(id: AppScene.picker) }
        .keyboardShortcut(shortcuts.shortcut(.switchProject))

      // 저장·스냅샷도 이 묶음에 둔다. 문서 앱이 아니면 시스템 저장 묶음(.saveItem)이 비어 있어서
      // CommandGroup(after: .saveItem)로 붙인 항목은 메뉴에 아예 나타나지 않는다.
      Divider()
      // "저장하면서 스냅샷 찍기"를 켜면 같은 항목이 그 키로 저장과 스냅샷을 함께 한다.
      Button(ShortcutCommand.saveNow.title) {
        if shortcuts.savesWithSnapshot { actions?.saveWithSnapshot?() } else { actions?.saveNow?() }
      }
      .keyboardShortcut(shortcuts.saveMenuShortcut)
      .disabled(actions?.saveNow == nil)
      Button(ShortcutCommand.takeSnapshot.title) { actions?.takeSnapshot?() }
        .keyboardShortcut(shortcuts.shortcut(.takeSnapshot))
        .disabled(actions?.takeSnapshot == nil)
      Button(ShortcutCommand.showSnapshots.title) { actions?.showSnapshots?() }
        .keyboardShortcut(shortcuts.shortcut(.showSnapshots))
        .disabled(actions?.showSnapshots == nil)
    }
  }

  private var launcher: ProjectLauncher {
    ProjectLauncher(openWindow: openWindow, dismissWindow: dismissWindow)
  }
}
