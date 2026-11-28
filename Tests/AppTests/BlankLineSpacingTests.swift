import AppKit
import XCTest
@testable import NovelEditor

/// Blank lines get no paragraph spacing (DESIGN.md ch.3). Text lines still do.
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
    // 가 / blank / 나 / blank / blank / 다
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

  /// A line with only spaces counts as a text line, not a blank line.
  func testSpaceOnlyLineKeepsSpacing() {
    let style = EditorStyle()
    let full = style.lineHeight + style.lineHeight * style.paragraphSpacing
    XCTAssertEqual(lineHeights("가\n \n나", style: style)[1], full)
  }
}
