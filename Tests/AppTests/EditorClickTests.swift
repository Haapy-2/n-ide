import AppKit
import XCTest
@testable import NovelEditor

/// 편집 영역 어디를 눌러도 편집기가 클릭을 받는다. 오른쪽 여백(텍스트 칸 오른쪽) 클릭이 뒤의 clip view로 빠져
/// 커서가 움직이지 않던 문제(2026-11-18)를 막는다.
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
    // 본문 폭 680pt를 가운데 두면 오른쪽 여백은 990pt쯤부터 시작한다.
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
