import Foundation

/// The single rule for splitting "lines". Kept in one place so editor line numbers and diff line numbers point at the same lines.
///
/// Line = paragraph. Split at Return's `\n`, `\r\n`/`\r` from other editors, and the Unicode paragraph separator (U+2029).
/// Same rule as NSTextView (NSString paragraphs). U+2028 (line separator) only breaks lines on screen without splitting paragraphs,
/// and U+0085 (NEL) isn't a paragraph to NSString, so it doesn't split here either (verified by tests).
///
/// Swift `String` groups `\r\n` into one character, so `split(separator: "\n")` doesn't split it.
/// So count UTF-16 units directly.
public enum ParagraphLines {
  static let lineFeed: UInt16 = 0x0A
  static let carriageReturn: UInt16 = 0x0D
  static let paragraphSeparator: UInt16 = 0x2029

  /// Whether this UTF-16 unit ends a line. For `\r\n`, the `\r` isn't an end; it's counted once at the `\n`.
  @inline(__always)
  static func endsLine(_ unit: UInt16, next: UInt16?) -> Bool {
    switch unit {
    case lineFeed, paragraphSeparator: true
    case carriageReturn: next != lineFeed
    default: false
    }
  }

  /// Split into lines. Line terminators are dropped; a trailing newline adds one empty line at the end.
  /// Empty text has no lines (empty → new text means all "inserted lines").
  public static func split(_ text: String) -> [String] {
    if text.isEmpty { return [] }
    let units = Array(text.utf16)
    var lines: [String] = []
    var start = 0
    var index = 0
    while index < units.count {
      let unit = units[index]
      let next = index + 1 < units.count ? units[index + 1] : nil
      if unit == carriageReturn && next == lineFeed {
        lines.append(Self.string(units[start..<index]))
        index += 2
        start = index
        continue
      }
      if endsLine(unit, next: next) {
        lines.append(Self.string(units[start..<index]))
        start = index + 1
      }
      index += 1
    }
    lines.append(Self.string(units[start..<units.count]))
    return lines
  }

  /// Number of lines ended before `offset` (UTF-16). The line number containing that offset is this + 1.
  /// Used by the editor to get the number of the first visible paragraph. Reads chunk by chunk without copying the body.
  public static func lineBreaks(in text: NSString, before offset: Int) -> Int {
    let end = min(max(offset, 0), text.length)
    var count = 0
    var buffer = [UInt16](repeating: 0, count: 4096)
    var location = 0
    while location < end {
      let length = min(buffer.count, end - location)
      buffer.withUnsafeMutableBufferPointer { pointer in
        text.getCharacters(pointer.baseAddress!, range: NSRange(location: location, length: length))
      }
      for index in 0..<length {
        let unit = buffer[index]
        guard unit == lineFeed || unit == carriageReturn || unit == paragraphSeparator else { continue }
        if unit == carriageReturn {
          // If the next unit is \n, count it there. If the next unit is outside the chunk, look it up in the body directly.
          let nextLocation = location + index + 1
          let next: UInt16? = index + 1 < length
            ? buffer[index + 1]
            : (nextLocation < text.length ? text.character(at: nextLocation) : nil)
          if next == lineFeed { continue }
        }
        count += 1
      }
      location += length
    }
    return count
  }

  /// Total line count. Empty text still shows line 1 in the editor, so 1. A trailing newline counts the empty line after it.
  public static func lineCount(in text: NSString) -> Int {
    lineBreaks(in: text, before: text.length) + 1
  }

  private static func string(_ units: ArraySlice<UInt16>) -> String {
    String(decoding: units, as: UTF16.self)
  }
}
