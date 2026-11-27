import AppKit
import XCTest
@testable import NovelEditor

/// 빈 회차 안내 글은 그리기만 하고 본문(텍스트 저장소)에는 들어가지 않는다.
@MainActor
final class EmptyEpisodePlaceholderTests: XCTestCase {
  func testPlaceholderFollowsEmptinessWithoutTouchingText() {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1100, height: 700))
    let textView = ManuscriptTextView.make()
    scrollView.documentView = textView
    textView.replaceAllText(with: "")
    XCTAssertTrue(textView.placeholderShown)
    XCTAssertEqual(textView.string, "")
    textView.replaceAllText(with: "가")
    XCTAssertFalse(textView.placeholderShown)
    textView.replaceAllText(with: "")
    XCTAssertTrue(textView.placeholderShown)
  }
}
