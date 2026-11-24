import Foundation
import Testing
@testable import NovelCore

struct MultiCursorTests {
  private func range(of word: String, in text: String, from: Int = 0) -> NSRange {
    let text = text as NSString
    return text.range(of: word, options: [], range: NSRange(location: from, length: text.length - from))
  }

  private func words(_ cursor: MultiCursor, in text: String) -> [String] {
    cursor.ranges.map { (text as NSString).substring(with: $0) }
  }

  // MARK: - ⌘D 다음 일치

  @Test func addsNextAfterNewestThenWrapsToStart() throws {
    let text = "민준 가 민준 나 민준"
    var cursor = try #require(MultiCursor(selection: range(of: "민준", in: text, from: 3), wholeWord: false))

    #expect(cursor.addNext(in: text) == .added(NSRange(location: 10, length: 2)))
    #expect(cursor.addNext(in: text) == .added(NSRange(location: 0, length: 2)), "끝까지 없으면 처음부터")
    #expect(cursor.ranges.map(\.location) == [0, 5, 10], "늘 앞에서부터")
    #expect(cursor.newest == 0)
    #expect(cursor.addNext(in: text) == .noMore, "모두 골랐으면 더 늘지 않는다")
  }

  @Test func selectionStartMatchesInsideLongerWordButCaretStartDoesNot() throws {
    let text = "민준이 민준이가 민준이"
    var part = try #require(MultiCursor(selection: range(of: "민준", in: text), wholeWord: false))
    var whole = try #require(MultiCursor(selection: range(of: "민준이", in: text), wholeWord: true))

    _ = part.addNext(in: text)
    _ = whole.addNext(in: text)

    #expect(part.ranges.map(\.location) == [0, 4])
    #expect(whole.ranges.map(\.location) == [0, 9], "단어 전체: '민준이가'는 건너뛴다")
  }

  @Test func isCaseSensitive() throws {
    let text = "Kim kim Kim"
    var cursor = try #require(MultiCursor(selection: NSRange(location: 0, length: 3), wholeWord: true))

    #expect(cursor.addNext(in: text) == .added(NSRange(location: 8, length: 3)))
  }

  /// 자모를 따로 적은 한글도 같은 말로 고른다(검색과 같은 규칙). 길이는 다르다.
  @Test func matchesDecomposedHangul() throws {
    let decomposed = "민준".decomposedStringWithCanonicalMapping
    let text = "민준 \(decomposed)"
    var cursor = try #require(MultiCursor(selection: NSRange(location: 0, length: 2), wholeWord: true))

    guard case .added(let found) = cursor.addNext(in: text) else { Issue.record("못 찾음"); return }
    #expect(found.length == (decomposed as NSString).length)
    #expect(found.length != 2)
  }

  /// 한 글자를 가르는 일치(피부색이 붙은 이모지 안의 이모지)는 건너뛴다(E3).
  @Test func skipsMatchSplittingOneCharacter() throws {
    let text = "👍 👍🏽 👍"
    var cursor = try #require(MultiCursor(selection: NSRange(location: 0, length: 2), wholeWord: false))

    #expect(cursor.addNext(in: text) == .added(range(of: "👍", in: text, from: 8)))
  }

  @Test func doesNothingForLineCrossingSelection() throws {
    let text = "가\n나 가\n나"
    var cursor = try #require(MultiCursor(selection: NSRange(location: 0, length: 3), wholeWord: false))

    #expect(cursor.addNext(in: text) == .notSearchable)
  }

  @Test func emptySelectionIsNotACursor() {
    #expect(MultiCursor(selection: NSRange(location: 3, length: 0), wholeWord: true) == nil)
  }

  @Test func stopsAtLimit() throws {
    let text = String(repeating: "가 ", count: MultiCursor.limit + 5)
    var cursor = try #require(MultiCursor(selection: NSRange(location: 0, length: 1), wholeWord: true))

    for _ in 1..<MultiCursor.limit { _ = cursor.addNext(in: text) }

    #expect(cursor.ranges.count == MultiCursor.limit)
    #expect(cursor.addNext(in: text) == .limitReached)
  }

  // MARK: - 여러 자리 고치기

  @Test func editPlacesTextAndShiftsLaterRanges() throws {
    let text = "민준 가 민준"
    let edit = try #require(MultiCursor.edit(
      [NSRange(location: 0, length: 2), NSRange(location: 5, length: 2)], texts: ["도윤이", "도윤이"], textLength: 7))

    #expect(TextChange.applying(edit.changes, to: text) == "도윤이 가 도윤이")
    #expect(edit.inserted == [NSRange(location: 0, length: 3), NSRange(location: 6, length: 3)])
  }

  /// 낡은 자리로 고치지 않는다(D1): 본문 밖, 겹침, 같은 자리, 뒤죽박죽 순서.
  @Test func editRefusesStaleOrOverlappingRanges() {
    let one = [""]
    let two = ["", ""]
    #expect(MultiCursor.edit([NSRange(location: 5, length: 3)], texts: one, textLength: 7) == nil)
    #expect(MultiCursor.edit([NSRange(location: 0, length: 3), NSRange(location: 2, length: 1)], texts: two, textLength: 7) == nil)
    #expect(MultiCursor.edit([NSRange(location: 2, length: 0), NSRange(location: 2, length: 0)], texts: two, textLength: 7) == nil)
    #expect(MultiCursor.edit([NSRange(location: 4, length: 0), NSRange(location: 1, length: 0)], texts: two, textLength: 7) == nil)
    #expect(MultiCursor.edit([NSRange(location: 0, length: 1)], texts: two, textLength: 7) == nil, "개수가 다름")
  }

  // MARK: - 입력기 범위 옮기기

  @Test func movesReplacementAroundFirstCursorToEveryCursor() throws {
    let anchors = [NSRange(location: 3, length: 0), NSRange(location: 8, length: 0)]

    let targets = MultiCursor.targets(forReplacement: NSRange(location: 2, length: 1), around: anchors, textLength: 10)

    #expect(targets == [NSRange(location: 2, length: 1), NSRange(location: 7, length: 1)])
  }

  /// 자리마다 자기 길이를 쓴다(자모를 따로 적은 한글처럼 같은 말인데 길이가 다른 선택, E2).
  @Test func keepsEachAnchorsOwnLength() {
    let anchors = [NSRange(location: 0, length: 2), NSRange(location: 5, length: 4)]

    let targets = MultiCursor.targets(forReplacement: NSRange(location: 0, length: 2), around: anchors, textLength: 10)

    #expect(targets == [NSRange(location: 0, length: 2), NSRange(location: 5, length: 4)])
  }

  /// 맨 앞 자리 둘레가 아니면(재변환·한자 변환) 옮기지 않는다(I2).
  @Test func refusesReplacementNotAroundFirstCursor() {
    let anchors = [NSRange(location: 3, length: 0), NSRange(location: 8, length: 0)]

    #expect(MultiCursor.targets(forReplacement: NSRange(location: 7, length: 1), around: anchors, textLength: 10) == nil)
    #expect(MultiCursor.targets(forReplacement: NSRange(location: 4, length: 1), around: anchors, textLength: 10) == nil)
    #expect(MultiCursor.targets(forReplacement: NSRange(location: 0, length: 3), around: [NSRange(location: 3, length: 0), NSRange(location: 1, length: 0)], textLength: 10) == nil, "옮긴 범위가 본문 밖")
    #expect(MultiCursor.targets(forReplacement: NSRange(location: 0, length: 3), around: [NSRange(location: 3, length: 0), NSRange(location: 5, length: 0)], textLength: 10) == nil, "옮긴 범위끼리 겹침")
  }

  /// 두벌식이 표시된 글자 없이 조합하는 순서(16장 5번 ⓐ)를 세 자리에 재생하면 모두 같은 글이 된다.
  @Test func replaysReplacementModeTypingOnThreeCursors() throws {
    var text = "민준 가 민준 나 민준"
    var cursor = try #require(MultiCursor(selection: NSRange(location: 0, length: 2), wholeWord: true))
    _ = cursor.addNext(in: text)
    _ = cursor.addNext(in: text)
    // (넣을 글, 맨 앞 커서 앞 몇 글자를 바꾸나: nil이면 선택·커서 자리 그대로)
    let calls: [(String, Int?)] = [("ㄷ", nil), ("도", 1), ("동", 1), ("도", 1), ("유", nil), ("윤", 1), (" ", nil)]
    for (insert, before) in calls {
      let anchors = cursor.ranges
      let targets: [NSRange]
      if let before {
        let first = anchors[0]
        targets = try #require(MultiCursor.targets(
          forReplacement: NSRange(location: first.location - before, length: before), around: anchors,
          textLength: (text as NSString).length))
      } else {
        targets = anchors
      }
      let edit = try #require(MultiCursor.edit(
        targets, texts: targets.map { _ in insert }, textLength: (text as NSString).length))
      text = TextChange.applying(edit.changes, to: text)
      cursor.place(edit.inserted.map { NSRange(location: NSMaxRange($0), length: 0) })
    }

    #expect(text == "도윤  가 도윤  나 도윤 ")
    #expect(cursor.ranges.map(\.length) == [0, 0, 0])
  }

  // MARK: - 지우기

  @Test func deleteBackwardTakesWholeCharacterOrSelection() {
    let text = "가👍🏽 나다"
    let emojiEnd = range(of: "👍🏽", in: text).location + range(of: "👍🏽", in: text).length

    let targets = MultiCursor.deleteBackwardTargets(
      [NSRange(location: 0, length: 0), NSRange(location: emojiEnd, length: 0), NSRange(location: emojiEnd + 1, length: 2)],
      in: text)

    #expect(targets == [NSRange(location: 0, length: 0), range(of: "👍🏽", in: text), NSRange(location: emojiEnd + 1, length: 2)])
  }

  /// 맞닿은 커서를 지우면 한 자리에서 만나 하나로 합쳐진다(E4).
  @Test func cursorsThatMeetMerge() throws {
    var cursor = try #require(MultiCursor(selection: NSRange(location: 0, length: 1), wholeWord: false))
    _ = cursor.addNext(in: "가가가")
    let targets = MultiCursor.deleteBackwardTargets(cursor.ranges, in: "가가가")
    let edit = try #require(MultiCursor.edit(targets, texts: targets.map { _ in "" }, textLength: 3))

    cursor.place(edit.inserted)

    #expect(TextChange.applying(edit.changes, to: "가가가") == "가")
    #expect(cursor.ranges == [NSRange(location: 0, length: 0)])
  }

  @Test func mergedJoinsOverlapsAndSameSpotCarets() {
    let merged = MultiCursor.merged([
      NSRange(location: 5, length: 0), NSRange(location: 0, length: 3), NSRange(location: 2, length: 2),
      NSRange(location: 5, length: 0), NSRange(location: 7, length: 1),
    ])

    #expect(merged == [NSRange(location: 0, length: 4), NSRange(location: 5, length: 0), NSRange(location: 7, length: 1)])
  }
}
