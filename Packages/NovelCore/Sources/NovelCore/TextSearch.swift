import Foundation

/// 본문 한 곳에서 찾은 문구.
public struct SearchMatch: Equatable, Sendable {
  /// 본문 전체에서의 자리(UTF-16 단위). 편집기 선택(NSRange)에 그대로 쓴다.
  public let location: Int
  public let length: Int
  /// 1부터. 엔터(문단)마다 하나로, 편집기 줄 번호와 같다.
  public let line: Int
  /// 그 줄의 글. 길면 일치한 곳 앞뒤만 남기고 `…`로 자른다.
  public let preview: String
  /// `preview` 안에서 일치한 곳(UTF-16 단위)
  public let previewMatch: Range<Int>
}

/// 한 본문에서 문구 찾기. 입력한 문구 그대로, 문단을 넘지 않고, 영문 대소문자 구분은 고른다(SPEC 7장).
/// 정규화 비교를 써서 자모를 따로 적은 한글(NFD)도 같은 글자로 찾는다.
public enum TextSearch {
  /// 미리 보기에서 일치한 곳 앞에 남길 글자 수(UTF-16). 사이드바 폭에 맞춰 앞쪽을 짧게 둔다.
  static let previewLead = 20
  static let previewTrail = 60

  /// `limit`개까지만 찾는다. 줄을 넘는 문구(줄바꿈이 든 문구)와 빈 문구는 찾지 않는다.
  public static func matches(of query: String, in text: String, caseSensitive: Bool, limit: Int = .max) -> [SearchMatch] {
    guard isSearchable(query), limit > 0 else { return [] }
    let text = text as NSString
    let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
    var found: [SearchMatch] = []
    var start = 0
    var line = 1
    while start <= text.length {
      var end = 0
      var contentsEnd = 0
      text.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
      var from = start
      while from < contentsEnd {
        let hit = text.range(of: query, options: options, range: NSRange(location: from, length: contentsEnd - from))
        guard hit.location != NSNotFound, hit.length > 0 else { break }
        found.append(match(hit, line: line, paragraph: NSRange(location: start, length: contentsEnd - start), in: text))
        if found.count == limit { return found }
        from = hit.location + hit.length
      }
      guard end > start, end < text.length else { break }
      start = end
      line += 1
    }
    return found
  }

  /// 찾을 수 있는 문구인지. 줄바꿈이 들면 문단 안에서는 절대 맞지 않는다.
  public static func isSearchable(_ query: String) -> Bool {
    !query.isEmpty && query.rangeOfCharacter(from: .newlines) == nil
  }

  private static func match(_ hit: NSRange, line: Int, paragraph: NSRange, in text: NSString) -> SearchMatch {
    let lead = hit.location - paragraph.location
    let trail = paragraph.location + paragraph.length - (hit.location + hit.length)
    var shown = paragraph
    var prefix = ""
    var suffix = ""
    if lead > previewLead {
      shown.location = hit.location - previewLead
      shown.length -= lead - previewLead
      prefix = "…"
    }
    if trail > previewTrail {
      shown.length -= trail - previewTrail
      suffix = "…"
    }
    // 자른 자리가 이모지 같은 두 단위 글자 가운데면 한 글자 단위로 넓힌다.
    shown = text.rangeOfComposedCharacterSequences(for: shown)
    let body = text.substring(with: shown)
    let matchStart = (prefix as NSString).length + hit.location - shown.location
    return SearchMatch(
      location: hit.location, length: hit.length, line: line,
      preview: prefix + body + suffix, previewMatch: matchStart..<(matchStart + hit.length))
  }
}

public struct ProjectSearchResult: Equatable, Sendable {
  public struct Episode: Equatable, Sendable {
    public let id: EpisodeID
    public let matches: [SearchMatch]
  }

  /// 찾은 것이 있는 회차만, 회차 순서대로
  public var episodes: [Episode] = []
  /// 상한에 닿아 뒤쪽은 찾지 않았다.
  public var isTruncated = false
  /// 본문을 읽지 못한 회차(파일 없음, UTF-8 아님 등)
  public var unreadable: [EpisodeID] = []

  public var matchCount: Int { episodes.reduce(0) { $0 + $1.matches.count } }
}

extension ProjectStore {
  /// 회차들을 순서대로 찾는다. `texts`에 든 회차는 파일 대신 그 글을 찾는다(열린 회차의 편집기 글, 저장 못 한 글).
  /// 회차 하나를 끝낼 때마다 취소를 확인한다. 메인 스레드 밖에서 부른다.
  public func search(
    _ query: String, in ids: [EpisodeID], texts: [EpisodeID: String] = [:],
    caseSensitive: Bool, limit: Int = 1_000
  ) throws -> ProjectSearchResult {
    var result = ProjectSearchResult()
    guard TextSearch.isSearchable(query) else { return result }
    var remaining = limit
    for id in ids {
      try Task.checkCancellation()
      let text: String
      if let given = texts[id] {
        text = given
      } else {
        do { text = try readEpisode(id) } catch {
          result.unreadable.append(id)
          continue
        }
      }
      // 하나 더 찾아서 상한을 넘는지 안다.
      let found = TextSearch.matches(of: query, in: text, caseSensitive: caseSensitive, limit: remaining + 1)
      guard !found.isEmpty else { continue }
      if found.count > remaining {
        if remaining > 0 { result.episodes.append(.init(id: id, matches: Array(found.prefix(remaining)))) }
        result.isTruncated = true
        break
      }
      result.episodes.append(.init(id: id, matches: found))
      remaining -= found.count
    }
    return result
  }
}
