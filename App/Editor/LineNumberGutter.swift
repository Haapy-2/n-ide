import AppKit
import NovelCore

/// Editor line numbers.
///
/// - Line = per Return (paragraph). Same rule as the diff view, `ParagraphLines`.
/// - The text container's position and width are untouched; numbers are only drawn in the left margin, so toggling never moves text.
/// - Text storage is read only. Safe during composition.
/// - Only paragraphs visible on screen are computed.
extension ManuscriptTextView {
  struct LineNumberPlacement: Equatable {
    let number: Int
    /// Baseline y of the number text (editor coordinates, top is 0)
    let baselineY: CGFloat
    /// Right edge x of the number column. Numbers are right-aligned here.
    let rightX: CGFloat
  }

  static let lineNumberLeading: CGFloat = 20
  static let newline: unichar = 0x0A
  static func isLineBreak(_ character: unichar) -> Bool { character == 0x0A || character == 0x0D }
  static let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

  /// Widest number width. Numbers are right-aligned to it so ends line up regardless of digit count.
  var lineNumberColumnWidth: CGFloat {
    let digits = String(currentLineCount).count
    let sample = String(repeating: "0", count: digits) as NSString
    return ceil(sample.size(withAttributes: [.font: Self.lineNumberFont]).width)
  }

  /// If the left margin is narrower than `number column + 40pt`, hide only the numbers (don't push the text).
  var lineNumbersFit: Bool {
    textContainerInset.width >= lineNumberColumnWidth + Self.lineNumberLeading * 2
  }

  /// Number positions for paragraphs overlapping `rect` (editor coordinates). Shared by drawing and tests.
  func lineNumberPlacements(in rect: NSRect) -> [LineNumberPlacement] {
    guard showsLineNumbers, lineNumbersFit, let layoutManager, let textContainer, let storage = textStorage else {
      return []
    }
    let text = storage.mutableString
    let origin = textContainerOrigin
    let rightX = Self.lineNumberLeading + lineNumberColumnWidth
    var result: [LineNumberPlacement] = []

    if text.length > 0 {
      // Convert to container coordinates and pick glyphs overlapping that height. Horizontally the whole container (the number column is outside it).
      let probe = NSRect(x: 0, y: rect.minY - origin.y, width: textContainer.size.width, height: rect.height)
      let glyphs = layoutManager.glyphRange(forBoundingRect: probe, in: textContainer)
      let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
      if characters.location < text.length {
        var location = text.paragraphRange(for: NSRange(location: characters.location, length: 0)).location
        var number = ParagraphLines.lineBreaks(in: text, before: location) + 1
        let end = NSMaxRange(characters)
        let blankBaseline = emptyLineBaselineFromTop
        while location < text.length && location <= end {
          let glyph = layoutManager.glyphIndexForCharacter(at: location)
          let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
          // A blank line's newline glyph sits above the text baseline, so use the same baseline as text lines.
          let isBlank = Self.isLineBreak(text.character(at: location))
          let baseline: CGFloat
          if let images = manuscriptLayout, images.imageLines.entry(startingAt: location) != nil {
            // Next to the top of the picture, not its bottom where the image line's baseline sits.
            baseline = origin.y + line.minY + images.imagePadding + Self.lineNumberFont.ascender
          } else {
            baseline = origin.y + line.minY + (isBlank ? blankBaseline : layoutManager.location(forGlyphAt: glyph).y)
          }
          if (!isBlank || numbersBlankLines), baseline - Self.lineNumberFont.ascender <= rect.maxY {
            result.append(LineNumberPlacement(number: number, baselineY: baseline, rightX: rightX))
          }
          location = NSMaxRange(text.paragraphRange(for: NSRange(location: location, length: 0)))
          number += 1
        }
      }
    }

    // If the text ends with Return (or the episode is empty), the caret can sit on the blank line below, so number it.
    let extra = layoutManager.extraLineFragmentRect
    if numbersBlankLines, !extra.isEmpty || text.length == 0 {
      let lineTop = origin.y + (extra.isEmpty ? 0 : extra.minY)
      let baseline = lineTop + emptyLineBaselineFromTop
      let lineHeight = max(extra.height, style.lineHeight)
      if lineTop <= rect.maxY && lineTop + lineHeight >= rect.minY {
        result.append(LineNumberPlacement(number: currentLineCount, baselineY: baseline, rightX: rightX))
      }
    }
    return result
  }

  /// How far a blank (glyphless) line's baseline is below the line top. Same for every line since line height is fixed.
  /// Use the actual value from the body's first non-newline character; compute by formula only when there's none. The formula is ~0.1 pt off.
  var emptyLineBaselineFromTop: CGFloat {
    if let layoutManager, let storage = textStorage {
      let text = storage.mutableString
      var from = 0
      // An image line's baseline is at the bottom of its picture, so skip those.
      while from < text.length {
        let first = text.rangeOfCharacter(from: CharacterSet.newlines.inverted, range: NSRange(location: from, length: text.length - from))
        guard first.location != NSNotFound else { break }
        guard let entry = manuscriptLayout?.imageLines.entry(startingAt: first.location) else {
          return layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: first.location)).y
        }
        from = NSMaxRange(entry.range)
      }
    }
    let font = style.font
    return style.lineHeight + font.descender - style.baselineOffset
  }

  func drawLineNumbers(in rect: NSRect) {
    let placements = lineNumberPlacements(in: rect)
    guard !placements.isEmpty else { return }
    let font = Self.lineNumberFont
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.inkMuted]
    for placement in placements {
      let label = String(placement.number) as NSString
      let width = label.size(withAttributes: attributes).width
      // The editor is flipped (top is 0), so draw(at:)'s point is the glyph box's top-left. Raise by the ascender from the baseline.
      let point = NSPoint(x: placement.rightX - width, y: placement.baselineY - font.ascender)
      label.draw(at: point, withAttributes: attributes)
    }
  }
}
