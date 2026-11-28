import Foundation

/// Difference between two texts (PLAN ch.10 #4). Built in a shape the past (old) ↔ present (new) diff view can draw directly.
/// - Line = paragraph (`ParagraphLines` rule, same as editor line numbers). Unchanged lines side by side, deleted lines left only, inserted right only.
/// - Adjacent "deleted" and "inserted" lines are paired in order into "modified lines" (same height in both columns).
/// - Within a modified line, highlighting scales with the change: whole line if much changed, else words, or just a few characters within a word.
public struct TextDiff: Sendable, Equatable {
  /// What to highlight in a modified line. Ranges are `Character` offsets within the line (from 0), so Hangul syllables and emoji never split.
  public enum Highlight: Sendable, Equatable {
    /// Treat the whole line as changed (sentence level)
    case wholeLine
    /// Only the changed parts. One side may be empty (e.g. 했다→했었다 has nothing to highlight in the past column).
    case ranges(old: [Range<Int>], new: [Range<Int>])
  }

  public enum Row: Sendable, Equatable {
    case same(old: Int, new: Int)
    case removed(old: Int)
    case added(new: Int)
    case changed(old: Int, new: Int, Highlight)
  }

  /// Line number is this position + 1
  public let oldLines: [String]
  public let newLines: [String]
  public let rows: [Row]
  /// Too large, so modified lines weren't compared internally (all `.wholeLine`). Reported on screen.
  public let isLineOnly: Bool

  public var hasChanges: Bool {
    rows.contains { if case .same = $0 { false } else { true } }
  }

  /// Max number of modified lines compared internally. Beyond it, line level only.
  /// Measured ~0.013 ms per line, so ~26 ms for 2,000 lines (2,861 lines with all 100k chars modified took 37 ms more).
  public static let defaultInlineLimit = 2_000

  /// If changed characters in a modified line exceed this ratio, highlight the whole line. Set from 10 Korean sentence edits (PLAN ch.10 #4):
  /// at 0.5 even lengthening a short line (`"어디 가?"` → `"어디 가는 거야?"`) becomes whole-line, and at 0.7 a fully rewritten sentence gets highlighted in pieces.
  public static let defaultWholeLineRatio = 0.6

  /// Call off the main thread. Throws `CancellationError` if the task is cancelled midway.
  public init(
    old: String, new: String, wholeLineRatio: Double = TextDiff.defaultWholeLineRatio,
    inlineLimit: Int = TextDiff.defaultInlineLimit
  ) throws {
    // Normalized so Hangul saved decomposed into jamo by other editors (NFD) counts as the same characters.
    let oldLines = Self.lines(old.precomposedStringWithCanonicalMapping)
    let newLines = Self.lines(new.precomposedStringWithCanonicalMapping)
    var pairs = try Self.lineRows(oldLines, newLines)
    let changedCount = pairs.reduce(0) { if case .changed = $1 { $0 + 1 } else { $0 } }
    let isLineOnly = changedCount > inlineLimit
    if !isLineOnly {
      for index in pairs.indices {
        guard case .changed(let o, let n, _) = pairs[index] else { continue }
        try Task.checkCancellation()
        pairs[index] = .changed(
          old: o, new: n, Self.highlight(Array(oldLines[o]), Array(newLines[n]), wholeLineRatio: wholeLineRatio))
      }
    }
    self.oldLines = oldLines
    self.newLines = newLines
    self.rows = pairs
    self.isLineOnly = isLineOnly
  }

  static func lines(_ text: String) -> [String] {
    ParagraphLines.split(text)
  }

  // MARK: - Line level

  /// Trim identical leading/trailing lines, compare only the middle with `difference(from:)`, then flatten into an aligned row list.
  /// Modified lines are left as `.wholeLine` with no highlights yet.
  private static func lineRows(_ old: [String], _ new: [String]) throws -> [Row] {
    var prefix = 0
    while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < old.count - prefix, suffix < new.count - prefix,
      old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
    {
      suffix += 1
    }
    // Number each line and compare numbers, avoiding millions of string comparisons (Unicode rules) (measured, worst case 316 ms for 100k chars).
    var numbers: [String: Int] = [:]
    func number(_ line: String) -> Int {
      if let known = numbers[line] { return known }
      numbers[line] = numbers.count
      return numbers.count - 1
    }
    let oldMiddle = old[prefix..<(old.count - suffix)].map(number)
    let newMiddle = new[prefix..<(new.count - suffix)].map(number)
    // Lines present on only one side can't pair, so they're removed up front and only lines present on both sides are compared.
    // Modified paragraphs usually exist on one side only, which shrinks the comparison a lot (measured: 100k chars with no shared lines 155 ms → 14 ms).
    let oldSet = Set(oldMiddle)
    let newSet = Set(newMiddle)
    let oldCommon = oldMiddle.indices.filter { newSet.contains(oldMiddle[$0]) }
    let newCommon = newMiddle.indices.filter { oldSet.contains(newMiddle[$0]) }
    try Task.checkCancellation()
    let difference = newCommon.map { newMiddle[$0] }.difference(from: oldCommon.map { oldMiddle[$0] })
    try Task.checkCancellation()

    // Start with everything as deleted/inserted, then remove the lines left (unchanged) by the comparison.
    var removed = Set(prefix..<(old.count - suffix))
    var inserted = Set(prefix..<(new.count - suffix))
    var removedCommon = Set<Int>()
    var insertedCommon = Set<Int>()
    for change in difference {
      switch change {
      case .remove(let offset, _, _): removedCommon.insert(offset)
      case .insert(let offset, _, _): insertedCommon.insert(offset)
      }
    }
    for (k, index) in oldCommon.enumerated() where !removedCommon.contains(k) { removed.remove(prefix + index) }
    for (k, index) in newCommon.enumerated() where !insertedCommon.contains(k) { inserted.remove(prefix + index) }

    var rows: [Row] = []
    rows.reserveCapacity(max(old.count, new.count))
    var i = 0
    var j = 0
    while i < old.count || j < new.count {
      var removedRun: [Int] = []
      while i < old.count, removed.contains(i) {
        removedRun.append(i)
        i += 1
      }
      var insertedRun: [Int] = []
      while j < new.count, inserted.contains(j) {
        insertedRun.append(j)
        j += 1
      }
      if removedRun.isEmpty, insertedRun.isEmpty {
        // If only one side finished, the computation went wrong. To avoid crashing, emit the remaining lines as deleted/inserted.
        guard i < old.count, j < new.count else {
          rows += (i..<old.count).map { Row.removed(old: $0) } + (j..<new.count).map { Row.added(new: $0) }
          break
        }
        rows.append(.same(old: i, new: j))
        i += 1
        j += 1
        continue
      }
      let paired = min(removedRun.count, insertedRun.count)
      for k in 0..<paired { rows.append(.changed(old: removedRun[k], new: insertedRun[k], .wholeLine)) }
      for o in removedRun.dropFirst(paired) { rows.append(.removed(old: o)) }
      for n in insertedRun.dropFirst(paired) { rows.append(.added(new: n)) }
    }
    return rows
  }

  // MARK: - Within modified lines

  /// Compare by words; if changed characters exceed `wholeLineRatio`, treat as the whole line.
  /// When one deleted word and one inserted word are adjacent and share leading or trailing characters, highlight only the differing characters (을→를, 했다→했었다).
  static func highlight(_ old: [Character], _ new: [Character], wholeLineRatio: Double) -> Highlight {
    let oldTokens = tokens(old)
    let newTokens = tokens(new)
    let difference = newTokens.map(\.text).difference(from: oldTokens.map(\.text))
    var removed = Set<Int>()
    var inserted = Set<Int>()
    for change in difference {
      switch change {
      case .remove(let offset, _, _): removed.insert(offset)
      case .insert(let offset, _, _): inserted.insert(offset)
      }
    }

    var oldRanges: [Range<Int>] = []
    var newRanges: [Range<Int>] = []
    var changedCharacters = 0
    var i = 0
    var j = 0
    while i < oldTokens.count || j < newTokens.count {
      var removedRun: [Token] = []
      while i < oldTokens.count, removed.contains(i) {
        removedRun.append(oldTokens[i])
        i += 1
      }
      var insertedRun: [Token] = []
      while j < newTokens.count, inserted.contains(j) {
        insertedRun.append(newTokens[j])
        j += 1
      }
      if removedRun.isEmpty, insertedRun.isEmpty {
        guard i < oldTokens.count, j < newTokens.count else { return .wholeLine }
        i += 1
        j += 1
        continue
      }
      // Spaces caught inside changed words aren't highlighted (highlighting invisible cells looks odd).
      let removedWords = removedRun.filter { !$0.isSpace }
      let insertedWords = insertedRun.filter { !$0.isSpace }
      if removedWords.count == 1, insertedWords.count == 1,
        let ranges = characterRanges(removedWords[0], insertedWords[0])
      {
        let (o, n) = ranges
        if !o.isEmpty { oldRanges.append(o) }
        if !n.isEmpty { newRanges.append(n) }
        changedCharacters += max(o.count, n.count)
      } else {
        for token in removedWords { oldRanges.append(token.range) }
        for token in insertedWords { newRanges.append(token.range) }
        changedCharacters += max(
          removedWords.reduce(0) { $0 + $1.range.count }, insertedWords.reduce(0) { $0 + $1.range.count })
      }
    }

    let length = max(old.count, new.count)
    if length == 0 || Double(changedCharacters) > Double(length) * wholeLineRatio { return .wholeLine }
    return .ranges(old: merged(oldRanges), new: merged(newRanges))
  }

  /// The middle left after removing the shared prefix/suffix of two words. nil if no characters are shared (highlight the whole word).
  private static func characterRanges(_ old: Token, _ new: Token) -> (Range<Int>, Range<Int>)? {
    let a = old.characters
    let b = new.characters
    var prefix = 0
    while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] {
      suffix += 1
    }
    guard prefix + suffix > 0 else { return nil }
    let start = old.range.lowerBound
    let newStart = new.range.lowerBound
    return (
      (start + prefix)..<(start + a.count - suffix),
      (newStart + prefix)..<(newStart + b.count - suffix)
    )
  }

  /// Merge touching ranges into one (fewer pieces for the view to paint).
  private static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
    var result: [Range<Int>] = []
    for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
      if let last = result.last, last.upperBound >= range.lowerBound {
        result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
      } else {
        result.append(range)
      }
    }
    return result
  }

  /// Split alternately into words (runs of non-space characters) and space runs. Both are tokens, so concatenating restores the line.
  struct Token {
    let characters: [Character]
    let range: Range<Int>
    var text: String { String(characters) }
    var isSpace: Bool { characters.first?.isWhitespace ?? false }
  }

  static func tokens(_ line: [Character]) -> [Token] {
    var result: [Token] = []
    var start = 0
    while start < line.count {
      let space = line[start].isWhitespace
      var end = start + 1
      while end < line.count, line[end].isWhitespace == space { end += 1 }
      result.append(Token(characters: Array(line[start..<end]), range: start..<end))
      start = end
    }
    return result
  }
}
