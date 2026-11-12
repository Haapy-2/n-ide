import AppKit
import XCTest
@testable import NovelEditor

/// 입력 칸 밖을 누르면 입력이 끝나고(값 확정), 칸 안을 누르면 그대로다(AppDelegate의 클릭 감시).
@MainActor
final class FieldEditingTests: XCTestCase {
  func testClickOutsideEndsEditingAndInsideKeepsIt() throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let field = NSTextField(frame: NSRect(x: 20, y: 150, width: 100, height: 22))
    window.contentView?.addSubview(field)
    XCTAssertTrue(window.makeFirstResponder(field))
    XCTAssertTrue((window.firstResponder as? NSTextView)?.isFieldEditor == true)

    AppDelegate.endFieldEditingIfClickedOutside(try click(at: NSPoint(x: 30, y: 160), in: window))
    XCTAssertTrue((window.firstResponder as? NSTextView)?.isFieldEditor == true, "칸 안을 누르면 계속 입력 중")

    AppDelegate.endFieldEditingIfClickedOutside(try click(at: NSPoint(x: 200, y: 40), in: window))
    XCTAssertFalse(window.firstResponder is NSTextView, "칸 밖을 누르면 입력이 끝난다")
  }

  private func click(at point: NSPoint, in window: NSWindow) throws -> NSEvent {
    try XCTUnwrap(NSEvent.mouseEvent(
      with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
      context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
  }
}
