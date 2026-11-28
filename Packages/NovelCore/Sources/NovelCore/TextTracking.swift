import Foundation

/// Track where positions in an old text went in a new text (PLAN ch.14 #5, reverting only replaced spots).
/// Compares the two texts into a list of "unchanged character spans"; if an old range lies wholly within one span, reports its new position.
///
/// Compared in UTF-16 units (same as editor/`NSString` ranges). After trimming identical head/tail, the middle is aligned by paragraph,
/// and only unmatched paragraph groups are compared by character. Character comparison is skipped for groups larger than `characterLimit`:
/// its time grows with (length × amount changed), so spots inside heavily rewritten groups count as "edited, can't track".
public struct TextTracking: Sendable {
  struct Segment: Equatable, Sendable {
    let old: Int
    let new: Int
    let length: Int
  }

  /// Unchanged character spans, in old-text order (same as new-text order)
  let segments: [Segment]
  let oldLength: Int

  /// Size cap for groups compared by character (sum of both sides' UTF-16 lengths)
  public static let characterLimit = 4_000

  /// Call off the main thread. Throws `CancellationError` if the task is cancelled midway.
  public init(old: String, new: String) throws {
    let a = Array(old.utf16)
    let b = Array(new.utf16)
    var prefix = 0
    while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] {
      suffix += 1
    }
    // Cutting mid-paragraph would make the middle's paragraph alignment pair up cut fragments wrongly (blank-line fragments with blank lines etc.).
    // The identical head is shrunk to right after the end of its last line, the identical tail to right after the end of its first line.
    while prefix > 0, !(Self.isLineStart(prefix, in: a) && Self.isLineStart(prefix, in: b)) { prefix -= 1 }
    let shift = b.count - a.count
    var suffixStart = a.count - suffix
    while suffixStart < a.count, !(Self.isLineStart(suffixStart, in: a) && Self.isLineStart(suffixStart + shift, in: b)) {
      suffixStart += 1
    }
    suffix = a.count - suffixStart
    var builder = SegmentBuilder()
    builder.add(old: 0, new: 0, length: prefix)
    try Self.matchParagraphs(a, prefix..<(a.count - suffix), b, prefix..<(b.count - suffix), into: &builder)
    builder.add(old: a.count - suffix, new: b.count - suffix, length: suffix)
    segments = builder.segments
    oldLength = a.count
  }

  /// Position of an old range in the new text. nil if any of its characters changed or it straddles a span boundary.
  /// An empty range (a deleted spot) is tracked only if the characters on both sides remain contiguous: if the surroundings were edited, there's no context to restore into.
  public func track(_ range: NSRange) -> NSRange? {
    let start = range.location
    let end = range.location + range.length
    guard let index = segments.lastIndex(where: { $0.old <= start }) else { return nil }
    let segment = segments[index]
    let segmentEnd = segment.old + segment.length
    let fits: Bool
    if range.length > 0 {
      fits = end <= segmentEnd
    } else {
      let insideAfterStart = start > segment.old || start == 0
      let insideBeforeEnd = start < segmentEnd || start == oldLength
      fits = insideAfterStart && insideBeforeEnd && start <= segmentEnd
    }
    guard fits else { return nil }
    return NSRange(location: segment.new + (start - segment.old), length: range.length)
  }

  // MARK: - Comparison

  /// At the start, or right after a line terminator. Between `\r\n` is not a line start.
  private static func isLineStart(_ index: Int, in units: [UInt16]) -> Bool {
    guard index > 0 else { return true }
    return ParagraphLines.endsLine(units[index - 1], next: index < units.count ? units[index] : nil)
  }

  /// Collect while merging touching spans into one.
  struct SegmentBuilder {
    var segments: [Segment] = []

    mutating func add(old: Int, new: Int, length: Int) {
      guard length > 0 else { return }
      if let last = segments.last, last.old + last.length == old, last.new + last.length == new {
        segments[segments.count - 1] = Segment(old: last.old, new: last.new, length: last.length + length)
      } else {
        segments.append(Segment(old: old, new: new, length: length))
      }
    }
  }

  /// Align paragraphs (including line terminators), then align the leftover groups in between by character.
  private static func matchParagraphs(
    _ a: [UInt16], _ aRange: Range<Int>, _ b: [UInt16], _ bRange: Range<Int>, into builder: inout SegmentBuilder
  ) throws {
    guard !aRange.isEmpty, !bRange.isEmpty else { return }
    let aLines = paragraphs(a, aRange)
    let bLines = paragraphs(b, bRange)
    // Number each paragraph and compare numbers (same reason as TextDiff).
    var numbers: [ArraySlice<UInt16>: Int] = [:]
    func number(_ line: Range<Int>, _ units: [UInt16]) -> Int {
      let key = units[line]
      if let known = numbers[key] { return known }
      numbers[key] = numbers.count
      return numbers.count - 1
    }
    let aNumbers = aLines.map { number($0, a) }
    let bNumbers = bLines.map { number($0, b) }
    try Task.checkCancellation()
    let difference = bNumbers.difference(from: aNumbers)
    try Task.checkCancellation()
    var removed = Set<Int>()
    var inserted = Set<Int>()
    for change in difference {
      switch change {
      case .remove(let offset, _, _): removed.insert(offset)
      case .insert(let offset, _, _): inserted.insert(offset)
      }
    }
    // Remaining (identical) paragraphs pair up in order. Groups between pairs are compared by character.
    var i = 0
    var j = 0
    var aGapStart = aRange.lowerBound
    var bGapStart = bRange.lowerBound
    while true {
      while i < aLines.count, removed.contains(i) { i += 1 }
      while j < bLines.count, inserted.contains(j) { j += 1 }
      let aGapEnd = i < aLines.count ? aLines[i].lowerBound : aRange.upperBound
      let bGapEnd = j < bLines.count ? bLines[j].lowerBound : bRange.upperBound
      try matchCharacters(a, aGapStart..<aGapEnd, b, bGapStart..<bGapEnd, into: &builder)
      guard i < aLines.count, j < bLines.count else { break }
      builder.add(old: aLines[i].lowerBound, new: bLines[j].lowerBound, length: aLines[i].count)
      aGapStart = aLines[i].upperBound
      bGapStart = bLines[j].upperBound
      i += 1
      j += 1
    }
  }

  private static func matchCharacters(
    _ a: [UInt16], _ aRange: Range<Int>, _ b: [UInt16], _ bRange: Range<Int>, into builder: inout SegmentBuilder
  ) throws {
    guard !aRange.isEmpty, !bRange.isEmpty else { return }
    // Identical head/tail inside a group is kept without comparing. So a single very long paragraph edited in one place still tracks the rest.
    var head = 0
    while head < aRange.count, head < bRange.count, a[aRange.lowerBound + head] == b[bRange.lowerBound + head] {
      head += 1
    }
    var tail = 0
    while tail < aRange.count - head, tail < bRange.count - head,
      a[aRange.upperBound - 1 - tail] == b[bRange.upperBound - 1 - tail]
    {
      tail += 1
    }
    builder.add(old: aRange.lowerBound, new: bRange.lowerBound, length: head)
    defer { builder.add(old: aRange.upperBound - tail, new: bRange.upperBound - tail, length: tail) }
    let aRange = (aRange.lowerBound + head)..<(aRange.upperBound - tail)
    let bRange = (bRange.lowerBound + head)..<(bRange.upperBound - tail)
    guard !aRange.isEmpty, !bRange.isEmpty, aRange.count + bRange.count <= characterLimit else { return }
    try Task.checkCancellation()
    let difference = b[bRange].difference(from: a[aRange])
    var removed = Set<Int>()
    var inserted = Set<Int>()
    for change in difference {
      switch change {
      case .remove(let offset, _, _): removed.insert(offset)
      case .insert(let offset, _, _): inserted.insert(offset)
      }
    }
    var i = 0
    var j = 0
    while i < aRange.count, j < bRange.count {
      if removed.contains(i) {
        i += 1
      } else if inserted.contains(j) {
        j += 1
      } else {
        builder.add(old: aRange.lowerBound + i, new: bRange.lowerBound + j, length: 1)
        i += 1
        j += 1
      }
    }
  }

  /// Split a range into paragraphs. Line terminators (`\n`, `\r\n`, `\r`, U+2029) belong to their paragraph, so concatenating restores the range.
  private static func paragraphs(_ units: [UInt16], _ range: Range<Int>) -> [Range<Int>] {
    var lines: [Range<Int>] = []
    var start = range.lowerBound
    var index = range.lowerBound
    while index < range.upperBound {
      let next = index + 1 < range.upperBound ? units[index + 1] : nil
      if ParagraphLines.endsLine(units[index], next: next) {
        lines.append(start..<(index + 1))
        start = index + 1
      }
      index += 1
    }
    if start < range.upperBound { lines.append(start..<range.upperBound) }
    return lines
  }
}
