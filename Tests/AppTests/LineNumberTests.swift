import AppKit
import XCTest
@testable import NovelEditor

/// Editor line numbers. Checks that toggling never moves the body, numbers match per Return, and the rule matches the diff view.
@MainActor
final class LineNumberTests: XCTestCase {
  private func makeEditor(_ text: String, width: CGFloat = 1300, height: CGFloat = 800, numbers: Bool = true) -> ManuscriptTextView {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    let textView = ManuscriptTextView.make()
    scrollView.documentView = textView
    textView.setFrameSize(NSSize(width: width, height: height))
    textView.replaceAllText(with: text)
    textView.showsLineNumbers = numbers
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    return textView
  }

  private func numbers(_ textView: ManuscriptTextView, in rect: NSRect? = nil) -> [Int] {
    textView.lineNumberPlacements(in: rect ?? textView.bounds).map(\.number)
  }

  private func baselines(_ textView: ManuscriptTextView) -> [CGFloat] {
    textView.lineNumberPlacements(in: textView.bounds).map(\.baselineY)
  }

  func testTogglingDoesNotMoveText() {
    let textView = makeEditor("첫 문단입니다.\n둘째 문단입니다.", numbers: false)
    let layoutManager = textView.layoutManager!
    let before = layoutManager.boundingRect(forGlyphRange: NSRange(location: 3, length: 4), in: textView.textContainer!)
    let originBefore = textView.textContainerOrigin
    let insetBefore = textView.textContainerInset
    textView.showsLineNumbers = true
    layoutManager.ensureLayout(for: textView.textContainer!)
    XCTAssertEqual(layoutManager.boundingRect(forGlyphRange: NSRange(location: 3, length: 4), in: textView.textContainer!), before)
    XCTAssertEqual(textView.textContainerOrigin, originBefore)
    XCTAssertEqual(textView.textContainerInset, insetBefore)
  }

  /// Blank line numbers share the text lines' baseline (same distance from the line top). Using the newline glyph position made them float up.
  func testBlankLineNumberSitsOnTextBaseline() {
    for text in ["가\n\n나", "\n가", "가\r\n\r\n나"] {
      let textView = makeEditor(text)
      let layoutManager = textView.layoutManager!
      let storage = textView.textStorage!.mutableString
      let placements = textView.lineNumberPlacements(in: textView.bounds)
      var offsets: [CGFloat] = []
      var location = 0
      for placement in placements where location < storage.length {
        let line = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: location), effectiveRange: nil)
        offsets.append(placement.baselineY - textView.textContainerOrigin.y - line.minY)
        location = NSMaxRange(storage.paragraphRange(for: NSRange(location: location, length: 0)))
      }
      XCTAssertEqual(Set(offsets).count, 1, "\(text.debugDescription): \(offsets)")
    }
  }

  /// Turning off blank-line numbers drops only blank lines; numbering stays the same (same as the diff view).
  func testBlankLineNumbersCanBeHidden() {
    let textView = makeEditor("가\n\n나\n")
    textView.numbersBlankLines = false
    XCTAssertEqual(numbers(textView), [1, 3])
  }

  func testOffDrawsNothing() {
    XCTAssertEqual(numbers(makeEditor("가\n나", numbers: false)), [])
  }

  func testOneNumberPerEnter() {
    let textView = makeEditor("가\n나\n\n다")
    XCTAssertEqual(numbers(textView), [1, 2, 3, 4])
    let ys = baselines(textView)
    XCTAssertEqual(ys, ys.sorted())
    XCTAssertEqual(Set(ys).count, ys.count)
  }

  func testWrappedParagraphHasOneNumber() {
    let textView = makeEditor(String(repeating: "가나다라마바사 ", count: 60) + "\n짧은 문단")
    XCTAssertEqual(numbers(textView), [1, 2])
    let ys = baselines(textView)
    // The first paragraph wraps to several lines, so the gap between two numbers is much larger than one line height.
    XCTAssertGreaterThan(ys[1] - ys[0], textView.style.lineHeight * 3)
  }

  func testTrailingEnterGetsNumberAtNextLineHeight() {
    let trailing = makeEditor("가\n")
    let normal = makeEditor("가\n나")
    XCTAssertEqual(numbers(trailing), [1, 2])
    XCTAssertEqual(baselines(trailing)[1], baselines(normal)[1], accuracy: 0.5)
  }

  func testEmptyEpisodeShowsOneAtFirstLineHeight() {
    let empty = makeEditor("")
    let filled = makeEditor("가")
    XCTAssertEqual(numbers(empty), [1])
    XCTAssertEqual(baselines(empty)[0], baselines(filled)[0], accuracy: 0.5)
  }

  /// \r\n from other editors counts once too (same rule as the diff view).
  func testWindowsLineEndings() {
    XCTAssertEqual(numbers(makeEditor("가\r\n나\r\n다")), [1, 2, 3])
  }

  func testNumberSitsLeftOfTextAndRightAligned() {
    let textView = makeEditor("가\n나")
    let placements = textView.lineNumberPlacements(in: textView.bounds)
    let right = ManuscriptTextView.lineNumberLeading + textView.lineNumberColumnWidth
    XCTAssertTrue(placements.allSatisfy { $0.rightX == right })
    XCTAssertLessThan(right, textView.textContainerOrigin.x)
  }

  func testHiddenWhenMarginTooNarrow() {
    let textView = makeEditor("가\n나", width: 740)
    XCTAssertFalse(textView.lineNumbersFit)
    XCTAssertEqual(numbers(textView), [])
  }

  /// When redrawing only part of the bottom, that paragraph's number is right (the start number is computed by counting earlier paragraphs).
  func testPartialRectFarDownStartsAtRightNumber() {
    let text = (1...500).map { "\($0)번째 문단" }.joined(separator: "\n")
    let textView = makeEditor(text, height: 400)
    let ns = text as NSString
    let start = ns.range(of: "300번째").location
    let layoutManager = textView.layoutManager!
    let glyph = layoutManager.glyphIndexForCharacter(at: start)
    let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    let y = textView.textContainerOrigin.y + line.minY
    let found = numbers(textView, in: NSRect(x: 0, y: y + 2, width: 100, height: line.height - 4))
    XCTAssertEqual(found, [300])
  }

  func testColumnWidensAtThousandLines() {
    let short = makeEditor((1...999).map(String.init).joined(separator: "\n"))
    let long = makeEditor((1...1000).map(String.init).joined(separator: "\n"))
    XCTAssertGreaterThan(long.lineNumberColumnWidth, short.lineNumberColumnWidth)
  }

  func testLineCountFollowsEditing() {
    let textView = makeEditor("가")
    XCTAssertEqual(textView.currentLineCount, 1)
    textView.setSelectedRange(NSRange(location: 1, length: 0))
    textView.insertText("\n나", replacementRange: textView.selectedRange())
    XCTAssertEqual(textView.currentLineCount, 2)
    XCTAssertEqual(numbers(textView), [1, 2])
    textView.setSelectedRange(NSRange(location: 1, length: 1))
    textView.deleteBackward(nil)
    XCTAssertEqual(textView.currentLineCount, 1)
  }

  func testTogglingDuringCompositionKeepsMarkedText() {
    let textView = makeEditor("가\n", numbers: false)
    textView.setSelectedRange(NSRange(location: 2, length: 0))
    textView.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    XCTAssertTrue(textView.hasMarkedText())
    let before = textView.string
    textView.showsLineNumbers = true
    _ = textView.lineNumberPlacements(in: textView.bounds)
    textView.showsLineNumbers = false
    XCTAssertTrue(textView.hasMarkedText())
    XCTAssertEqual(textView.string, before)
    XCTAssertEqual(textView.markedRange(), NSRange(location: 2, length: 1))
  }
}
