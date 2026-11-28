import Foundation

/// A phrase found at one spot in a body.
public struct SearchMatch: Equatable, Sendable {
  /// Position in the whole body (UTF-16 units). Used directly as the editor selection (NSRange).
  public let location: Int
  public let length: Int
  /// From 1. One per Return (paragraph), same as editor line numbers.
  public let line: Int
  /// That line's text. Long lines keep only the area around the match, cut with `…`.
  public let preview: String
  /// Match position within `preview` (UTF-16 units)
  public let previewMatch: Range<Int>
}

/// Find a phrase in one body. The phrase as typed, never across paragraphs, Latin case sensitivity selectable (SPEC ch.7).
/// Uses normalized comparison so decomposed Hangul (NFD) matches the same characters.
public enum TextSearch {
  /// Characters (UTF-16) kept before the match in previews. Kept short in front to fit the sidebar width.
  static let previewLead = 20
  static let previewTrail = 60

  /// Finds up to `limit`. Phrases spanning lines (containing newlines) and empty phrases aren't searched.
  public static func matches(of query: String, in text: String, caseSensitive: Bool, limit: Int = .max) -> [SearchMatch] {
    guard limit > 0 else { return [] }
    let text = text as NSString
    var found: [SearchMatch] = []
    forEachHit(of: query, in: text, caseSensitive: caseSensitive) { hit, line, paragraph in
      found.append(match(hit, line: line, paragraph: paragraph, in: text))
      return found.count < limit
    }
    return found
  }

  /// Calls `body(position, line number, its paragraph)` for each match. Returning false stops.
  /// Find and replace both use this one function so they pick the same spots.
  static func forEachHit(
    of query: String, in text: NSString, caseSensitive: Bool, _ body: (NSRange, Int, NSRange) -> Bool
  ) {
    guard isSearchable(query) else { return }
    let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
    var start = 0
    var line = 1
    while start <= text.length {
      var end = 0
      var contentsEnd = 0
      text.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
      let paragraph = NSRange(location: start, length: contentsEnd - start)
      // Path characters of image lines are neither found nor replaced (replacing "png" would break the image, G6).
      var from = ImageLine.isImageLine(text, paragraph: paragraph) ? contentsEnd : start
      while from < contentsEnd {
        let hit = text.range(of: query, options: options, range: NSRange(location: from, length: contentsEnd - from))
        guard hit.location != NSNotFound, hit.length > 0 else { break }
        guard body(hit, line, paragraph) else { return }
        from = hit.location + hit.length
      }
      guard end > start, end < text.length else { break }
      start = end
      line += 1
    }
  }

  /// Whether the phrase is searchable. One containing a newline can never match within a paragraph.
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
    // If the cut lands inside a two-unit character like an emoji, widen to whole characters.
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

  /// Only episodes with matches, in episode order
  public var episodes: [Episode] = []
  /// Hit the cap; later ones weren't searched.
  public var isTruncated = false
  /// Episodes whose body couldn't be read (missing file, not UTF-8 etc.)
  public var unreadable: [EpisodeID] = []

  public var matchCount: Int { episodes.reduce(0) { $0 + $1.matches.count } }
}

extension ProjectStore {
  /// Search episodes in order. Episodes in `texts` are searched from that text instead of the file (open episode's editor text, unsaved text).
  /// Checks for cancellation after each episode. Call off the main thread.
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
      // Find one more to know whether the cap is exceeded.
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
