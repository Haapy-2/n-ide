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
