import AppKit
import XCTest
@testable import NovelEditor

/// Caret height. Drawing itself needs the window in front, so it's checked by hand.
@MainActor
final class InsertionCaretTests: XCTestCase {
  private func makeEditor(_ style: EditorStyle = EditorStyle()) -> ManuscriptTextView {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1100, height: 700))
    let textView = ManuscriptTextView.make()
    scrollView.documentView = textView
    textView.setFrameSize(NSSize(width: 1100, height: 700))
    textView.style = style
    textView.replaceAllText(with: "가나다\n라마바")
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    return textView
  }

  /// A line-height rect starting at the top of the second line, like the caret rect the system provides.
  private func secondLineRect(_ textView: ManuscriptTextView) -> NSRect {
    let layoutManager = textView.layoutManager!
    let glyph = layoutManager.glyphIndexForCharacter(at: 4)
    var line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    line.origin.y += textView.textContainerOrigin.y
    line.origin.x = textView.textContainerOrigin.x
    line.size.width = 1
    line.size.height = textView.style.lineHeight
    return line
  }

  func testHeightIsFontSizePlusTwentyPercent() {
    for size: CGFloat in [13, 17, 24] {
      var style = EditorStyle()
      style.fontSize = size
      let textView = makeEditor(style)
      let caret = textView.caretRect(in: secondLineRect(textView))
      XCTAssertEqual(caret.height, (size * 1.2).rounded(), "글자 크기 \(size)")
    }
  }

  /// The caret's middle aligns within 1 pt of the middle of that line's (Hangul) glyph body.
  func testCaretIsCenteredOnGlyphs() {
    let textView = makeEditor()
    let line = secondLineRect(textView)
    let caret = textView.caretRect(in: line)
    let baseline = line.minY + textView.emptyLineBaselineFromTop
    let font = textView.style.font
    let glyphCenter = baseline - (font.ascender + font.descender) / 2
    XCTAssertEqual(caret.midY, glyphCenter, accuracy: 1)
    XCTAssertGreaterThanOrEqual(caret.minY, line.minY)
    XCTAssertLessThanOrEqual(caret.maxY, line.maxY)
    XCTAssertEqual(caret.minX, line.minX)
    XCTAssertEqual(caret.width, 2)
  }

  /// The 1 pt rect the system erases is widened to caret width + 1 pt so no trail remains. Wide rects are unchanged.
  func testThinInvalidationsCoverWideCaret() {
    let textView = makeEditor()
    XCTAssertEqual(textView.widenedForCaret(NSRect(x: 100, y: 50, width: 1, height: 30)), NSRect(x: 100, y: 50, width: 3, height: 30))
    XCTAssertEqual(textView.widenedForCaret(NSRect(x: 100, y: 50, width: 680, height: 30)).width, 680)
    XCTAssertTrue(textView.widenedForCaret(.zero).isEmpty)
  }

  /// Remember where the caret was drawn and forget it when it moves, turns off or the window deactivates (then it's erased directly).
  func testRemembersAndForgetsDrawnCaret() {
    let textView = makeEditor()
    let first = secondLineRect(textView)
    var second = first
    second.origin.x += 40
    let image = NSImage(size: textView.bounds.size)
    image.lockFocusFlipped(true)
    textView.drawInsertionPoint(in: first, color: .red, turnedOn: true)
    XCTAssertEqual(textView.lastCaretRect, textView.caretRect(in: first))
    textView.drawInsertionPoint(in: second, color: .red, turnedOn: true)
    XCTAssertEqual(textView.lastCaretRect, textView.caretRect(in: second))
    textView.drawInsertionPoint(in: second, color: .red, turnedOn: false)
    XCTAssertNil(textView.lastCaretRect)
    textView.drawInsertionPoint(in: first, color: .red, turnedOn: true)
    image.unlockFocus()
    XCTAssertNotNil(textView.lastCaretRect)
    // Notifications from other windows are ignored; erased when the app goes to the background.
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: NSWindow())
    XCTAssertNotNil(textView.lastCaretRect)
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    XCTAssertNil(textView.lastCaretRect)
  }

  /// Even at the tightest line spacing (1.4), the caret doesn't leave the line rect.
  func testStaysInsideTightLine() {
    var style = EditorStyle()
    style.fontSize = 24
    style.lineSpacing = 1.4
    let textView = makeEditor(style)
    let line = secondLineRect(textView)
    let caret = textView.caretRect(in: line)
    XCTAssertGreaterThanOrEqual(caret.minY, line.minY)
    XCTAssertLessThanOrEqual(caret.maxY, line.maxY)
  }
}
