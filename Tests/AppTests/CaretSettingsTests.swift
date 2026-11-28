import AppKit
import XCTest
@testable import NovelEditor

@MainActor
final class CaretSettingsTests: XCTestCase {
  func testWidthStaysBetweenOneAndFour() {
    XCTAssertEqual(EditorSetting.caretWidth.clamped(7), 4)
    XCTAssertEqual(EditorSetting.caretWidth.clamped(0.3), 1)
    XCTAssertEqual(EditorSetting.caretWidth.clamped(2.3), 2.5)
    XCTAssertEqual(EditorSetting.caretWidth.clamped(.nan), 2)
    XCTAssertEqual(EditorSetting.caretHeightRatio.clamped(3), 1.75)
  }

  func testColorStorageRoundTrips() {
    for color in CaretPalette.allCases.map(CaretColor.palette) + [.custom(red: 1, green: 0.5, blue: 0)] {
      XCTAssertEqual(CaretColor(storageText: color.storageText).storageText, color.storageText)
    }
    XCTAssertEqual(CaretColor.standard.storageText, "", "기본 색은 빈 글자로 저장")
    XCTAssertEqual(CaretColor(storageText: "#FF8000"), .custom(red: 1, green: 128.0 / 255, blue: 0))
    XCTAssertEqual(CaretColor(storageText: "이상한 값"), .standard)
    XCTAssertEqual(CaretColor(storageText: "#12"), .standard)
  }

  func testPaletteResolvesPerMode() {
    let light = CaretColor.palette(.accent).nsColor(dark: false)
    let dark = CaretColor.palette(.accent).nsColor(dark: true)
    XCTAssertNotEqual(light, dark)
    for palette in CaretPalette.allCases {
      XCTAssertNotNil(NSColor(named: palette.rawValue), palette.rawValue)
    }
  }

  func testEditorCaretFollowsSettings() {
    let textView = ManuscriptTextView.make()
    textView.style = EditorStyle()
    textView.caret = CaretStyle(width: 4, heightRatio: 1.5)
    let line = NSRect(x: 100, y: 40, width: 1, height: textView.style.lineHeight)
    let caret = textView.caretRect(in: line)
    XCTAssertEqual(caret.width, 4)
    XCTAssertEqual(caret.height, (17 * 1.5).rounded())
    // Even a thick caret leaves no trail: the redraw rect is widened to width + 1 pt.
    XCTAssertEqual(textView.widenedForCaret(NSRect(x: 0, y: 0, width: 1, height: 30)).width, 5)
  }
}
