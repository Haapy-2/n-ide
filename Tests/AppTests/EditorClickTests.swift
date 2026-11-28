import AppKit
import XCTest
@testable import NovelEditor

/// The editor receives clicks anywhere in the editor area. Prevents right-margin clicks (right of the text container) falling through to the clip view behind
/// and the caret not moving.
@MainActor
final class EditorClickTests: XCTestCase {
  private func makeEditor(width: CGFloat) -> (NSScrollView, ManuscriptTextView) {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
    let textView = ManuscriptTextView.make()
    scrollView.documentView = textView
    textView.setFrameSize(NSSize(width: width, height: 600))
    textView.replaceAllText(with: "가나다라마바사")
    return (scrollView, textView)
  }

  func testRightMarginClickGoesToEditor() {
    let (scrollView, textView) = makeEditor(width: 1300)
    // With a 680 pt body width centered, the right margin starts around 990 pt.
    let textRight = textView.textContainerOrigin.x + (textView.textContainer?.size.width ?? 0)
    XCTAssertLessThan(textRight, 1100)
    XCTAssertTrue(scrollView.hitTest(NSPoint(x: 1200, y: 100)) === textView)
  }

  func testLeftMarginAndTextClicksGoToEditor() {
    let (scrollView, textView) = makeEditor(width: 1300)
    XCTAssertTrue(scrollView.hitTest(NSPoint(x: 40, y: 100)) === textView)
    XCTAssertTrue(scrollView.hitTest(NSPoint(x: textView.textContainerOrigin.x + 10, y: 50)) === textView)
  }

  func testPointOutsideEditorIsNotTaken() {
    let (_, textView) = makeEditor(width: 1300)
    XCTAssertNil(textView.hitTest(NSPoint(x: 1400, y: 100)))
  }
}
