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

  @Test func deleteTargetsTakeSelectionOrUpToStop() {
    let text = "가👍🏽 나다" as NSString
    let emoji = text.range(of: "👍🏽")
    let ranges = [NSRange(location: 0, length: 0), NSRange(location: NSMaxRange(emoji), length: 0), NSRange(location: NSMaxRange(emoji) + 1, length: 2)]

    let targets = MultiCursor.deleteTargets(ranges, to: ranges.map { MultiCursor.characterStart(before: $0.location, in: text) })

    #expect(targets == [NSRange(location: 0, length: 0), emoji, NSRange(location: NSMaxRange(emoji) + 1, length: 2)], "⌫: 맨 앞은 빈 범위, 이모지는 통째로, 선택은 그대로")
    let forward = MultiCursor.deleteTargets([NSRange(location: 1, length: 0)], to: [MultiCursor.characterEnd(after: 1, in: text)])
    #expect(forward == [emoji], "⌦도 같은 함수로")
  }

  /// 맞닿은 커서를 지우면 한 자리에서 만나 하나로 합쳐진다(E4).
  @Test func cursorsThatMeetMerge() throws {
    var cursor = try #require(MultiCursor(selection: NSRange(location: 0, length: 1), wholeWord: false))
    _ = cursor.addNext(in: "가가가")
    let targets = MultiCursor.deleteTargets(
      cursor.ranges, to: cursor.ranges.map { MultiCursor.characterStart(before: $0.location, in: "가가가") })
    let edit = try #require(MultiCursor.edit(targets, texts: targets.map { _ in "" }, textLength: 3))

    cursor.place(edit.inserted)

    #expect(TextChange.applying(edit.changes, to: "가가가") == "가")
    #expect(cursor.ranges == [NSRange(location: 0, length: 0)])
  }

  /// 맞닿은 자리를 지운 뒤의 되돌리기 기록은 빈 범위들이 한 점에서 만난다. 하나로 합쳐야 되돌릴 수 있다(E4).
  @Test func meetingPointsJoinForUndo() throws {
    let joined = MultiCursor.joinedAtMeetingPoints(
      [NSRange(location: 0, length: 0), NSRange(location: 0, length: 0), NSRange(location: 0, length: 1), NSRange(location: 2, length: 0)],
      texts: ["가", "가", "나", "다"])

    #expect(joined.ranges == [NSRange(location: 0, length: 1), NSRange(location: 2, length: 0)])
    #expect(joined.texts == ["가가나", "다"])
    let edit = try #require(MultiCursor.edit(joined.ranges, texts: joined.texts, textLength: 2))
    #expect(TextChange.applying(edit.changes, to: "x ") == "가가나 다")
  }

  @Test func mergedJoinsOverlapsAndSameSpotCarets() {
    let merged = MultiCursor.merged([
      NSRange(location: 5, length: 0), NSRange(location: 0, length: 3), NSRange(location: 2, length: 2),
      NSRange(location: 5, length: 0), NSRange(location: 7, length: 1),
    ])

    #expect(merged == [NSRange(location: 0, length: 4), NSRange(location: 5, length: 0), NSRange(location: 7, length: 1)])
  }

  // MARK: - 움직이기 (E5)

  private func twoCarets(_ first: Int, _ second: Int) throws -> MultiCursor {
    try #require(MultiCursor(ranges: [NSRange(location: first, length: 0), NSRange(location: second, length: 0)], wholeWord: false))
  }

  /// ⇧로 늘리면 붙박인 끝은 그대로라, 반대로 움직이면 선택이 줄어든다.
  @Test func extendingKeepsAnchorSoReverseShrinks() throws {
    var cursor = try twoCarets(2, 10)

    cursor.move(to: [4, 12], extending: true)
    #expect(cursor.ranges == [NSRange(location: 2, length: 2), NSRange(location: 10, length: 2)])
    cursor.move(to: [3, 11], extending: true)
    #expect(cursor.ranges == [NSRange(location: 2, length: 1), NSRange(location: 10, length: 1)])
    cursor.move(to: [1, 9], extending: true)
    #expect(cursor.selections == [.init(anchor: 2, head: 1), .init(anchor: 10, head: 9)], "붙박인 끝을 넘으면 방향이 바뀐다")
    cursor.move(to: [5, 13], extending: false)
    #expect(cursor.ranges == [NSRange(location: 5, length: 0), NSRange(location: 13, length: 0)])
  }

  /// ⌘D로 고른 선택은 앞에서 뒤로: ⇧←는 끝을 당겨 줄인다.
  @Test func findSelectionsAreForward() throws {
    let text = "민준 가 민준"
    var cursor = try #require(MultiCursor(selection: range(of: "민준", in: text), wholeWord: false))
    _ = cursor.addNext(in: text)

    #expect(cursor.selections == [.init(anchor: 0, head: 2), .init(anchor: 5, head: 7)])
    cursor.move(to: cursor.selections.map { $0.head - 1 }, extending: true)
    #expect(words(cursor, in: text) == ["민", "민"])
  }

  /// 움직여 만난 커서는 하나로, 겹친 선택은 첫 선택의 방향으로 합친다(E4).
  @Test func movedCursorsThatMeetMerge() throws {
    var carets = try twoCarets(3, 5)
    carets.move(to: [0, 0], extending: false)
    #expect(carets.ranges == [NSRange(location: 0, length: 0)])

    var left = try twoCarets(3, 5)
    left.move(to: [0, 2], extending: true)
    #expect(left.selections == [.init(anchor: 5, head: 0)], "⇧←로 겹친 선택은 계속 왼쪽으로 늘어난다")

    var right = try twoCarets(3, 5)
    right.move(to: [6, 8], extending: true)
    #expect(right.selections == [.init(anchor: 3, head: 8)])
  }

  @Test func characterAndParagraphBoundaries() {
    let text = "가👍🏽\n둘째 줄\n" as NSString
    let emoji = text.range(of: "👍🏽")
    #expect(MultiCursor.characterEnd(after: 1, in: text) == NSMaxRange(emoji))
    #expect(MultiCursor.characterStart(before: NSMaxRange(emoji), in: text) == 1)
    #expect(MultiCursor.characterEnd(after: text.length, in: text) == text.length)
    #expect(MultiCursor.characterStart(before: 0, in: text) == 0)
    let second = text.range(of: "둘째").location
    #expect(MultiCursor.paragraphStart(at: second + 3, in: text) == second)
    #expect(MultiCursor.paragraphEnd(at: second, in: text) == text.range(of: "줄").location + 1, "줄바꿈 앞")
    #expect(MultiCursor.paragraphEnd(at: 0, in: text) == NSMaxRange(emoji))
  }

  // MARK: - 복사와 붙여 넣기 (E7)

  @Test func copyJoinsSelectionsWithNewlines() {
    let text = "민준 가 도윤 나" as NSString
    let ranges = [text.range(of: "민준"), NSRange(location: 3, length: 0), text.range(of: "도윤")]

    #expect(MultiCursor.copiedText(ranges, in: text) == "민준\n도윤", "빈 선택은 뺀다")
    #expect(MultiCursor.copiedText([NSRange(location: 1, length: 0)], in: text) == nil)
  }

  @Test func pasteSpreadsLinesOnlyWhenCountsMatch() {
    #expect(MultiCursor.pasteTexts("가\n나\n다", count: 3) == ["가", "나", "다"])
    #expect(MultiCursor.pasteTexts("가\n나\n다\n", count: 3) == ["가", "나", "다"], "끝 줄바꿈 하나는 뗀다")
    #expect(MultiCursor.pasteTexts("가\r\n나\r\n", count: 2) == ["가", "나"])
    #expect(MultiCursor.pasteTexts("가\n나", count: 3) == ["가\n나", "가\n나", "가\n나"], "수가 다르면 모든 자리에 같은 글")
    #expect(MultiCursor.pasteTexts("가", count: 2) == ["가", "가"])
  }
}
