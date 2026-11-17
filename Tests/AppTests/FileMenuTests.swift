import AppKit
import XCTest
@testable import NovelEditor

/// 파일 메뉴에 저장·스냅샷 항목이 실제로 있고 단축키가 맞는지.
/// (CommandGroup(after: .saveItem)에 붙였을 때 메뉴에서 통째로 빠져 ⌥⌘S·⇧⌘S가 듣지 않았다. 2026-11-17)
/// 항목이 켜지는지는 보지 않는다. 시험용 창(NSHostingView)은 SwiftUI 장면이 아니라 초점 값이 메뉴에 닿지 않아
/// "새 회차"까지 모두 흐리게 나온다. 켜짐과 판 열기는 손 확인으로 본다.
@MainActor
final class FileMenuTests: XCTestCase {
  private func menuItem(_ title: String, in menu: NSMenu?) -> NSMenuItem? {
    for item in menu?.items ?? [] {
      if item.title == title { return item }
      if let found = menuItem(title, in: item.submenu) { return found }
    }
    return nil
  }

  /// SwiftUI는 메뉴를 열거나 단축키를 누를 때 메뉴 항목을 다시 만든다. 테스트에서는 그 순간을 직접 부른다.
  private func refreshMenus() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    for item in NSApp.mainMenu?.items ?? [] {
      if let menu = item.submenu { menu.delegate?.menuNeedsUpdate?(menu) }
    }
  }

  func testSaveAndSnapshotItemsExist() throws {
    refreshMenus()
    let expected: [(String, NSEvent.ModifierFlags)] = [
      ("지금 저장", [.command]),
      ("스냅샷 찍기", [.command, .control]),
      ("스냅샷 보기…", [.command, .shift]),
    ]
    for (title, modifiers) in expected {
      let item = try XCTUnwrap(menuItem(title, in: NSApp.mainMenu), "\(title) 항목이 메뉴에 없다")
      XCTAssertEqual(item.keyEquivalent, "s", title)
      XCTAssertEqual(item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask), modifiers, title)
    }
  }

  /// 설정에서 바꾼 단축키가 실제 메뉴에 반영된다. 실제 앱 설정(UserDefaults)에 남으므로 끝나면 되돌린다.
  func testCustomShortcutReachesMenu() throws {
    let store = ShortcutStore.shared
    let previous = store.settings
    defer {
      store.update { $0 = previous }
      refreshMenus()
    }
    store.update {
      $0.resetAll()
      $0.set(KeyCombo("j", [.command, .control]), for: .saveNow)
      $0.set(nil, for: .showSnapshots)
    }
    refreshMenus()

    let save = try XCTUnwrap(menuItem("지금 저장", in: NSApp.mainMenu))
    XCTAssertEqual(save.keyEquivalent, "j")
    XCTAssertEqual(save.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask), [.command, .control])
    let show = try XCTUnwrap(menuItem("스냅샷 보기…", in: NSApp.mainMenu))
    XCTAssertEqual(show.keyEquivalent, "")
  }

  /// 저장하면서 스냅샷 찍기를 켜면 "지금 저장" 항목이 그 전용 키를 갖는다. 끄면 원래 키로 돌아온다.
  func testSaveWithSnapshotKeyReachesMenu() throws {
    let store = ShortcutStore.shared
    let previous = store.settings
    defer {
      store.update { $0 = previous }
      refreshMenus()
    }
    store.update {
      $0.resetAll()
      $0.setSavesWithSnapshot(true)
      $0.set(KeyCombo("k", [.command, .control]), for: .saveWithSnapshot)
    }
    refreshMenus()
    let save = try XCTUnwrap(menuItem("지금 저장", in: NSApp.mainMenu))
    XCTAssertEqual(save.keyEquivalent, "k")
    XCTAssertEqual(save.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask), [.command, .control])

    store.update { $0.setSavesWithSnapshot(false) }
    refreshMenus()
    let restored = try XCTUnwrap(menuItem("지금 저장", in: NSApp.mainMenu))
    XCTAssertEqual(restored.keyEquivalent, "s")
    XCTAssertEqual(restored.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask), [.command])
  }
}
