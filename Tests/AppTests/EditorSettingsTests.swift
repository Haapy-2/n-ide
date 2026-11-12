import AppKit
import XCTest
@testable import NovelEditor

/// 편집기 설정 값: 기본값이 DESIGN.md 3장과 같은지, 이상한 저장 값이 쓸 수 있는 값으로 맞춰지는지, 글꼴 3종이 다 있는지.
@MainActor
final class EditorSettingsTests: XCTestCase {
  func testDefaultsMatchDesign() {
    let style = EditorStyle(
      font: .pretendard,
      fontSize: EditorSetting.fontSize.defaultValue,
      lineSpacing: EditorSetting.lineSpacing.defaultValue,
      paragraphSpacing: EditorSetting.paragraphSpacing.defaultValue,
      lineWidthInCharacters: EditorSetting.lineWidthInCharacters.defaultValue)
    XCTAssertEqual(style, EditorStyle())
    XCTAssertEqual(style.textWidth, 680)
  }

  func testOutOfRangeValuesSnapToEdges() {
    XCTAssertEqual(EditorSetting.fontSize.clamped(8), 13)
    XCTAssertEqual(EditorSetting.fontSize.clamped(99), 24)
    XCTAssertEqual(EditorSetting.lineSpacing.clamped(3), 2.2)
    XCTAssertEqual(EditorSetting.paragraphSpacing.clamped(-1), 0)
    XCTAssertEqual(EditorSetting.lineWidthInCharacters.clamped(10), 30)
  }

  func testValuesSnapToStep() {
    XCTAssertEqual(EditorSetting.lineSpacing.clamped(1.76), 1.75)
    XCTAssertEqual(EditorSetting.lineSpacing.clamped(2.03), 2.05)
    XCTAssertEqual(EditorSetting.paragraphSpacing.clamped(0.64), 0.6)
    XCTAssertEqual(EditorSetting.fontSize.clamped(17.4), 17)
    XCTAssertEqual(EditorSetting.lineWidthInCharacters.clamped(44.6), 45)
  }

  func testNonNumbersFallBackToDefault() {
    XCTAssertEqual(EditorSetting.fontSize.clamped(.nan), 17)
    XCTAssertEqual(EditorSetting.lineSpacing.clamped(.infinity), 1.75)
  }

  func testAllBodyFontsAreInstalled() {
    for font in BodyFont.allCases {
      XCTAssertNotNil(NSFont(name: font.postScriptName, size: 17), font.title)
    }
  }

  /// 조합 중에는 모양을 바꿔도 본문 글자의 속성을 건드리지 않는다(한글 입력 보호).
  func testStyleChangeDuringCompositionKeepsStorage() {
    let textView = ManuscriptTextView.make()
    textView.replaceAllText(with: "가나다")
    textView.setSelectedRange(NSRange(location: 3, length: 0))
    textView.setMarkedText("ㄹ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    let before = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

    textView.style = EditorStyle(font: .appleMyungjo, fontSize: 20, lineSpacing: 2, paragraphSpacing: 1, lineWidthInCharacters: 35)

    XCTAssertTrue(textView.hasMarkedText())
    XCTAssertEqual(textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, before)
  }
}
