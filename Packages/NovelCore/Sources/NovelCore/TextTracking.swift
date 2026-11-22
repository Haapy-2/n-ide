import Foundation

/// 옛 글의 자리가 새 글의 어디로 갔는지 따라간다(PLAN 14장 5번, 바꾼 자리만 되돌리기).
/// 두 글을 비교해 "그대로 남은 글자 구간" 목록을 만들고, 옛 글의 범위가 한 구간 안에 고스란히 들어 있으면 그 자리를 알려 준다.
///
/// 비교는 UTF-16 단위로 한다(편집기·`NSString` 범위와 같은 단위). 앞뒤 같은 부분을 잘라 낸 뒤 가운데를 문단 단위로 맞추고,
/// 짝이 안 맞은 문단 묶음만 글자 단위로 비교한다. 글자 비교는 묶음이 `characterLimit`보다 크면 하지 않는다:
/// 비교 시간이 (길이 × 바뀐 양)으로 늘어서, 크게 고쳐 쓴 묶음은 그 안의 자리를 "고쳐서 못 따라감"으로 본다.
public struct TextTracking: Sendable {
  struct Segment: Equatable, Sendable {
    let old: Int
    let new: Int
    let length: Int
  }

  /// 같은 글자 구간, 옛 글 순서(새 글 순서도 같다)
  let segments: [Segment]
  let oldLength: Int

  /// 글자 단위로 비교할 묶음 크기 상한(두 쪽 UTF-16 길이 합)
  public static let characterLimit = 4_000

  /// 메인 스레드 밖에서 부른다. 도중에 작업이 취소되면 `CancellationError`를 던진다.
  public init(old: String, new: String) throws {
    let a = Array(old.utf16)
    let b = Array(new.utf16)
    var prefix = 0
    while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] {
      suffix += 1
    }
    // 문단 중간에서 자르면 가운데의 문단 맞추기가 잘린 조각끼리 엉뚱하게 짝짓는다(빈 줄 조각과 빈 줄 등).
    // 같은 앞부분은 마지막 줄 끝 바로 뒤까지, 같은 뒷부분은 첫 줄 끝 바로 뒤부터로 줄인다.
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

  /// 옛 글의 범위가 새 글에서 있는 자리. 범위의 글자가 하나라도 바뀌었거나 구간 경계에 걸치면 nil.
  /// 빈 범위(지운 자리)는 앞뒤 글자가 모두 그대로 이어져 있을 때만 따라간다: 둘레를 고쳤으면 그 자리에 되살릴 글의 맥락이 없다.
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

  // MARK: - 비교

  /// 맨 앞이거나 바로 앞 글자가 줄 끝. `\r\n` 사이는 줄 시작이 아니다.
  private static func isLineStart(_ index: Int, in units: [UInt16]) -> Bool {
    guard index > 0 else { return true }
    return ParagraphLines.endsLine(units[index - 1], next: index < units.count ? units[index] : nil)
  }

  /// 맞닿은 구간을 하나로 합치며 모은다.
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

  /// 문단(줄 끝 문자까지 포함)끼리 맞추고, 사이에 남은 묶음은 글자 단위로 맞춘다.
  private static func matchParagraphs(
    _ a: [UInt16], _ aRange: Range<Int>, _ b: [UInt16], _ bRange: Range<Int>, into builder: inout SegmentBuilder
  ) throws {
    guard !aRange.isEmpty, !bRange.isEmpty else { return }
    let aLines = paragraphs(a, aRange)
    let bLines = paragraphs(b, bRange)
    // 문단마다 번호를 붙여 번호끼리 비교한다(TextDiff와 같은 까닭).
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
    // 남은(같은) 문단은 순서대로 짝이 된다. 짝 사이에 낀 묶음은 글자 단위로.
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
    // 묶음 안의 같은 앞뒤는 비교 없이 남긴다. 아주 긴 문단 하나에서 한 곳만 고쳤을 때도 나머지를 따라가게.
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

  /// 범위 안을 문단으로 나눈다. 줄 끝 문자(`\n`, `\r\n`, `\r`, U+2029)는 그 문단에 넣어 이어 붙이면 원래 범위가 된다.
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
