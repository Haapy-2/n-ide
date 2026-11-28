import Foundation

/// Character count of one episode (SPEC ch.7 #3). Counted in `Character` units (visible characters).
/// - With spaces: everything except newlines.
/// - Without spaces: all whitespace (space, tab, newline etc.) removed (full-width spaces too).
public struct CharacterCount: Codable, Equatable, Hashable, Sendable {
  public var withSpaces: Int
  public var withoutSpaces: Int

  public init(withSpaces: Int, withoutSpaces: Int) {
    self.withSpaces = withSpaces
    self.withoutSpaces = withoutSpaces
  }

  public static let zero = CharacterCount(withSpaces: 0, withoutSpaces: 0)

  /// Call off the main thread.
  public init(counting text: String) {
    // Strings from the editor wrap a UTF-16 NSString, so iterating by Character is slow.
    // Converting to a Swift string once before counting: 20 ms → 10 ms for 100k chars (a no-op for native Swift strings).
    var text = text
    text.makeContiguousUTF8()
    var withSpaces = 0
    var withoutSpaces = 0
    // Image lines are skipped entirely (decision 32). Bodies without images are scanned in one pass without splitting lines.
    if ImageLine.mayContainImageLine(text) {
      for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      where ImageLine.parse(line) == nil {
        Self.add(line, withSpaces: &withSpaces, withoutSpaces: &withoutSpaces)
      }
    } else {
      Self.add(text[...], withSpaces: &withSpaces, withoutSpaces: &withoutSpaces)
    }
    self.init(withSpaces: withSpaces, withoutSpaces: withoutSpaces)
  }

  private static func add(_ text: Substring, withSpaces: inout Int, withoutSpaces: inout Int) {
    for character in text {
      if character.isNewline { continue }
      withSpaces += 1
      if !character.isWhitespace { withoutSpaces += 1 }
    }
  }

  /// Value used for goal progress.
  public func value(for basis: CharacterCountBasis) -> Int {
    switch basis {
    case .withSpaces: withSpaces
    case .withoutSpaces: withoutSpaces
    }
  }
}

/// Basis for goal progress and sidebar counts (PLAN decision 3).
public enum CharacterCountBasis: String, CaseIterable, Sendable {
  case withSpaces
  case withoutSpaces
}
