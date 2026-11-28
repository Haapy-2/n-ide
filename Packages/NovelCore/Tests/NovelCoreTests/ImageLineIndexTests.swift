import Foundation
import Testing
@testable import NovelCore

struct ImageLineIndexTests {
  private let body = "첫 줄\n![](../images/a.png)\n가운데\n![](images/b.jpg)\n끝"

  private func index(_ text: String) -> ImageLineIndex {
    var index = ImageLineIndex()
    index.rebuild(text as NSString)
    return index
  }

  /// Apply an edit and update incrementally; the result must equal a full rebuild.
  private func edit(_ text: String, _ range: NSRange, _ replacement: String) -> (text: String, index: ImageLineIndex, changed: NSRange?) {
    var index = index(text)
    let new = (text as NSString).replacingCharacters(in: range, with: replacement)
    let changed = index.update(new as NSString, edited: NSRange(location: range.location, length: (replacement as NSString).length),
                               delta: (replacement as NSString).length - range.length)
    return (new, index, changed)
  }

  @Test func rebuildFindsImageLinesInOrder() {
    let entries = index(body).entries
    #expect(entries.map(\.line.source) == [.project(fileName: "a.png"), .project(fileName: "b.jpg")])
    #expect((body as NSString).substring(with: entries[1].range) == "![](images/b.jpg)")
  }

  @Test func typingInATextLineShiftsLaterEntriesAndReportsNoChange() {
    let result = edit(body, NSRange(location: 1, length: 0), "한")
    #expect(result.changed == nil)
    #expect(result.index.entries == index(result.text).entries)
  }

  @Test func completingAnImageLineReportsItsParagraph() {
    let text = "앞\n![](images/c.png\n뒤"
    let result = edit(text, NSRange(location: 18, length: 0), ")")
    #expect(result.index.entries.count == 1)
    #expect(result.changed == NSRange(location: 2, length: 18))
  }

  @Test func breakingAnImageLineReportsItsParagraph() {
    let result = edit(body, NSRange(location: 24, length: 0), "글")
    #expect(result.index.entries.count == 1)
    #expect(result.changed != nil)
    #expect(result.index.entries == index(result.text).entries)
  }

  @Test func deletingTheLineAboveKeepsTheImage() {
    let result = edit(body, NSRange(location: 0, length: 4), "")
    #expect(result.changed == nil)
    #expect(result.index.entries == index(result.text).entries)
  }

  @Test func joiningTextOntoAnImageLineTurnsItIntoText() {
    let result = edit(body, NSRange(location: 3, length: 1), "")
    #expect(result.index.entries.count == 1)
    #expect(result.changed != nil)
    #expect(result.index.entries == index(result.text).entries)
  }

  @Test func replacingEverythingRebuilds() {
    let text = "![](images/x.png)\n글"
    let result = edit(body, NSRange(location: 0, length: (body as NSString).length), text)
    #expect(result.index.entries == index(text).entries)
  }

  @Test func deletingAtTheEnd() {
    let text = "글\n![](images/x.png)"
    let result = edit(text, NSRange(location: (text as NSString).length - 1, length: 1), "")
    #expect(result.index.entries.isEmpty)
    #expect(result.changed != nil)
  }

  @Test func enterBeforeTheMarkdownTurnsTheRestIntoAnImageLine() {
    let result = edit("글![](../images/a.png)", NSRange(location: 1, length: 0), "\n")
    #expect(result.index.entries.map(\.range) == [NSRange(location: 2, length: 20)])
    #expect(result.changed != nil)
  }

  @Test func editEndingInALineBreakThatCutsTheNextLineStartRereadsIt() {
    let result = edit("앞\nX![](../images/a.png)", NSRange(location: 1, length: 2), "\n")
    #expect(result.text == "앞\n![](../images/a.png)")
    #expect(result.index.entries.map(\.range) == [NSRange(location: 2, length: 20)])
  }

  /// Random edits (fixed seed) must always leave the same entries as a full rescan.
  @Test func randomEditsMatchAFullRescan() {
    var random = SeededRandom(seed: 52)
    let pieces = ["\n", "\r\n", "\u{2029}", "가", "ab", " ", "!", "[", "]", "(", ")", "![](../images/a.png)", "  ![](images/b.jpg) ", "![](x y)"]
    for _ in 0..<1_000 {
      let text = NSMutableString(string: (0..<Int.random(in: 0...12, using: &random)).map { _ in pieces.randomElement(using: &random)! }.joined())
      var index = ImageLineIndex()
      index.rebuild(text)
      for _ in 0..<20 {
        let start = Int.random(in: 0...text.length, using: &random)
        let length = Int.random(in: 0...min(6, text.length - start), using: &random)
        let insert = Bool.random(using: &random) ? pieces.randomElement(using: &random)! : ""
        text.replaceCharacters(in: NSRange(location: start, length: length), with: insert)
        let inserted = (insert as NSString).length
        index.update(text, edited: NSRange(location: start, length: inserted), delta: inserted - length)
        var full = ImageLineIndex()
        full.rebuild(text)
        #expect(index.entries == full.entries)
        if index.entries != full.entries { return }
      }
    }
  }

  @Test func lookupsByPosition() {
    let index = index(body)
    let first = index.entries[0].range
    #expect(index.entry(containing: first.location + 3)?.range == first)
    #expect(index.entry(containing: NSMaxRange(first)) == nil)
    #expect(index.entry(startingAt: first.location)?.range == first)
    #expect(index.entry(startingAt: first.location + 1) == nil)
    #expect(index.entry(endingAt: NSMaxRange(first))?.range == first)
    #expect(index.entry(endingAt: first.location) == nil)
    #expect(index.entries(intersecting: NSRange(location: 0, length: 5)).count == 1)
    #expect(index.entries(intersecting: NSRange(location: 0, length: (body as NSString).length)).count == 2)
    #expect(index.entries(intersecting: NSRange(location: 0, length: 3)).isEmpty)
  }
}

/// Deterministic generator so a failing random case repeats (SplitMix64).
private struct SeededRandom: RandomNumberGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
