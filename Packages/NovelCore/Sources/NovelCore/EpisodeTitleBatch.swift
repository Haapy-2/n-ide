import Foundation

/// Rules for renaming many episodes at once (PLAN ch.15). The same three methods as Finder's batch rename.
/// The sheet's preview and apply both use this one function, so previewed and actual names never diverge.
public enum EpisodeTitleBatch {
  public enum Rule: Equatable, Sendable {
    /// Matching is the same as project search (case-insensitive for Latin, decomposed Hangul too). An empty search term leaves names as is.
    case replace(find: String, with: String)
    case affix(prefix: String, suffix: String)
    /// Number from `start` in the given order. An empty name gives just the number.
    case numbered(name: String, start: Int, numberFirst: Bool)
  }

  /// New titles in the same order. Surrounding whitespace is trimmed (same as single rename).
  public static func titles(_ titles: [String], by rule: Rule) -> [String] {
    titles.enumerated().map { index, title in
      let raw: String
      switch rule {
      case .replace(let find, let replacement):
        raw = find.isEmpty
          ? title : TextReplace.replacing(find, with: replacement, in: title, caseSensitive: false)?.text ?? title
      case .affix(let prefix, let suffix):
        raw = prefix + title + suffix
      case .numbered(let name, let start, let numberFirst):
        let number = String(start + index)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = name.isEmpty ? number : numberFirst ? "\(number) \(name)" : "\(name) \(number)"
      }
      return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }
}
