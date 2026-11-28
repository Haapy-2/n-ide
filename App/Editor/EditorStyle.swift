import AppKit

/// Editor style values (DESIGN.md ch.3). How they're built from settings: `EditorSettings.swift`.
struct EditorStyle: Equatable {
  var fontName = "Pretendard-Regular"
  var fontSize: CGFloat = 17
  /// Line spacing multiplier
  var lineSpacing: CGFloat = 1.75
  /// Paragraph spacing (in lines)
  var paragraphSpacing: CGFloat = 0.6
  /// Hangul characters per line
  var lineWidthInCharacters: CGFloat = 40

  static let topInset: CGFloat = 36
  static let minimumSideInset: CGFloat = 32

  var font: NSFont {
    NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
  }

  /// Line height is fixed so spacing doesn't wobble with each font's natural line height.
  var lineHeight: CGFloat { (fontSize * lineSpacing).rounded() }

  /// One Hangul character's width is taken as 1 em (font size).
  var textWidth: CGFloat { lineWidthInCharacters * fontSize }

  var paragraphStyle: NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = lineHeight
    style.maximumLineHeight = lineHeight
    style.paragraphSpacing = lineHeight * paragraphSpacing
    style.lineBreakStrategy = .hangulWordPriority
    return style
  }

  /// Raise glyphs so they sit near the middle of the fixed line height instead of the bottom.
  var baselineOffset: CGFloat {
    let font = font
    return ((lineHeight - (font.ascender - font.descender)) / 2).rounded()
  }

  var textAttributes: [NSAttributedString.Key: Any] {
    [
      .font: font,
      .paragraphStyle: paragraphStyle,
      .baselineOffset: baselineOffset,
      .foregroundColor: NSColor.ink,
    ]
  }
}
