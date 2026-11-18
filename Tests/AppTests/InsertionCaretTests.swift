import AppKit
import XCTest
@testable import NovelEditor

/// 커서 높이 (2026-11-18 사용자 요청: 글자 크기 + 20%). 그리는 것 자체는 창이 앞에 있어야 해서 손 확인으로 본다.
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

  /// 시스템이 주는 커서 칸처럼 둘째 줄 위에서 시작하는 줄 높이 칸.
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

  /// 커서 가운데가 그 줄 글자(한글) 몸통 가운데와 1pt 안으로 맞는다.
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

  /// 시스템이 지우는 1pt 칸을 커서 두께 + 1pt로 넓혀 자국이 남지 않게. 넓은 칸은 그대로.
  func testThinInvalidationsCoverWideCaret() {
    let textView = makeEditor()
    XCTAssertEqual(textView.widenedForCaret(NSRect(x: 100, y: 50, width: 1, height: 30)), NSRect(x: 100, y: 50, width: 3, height: 30))
    XCTAssertEqual(textView.widenedForCaret(NSRect(x: 100, y: 50, width: 680, height: 30)).width, 680)
    XCTAssertTrue(textView.widenedForCaret(.zero).isEmpty)
  }

  /// 커서를 그린 자리를 기억했다가, 다른 자리로 옮기거나 끄거나 창이 비활성화되면 잊는다(그때 직접 지운다).
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
    // 다른 창의 알림은 무시, 앱이 뒤로 가면 지운다.
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: NSWindow())
    XCTAssertNotNil(textView.lastCaretRect)
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    XCTAssertNil(textView.lastCaretRect)
  }

  /// 줄 간격을 가장 좁게(1.4) 해도 커서가 줄 칸 밖으로 나가지 않는다.
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
