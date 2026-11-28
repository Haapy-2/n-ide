import Foundation

/// Image line in the manuscript `![](../images/<ID>.png)` (PLAN ch.19 #1, decisions 37·52).
/// This is the single place that decides whether a line is an image line. Count, search, replace, ⌘D, export and image numbering all use it,
/// so they never disagree about which lines are images.
///
/// Image line: occupies a line by itself (only surrounding spaces/tabs allowed), empty alt, no whitespace in the path.
/// Lines with alt text, a `"title"`, `<img>`, or an image mid-paragraph stay text. Leaving unknown shapes as text
/// hides no characters, so the manuscript never appears to lose text.
public struct ImageLine: Equatable, Sendable {
  public enum Source: Equatable, Sendable {
    /// A file in the project's `images/` folder. Holds only the file name (both `../images/` and `images/` land here).
    case project(fileName: String)
    /// A path pointing outside the project (`/Users/…`, `../../`, `https://` etc.). Not accepted; shown as a box (G4).
    case outside(path: String)
  }

  public let source: Source

  static let prefix = "![]("
  private static let folderPrefixes = ["../images/", "images/"]

  /// Parse one line (without newline). nil if not an image line.
  public static func parse<Line: StringProtocol>(_ line: Line) -> ImageLine? {
    let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(")") else { return nil }
    let raw = trimmed.dropFirst(prefix.count).dropLast()
    guard !raw.isEmpty, !raw.contains(where: { $0.isWhitespace || $0 == "(" || $0 == ")" || $0 == "\"" }) else {
      return nil
    }
    guard let path = String(raw).removingPercentEncoding else { return nil }
    return ImageLine(source: source(of: path))
  }

  private static func source(of path: String) -> Source {
    for folder in folderPrefixes where path.hasPrefix(folder) {
      let name = String(path.dropFirst(folder.count))
      if !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") {
        return .project(fileName: name)
      }
    }
    return .outside(path: path)
  }

  /// Image line the app inserts. The file name is the app-made `<UUID>.<ext>`, so nothing needs encoding.
  public static func markdown(fileName: String) -> String {
    "\(prefix)../images/\(fileName))"
  }

  /// Whether one paragraph of the body (range excluding the newline) is an image line. For callers checking every paragraph, like search:
  /// if the first character isn't `!`, answers no immediately without building a string.
  public static func isImageLine(_ text: NSString, paragraph: NSRange) -> Bool {
    var index = paragraph.location
    let end = NSMaxRange(paragraph)
    while index < end {
      let unit = text.character(at: index)
      if unit == 0x20 || unit == 0x09 { index += 1; continue }
      guard unit == 0x21 else { return false }
      return parse(text.substring(with: paragraph)) != nil
    }
    return false
  }

  /// Image lines in the body from top to bottom, with their paragraph ranges (UTF-16, excluding newlines).
  /// The ordinal (N in `그림 N`) is this array's index + 1. Numbers are never stored, always counted here (decisions 36·52).
  public static func occurrences(in text: String) -> [(range: NSRange, line: ImageLine)] {
    let source = text as NSString
    var found: [(range: NSRange, line: ImageLine)] = []
    var start = 0
    while start < source.length {
      var end = 0
      var contentsEnd = 0
      source.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
      let paragraph = NSRange(location: start, length: contentsEnd - start)
      if isImageLine(source, paragraph: paragraph), let line = parse(source.substring(with: paragraph)) {
        found.append((paragraph, line))
      }
      guard end > start else { break }
      start = end
    }
    return found
  }

  /// Quick check whether the body might contain an image line. If not, counting doesn't split lines.
  static func mayContainImageLine(_ text: String) -> Bool {
    var first: UInt8 = 0
    var second: UInt8 = 0
    var third: UInt8 = 0
    for byte in text.utf8 {
      if byte == 0x28, first == 0x21, second == 0x5B, third == 0x5D { return true }
      (first, second, third) = (second, third, byte)
    }
    return false
  }
}
