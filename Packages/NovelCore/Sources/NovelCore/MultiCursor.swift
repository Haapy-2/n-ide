import Foundation

/// Computation for same-word multi-cursor (⌘D, PLAN ch.16). Only editor-independent parts: finding the next match, editing many spots at once,
/// mapping the range the IME gave the leading caret onto other spots.
/// Spots are UTF-16 ranges of the body (same unit as the editor selection), always in order and non-overlapping.
/// The caret tied to the IME is always the leading spot: the IME doesn't re-query the spot it inserted at within the same key event,
/// so editing anything before it shifts the remembered position (ch.16 #5 experiment).
public struct MultiCursor: Equatable, Sendable {
  /// Cursor count limit (ch.16 P1). Beyond it, no more are added and the user is told.
  public static let limit = 1_000

  /// One spot's selection. `anchor` is the fixed end when extending with ⇧, `head` the moving end (where the caret blinks).
  public struct Selection: Equatable, Sendable {
    public var anchor: Int
    public var head: Int

    public init(anchor: Int, head: Int) {
      self.anchor = anchor
      self.head = head
    }

    /// Selection made front to back (⌘D, after typing)
    public init(_ range: NSRange) {
      self.init(anchor: range.location, head: NSMaxRange(range))
    }

    public var range: NSRange { NSRange(location: min(anchor, head), length: abs(head - anchor)) }
  }

  public private(set) var selections: [Selection]
  public var ranges: [NSRange] { selections.map(\.range) }
  /// Most recently added spot (index into `ranges`). The next match is searched after it.
  public private(set) var newest: Int
  /// When started from a bare caret, match whole words only (same as VS Code).
  public let wholeWord: Bool

  /// Selection of the first ⌘D. nil if empty: picking the word under the caret is the editor's job (word boundaries come from layout).
  public init?(selection: NSRange, wholeWord: Bool) {
    guard selection.length > 0, selection.location != NSNotFound else { return nil }
    selections = [Selection(selection)]
    newest = 0
    self.wholeWord = wholeWord
  }

  /// Spots returned by undo. Multi-cursor only if two or more remain after merging.
  public init?(ranges: [NSRange], wholeWord: Bool) {
    let merged = Self.merged(ranges)
    guard merged.count > 1, merged.allSatisfy({ $0.location != NSNotFound && $0.location >= 0 }) else { return nil }
    selections = merged.map(Selection.init)
    newest = merged.count - 1
    self.wholeWord = wholeWord
  }

  public enum Addition: Equatable, Sendable {
    case added(NSRange)
    /// Nothing more to find (all chosen, or only one to begin with).
    case noMore
    case limitReached
    /// The chosen text is empty or spans lines (same rule as search).
    case notSearchable
  }

  /// One ⌘D: find the same text after the most recently added spot and add it. If none till the end, wrap to the start.
  /// Skips matches overlapping chosen spots, splitting one character (emoji, combining characters), or not whole words.
  public mutating func addNext(in text: String) -> Addition {
    let text = text as NSString
    let last = ranges[newest]
    guard NSMaxRange(last) <= text.length else { return .notSearchable }
    let query = text.substring(with: last)
    guard TextSearch.isSearchable(query) else { return .notSearchable }
    guard ranges.count < Self.limit else { return .limitReached }
    let found = firstMatch(of: query, in: text, from: NSMaxRange(last), to: text.length)
      ?? firstMatch(of: query, in: text, from: 0, to: text.length)
    guard let found else { return .noMore }
    let index = ranges.firstIndex { $0.location > found.location } ?? ranges.count
    selections.insert(Selection(found), at: index)
    newest = index
    return .added(found)
  }

  /// Replace with post-edit spots. Overlapping or touching identical spots merge into one (when carets meet while deleting).
  public mutating func place(_ newRanges: [NSRange]) {
    replaceSelections(newRanges.map(Selection.init))
  }

  /// Move each spot's moving end to `heads[i]` (same order, front to back). With `extending` the fixed end stays (⇧),
  /// otherwise only carets remain. Meeting spots merge: if only one remains, the caller ends multi-cursor.
  public mutating func move(to heads: [Int], extending: Bool) {
    guard heads.count == selections.count else { return }
    replaceSelections(zip(selections, heads).map { Selection(anchor: extending ? $0.anchor : $1, head: $1) })
  }

  /// Overlapping selections and same-position carets become one. The merged selection's direction follows the group's first selection
  /// (so touching ⇧← selections keep extending left, ⇧→ right).
  private mutating func replaceSelections(_ new: [Selection]) {
    let newestLocation = ranges[newest].location
    var result: [Selection] = []
    for selection in new.sorted(by: { ($0.range.location, $0.range.length) < ($1.range.location, $1.range.length) }) {
      let range = selection.range
      guard let last = result.last, range.location < NSMaxRange(last.range) || range.location == last.range.location else {
        result.append(selection)
        continue
      }
      let union = NSUnionRange(last.range, range)
      result[result.count - 1] = last.head < last.anchor
        ? Selection(anchor: NSMaxRange(union), head: union.location)
        : Selection(anchor: union.location, head: NSMaxRange(union))
    }
    selections = result
    newest = ranges.lastIndex { $0.location <= newestLocation } ?? 0
  }

  private func firstMatch(of query: String, in text: NSString, from start: Int, to end: Int) -> NSRange? {
    var from = start
    while from < end {
      let hit = text.range(of: query, options: [], range: NSRange(location: from, length: end - from))
      guard hit.location != NSNotFound, hit.length > 0 else { return nil }
      if isUsable(hit, in: text) { return hit }
      from = hit.location + text.rangeOfComposedCharacterSequence(at: hit.location).length
    }
    return nil
  }

  private func isUsable(_ hit: NSRange, in text: NSString) -> Bool {
    guard !ranges.contains(where: { NSIntersectionRange($0, hit).length > 0 || $0.location == hit.location }) else {
      return false
    }
    guard text.rangeOfComposedCharacterSequences(for: hit) == hit else { return false }
    // Spots inside image lines can't be chosen. Editing path characters would break the image (G7).
    guard !ImageLine.isImageLine(text, paragraph: Self.paragraphContents(at: hit.location, in: text)) else { return false }
    guard wholeWord else { return true }
    return !Self.isWordCharacter(before: hit.location, in: text) && !Self.isWordCharacter(at: NSMaxRange(hit), in: text)
  }

  private static func isWordCharacter(before index: Int, in text: NSString) -> Bool {
    guard index > 0 else { return false }
    return isWordCharacter(at: text.rangeOfComposedCharacterSequence(at: index - 1).location, in: text)
  }

  private static func isWordCharacter(at index: Int, in text: NSString) -> Bool {
    guard index < text.length else { return false }
    let character = text.substring(with: text.rangeOfComposedCharacterSequence(at: index))
    guard let scalar = character.unicodeScalars.first else { return false }
    return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
  }

  // MARK: - Editing many spots

  public struct Edit: Equatable, Sendable {
    /// Front to back. The editor edits back to front (editing the front first would shift later spots).
    public let changes: [TextChange]
    /// Per-spot range of the new text after the edit (front to back)
    public let inserted: [NSRange]
  }

  /// Replace each `targets[i]` with `texts[i]`. nil if a range is outside the body, out of order, overlapping, or starts at the same spot:
  /// editing with stale spots crashes (out of range) or mixes in other text (ch.16 D1). The editor then doesn't edit and ends multi-cursor.
  public static func edit(_ targets: [NSRange], texts: [String], textLength: Int) -> Edit? {
    guard !targets.isEmpty, targets.count == texts.count else { return nil }
    var previous: NSRange?
    for target in targets {
      guard target.location != NSNotFound, target.location >= 0, NSMaxRange(target) <= textLength else { return nil }
      if let previous {
        guard target.location >= NSMaxRange(previous), target.location > previous.location else { return nil }
      }
      previous = target
    }
    var shift = 0
    var inserted: [NSRange] = []
    for (target, text) in zip(targets, texts) {
      let length = (text as NSString).length
      inserted.append(NSRange(location: target.location + shift, length: length))
      shift += length - target.length
    }
    return Edit(changes: zip(targets, texts).map { TextChange(range: $0, text: $1) }, inserted: inserted)
  }

  /// For re-editing post-edit spots (`Edit.inserted`) (undo). Deleting touching selections yields an empty range and the next range starting at one point (E4),
  /// which `edit` rejects as stale (same start). Such neighbors are merged into one and their texts joined front to back.
  public static func joinedAtMeetingPoints(_ ranges: [NSRange], texts: [String]) -> (ranges: [NSRange], texts: [String]) {
    var joinedRanges: [NSRange] = []
    var joinedTexts: [String] = []
    for (range, text) in zip(ranges, texts) {
      if let last = joinedRanges.last, last.length == 0, range.location == last.location {
        joinedRanges[joinedRanges.count - 1] = range
        joinedTexts[joinedTexts.count - 1] += text
      } else {
        joinedRanges.append(range)
        joinedTexts.append(text)
      }
    }
    return (joinedRanges, joinedTexts)
  }

  /// When the IME asks to replace `replacement` around the leading spot (`anchors[0]`), the same relative range at each spot
  /// (from N chars before to M chars after the spot). Each spot uses its own length, so spots of differing lengths like decomposed Hangul work (E2).
  /// nil if `replacement` isn't around the leading spot (reconversion, Hanja conversion etc.) or the mapped ranges fall outside the body or overlap:
  /// there's no intent to map to other spots, so the editor ends multi-cursor and falls back to normal input (I2).
  public static func targets(
    forReplacement replacement: NSRange, around anchors: [NSRange], textLength: Int
  ) -> [NSRange]? {
    guard let first = anchors.first, replacement.location != NSNotFound else { return nil }
    let before = first.location - replacement.location
    let after = NSMaxRange(replacement) - NSMaxRange(first)
    guard before >= 0, after >= 0 else { return nil }
    let targets = anchors.map {
      NSRange(location: $0.location - before, length: before + $0.length + after)
    }
    guard targets.allSatisfy({ $0.location >= 0 && NSMaxRange($0) <= textLength }) else { return nil }
    for (a, b) in zip(targets, targets.dropFirst()) where b.location < NSMaxRange(a) {
      return nil
    }
    return targets
  }

  /// Delete keys (⌫·⌦·⌥⌫·⌘⌫ etc.): the selection if any, otherwise between the caret and `stops[i]` (where the editor decided per key).
  /// Merged with the previous spot's deletion if they overlap (touching carets).
  public static func deleteTargets(_ ranges: [NSRange], to stops: [Int]) -> [NSRange] {
    let targets = zip(ranges, stops).map { range, stop -> NSRange in
      guard range.length == 0 else { return range }
      return NSRange(location: min(range.location, stop), length: abs(stop - range.location))
    }
    return merged(targets)
  }

  // MARK: - Character/paragraph boundaries (arrows, delete)

  /// One character forward (emoji, combining characters, decomposed Hangul as a whole). Unchanged at the end.
  public static func characterEnd(after index: Int, in text: NSString) -> Int {
    guard index < text.length else { return text.length }
    return NSMaxRange(text.rangeOfComposedCharacterSequence(at: index))
  }

  /// One character back. Unchanged at the start.
  public static func characterStart(before index: Int, in text: NSString) -> Int {
    guard index > 0 else { return 0 }
    return text.rangeOfComposedCharacterSequence(at: min(index, text.length) - 1).location
  }

  /// Paragraph start (⌃A, second step of ⌥↑)
  public static func paragraphStart(at index: Int, in text: NSString) -> Int {
    text.paragraphRange(for: NSRange(location: min(index, text.length), length: 0)).location
  }

  /// Paragraph end, before the newline (⌃E, second step of ⌥↓)
  public static func paragraphEnd(at index: Int, in text: NSString) -> Int {
    var end = 0
    var contentsEnd = 0
    text.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: min(index, text.length), length: 0))
    return contentsEnd
  }

  private static func paragraphContents(at index: Int, in text: NSString) -> NSRange {
    let start = paragraphStart(at: index, in: text)
    return NSRange(location: start, length: paragraphEnd(at: index, in: text) - start)
  }

  // MARK: - Copy and paste (E7)

  /// ⌘C/⌘X: join selections front to back with newlines (VS Code). Empty selections are skipped; nil (no copy) if all are empty.
  public static func copiedText(_ ranges: [NSRange], in text: NSString) -> String? {
    let parts = ranges.filter { $0.length > 0 && NSMaxRange($0) <= text.length }.map { text.substring(with: $0) }
    return parts.isEmpty ? nil : parts.joined(separator: "\n")
  }

  /// Text to paste per spot (VS Code `multiCursorPaste: spread`): if the line count after dropping one trailing newline equals the cursor count,
  /// one line each; otherwise the same text everywhere.
  public static func pasteTexts(_ text: String, count: Int) -> [String] {
    var trimmed = text
    // "\r\n" is one Character in Swift, so `hasSuffix("\n")` misses it.
    if trimmed.hasSuffix("\r\n") || trimmed.hasSuffix("\n") || trimmed.hasSuffix("\r") { trimmed.removeLast() }
    let lines = trimmed.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: CharacterSet(charactersIn: "\n\r"))
    return lines.count == count ? lines : Array(repeating: text, count: count)
  }

  /// Ordered front to back; overlapping ranges and same-position empty ranges merge into one.
  public static func merged(_ ranges: [NSRange]) -> [NSRange] {
    var result: [NSRange] = []
    for range in ranges.sorted(by: { ($0.location, $0.length) < ($1.location, $1.length) }) {
      if let last = result.last, range.location < NSMaxRange(last) || range.location == last.location {
        result[result.count - 1] = NSUnionRange(last, range)
      } else {
        result.append(range)
      }
    }
    return result
  }
}
