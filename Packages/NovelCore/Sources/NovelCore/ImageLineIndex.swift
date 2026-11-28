import Foundation

/// Image lines of the body being edited, top to bottom, kept current edit by edit.
/// Only the edited paragraphs are re-parsed, so typing in a long episode costs one paragraph, not the whole body.
public struct ImageLineIndex: Sendable {
  public struct Entry: Equatable, Sendable {
    /// Paragraph range excluding the newline (UTF-16)
    public var range: NSRange
    public let line: ImageLine
  }

  public private(set) var entries: [Entry] = []

  public init() {}

  public mutating func rebuild(_ text: NSString) {
    entries = Self.scan(text, in: NSRange(location: 0, length: text.length))
  }

  /// After the text changed in `edited` (new coordinates) by `delta` characters.
  /// Returns the re-parsed paragraph range when some line became, stopped being, or changed as an image line there;
  /// its glyphs must be regenerated beyond the edited characters. nil when no image line changed.
  @discardableResult
  public mutating func update(_ text: NSString, edited: NSRange, delta: Int) -> NSRange? {
    let location = min(edited.location, text.length)
    let paragraphs = text.paragraphRange(for: NSRange(location: location, length: min(edited.length, text.length - location)))
    let oldEnd = NSMaxRange(paragraphs) - delta
    let fresh = Self.scan(text, in: paragraphs)
    var removed: [Entry] = []
    var result: [Entry] = []
    result.reserveCapacity(entries.count + fresh.count)
    var inserted = false
    for var entry in entries {
      if entry.range.location < paragraphs.location {
        result.append(entry)
      } else if entry.range.location < oldEnd {
        removed.append(entry)
      } else {
        if !inserted {
          result += fresh
          inserted = true
        }
        entry.range.location += delta
        result.append(entry)
      }
    }
    if !inserted { result += fresh }
    entries = result
    let same = removed.count == fresh.count
      && zip(removed, fresh).allSatisfy { $0.line == $1.line && $0.range.length == $1.range.length }
    return same ? nil : paragraphs
  }

  public func entry(containing index: Int) -> Entry? {
    var low = 0
    var high = entries.count - 1
    while low <= high {
      let mid = (low + high) / 2
      let range = entries[mid].range
      if index < range.location {
        high = mid - 1
      } else if index >= NSMaxRange(range) {
        low = mid + 1
      } else {
        return entries[mid]
      }
    }
    return nil
  }

  /// Image line whose paragraph ends exactly at `index` (caret right after it).
  public func entry(endingAt index: Int) -> Entry? {
    guard index > 0, let entry = entry(containing: index - 1), NSMaxRange(entry.range) == index else { return nil }
    return entry
  }

  /// Image line that starts exactly at `index` (caret right before it).
  public func entry(startingAt index: Int) -> Entry? {
    guard let entry = entry(containing: index), entry.range.location == index else { return nil }
    return entry
  }

  public func entries(intersecting range: NSRange) -> ArraySlice<Entry> {
    var low = 0
    var high = entries.count
    while low < high {
      let mid = (low + high) / 2
      if NSMaxRange(entries[mid].range) <= range.location { low = mid + 1 } else { high = mid }
    }
    var end = low
    while end < entries.count, entries[end].range.location < max(NSMaxRange(range), range.location + 1) { end += 1 }
    return entries[low..<end]
  }

  private static func scan(_ text: NSString, in range: NSRange) -> [Entry] {
    var found: [Entry] = []
    var start = range.location
    let end = NSMaxRange(range)
    while start < end {
      var next = 0
      var contentsEnd = 0
      text.getParagraphStart(nil, end: &next, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
      let paragraph = NSRange(location: start, length: contentsEnd - start)
      if ImageLine.isImageLine(text, paragraph: paragraph), let line = ImageLine.parse(text.substring(with: paragraph)) {
        found.append(Entry(range: paragraph, line: line))
      }
      guard next > start else { break }
      start = next
    }
    return found
  }
}
