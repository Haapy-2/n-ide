import AppKit
import XCTest
@testable import NovelEditor

/// 설정 창(SwiftUI `Settings`)은 기본으로 크기 조절이 꺼져 있어서, 앞에 올 때 앱이 켠다(드래그로 크기 바꾸기).
@MainActor
final class SettingsWindowTests: XCTestCase {
  func testSettingsWindowBecomesResizableWhenKey() throws {
    let item = try XCTUnwrap(NSApp.mainMenu?.items.first?.submenu?.items.first { $0.keyEquivalent == "," })
    let menu = try XCTUnwrap(item.menu)
    menu.performActionForItem(at: menu.index(of: item))
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    let window = try XCTUnwrap(NSApp.windows.first(where: AppDelegate.isSettingsWindow))
    defer { window.close() }
    // 테스트 실행기는 맨 앞 앱이 아니라 창이 실제로 키 창이 되지 않으므로, 키 창이 됐다는 알림을 직접 보낸다.
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)

    XCTAssertTrue(window.styleMask.contains(.resizable))
    XCTAssertGreaterThanOrEqual(window.contentMinSize.width, 420)
  }
}
