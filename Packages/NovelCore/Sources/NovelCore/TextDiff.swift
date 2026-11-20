import Foundation

/// 두 글의 차이 (PLAN 10장 4번). 과거(old) ↔ 현재(new) 비교 화면이 그대로 그릴 수 있는 모양으로 만든다.
/// - 줄 = 문단(`ParagraphLines` 규칙, 편집기 줄 번호와 같음). 같은 줄은 두 칸에 나란히, 지운 줄은 왼쪽만, 넣은 줄은 오른쪽만.
/// - 붙어 있는 "지운 줄"과 "넣은 줄"은 순서대로 짝지어 "고친 줄"로 만든다(두 칸에서 같은 높이).
/// - 고친 줄 안은 바뀐 크기에 맞춰 칠할 곳을 정한다: 많이 바뀌면 줄 전체, 아니면 어절, 어절 안에서 몇 글자면 그 글자만.
public struct TextDiff: Sendable, Equatable {
  /// 고친 줄에서 칠할 곳. 범위는 그 줄 안의 `Character` 위치(0부터)라 한글 음절·이모지가 쪼개지지 않는다.
  public enum Highlight: Sendable, Equatable {
    /// 줄 전체가 바뀐 것으로 본다(문장 단위)
    case wholeLine
    /// 바뀐 부분만. 한쪽이 비어 있을 수 있다(예: 했다→했었다는 과거 칸에 칠할 곳이 없다).
    case ranges(old: [Range<Int>], new: [Range<Int>])
  }

  public enum Row: Sendable, Equatable {
    case same(old: Int, new: Int)
    case removed(old: Int)
    case added(new: Int)
    case changed(old: Int, new: Int, Highlight)
  }

  /// 줄 번호는 여기 위치 + 1
  public let oldLines: [String]
  public let newLines: [String]
  public let rows: [Row]
  /// 너무 커서 고친 줄 안을 비교하지 않았다(모두 `.wholeLine`). 화면에 알린다.
  public let isLineOnly: Bool

  public var hasChanges: Bool {
    rows.contains { if case .same = $0 { false } else { true } }
  }

  /// 고친 줄 안을 비교하는 최대 개수. 넘으면 줄 단위만 한다.
  /// 측정: 한 줄에 약 0.013ms라 2,000줄이면 26ms 안팎(10만 자 전부 고친 2,861줄은 37ms 더 듦).
  public static let defaultInlineLimit = 2_000

  /// 메인 스레드 밖에서 부른다. 도중에 작업이 취소되면 `CancellationError`를 던진다.
  /// `wholeLineRatio`: 고친 줄에서 바뀐 글자가 이 비율을 넘으면 줄 전체를 칠한다.
  public init(
    old: String, new: String, wholeLineRatio: Double = 0.5, inlineLimit: Int = TextDiff.defaultInlineLimit
  ) throws {
    // 다른 편집기가 한글을 자모로 풀어 저장해도(NFD) 같은 글자로 보도록 맞춘다.
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

  // MARK: - 줄 단위

  /// 앞뒤의 같은 줄을 잘라내고 가운데만 `difference(from:)`로 비교한 뒤, 줄 맞춤 목록으로 편다.
  /// 고친 줄은 아직 칠할 곳 없이 `.wholeLine`으로 둔다.
  private static func lineRows(_ old: [String], _ new: [String]) throws -> [Row] {
    var prefix = 0
    while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < old.count - prefix, suffix < new.count - prefix,
      old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
    {
      suffix += 1
    }
    // 줄마다 번호를 붙여 번호끼리 비교한다. 문자열 비교(유니코드 규칙)를 수백만 번 하지 않게 하려는 것(측정, 10만 자 최악 316ms).
    var numbers: [String: Int] = [:]
    func number(_ line: String) -> Int {
      if let known = numbers[line] { return known }
      numbers[line] = numbers.count
      return numbers.count - 1
    }
    let oldMiddle = old[prefix..<(old.count - suffix)].map(number)
    let newMiddle = new[prefix..<(new.count - suffix)].map(number)
    // 한쪽에만 있는 줄은 짝이 될 수 없으니 미리 빼고, 양쪽에 다 있는 줄끼리만 비교한다.
    // 고친 문단은 대개 한쪽에만 있어서 비교할 양이 크게 준다(측정: 겹치는 줄이 없는 10만 자 155ms → 14ms).
    let oldSet = Set(oldMiddle)
    let newSet = Set(newMiddle)
    let oldCommon = oldMiddle.indices.filter { newSet.contains(oldMiddle[$0]) }
    let newCommon = newMiddle.indices.filter { oldSet.contains(newMiddle[$0]) }
    try Task.checkCancellation()
    let difference = newCommon.map { newMiddle[$0] }.difference(from: oldCommon.map { oldMiddle[$0] })
    try Task.checkCancellation()

    // 처음엔 모두 지운 줄·넣은 줄로 두고, 비교에서 남은(같은) 줄만 뺀다.
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
        // 한쪽만 끝났다면 계산이 어긋난 것이다. 앱이 죽지 않게 남은 줄을 지운 줄·넣은 줄로 내보낸다.
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

  // MARK: - 고친 줄 안

  /// 어절 단위로 비교하고, 바뀐 글자가 `wholeLineRatio`를 넘으면 줄 전체로 본다.
  /// 지운 어절 하나와 넣은 어절 하나가 맞붙어 있고 앞이나 뒤 글자가 같으면 다른 글자만 칠한다(을→를, 했다→했었다).
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
      // 바뀐 어절에 낀 띄어쓰기만은 칠하지 않는다(보이지 않는 칸이 칠해지면 어색하다).
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

  /// 두 어절의 같은 앞부분·뒷부분을 빼고 남은 가운데. 같은 글자가 하나도 없으면 nil(어절 전체를 칠한다).
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

  /// 맞닿은 범위를 하나로 합친다(화면이 칠할 조각 수를 줄인다).
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

  /// 어절(빈칸이 아닌 글자 묶음)과 빈칸 묶음을 번갈아 나눈다. 둘 다 토큰이라 이어 붙이면 원래 줄이 된다.
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
