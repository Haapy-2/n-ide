import Foundation

/// Reverting replace all at only the replaced spots, and redoing it (PLAN ch.14 #5).
/// The episode isn't overwritten wholesale with the `바꾸기 전` text. Replaced spots are re-derived, tracked into the current text (`TextTracking`), and only those are edited.
/// So text written after the replace and pre-existing occurrences of the same word stay, as do replaced spots the writer edited.
public enum ReplaceRevert {
  /// Result of applying to one episode
  public struct Outcome: Equatable, Sendable {
    /// The applied text. Unchanged current text if nothing was edited.
    public let text: String
    /// Spots to edit in the current text (current-text coordinates, front to back). For the open episode the editor edits only these.
    public let changes: [TextChange]
    /// Spots edited since, left alone
    public let kept: Int

    /// Edited spots (result-text coordinates). Redo replace uses these.
    public var applied: [NSRange] {
      var shift = 0
      return changes.map { change in
        let length = (change.text as NSString).length
        defer { shift += length - change.range.length }
        return NSRange(location: change.range.location + shift, length: length)
      }
    }
  }

  /// Re-find the replaced spots in `before` (the pre-replace snapshot) and turn those spots in the current text back to the original word.
  /// The post-replace text is rebuilt by reapplying the same replace to `before` instead of using a snapshot (the `바꾼 뒤` snapshot may not have been kept).
  /// Call off the main thread.
  public static func reverting(
    _ query: String, with replacement: String, caseSensitive: Bool, before: String, current: String
  ) throws -> Outcome {
    let source = before as NSString
    let after = NSMutableString(capacity: source.length)
    var edits: [TextChange] = []
    var copied = 0
    TextSearch.forEachHit(of: query, in: source, caseSensitive: caseSensitive) { hit, _, _ in
      after.append(source.substring(with: NSRange(location: copied, length: hit.location - copied)))
      edits.append(TextChange(range: NSRange(location: after.length, length: (replacement as NSString).length),
        text: source.substring(with: hit)))
      after.append(replacement)
      copied = hit.location + hit.length
      return true
    }
    guard !edits.isEmpty else { return Outcome(text: current, changes: [], kept: 0) }
    after.append(source.substring(from: copied))
    return try apply(edits, madeOn: after as String, to: current, written: replacement)
  }

  /// Redo what was reverted. `revertedFrom` is the text right before the revert (`되돌리기 전` snapshot).
  /// Reapply the same revert to that text to locate the reverted spots, then change those spots in the current text to the replacement.
  public static func redoing(
    _ query: String, with replacement: String, caseSensitive: Bool, before: String, revertedFrom: String,
    current: String
  ) throws -> Outcome {
    let reverted = try reverting(
      query, with: replacement, caseSensitive: caseSensitive, before: before, current: revertedFrom)
    let source = reverted.text as NSString
    let edits = reverted.applied.map { TextChange(range: $0, text: replacement) }
    guard !edits.isEmpty else { return Outcome(text: current, changes: [], kept: 0) }
    return try apply(edits, madeOn: source as String, to: current, written: nil)
  }

  /// Track spots decided in `base` into the current text and edit them. Spots that can't be tracked count as `kept`.
  /// `written` is the word that should currently be at the spot (the replacement). If it's part of the original word (`민준이` → `민준`),
  /// the writer re-adding `이` or an already reverted spot could be tracked and doubled, so skip when the original word is already in the current text.
  static func apply(_ edits: [TextChange], madeOn base: String, to current: String, written: String?) throws -> Outcome {
    let tracking = try TextTracking(old: base, new: current)
    let now = current as NSString
    var changes: [TextChange] = []
    var kept = 0
    for edit in edits {
      guard let range = tracking.track(edit.range), range.location >= (changes.last?.range.upperBound ?? 0),
        !alreadyHas(edit.text, around: range, written: written, in: now)
      else {
        kept += 1
        continue
      }
      changes.append(TextChange(range: range, text: edit.text))
    }
    guard !changes.isEmpty else { return Outcome(text: current, changes: [], kept: kept) }
    return Outcome(text: TextChange.applying(changes, to: current), changes: changes, kept: kept)
  }

  /// Whether the current text around the tracked spot already contains the word about to be inserted.
  private static func alreadyHas(_ text: String, around range: NSRange, written: String?, in now: NSString) -> Bool {
    guard let written, !written.isEmpty else { return false }
    let original = text as NSString
    var search = NSRange(location: 0, length: original.length)
    while true {
      let inner = original.range(of: written, options: .literal, range: search)
      guard inner.location != NSNotFound else { return false }
      let start = range.location - inner.location
      if start >= 0, start + original.length <= now.length,
        now.substring(with: NSRange(location: start, length: original.length)) == text
      {
        return true
      }
      search = NSRange(location: inner.location + 1, length: original.length - inner.location - 1)
      if search.length <= 0 { return false }
    }
  }
}
