import Foundation

/// Replace all within one body. Matching is identical to `TextSearch` (within paragraphs, optional case sensitivity, decomposed Hangul too).
public enum TextReplace {
  /// The replaced body and the replace count. nil if nothing was found. An empty replacement deletes the matches.
  /// Builds the new body by appending front to back. Match positions are relative to the original body, so replacing doesn't shift them.
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

  /// Match positions (UTF-16), front to back. Used when the editor replaces only the matches.
  public static func ranges(of query: String, in text: String, caseSensitive: Bool) -> [NSRange] {
    var ranges: [NSRange] = []
    TextSearch.forEachHit(of: query, in: text as NSString, caseSensitive: caseSensitive) { hit, _, _ in
      ranges.append(hit)
      return true
    }
    return ranges
  }

  /// Number of matches. Doesn't build the replaced body.
  public static func count(of query: String, in text: String, caseSensitive: Bool) -> Int {
    var count = 0
    TextSearch.forEachHit(of: query, in: text as NSString, caseSensitive: caseSensitive) { _, _, _ in
      count += 1
      return true
    }
    return count
  }

  /// Whether this is a replaceable pair. No replace if the query can't be searched, the replacement contains a newline, or they're identical.
  /// Even case-insensitive, `Sword`→`sword` is a legitimate replace, so compare characters literally.
  public static func canReplace(_ query: String, with replacement: String) -> Bool {
    TextSearch.isSearchable(query) && replacement.rangeOfCharacter(from: .newlines) == nil && query != replacement
  }
}

/// One text edit: replace this range (UTF-16) with this text. The editor applies several at once as one undo unit.
public struct TextChange: Equatable, Sendable {
  public let range: NSRange
  public let text: String

  public init(range: NSRange, text: String) {
    self.range = range
    self.text = text
  }

  /// Text with the edit spots (front to back, non-overlapping) applied. Built in one pass appending front to back (inserting from the back would shift later text per spot).
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

/// Full count taken before a project-wide replace (the confirmation's number). Execution re-finds in each episode's text at replace time, so
/// bodies aren't held (so copies don't pile up while counting 500 episodes).
public struct ReplacementPlan: Equatable, Sendable {
  public struct Episode: Equatable, Sendable {
    public let id: EpisodeID
    public let count: Int
  }

  /// Only episodes with spots to replace, in episode order
  public var episodes: [Episode] = []
  /// Episodes whose body couldn't be read
  public var unreadable: [EpisodeID] = []

  public var count: Int { episodes.reduce(0) { $0 + $1.count } }
}

extension ProjectStore {
  /// Count every spot to replace with no cap. Episodes in `texts` are counted from that text instead of the file (open episode, unsaved text).
  /// Checks for cancellation after each episode. Call off the main thread.
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
