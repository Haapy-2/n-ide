import Foundation
import Testing
@testable import NovelCore

struct ReplaceRevertTests {
  /// Apply the replace to the pre-replace text, build the writer's later edits with `edit`, then revert.
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

  /// Occurrences of the replacement (`도윤`) that existed before the replace aren't replaced spots, so they stay.
  @Test func wordThatWasAlreadyThereStays() throws {
    let outcome = try revert("도윤과 민준은 친구다.")

    #expect(outcome.text == "도윤과 민준은 친구다.")
    #expect(outcome.applied.count == 1)
  }

  /// Text written after the replace (including a newly written `도윤`) stays; only replaced spots revert.
  @Test func textWrittenAfterwardsStays() throws {
    let outcome = try revert("민준은 웃었다.\n민준이 왔다.") { after in
      after.replacingOccurrences(of: "웃었다.", with: "웃었다. 도윤은 늘 그랬다.") + "\n\n새 문단, 도윤이 말했다."
    }

    #expect(outcome.text == "민준은 웃었다. 도윤은 늘 그랬다.\n민준이 왔다.\n\n새 문단, 도윤이 말했다.")
    #expect(outcome.applied.count == 2)
    #expect(outcome.kept == 0)
  }

  /// For the open episode the editor edits only `changes`. The result must equal `text`.
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

  /// Adding a particle right after the replaced word doesn't count as editing the replaced spot.
  @Test func particleAddedRightAfterStillReverts() throws {
    let outcome = try revert("민준 왔다.") { $0.replacingOccurrences(of: "도윤 ", with: "도윤이 ") }

    #expect(outcome.text == "민준이 왔다.")
  }

  /// When the replacement is part of the original (`민준이` → `민준`) and the writer re-added `이`, skip so it doesn't become `민준이이`.
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

  /// If the writer typed text into a deleted spot, that spot isn't restored (no way to know where to insert).
  @Test func deletionPlaceWrittenOverIsKept() throws {
    let outcome = try revert("아, 민준아.", "민준", "") { $0.replacingOccurrences(of: "아, 아.", with: "아, 그래 아.") }

    #expect(outcome.text == "아, 그래 아.")
    #expect(outcome.kept == 1)
  }

  /// An original word written decomposed (NFD) comes back in that same form.
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

    // Only one spot in a deleted paragraph can't be tracked. A paragraph with its sentence start rewritten still has the name spot intact, so it reverts.
    #expect(outcome.applied.count == 29)
    #expect(outcome.kept == 1)
    #expect(outcome.text.contains("새로 쓴 문단\n"))
    #expect(outcome.text.contains("고쳐 쓴 문단, 민준이 말했다."))
    #expect(!outcome.text.contains("도윤"))
  }

  @Test func redoReplacesOnlyWhatWasReverted() throws {
    let before = "민준이 왔다. 민준은 웃었다."
    let after = TextReplace.replacing("민준", with: "도윤", in: before, caseSensitive: false)!.text
    // After editing the second spot, revert → only the first spot reverts.
    let edited = after.replacingOccurrences(of: "도윤은", with: "도현은")
    let reverted = try ReplaceRevert.reverting(
      "민준", with: "도윤", caseSensitive: false, before: before, current: edited)
    // Write more after reverting, then redo the replace.
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

  /// Heavily rewritten paragraph groups aren't compared by character; spots inside count as untrackable (time grows with length × amount changed).
  @Test func hugeRewrittenBlockIsNotComparedByCharacter() throws {
    let long = String(repeating: "가", count: TextTracking.characterLimit)
    let tracking = try TextTracking(old: "앞\n" + long + "\n뒤", new: "앞\n나" + long + "나\n뒤")

    #expect(tracking.track(NSRange(location: 3, length: 1)) == nil)
    #expect(tracking.track(NSRange(location: 0, length: 1)) == NSRange(location: 0, length: 1))
  }

  /// Even with one edit in a single long paragraph without newlines, the other spots are tracked.
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
