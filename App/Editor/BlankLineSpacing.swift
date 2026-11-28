import AppKit

/// Blank lines (paragraphs with only a newline) get no paragraph spacing (DESIGN.md ch.3).
/// Web novels separate paragraphs with blank lines; spacing on those too makes the gap "line spacing + blank line + blank spacing", far too wide.
/// The storage's paragraph attributes stay as-is; only the line fragment shrinks at layout, so storage isn't touched even during Hangul composition.
final class BlankLineSpacing: NSObject, NSLayoutManagerDelegate {
  func layoutManager(
    _ layoutManager: NSLayoutManager,
    shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
    lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
    baselineOffset: UnsafeMutablePointer<CGFloat>,
    in textContainer: NSTextContainer,
    forGlyphRange glyphRange: NSRange
  ) -> Bool {
    guard let storage = layoutManager.textStorage else { return false }
    let range = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    // Blank line = a line with only a newline ("\n", or "\r\n" in Windows files), preceded by a newline or the start of the text.
    guard range.length == 1 || range.length == 2 else { return false }
    let text = storage.string as NSString
    let isBreak = ManuscriptTextView.isLineBreak
    guard (range.location..<NSMaxRange(range)).allSatisfy({ isBreak(text.character(at: $0)) }),
      range.length == 1 || text.character(at: range.location) == 0x0D,
      range.location == 0 || isBreak(text.character(at: range.location - 1))
    else { return false }
    // The part taller than the used rect (line height) is the paragraph spacing.
    guard lineFragmentRect.pointee.height > lineFragmentUsedRect.pointee.height else { return false }
    lineFragmentRect.pointee.size.height = lineFragmentUsedRect.pointee.height
    return true
  }
}
