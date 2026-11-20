import Foundation
import Testing
@testable import NovelCore

/// 줄 나누는 규칙. 편집기 줄 번호와 비교 화면이 같은 줄을 가리키는지가 핵심이라
/// NSString 문단 나누기(NSTextView가 쓰는 규칙)와 늘 같은 답을 내는지 본다.
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

  /// Swift String은 \r\n을 글자 하나로 묶어 "\n"으로 나뉘지 않는다(그대로 나누면 회차 전체가 한 줄이 된다).
  @Test func windowsLineEndingIsOneBreak() {
    #expect(ParagraphLines.split("가\r\n나\r\n다") == ["가", "나", "다"])
    #expect(ParagraphLines.lineCount(in: "가\r\n나\r\n다" as NSString) == 3)
  }

  @Test func oldMacAndParagraphSeparator() {
    #expect(ParagraphLines.split("가\r나\u{2029}다") == ["가", "나", "다"])
  }

  /// U+2028은 화면에서 줄만 넘기고 문단은 그대로, U+0085는 NSString이 문단으로 안 봄(NSTextView와 같음).
  @Test func lineSeparatorAndNextLineDoNotSplit() {
    #expect(ParagraphLines.split("가\u{2028}나") == ["가\u{2028}나"])
    #expect(ParagraphLines.split("가\u{85}나") == ["가\u{85}나"])
  }

  @Test func breaksBeforeOffset() {
    let text = "첫째\n둘째\r\n셋째" as NSString
    #expect(ParagraphLines.lineBreaks(in: text, before: 0) == 0)
    #expect(ParagraphLines.lineBreaks(in: text, before: 2) == 0)
    #expect(ParagraphLines.lineBreaks(in: text, before: 3) == 1)
    // \r과 \n 사이는 아직 둘째 줄
    #expect(ParagraphLines.lineBreaks(in: text, before: 6) == 1)
    #expect(ParagraphLines.lineBreaks(in: text, before: 7) == 2)
    #expect(ParagraphLines.lineBreaks(in: text, before: 999) == 2)
    #expect(ParagraphLines.lineBreaks(in: text, before: -1) == 0)
  }

  /// 읽기 조각(4096) 끝에 \r, 다음 조각 처음에 \n이 걸려도 한 번만 센다.
  @Test func crlfAcrossReadChunk() {
    let head = String(repeating: "가", count: 4095)
    let text = (head + "\r\n나") as NSString
    #expect(ParagraphLines.lineBreaks(in: text, before: text.length) == 1)
    #expect(ParagraphLines.lineCount(in: text) == 2)
  }

  @Test func emojiAndHangulStayWhole() {
    #expect(ParagraphLines.split("👩‍👩‍👧 가\n한글") == ["👩‍👩‍👧 가", "한글"])
  }

  /// 여러 줄바꿈이 섞인 글에서 NSString 문단 수, split 결과, lineCount가 모두 같다.
  @Test func agreesWithNSStringParagraphs() {
    let pieces = ["가", "나다", "", "👍", "\n", "\r\n", "\r", "\u{2029}", "\u{85}", "\u{2028}", " "]
    var generator = SystemRandomNumberGenerator()
    for _ in 0..<300 {
      let text = (0..<Int.random(in: 1...12, using: &generator))
        .map { _ in pieces.randomElement(using: &generator)! }.joined()
      let ns = text as NSString
      // NSString 문단을 처음부터 하나씩 건너며 센다(NSTextView가 문단을 나누는 방식).
      var paragraphs = 0
      var location = 0
      while location < ns.length {
        paragraphs += 1
        location = NSMaxRange(ns.paragraphRange(for: NSRange(location: location, length: 0)))
      }
      // NSString은 끝의 줄바꿈 뒤 빈 문단을 세지 않는다. 편집기는 그 줄에도 커서를 둘 수 있어서 번호를 단다.
      let lastUnit = text.utf16.last
      let endsWithBreak = lastUnit == 0x0A || lastUnit == 0x0D || lastUnit == 0x2029
      let expected = paragraphs + (endsWithBreak ? 1 : 0)
      #expect(ParagraphLines.split(text).count == expected, "\(text.debugDescription)")
      // 빈 글만 다르다: 비교는 줄 없음(0), 편집기는 1번 줄이 보임(1).
      #expect(ParagraphLines.lineCount(in: ns) == max(ParagraphLines.split(text).count, 1), "\(text.debugDescription)")
    }
  }

  // MARK: - 비교 엔진이 같은 규칙을 쓰는지

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
