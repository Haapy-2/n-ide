import AppKit
import XCTest
@testable import NovelEditor

/// 설정 창은 고정 크기다(2026-11-12 사용자 요청). 테두리를 끌어 크기를 바꿀 수 없다.
@MainActor
final class SettingsWindowTests: XCTestCase {
  func testSettingsWindowHasFixedSize() throws {
    let item = try XCTUnwrap(NSApp.mainMenu?.items.first?.submenu?.items.first { $0.keyEquivalent == "," })
    let menu = try XCTUnwrap(item.menu)
    menu.performActionForItem(at: menu.index(of: item))
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    // SwiftUI `Settings` 장면이 만드는 창의 고정 이름
    let window = try XCTUnwrap(NSApp.windows.first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" })
    defer { window.close() }

    XCTAssertFalse(window.styleMask.contains(.resizable))
    let content = try XCTUnwrap(window.contentView).frame.size
    XCTAssertEqual(content.width, SettingsView.windowSize.width)
    XCTAssertEqual(content.height, SettingsView.windowSize.height, accuracy: 60, "제목 막대 높이만큼만 다를 수 있다")
  }
}
