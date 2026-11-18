import AppKit
import XCTest
@testable import NovelEditor

/// 편집기 줄 번호 (11f). 켜고 꺼도 본문이 움직이지 않는지, 엔터마다 번호가 맞는지, 비교 화면과 같은 규칙인지 본다.
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

  /// 화면에서 저절로 넘어간 줄에는 번호가 없다(엔터마다 하나).
  func testWrappedParagraphHasOneNumber() {
    let textView = makeEditor(String(repeating: "가나다라마바사 ", count: 60) + "\n짧은 문단")
    XCTAssertEqual(numbers(textView), [1, 2])
    let ys = baselines(textView)
    // 첫 문단이 여러 줄이라 두 번호 사이가 한 줄 높이보다 훨씬 크다.
    XCTAssertGreaterThan(ys[1] - ys[0], textView.style.lineHeight * 3)
  }

  func testTrailingEnterGetsNumberAtNextLineHeight() {
    let trailing = makeEditor("가\n")
    let normal = makeEditor("가\n나")
    XCTAssertEqual(numbers(trailing), [1, 2])
    XCTAssertEqual(baselines(trailing)[1], baselines(normal)[1], accuracy: 0.5)
  }

  /// 빈 회차도 1번 줄이 보이고, 높이는 글자가 있는 첫 줄과 같다.
  func testEmptyEpisodeShowsOneAtFirstLineHeight() {
    let empty = makeEditor("")
    let filled = makeEditor("가")
    XCTAssertEqual(numbers(empty), [1])
    XCTAssertEqual(baselines(empty)[0], baselines(filled)[0], accuracy: 0.5)
  }

  /// 다른 편집기에서 온 \r\n도 한 번만 센다(비교 화면과 같은 규칙).
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

  /// 왼쪽 여백이 좁으면 번호만 숨긴다.
  func testHiddenWhenMarginTooNarrow() {
    let textView = makeEditor("가\n나", width: 740)
    XCTAssertFalse(textView.lineNumbersFit)
    XCTAssertEqual(numbers(textView), [])
  }

  /// 아래쪽 일부만 다시 그릴 때 그 자리 문단의 번호가 맞다(앞 문단을 세어 시작 번호를 구함).
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

  /// 엔터를 치면 줄 수가 바로 늘고, 지우면 줄어든다.
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

  /// 한글 조합 중에 켜고 꺼도 조합과 본문이 그대로다.
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
