import Foundation
import Testing
@testable import NovelCore

/// Line-splitting rule. The key is that editor line numbers and the diff view point at the same lines, so
/// check that it always agrees with NSString paragraph splitting (the rule NSTextView uses).
struct ParagraphLinesTests {
  @Test func enterSplitsLines() {
    #expect(ParagraphLines.split("가\n나\n다") == ["가", "나", "다"])
  }

  @Test func emptyTextHasNoLinesButEditorShowsOne() {
    #expect(ParagraphLines.split("") == [])
    #expect(ParagraphLines.lineCount(in: "" as NSString) == 1)
  }

  @Test func trailingEnterMakesEmptyLastLine() {
    #expect(ParagraphLines.split("가\n") == ["가", ""])
    #expect(ParagraphLines.lineCount(in: "가\n" as NSString) == 2)
  }

  @Test func blankLinesCount() {
    #expect(ParagraphLines.split("가\n\n나") == ["가", "", "나"])
  }

  /// Swift String groups \r\n into one character, so it doesn't split on "\n" (splitting naively makes a whole episode one line).
  @Test func windowsLineEndingIsOneBreak() {
    #expect(ParagraphLines.split("가\r\n나\r\n다") == ["가", "나", "다"])
    #expect(ParagraphLines.lineCount(in: "가\r\n나\r\n다" as NSString) == 3)
  }

  @Test func oldMacAndParagraphSeparator() {
    #expect(ParagraphLines.split("가\r나\u{2029}다") == ["가", "나", "다"])
  }

  /// U+2028 only breaks the line on screen, not the paragraph; NSString doesn't treat U+0085 as a paragraph (same as NSTextView).
  @Test func lineSeparatorAndNextLineDoNotSplit() {
    #expect(ParagraphLines.split("가\u{2028}나") == ["가\u{2028}나"])
    #expect(ParagraphLines.split("가\u{85}나") == ["가\u{85}나"])
  }

  @Test func breaksBeforeOffset() {
    let text = "첫째\n둘째\r\n셋째" as NSString
    #expect(ParagraphLines.lineBreaks(in: text, before: 0) == 0)
    #expect(ParagraphLines.lineBreaks(in: text, before: 2) == 0)
    #expect(ParagraphLines.lineBreaks(in: text, before: 3) == 1)
    // Between \r and \n is still the second line
    #expect(ParagraphLines.lineBreaks(in: text, before: 6) == 1)
    #expect(ParagraphLines.lineBreaks(in: text, before: 7) == 2)
    #expect(ParagraphLines.lineBreaks(in: text, before: 999) == 2)
    #expect(ParagraphLines.lineBreaks(in: text, before: -1) == 0)
  }

  /// Counted once even when \r ends one read chunk (4096) and \n starts the next.
  @Test func crlfAcrossReadChunk() {
    let head = String(repeating: "가", count: 4095)
    let text = (head + "\r\n나") as NSString
    #expect(ParagraphLines.lineBreaks(in: text, before: text.length) == 1)
    #expect(ParagraphLines.lineCount(in: text) == 2)
  }

  @Test func emojiAndHangulStayWhole() {
    #expect(ParagraphLines.split("👩‍👩‍👧 가\n한글") == ["👩‍👩‍👧 가", "한글"])
  }

  /// In text mixing several newline kinds, NSString paragraph count, split result and lineCount all agree.
  @Test func agreesWithNSStringParagraphs() {
    let pieces = ["가", "나다", "", "👍", "\n", "\r\n", "\r", "\u{2029}", "\u{85}", "\u{2028}", " "]
    var generator = SystemRandomNumberGenerator()
    for _ in 0..<300 {
      let text = (0..<Int.random(in: 1...12, using: &generator))
        .map { _ in pieces.randomElement(using: &generator)! }.joined()
      let ns = text as NSString
      // Count by stepping through NSString paragraphs from the start (how NSTextView splits paragraphs).
      var paragraphs = 0
      var location = 0
      while location < ns.length {
        paragraphs += 1
        location = NSMaxRange(ns.paragraphRange(for: NSRange(location: location, length: 0)))
      }
      // NSString doesn't count the empty paragraph after a trailing newline. The editor can put the caret on that line, so it gets a number.
      let lastUnit = text.utf16.last
      let endsWithBreak = lastUnit == 0x0A || lastUnit == 0x0D || lastUnit == 0x2029
      let expected = paragraphs + (endsWithBreak ? 1 : 0)
      #expect(ParagraphLines.split(text).count == expected, "\(text.debugDescription)")
      // Only empty text differs: the diff has no lines (0), the editor shows line 1 (1).
      #expect(ParagraphLines.lineCount(in: ns) == max(ParagraphLines.split(text).count, 1), "\(text.debugDescription)")
    }
  }

  // MARK: - The diff engine uses the same rule

  @Test func diffSplitsWindowsLineEndings() throws {
    let result = try TextDiff(old: "가\r\n나\r\n다", new: "가\r\n나\r\n라")
    #expect(result.oldLines.count == 3)
    #expect(result.rows.count == 3)
    if case .changed(2, 2, _) = result.rows[2] {} else { Issue.record("셋째 줄이 고친 줄이 아님: \(result.rows)") }
  }

  @Test func diffIgnoresLineEndingStyle() throws {
    let result = try TextDiff(old: "가\r\n나\r\n", new: "가\n나\n")
    #expect(!result.hasChanges)
  }
}
