import Foundation

/// 같은 말 여러 커서(⌘D, PLAN 16장)의 계산. 편집기와 상관없는 것만 둔다: 다음 일치 찾기, 여러 자리 한 번에 고치기,
/// 입력기가 맨 앞 커서에 준 범위를 다른 자리로 옮기기.
/// 자리는 본문의 UTF-16 범위(편집기 선택과 같은 단위)이고, 늘 앞에서부터 놓이며 서로 겹치지 않는다.
/// 입력기와 이어진 커서는 늘 맨 앞 자리다: 입력기는 같은 키 이벤트 안에서 자기가 넣은 자리를 다시 묻지 않아서,
/// 그보다 앞을 고치면 기억한 자리가 밀린다(16장 5번 실험).
public struct MultiCursor: Equatable, Sendable {
  /// 커서 수 한도(16장 P1). 넘으면 더 늘리지 않고 알린다.
  public static let limit = 1_000

  /// 한 자리의 선택. `anchor`는 ⇧로 늘릴 때 붙박인 끝, `head`는 움직이는 끝(커서가 깜빡이는 곳).
  public struct Selection: Equatable, Sendable {
    public var anchor: Int
    public var head: Int

    public init(anchor: Int, head: Int) {
      self.anchor = anchor
      self.head = head
    }

    /// 앞에서 뒤로 고른 선택(⌘D, 입력 뒤)
    public init(_ range: NSRange) {
      self.init(anchor: range.location, head: NSMaxRange(range))
    }

    public var range: NSRange { NSRange(location: min(anchor, head), length: abs(head - anchor)) }
  }

  public private(set) var selections: [Selection]
  public var ranges: [NSRange] { selections.map(\.range) }
  /// 마지막으로 더한 자리(`ranges`의 번호). 다음 일치는 그 뒤에서 찾는다.
  public private(set) var newest: Int
  /// 커서만 있던 자리에서 시작했으면 단어 전체로만 찾는다(VS Code와 같다).
  public let wholeWord: Bool

  /// 첫 ⌘D의 선택. 빈 선택이면 nil: 커서 아래 단어 고르기는 편집기가 한다(글자 배치가 정하는 단어 경계).
  public init?(selection: NSRange, wholeWord: Bool) {
    guard selection.length > 0, selection.location != NSNotFound else { return nil }
    selections = [Selection(selection)]
    newest = 0
    self.wholeWord = wholeWord
  }

  /// 되돌리기로 돌아온 자리들. 합친 뒤 둘 이상이어야 여러 커서다.
  public init?(ranges: [NSRange], wholeWord: Bool) {
    let merged = Self.merged(ranges)
    guard merged.count > 1, merged.allSatisfy({ $0.location != NSNotFound && $0.location >= 0 }) else { return nil }
    selections = merged.map(Selection.init)
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
    selections.insert(Selection(found), at: index)
    newest = index
    return .added(found)
  }

  /// 고친 뒤의 자리로 바꾼다. 겹치거나 맞닿은 같은 자리는 하나로 합친다(지우다 커서가 만나면).
  public mutating func place(_ newRanges: [NSRange]) {
    replaceSelections(newRanges.map(Selection.init))
  }

  /// 자리마다 움직이는 끝을 `heads[i]`로 옮긴다(앞에서부터 같은 순서). `extending`이면 붙박인 끝은 그대로(⇧),
  /// 아니면 커서만 남는다. 만난 자리는 합친다: 하나만 남으면 부르는 쪽이 여러 커서를 끝낸다.
  public mutating func move(to heads: [Int], extending: Bool) {
    guard heads.count == selections.count else { return }
    replaceSelections(zip(selections, heads).map { Selection(anchor: extending ? $0.anchor : $1, head: $1) })
  }

  /// 겹치는 선택과 같은 자리 커서는 하나로. 합친 선택의 방향은 그 묶음의 첫 선택을 따른다
  /// (⇧←로 맞닿은 선택은 계속 왼쪽으로, ⇧→는 오른쪽으로 늘어나게).
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

  /// 고친 뒤의 자리(`Edit.inserted`)를 다시 고칠 때(되돌리기). 맞닿은 선택을 지우면 빈 범위와 다음 범위가 한 점에서 시작하는데(E4),
  /// `edit`은 같은 자리에서 시작하는 범위를 낡았다고 보고 받지 않는다. 그런 이웃을 하나로 합치고 글은 앞에서부터 잇는다.
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

  /// 지우기 키(⌫·⌦·⌥⌫·⌘⌫ 등): 선택이 있으면 그 선택, 커서만 있으면 커서와 `stops[i]` 사이(편집기가 키마다 정한 곳).
  /// 앞 자리의 지울 곳과 겹치면(맞닿은 커서) 하나로 합친다.
  public static func deleteTargets(_ ranges: [NSRange], to stops: [Int]) -> [NSRange] {
    let targets = zip(ranges, stops).map { range, stop -> NSRange in
      guard range.length == 0 else { return range }
      return NSRange(location: min(range.location, stop), length: abs(stop - range.location))
    }
    return merged(targets)
  }

  // MARK: - 글자·문단 경계 (화살표·지우기)

  /// 한 글자 뒤(이모지·결합 글자·자모를 따로 적은 한글은 통째로). 끝이면 그대로.
  public static func characterEnd(after index: Int, in text: NSString) -> Int {
    guard index < text.length else { return text.length }
    return NSMaxRange(text.rangeOfComposedCharacterSequence(at: index))
  }

  /// 한 글자 앞. 맨 앞이면 그대로.
  public static func characterStart(before index: Int, in text: NSString) -> Int {
    guard index > 0 else { return 0 }
    return text.rangeOfComposedCharacterSequence(at: min(index, text.length) - 1).location
  }

  /// 문단 처음(⌃A, ⌥↑의 둘째 단계)
  public static func paragraphStart(at index: Int, in text: NSString) -> Int {
    text.paragraphRange(for: NSRange(location: min(index, text.length), length: 0)).location
  }

  /// 문단 끝, 줄바꿈 앞(⌃E, ⌥↓의 둘째 단계)
  public static func paragraphEnd(at index: Int, in text: NSString) -> Int {
    var end = 0
    var contentsEnd = 0
    text.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: min(index, text.length), length: 0))
    return contentsEnd
  }

  // MARK: - 복사와 붙여 넣기 (E7)

  /// ⌘C·⌘X: 고른 글을 앞에서부터 줄바꿈으로 잇는다(VS Code). 빈 선택은 빼고, 모두 비었으면 nil(복사하지 않음).
  public static func copiedText(_ ranges: [NSRange], in text: NSString) -> String? {
    let parts = ranges.filter { $0.length > 0 && NSMaxRange($0) <= text.length }.map { text.substring(with: $0) }
    return parts.isEmpty ? nil : parts.joined(separator: "\n")
  }

  /// 붙여 넣을 글을 자리마다(VS Code `multiCursorPaste: spread`): 끝 줄바꿈 하나를 뗀 줄 수가 커서 수와 같으면
  /// 한 줄씩, 아니면 모든 자리에 같은 글.
  public static func pasteTexts(_ text: String, count: Int) -> [String] {
    var trimmed = text
    // "\r\n"은 Swift에서 한 글자라 `hasSuffix("\n")`로는 안 잡힌다.
    if trimmed.hasSuffix("\r\n") || trimmed.hasSuffix("\n") || trimmed.hasSuffix("\r") { trimmed.removeLast() }
    let lines = trimmed.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: CharacterSet(charactersIn: "\n\r"))
    return lines.count == count ? lines : Array(repeating: text, count: count)
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
