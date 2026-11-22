import Foundation
import Testing
@testable import NovelCore

struct ReplaceRevertTests {
  /// 바꾸기 전 글에 바꾸기를 하고, `edit`으로 작가가 그 뒤에 고친 글을 만든 다음 되돌린다.
  private func revert(
    _ before: String, _ query: String = "민준", _ replacement: String = "도윤",
    edit: (String) -> String = { $0 }
  ) throws -> ReplaceRevert.Outcome {
    let after = TextReplace.replacing(query, with: replacement, in: before, caseSensitive: false)?.text ?? before
    return try ReplaceRevert.reverting(
      query, with: replacement, caseSensitive: false, before: before, current: edit(after))
  }

  @Test func untouchedEpisodeGoesBackExactly() throws {
    let before = "민준은 웃었다.\n\n\"민준아!\" 민준이 돌아봤다."
    let outcome = try revert(before)

    #expect(outcome.text == before)
    #expect(outcome.applied.count == 3)
    #expect(outcome.kept == 0)
  }

  /// 바꾸기 전부터 있던 바꿀 말(`도윤`)은 바꾼 자리가 아니라 그대로 둔다.
  @Test func wordThatWasAlreadyThereStays() throws {
    let outcome = try revert("도윤과 민준은 친구다.")

    #expect(outcome.text == "도윤과 민준은 친구다.")
    #expect(outcome.applied.count == 1)
  }

  /// 바꾼 뒤에 쓴 글(새로 쓴 `도윤` 포함)은 남기고 바꾼 자리만 돌린다.
  @Test func textWrittenAfterwardsStays() throws {
    let outcome = try revert("민준은 웃었다.\n민준이 왔다.") { after in
      after.replacingOccurrences(of: "웃었다.", with: "웃었다. 도윤은 늘 그랬다.") + "\n\n새 문단, 도윤이 말했다."
    }

    #expect(outcome.text == "민준은 웃었다. 도윤은 늘 그랬다.\n민준이 왔다.\n\n새 문단, 도윤이 말했다.")
    #expect(outcome.applied.count == 2)
    #expect(outcome.kept == 0)
  }

  /// 열린 회차는 편집기가 `changes`만 고친다. 그 결과가 `text`와 같아야 한다.
  @Test func changesAreInCurrentTextCoordinates() throws {
    let before = "민준".decomposedStringWithCanonicalMapping + "이 왔다.\nSWORD와 sword"
    let after = TextReplace.replacing("sword", with: "검", in: before, caseSensitive: false)!.text
    let current = "앞. " + after
    let outcome = try ReplaceRevert.reverting("sword", with: "검", caseSensitive: false, before: before, current: current)
    let edited = NSMutableString(string: current)
    for change in outcome.changes.reversed() { edited.replaceCharacters(in: change.range, with: change.text) }

    #expect(outcome.changes.map(\.text) == ["SWORD", "sword"])
    #expect(edited as String == outcome.text)
    #expect(outcome.text == "앞. " + before)
  }

  @Test func editedPlaceIsKeptAndCounted() throws {
    let outcome = try revert("민준이 왔다. 민준은 웃었다.") { after in
      after.replacingOccurrences(of: "도윤은", with: "도현은")
    }

    #expect(outcome.text == "민준이 왔다. 도현은 웃었다.")
    #expect(outcome.applied.count == 1)
    #expect(outcome.kept == 1)
  }

  /// 바꾼 말 바로 뒤에 조사를 붙인 것은 바꾼 자리를 고친 것이 아니다.
  @Test func particleAddedRightAfterStillReverts() throws {
    let outcome = try revert("민준 왔다.") { $0.replacingOccurrences(of: "도윤 ", with: "도윤이 ") }

    #expect(outcome.text == "민준이 왔다.")
  }

  /// 바꿀 말이 원래 말의 일부일 때(`민준이` → `민준`), 작가가 `이`를 다시 붙였으면 `민준이이`가 되지 않게 건너뛴다.
  @Test func doesNotDoubleWhenReplacementIsPartOfOriginal() throws {
    let outcome = try revert("민준이 왔다. 민준이 웃었다.", "민준이", "민준") { after in
      after.replacingOccurrences(of: "민준 웃었다", with: "민준이 웃었다")
    }

    #expect(outcome.text == "민준이 왔다. 민준이 웃었다.")
    #expect(outcome.applied.count == 1)
    #expect(outcome.kept == 1)
  }

  @Test func revertingTwiceChangesNothing() throws {
    let before = "민준이 왔다.\n민준은 웃었다."
    let once = try revert(before)
    let twice = try ReplaceRevert.reverting(
      "민준", with: "도윤", caseSensitive: false, before: before, current: once.text)

    #expect(twice.applied.isEmpty)
    #expect(twice.text == before)
  }

  @Test func deletionPutsTheWordBack() throws {
    let before = "아, 민준아. 민준!"
    #expect(try revert(before, "민준", "").text == before)
  }

  /// 지운 자리에 작가가 글을 써 넣었으면 그 자리는 되살리지 않는다(어디에 넣을지 알 수 없다).
  @Test func deletionPlaceWrittenOverIsKept() throws {
    let outcome = try revert("아, 민준아.", "민준", "") { $0.replacingOccurrences(of: "아, 아.", with: "아, 그래 아.") }

    #expect(outcome.text == "아, 그래 아.")
    #expect(outcome.kept == 1)
  }

  /// 자모로 풀어 쓴 원래 말(NFD)은 그 모양 그대로 돌아온다.
  @Test func decomposedOriginalComesBackAsItWas() throws {
    let before = "민준".decomposedStringWithCanonicalMapping + "이 왔다. 😀민준😀"
    let outcome = try revert(before)

    #expect(outcome.text == before)
    #expect(outcome.applied.count == 2)
  }

  @Test func paragraphsInsertedAndRemovedAroundStillTrack() throws {
    let before = (1...30).map { "\($0)번 문단, 민준이 말했다." }.joined(separator: "\n")
    let outcome = try revert(before) { after in
      var lines = after.components(separatedBy: "\n")
      lines.remove(at: 3)
      lines.insert("새로 쓴 문단", at: 10)
      lines[20] = "고쳐 쓴 문단, 도윤이 말했다."
      return lines.joined(separator: "\n")
    }

    // 지운 문단의 한 곳만 못 따라간다. 문장 앞을 고쳐 쓴 문단도 이름 자리는 그대로라 되돌린다.
    #expect(outcome.applied.count == 29)
    #expect(outcome.kept == 1)
    #expect(outcome.text.contains("새로 쓴 문단\n"))
    #expect(outcome.text.contains("고쳐 쓴 문단, 민준이 말했다."))
    #expect(!outcome.text.contains("도윤"))
  }

  @Test func redoReplacesOnlyWhatWasReverted() throws {
    let before = "민준이 왔다. 민준은 웃었다."
    let after = TextReplace.replacing("민준", with: "도윤", in: before, caseSensitive: false)!.text
    // 두 번째 자리를 고친 뒤 되돌림 → 첫 자리만 되돌아간다.
    let edited = after.replacingOccurrences(of: "도윤은", with: "도현은")
    let reverted = try ReplaceRevert.reverting(
      "민준", with: "도윤", caseSensitive: false, before: before, current: edited)
    // 되돌린 뒤 글을 더 쓰고 다시 바꾼다.
    let written = reverted.text + " 끝."
    let redone = try ReplaceRevert.redoing(
      "민준", with: "도윤", caseSensitive: false, before: before, revertedFrom: edited, current: written)

    #expect(reverted.text == "민준이 왔다. 도현은 웃었다.")
    #expect(redone.text == "도윤이 왔다. 도현은 웃었다. 끝.")
    #expect(redone.applied.count == 1)
  }

  @Test func trackingFollowsAndRefusesEditedRanges() throws {
    let tracking = try TextTracking(old: "가나다라마", new: "가나X다라마바")

    #expect(tracking.track(NSRange(location: 2, length: 2)) == NSRange(location: 3, length: 2))
    #expect(tracking.track(NSRange(location: 1, length: 2)) == nil)
    #expect(tracking.track(NSRange(location: 0, length: 0)) == NSRange(location: 0, length: 0))
    #expect(tracking.track(NSRange(location: 2, length: 0)) == nil)
    #expect(tracking.track(NSRange(location: 4, length: 0)) == NSRange(location: 5, length: 0))
  }

  /// 크게 고쳐 쓴 문단 묶음은 글자 단위로 비교하지 않고, 그 안의 자리를 못 따라간 것으로 본다(시간이 길이 × 바뀐 양으로 늘어서).
  @Test func hugeRewrittenBlockIsNotComparedByCharacter() throws {
    let long = String(repeating: "가", count: TextTracking.characterLimit)
    let tracking = try TextTracking(old: "앞\n" + long + "\n뒤", new: "앞\n나" + long + "나\n뒤")

    #expect(tracking.track(NSRange(location: 3, length: 1)) == nil)
    #expect(tracking.track(NSRange(location: 0, length: 1)) == NSRange(location: 0, length: 1))
  }

  /// 줄바꿈 없는 긴 문단 하나에서 한 곳만 고쳐도 나머지 자리는 따라간다.
  @Test func longSingleParagraphWithOneEditStillTracks() throws {
    let before = String(repeating: "민준이 걸었다. ", count: 600)
    let outcome = try revert(before) { after in
      let middle = after.index(after.startIndex, offsetBy: after.count / 2)
      return after[..<middle] + "새로 쓴 말. " + after[middle...]
    }

    #expect(outcome.applied.count == 600)
    #expect(outcome.text.replacingOccurrences(of: "새로 쓴 말. ", with: "") == before)
  }
}
