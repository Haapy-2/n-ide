import AppKit
import XCTest
@testable import NovelEditor

/// 빈 줄에는 문단 간격이 붙지 않는다(DESIGN.md 3장). 글 줄은 그대로 붙는다.
@MainActor
final class BlankLineSpacingTests: XCTestCase {
  private func lineHeights(_ text: String, style: EditorStyle = EditorStyle()) -> [CGFloat] {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1100, height: 700))
    let textView = ManuscriptTextView.make()
    scrollView.documentView = textView
    textView.setFrameSize(NSSize(width: 1100, height: 700))
    textView.style = style
    textView.replaceAllText(with: text)
    let layoutManager = textView.layoutManager!
    layoutManager.ensureLayout(for: textView.textContainer!)
    var heights: [CGFloat] = []
    var glyph = 0
    while glyph < layoutManager.numberOfGlyphs {
      var range = NSRange()
      heights.append(layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range).height)
      glyph = NSMaxRange(range)
    }
    return heights
  }

  func testBlankLineGetsNoParagraphSpacing() {
    let style = EditorStyle()
    let full = style.lineHeight + style.lineHeight * style.paragraphSpacing
    // 가 / 빈 줄 / 나 / 빈 줄 / 빈 줄 / 다
    XCTAssertEqual(lineHeights("가\n\n나\n\n\n다", style: style), [full, style.lineHeight, full, style.lineHeight, style.lineHeight, style.lineHeight])
  }

  func testBlankFirstLine() {
    let style = EditorStyle()
    XCTAssertEqual(lineHeights("\n가", style: style).first, style.lineHeight)
  }

  func testWindowsLineEndings() {
    let style = EditorStyle()
    XCTAssertEqual(lineHeights("가\r\n\r\n나", style: style)[1], style.lineHeight)
  }

  /// 띄어쓰기만 있는 줄은 빈 줄이 아니라 글 줄로 본다.
  func testSpaceOnlyLineKeepsSpacing() {
    let style = EditorStyle()
    let full = style.lineHeight + style.lineHeight * style.paragraphSpacing
    XCTAssertEqual(lineHeights("가\n \n나", style: style)[1], full)
  }
}
