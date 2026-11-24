import Foundation

/// 같은 말 여러 커서(⌘D, PLAN 16장)의 계산. 편집기와 상관없는 것만 둔다: 다음 일치 찾기, 여러 자리 한 번에 고치기,
/// 입력기가 맨 앞 커서에 준 범위를 다른 자리로 옮기기.
/// 자리는 본문의 UTF-16 범위(편집기 선택과 같은 단위)이고, 늘 앞에서부터 놓이며 서로 겹치지 않는다.
/// 입력기와 이어진 커서는 늘 맨 앞 자리다: 입력기는 같은 키 이벤트 안에서 자기가 넣은 자리를 다시 묻지 않아서,
/// 그보다 앞을 고치면 기억한 자리가 밀린다(16장 5번 실험).
public struct MultiCursor: Equatable, Sendable {
  /// 커서 수 한도(16장 P1). 넘으면 더 늘리지 않고 알린다.
  public static let limit = 1_000

  public private(set) var ranges: [NSRange]
  /// 마지막으로 더한 자리(`ranges`의 번호). 다음 일치는 그 뒤에서 찾는다.
  public private(set) var newest: Int
  /// 커서만 있던 자리에서 시작했으면 단어 전체로만 찾는다(VS Code와 같다).
  public let wholeWord: Bool

  /// 첫 ⌘D의 선택. 빈 선택이면 nil: 커서 아래 단어 고르기는 편집기가 한다(글자 배치가 정하는 단어 경계).
  public init?(selection: NSRange, wholeWord: Bool) {
    guard selection.length > 0, selection.location != NSNotFound else { return nil }
    ranges = [selection]
    newest = 0
    self.wholeWord = wholeWord
  }

  /// 되돌리기로 돌아온 자리들. 합친 뒤 둘 이상이어야 여러 커서다.
  public init?(ranges: [NSRange], wholeWord: Bool) {
    let merged = Self.merged(ranges)
    guard merged.count > 1, merged.allSatisfy({ $0.location != NSNotFound && $0.location >= 0 }) else { return nil }
    self.ranges = merged
    newest = merged.count - 1
    self.wholeWord = wholeWord
  }

  public enum Addition: Equatable, Sendable {
    case added(NSRange)
    /// 더 찾을 곳이 없다(모두 골랐거나 처음부터 하나뿐).
    case noMore
    case limitReached
    /// 고른 말이 비었거나 줄을 넘는다(검색과 같은 규칙).
    case notSearchable
  }

  /// ⌘D 한 번: 마지막으로 더한 자리 뒤에서 같은 말을 찾아 더한다. 끝까지 없으면 처음부터 찾는다.
  /// 이미 고른 자리와 겹치는 곳, 한 글자(이모지·결합 글자)를 가르는 곳, 단어 전체가 아닌 곳은 건너뛴다.
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
    ranges.insert(found, at: index)
    newest = index
    return .added(found)
  }

  /// 고친 뒤의 자리로 바꾼다. 겹치거나 맞닿은 같은 자리는 하나로 합친다(지우다 커서가 만나면).
  public mutating func place(_ newRanges: [NSRange]) {
    let newestLocation = ranges[newest].location
    ranges = Self.merged(newRanges)
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

  // MARK: - 여러 자리 고치기

  public struct Edit: Equatable, Sendable {
    /// 앞에서부터. 편집기는 뒤에서부터 고친다(앞을 먼저 고치면 뒤 자리가 밀린다).
    public let changes: [TextChange]
    /// 고친 뒤 자리마다 새 글이 놓인 범위(앞에서부터)
    public let inserted: [NSRange]
  }

  /// 자리마다 `targets[i]`를 `texts[i]`로. 범위가 본문 밖이거나, 앞에서부터가 아니거나, 겹치거나, 같은 자리에서 시작하면 nil:
  /// 낡은 자리로 고치면 앱이 죽거나(범위 밖) 다른 글이 섞인다(16장 D1). 그때 편집기는 고치지 않고 여러 커서를 끝낸다.
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

  /// 입력기가 맨 앞 자리(`anchors[0]`) 둘레의 `replacement`를 바꾸라고 할 때, 자리마다 같은 상대 범위
  /// (자리 앞 N글자부터 자리 뒤 M글자까지). 자리마다 자기 길이를 쓰므로 자모를 따로 적은 한글처럼 길이가 다른 자리도 맞는다(E2).
  /// `replacement`가 맨 앞 자리 둘레가 아니거나(재변환·한자 변환 등) 옮긴 범위가 본문 밖이거나 서로 겹치면 nil:
  /// 다른 자리로 옮길 뜻이 없으니 편집기는 여러 커서를 끝내고 보통 입력으로 넘긴다(I2).
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

  /// ⌫: 선택이 있으면 그 선택, 커서만 있으면 바로 앞 한 글자(이모지·결합 글자는 통째로), 맨 앞이면 빈 범위.
  /// 앞 자리의 지울 곳과 겹치면(맞닿은 커서) 하나로 합친다.
  public static func deleteBackwardTargets(_ ranges: [NSRange], in text: String) -> [NSRange] {
    let text = text as NSString
    let targets = ranges.map { range -> NSRange in
      guard range.length == 0 else { return range }
      guard range.location > 0 else { return range }
      return text.rangeOfComposedCharacterSequence(at: range.location - 1)
    }
    return merged(targets)
  }

  /// 앞에서부터 놓고, 겹치는 범위와 같은 자리의 빈 범위는 하나로 합친다.
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
