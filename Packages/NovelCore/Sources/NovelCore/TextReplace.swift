import Foundation

/// 한 본문에서 모두 바꾸기. 찾는 곳은 `TextSearch`와 똑같다(문단 안, 대소문자 선택, 자모를 따로 적은 한글도).
public enum TextReplace {
  /// 바꾼 본문과 바꾼 곳 수. 찾은 곳이 없으면 nil. 바꿀 말이 비면 찾은 말을 지운다.
  /// 앞에서부터 이어 붙여 새 본문을 만든다. 찾은 자리는 원래 본문 기준이라 바꿔도 밀리지 않는다.
  public static func replacing(
    _ query: String, with replacement: String, in text: String, caseSensitive: Bool
  ) -> (text: String, count: Int)? {
    let source = text as NSString
    let result = NSMutableString(capacity: source.length)
    var copied = 0
    var count = 0
    TextSearch.forEachHit(of: query, in: source, caseSensitive: caseSensitive) { hit, _, _ in
      result.append(source.substring(with: NSRange(location: copied, length: hit.location - copied)))
      result.append(replacement)
      copied = hit.location + hit.length
      count += 1
      return true
    }
    guard count > 0 else { return nil }
    result.append(source.substring(from: copied))
    return (result as String, count)
  }

  /// 찾은 자리(UTF-16), 앞에서부터. 편집기에서 찾은 자리만 바꿀 때 쓴다.
  public static func ranges(of query: String, in text: String, caseSensitive: Bool) -> [NSRange] {
    var ranges: [NSRange] = []
    TextSearch.forEachHit(of: query, in: text as NSString, caseSensitive: caseSensitive) { hit, _, _ in
      ranges.append(hit)
      return true
    }
    return ranges
  }

  /// 찾은 곳 수. 바꾼 본문을 만들지 않는다.
  public static func count(of query: String, in text: String, caseSensitive: Bool) -> Int {
    var count = 0
    TextSearch.forEachHit(of: query, in: text as NSString, caseSensitive: caseSensitive) { _, _, _ in
      count += 1
      return true
    }
    return count
  }

  /// 바꿀 수 있는 짝인지. 찾을 수 없는 말이거나, 바꿀 말에 줄바꿈이 들었거나, 둘이 같으면 바꾸지 않는다.
  /// 대소문자를 구분하지 않아도 `Sword`→`sword`는 바꿀 일이 있으므로 글자 그대로 비교한다.
  public static func canReplace(_ query: String, with replacement: String) -> Bool {
    TextSearch.isSearchable(query) && replacement.rangeOfCharacter(from: .newlines) == nil && query != replacement
  }
}

/// 글 한 자리 고치기: 이 범위(UTF-16)를 이 말로. 편집기는 여러 개를 실행 취소 한 단위로 한꺼번에 고친다.
public struct TextChange: Equatable, Sendable {
  public let range: NSRange
  public let text: String

  public init(range: NSRange, text: String) {
    self.range = range
    self.text = text
  }

  /// 고칠 자리들(앞에서부터, 겹치지 않음)을 고친 글. 앞에서부터 이어 붙여 한 번에 만든다(뒤에서부터 끼워 넣으면 자리마다 뒤쪽 글을 민다).
  public static func applying(_ changes: [TextChange], to text: String) -> String {
    guard !changes.isEmpty else { return text }
    let source = text as NSString
    let result = NSMutableString(capacity: source.length)
    var copied = 0
    for change in changes {
      result.append(source.substring(with: NSRange(location: copied, length: change.range.location - copied)))
      result.append(change.text)
      copied = change.range.location + change.range.length
    }
    result.append(source.substring(from: copied))
    return result as String
  }
}

/// 작품 전체 바꾸기를 하기 전에 끝까지 센 결과(확인 창의 숫자). 실행은 회차마다 바꾸는 순간의 글에서 다시 찾으므로
/// 본문은 들고 있지 않는다(500화를 세는 동안 사본이 쌓이지 않게).
public struct ReplacementPlan: Equatable, Sendable {
  public struct Episode: Equatable, Sendable {
    public let id: EpisodeID
    public let count: Int
  }

  /// 바꿀 곳이 있는 회차만, 회차 순서대로
  public var episodes: [Episode] = []
  /// 본문을 읽지 못한 회차
  public var unreadable: [EpisodeID] = []

  public var count: Int { episodes.reduce(0) { $0 + $1.count } }
}

extension ProjectStore {
  /// 바꿀 곳을 상한 없이 끝까지 센다. `texts`에 든 회차는 파일 대신 그 글을 센다(열린 회차, 저장 못 한 글).
  /// 회차 하나를 끝낼 때마다 취소를 확인한다. 메인 스레드 밖에서 부른다.
  public func replacementPlan(
    _ query: String, in ids: [EpisodeID], texts: [EpisodeID: String] = [:], caseSensitive: Bool
  ) throws -> ReplacementPlan {
    var plan = ReplacementPlan()
    guard TextSearch.isSearchable(query) else { return plan }
    for id in ids {
      try Task.checkCancellation()
      let text: String
      if let given = texts[id] {
        text = given
      } else {
        do {
          text = try readEpisode(id)
        } catch {
          plan.unreadable.append(id)
          continue
        }
      }
      let count = TextReplace.count(of: query, in: text, caseSensitive: caseSensitive)
      guard count > 0 else { continue }
      plan.episodes.append(.init(id: id, count: count))
    }
    return plan
  }
}
