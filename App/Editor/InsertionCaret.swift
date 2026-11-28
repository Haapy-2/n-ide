import AppKit

/// Caret height as a multiple of font size.
/// Line height is fixed to font size × spacing (default 1.75), so left alone the caret would span the whole line, far taller than the glyphs.
/// Positioned at the middle of the glyph body (ascender–descender). Width, height and color: Settings › Caret (`CaretSettings.swift`).
extension ManuscriptTextView {

  /// The rect actually drawn, derived from the system's caret rect (`lineRect`: a line-height rect starting at the line top).
  /// With fixed line height the baseline is the same distance from every line top, so that distance gives the glyph body's middle.
  func caretRect(in lineRect: NSRect) -> NSRect {
    let font = style.font
    let height = (style.fontSize * caret.heightRatio).rounded()
    let baseline = lineRect.minY + emptyLineBaselineFromTop
    // Flipped coordinates (y grows downward). Glyph body = baseline − ascender … baseline − descender (descender is negative).
    let center = baseline - (font.ascender + font.descender) / 2
    var rect = lineRect
    rect.size.width = caret.width
    rect.size.height = min(height, lineRect.height)
    rect.origin.y = (center - rect.height / 2).rounded()
    // Don't extend outside the line rect (very large font, tight spacing).
    rect.origin.y = min(max(rect.minY, lineRect.minY), lineRect.maxY - rect.height)
    return rect
  }

  /// When moving or blinking the caret, the system erases only a default-width (1 pt) rect. Drawing thicker leaves the right 1 pt as a trail, so
  /// requests to redraw a caret-thin rect are widened to caret width + 1 pt. Other redraws are unchanged.
  func widenedForCaret(_ rect: NSRect) -> NSRect {
    guard isCaretSized(rect) else { return rect }
    var wide = rect
    wide.size.width = caret.width + 1
    return wide
  }

  /// Whether this is the thin rect the system sends for the caret (not an already widened one).
  func isCaretSized(_ rect: NSRect) -> Bool {
    !rect.isEmpty && rect.width < caret.width + 1
  }
}
