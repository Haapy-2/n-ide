import AppKit
import XCTest
@testable import NovelEditor

/// 설정 창(SwiftUI `Settings`)은 기본으로 크기 조절이 꺼져 있어서, 앞에 올 때 앱이 켠다(드래그로 크기 바꾸기).
@MainActor
final class SettingsWindowTests: XCTestCase {
  /// 테스트 실행기는 앱과 같은 설정 저장소를 쓴다. 테스트 창 크기가 사용자의 설정 창 크기로 남지 않게 지운다.
  override func tearDown() async throws {
    UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(AppDelegate.settingsFrameName)")
  }

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

  /// 처음엔 기본 크기, 바꾼 크기는 앱 전체에 하나 저장되어 다음에 그대로 열린다.
  func testSettingsWindowSizeIsRememberedAppWide() throws {
    let name = AppDelegate.settingsFrameName
    UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)")
    defer { UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)") }

    // 저장된 크기가 없으면 뜬 크기 그대로 둔다(다시 그리지 않게).
    let first = makeWindow()
    AppDelegate.prepareSettingsWindow(first)
    XCTAssertTrue(first.styleMask.contains(.resizable))
    XCTAssertEqual(first.contentLayoutRect.size, NSSize(width: 300, height: 300))
    first.setContentSize(NSSize(width: 640, height: 500))
    first.saveFrame(usingName: name)
    first.close()

    let second = makeWindow()
    defer { second.close() }
    AppDelegate.prepareSettingsWindow(second)
    XCTAssertEqual(second.contentLayoutRect.size, NSSize(width: 640, height: 500))
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    return window
  }
}
