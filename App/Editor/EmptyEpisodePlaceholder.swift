import AppKit

/// Draws faint hint text in an empty episode body. Not inserted into text storage (the body is the source), so unrelated to counts, saving or composition.
/// Composition puts the composing character into storage, so length becomes non-zero and the hint disappears immediately.
extension ManuscriptTextView {
  static let placeholderText = "첫 문장을 써 주세요."

  func drawPlaceholder() {
    guard textStorage?.length == 0, let textContainer else { return }
    let origin = NSPoint(
      x: textContainerOrigin.x + textContainer.lineFragmentPadding,
      y: textContainerOrigin.y + emptyLineBaselineFromTop)
    let attributes: [NSAttributedString.Key: Any] = [.font: style.font, .foregroundColor: NSColor.inkMuted]
    // Subtracting the line fragment origin makes origin the baseline position (same height as the first line's glyphs).
    (Self.placeholderText as NSString).draw(
      with: NSRect(origin: origin, size: NSSize(width: style.textWidth, height: style.lineHeight)),
      options: [], attributes: attributes)
  }

  /// Redraw the first line only when switching between empty and non-empty.
  func updatePlaceholderIfNeeded() {
    let isEmpty = textStorage?.length == 0
    guard isEmpty != placeholderShown else { return }
    placeholderShown = isEmpty
    setNeedsDisplay(NSRect(
      x: 0, y: textContainerOrigin.y, width: bounds.width, height: style.lineHeight * 2))
  }
}
