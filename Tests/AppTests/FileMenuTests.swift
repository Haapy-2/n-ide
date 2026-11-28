import AppKit
import XCTest
@testable import NovelEditor

/// Whether the File menu actually has the save/snapshot items with the right shortcuts.
/// (Attached via CommandGroup(after: .saveItem) they vanish from the menu entirely and shortcuts don't work.)
/// Whether items are enabled isn't checked. The test window (NSHostingView) isn't a SwiftUI scene, so focus values don't reach menus
/// and even "새 회차" shows dimmed. Enabled state and panel opening are checked by hand.
@MainActor
final class FileMenuTests: XCTestCase {
  private func menuItem(_ title: String, in menu: NSMenu?) -> NSMenuItem? {
    for item in menu?.items ?? [] {
      if item.title == title { return item }
      if let found = menuItem(title, in: item.submenu) { return found }
    }
    return nil
  }

  /// SwiftUI rebuilds menu items when a menu opens or a shortcut is pressed. Tests trigger that moment directly.
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

  /// Shortcuts changed in Settings show up in the real menu. They persist in real app settings (UserDefaults), so they're restored afterwards.
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

  /// With snapshot on save on, the "save now" item gets its dedicated key. Turning it off restores the original key.
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
