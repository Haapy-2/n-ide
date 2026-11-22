import Foundation

/// 전체 바꾸기를 바꾼 자리만 되돌리기, 그리고 다시 바꾸기(PLAN 14장 5번).
/// 회차를 `바꾸기 전` 글로 통째로 덮지 않는다. 바꾼 자리를 다시 알아내 지금 글에서 그 자리를 따라가(`TextTracking`) 그곳만 고친다.
/// 그래서 바꾼 뒤에 쓴 글과 원래부터 있던 같은 말은 그대로 남고, 작가가 손댄 바꾼 자리도 그대로 둔다.
public enum ReplaceRevert {
  /// 한 회차에 적용한 결과
  public struct Outcome: Equatable, Sendable {
    /// 적용한 글. 고친 곳이 없으면 지금 글 그대로.
    public let text: String
    /// 지금 글에서 고칠 자리(지금 글 기준, 앞에서부터). 열린 회차는 편집기가 이것만 고친다.
    public let changes: [TextChange]
    /// 그 뒤에 고쳐서 그대로 둔 곳
    public let kept: Int

    /// 고친 자리(결과 글 기준). 다시 바꾸기가 이 자리를 쓴다.
    public var applied: [NSRange] {
      var shift = 0
      return changes.map { change in
        let length = (change.text as NSString).length
        defer { shift += length - change.range.length }
        return NSRange(location: change.range.location + shift, length: length)
      }
    }
  }

  /// `before`(바꾸기 전 스냅샷)에서 바꾼 자리를 다시 찾아, 지금 글에서 그 자리를 원래 말로 돌린다.
  /// 바꾼 뒤 글은 스냅샷 대신 `before`에 같은 바꾸기를 다시 해서 만든다(`바꾼 뒤` 스냅샷은 남기지 못했을 수 있다).
  /// 메인 스레드 밖에서 부른다.
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

  /// 되돌린 것을 다시 바꾼다. `revertedFrom`은 되돌리기 직전 글(`되돌리기 전` 스냅샷).
  /// 그 글에 같은 되돌리기를 다시 해서 되돌린 자리를 알아낸 뒤, 지금 글에서 그 자리를 바꿀 말로 바꾼다.
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

  /// `base`에서 정한 자리들을 지금 글로 따라가 고친다. 못 따라간 자리는 `kept`로 센다.
  /// `written`은 그 자리에 지금 들어 있어야 할 말(바꿀 말). 그 말이 원래 말의 일부(`민준이` → `민준`)면
  /// 작가가 뒤에 `이`를 다시 붙였거나 이미 되돌린 자리가 그대로 따라와 두 번 붙을 수 있어, 지금 글에 원래 말이 이미 있으면 건너뛴다.
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

  /// 따라온 자리를 둘러싼 지금 글에 넣으려는 말이 이미 그대로 있는가.
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
