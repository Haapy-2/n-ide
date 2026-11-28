import AppKit
import XCTest
@testable import NovelEditor

/// The empty-episode hint is only drawn and never enters the body (text storage).
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
