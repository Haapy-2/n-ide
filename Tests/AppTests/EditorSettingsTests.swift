import AppKit
import SwiftUI
import XCTest
@testable import NovelEditor

/// Defaults must match the DESIGN.md ch.3 values.
@MainActor
final class EditorSettingsTests: XCTestCase {
  func testDefaultsMatchDesign() {
    let style = EditorStyle(
      font: .pretendard,
      fontSize: EditorSetting.fontSize.defaultValue,
      lineSpacing: EditorSetting.lineSpacing.defaultValue,
      paragraphSpacing: EditorSetting.paragraphSpacing.defaultValue,
      lineWidthInCharacters: EditorSetting.lineWidthInCharacters.defaultValue)
    XCTAssertEqual(style, EditorStyle())
    XCTAssertEqual(style.textWidth, 680)
  }

  func testOutOfRangeValuesSnapToEdges() {
    XCTAssertEqual(EditorSetting.fontSize.clamped(8), 13)
    XCTAssertEqual(EditorSetting.fontSize.clamped(99), 24)
    XCTAssertEqual(EditorSetting.lineSpacing.clamped(3), 2.2)
    XCTAssertEqual(EditorSetting.paragraphSpacing.clamped(-1), 0)
    XCTAssertEqual(EditorSetting.lineWidthInCharacters.clamped(10), 30)
  }

  func testValuesSnapToStep() {
    XCTAssertEqual(EditorSetting.lineSpacing.clamped(1.76), 1.75)
    XCTAssertEqual(EditorSetting.lineSpacing.clamped(2.03), 2.05)
    XCTAssertEqual(EditorSetting.paragraphSpacing.clamped(0.64), 0.6)
    XCTAssertEqual(EditorSetting.fontSize.clamped(17.4), 17)
    XCTAssertEqual(EditorSetting.lineWidthInCharacters.clamped(44.6), 45)
  }

  func testNonNumbersFallBackToDefault() {
    XCTAssertEqual(EditorSetting.fontSize.clamped(.nan), 17)
    XCTAssertEqual(EditorSetting.lineSpacing.clamped(.infinity), 1.75)
  }

  func testAllBodyFontsAreInstalled() {
    for font in BodyFont.allCases {
      XCTAssertNotNil(NSFont(name: font.postScriptName, size: 17), font.title)
    }
  }

  func testStyleChangeDuringCompositionKeepsStorage() {
    let textView = ManuscriptTextView.make()
    textView.replaceAllText(with: "가나다")
    textView.setSelectedRange(NSRange(location: 3, length: 0))
    textView.setMarkedText("ㄹ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    let before = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

    textView.style = EditorStyle(font: .appleMyungjo, fontSize: 20, lineSpacing: 2, paragraphSpacing: 1, lineWidthInCharacters: 35)

    XCTAssertTrue(textView.hasMarkedText())
    XCTAssertEqual(textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, before)
  }

  /// Settings preview: wrap width and height match after window width changes, so text isn't cut off.
  func testPreviewFitsTextAfterWidthChanges() throws {
    let host = NSHostingView(rootView: EditorPreview(style: EditorStyle()))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = host
    for width in [300.0, 700.0, 420.0] {
      window.setContentSize(NSSize(width: width, height: 400))
      host.layoutSubtreeIfNeeded()
      let textView = try XCTUnwrap(findTextView(in: host))
      let layoutManager = try XCTUnwrap(textView.layoutManager)
      let container = try XCTUnwrap(textView.textContainer)
      layoutManager.ensureLayout(for: container)
      let needed = layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2
      XCTAssertEqual(container.size.width, textView.bounds.width - textView.textContainerInset.width * 2, accuracy: 1, "폭 \(width)")
      XCTAssertLessThanOrEqual(needed, textView.bounds.height + 1, "폭 \(width)에서 아래가 잘림")
    }
  }

  private func findTextView(in view: NSView) -> NSTextView? {
    if let textView = view as? NSTextView { return textView }
    return view.subviews.lazy.compactMap { self.findTextView(in: $0) }.first
  }
}
