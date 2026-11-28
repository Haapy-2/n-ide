import AppKit
import NovelCore

/// Layout for the manuscript (PLAN ch.19 #2, plan A). The text storage keeps the markdown image line as is;
/// at layout its first character becomes a picture-sized blank and the rest invisible glyphs, and the picture is drawn there.
/// So file text = editor text: search, snapshots, ⌘D, remembered caret all use the same offsets, and saving converts nothing.
/// Nothing here touches the text storage, so it is safe during Hangul composition.
final class ManuscriptLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
  private(set) var imageLines = ImageLineIndex()
  private(set) var images: EditorImages!
  /// Space above and below a picture (half a body line each).
  var imagePadding: CGFloat = 15 {
    didSet { if imagePadding != oldValue, !imageLines.entries.isEmpty { invalidateAllImageLines() } }
  }
  static let boxHeight: CGFloat = 96

  // NSLayoutManager isn't main-actor isolated, so overrides are nonisolated. The editor lays out and draws only on the main thread.
  nonisolated override init() {
    super.init()
    nonisolated(unsafe) let manager = self
    MainActor.assumeIsolated {
      manager.delegate = manager
      manager.images = EditorImages()
      manager.images.onLoaded = { [weak manager] name in manager?.redraw(fileName: name) }
    }
  }

  nonisolated required init?(coder: NSCoder) { fatalError("not used") }

  /// Picture width fits the text box minus the line fragment padding. Measured against the view width instead,
  /// the trailing newline glyph spills onto an extra line fragment.
  var maxImageWidth: CGFloat {
    let container = textContainers.first
    return max(1, (container?.size.width ?? 0) - 2 * (container?.lineFragmentPadding ?? 0) - 4)
  }

  func displaySize(of line: ImageLine) -> NSSize {
    let width = maxImageWidth
    guard case .ready(let pixels) = images.status(of: line) else { return NSSize(width: width, height: Self.boxHeight) }
    let scale = min(1, width / pixels.width)
    return NSSize(width: max(1, (pixels.width * scale).rounded()), height: max(1, (pixels.height * scale).rounded()))
  }

  /// Image files changed outside (focus regained, reload): re-read the ones that changed and lay out their lines again.
  func revalidateImages() {
    let dropped = Set(images.revalidate())
    guard !dropped.isEmpty else { return }
    for entry in imageLines.entries {
      if case .project(let name) = entry.line.source, dropped.contains(name) {
        invalidateLayout(forCharacterRange: entry.range, actualCharacterRange: nil)
        invalidateDisplay(forCharacterRange: entry.range)
      }
    }
  }

  private func redraw(fileName: String) {
    for entry in imageLines.entries where entry.line.source == .project(fileName: fileName) {
      invalidateDisplay(forCharacterRange: entry.range)
    }
  }

  private func invalidateAllImageLines() {
    for entry in imageLines.entries { invalidateLayout(forCharacterRange: entry.range, actualCharacterRange: nil) }
  }

  // MARK: - Keeping the image line list current

  // A paragraph that becomes or stops being an image line changes glyphs outside the edited characters. Those are regenerated
  // right after the edit is processed, and only when a line's image state changed: widening the storage's edited range instead
  // makes NSTextView move the caret to the end of that range, and regenerating every edit costs a paragraph relayout per key.
  nonisolated override func processEditing(
    for textStorage: NSTextStorage, edited editMask: NSTextStorageEditActions, range newCharRange: NSRange,
    changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange
  ) {
    nonisolated(unsafe) let manager = self
    nonisolated(unsafe) let text = textStorage.mutableString
    let changed: NSRange? = MainActor.assumeIsolated {
      guard editMask.contains(.editedCharacters) else { return nil }
      return manager.imageLines.update(text, edited: newCharRange, delta: delta)
    }
    super.processEditing(
      for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta, invalidatedRange: invalidatedCharRange)
    if let changed, NSMaxRange(changed) <= textStorage.length {
      invalidateGlyphs(forCharacterRange: changed, changeInLength: 0, actualCharacterRange: nil)
      invalidateLayout(forCharacterRange: changed, actualCharacterRange: nil)
    }
  }

  // MARK: - Glyphs and line height

  func layoutManager(
    _ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
    properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>, font: NSFont,
    forGlyphRange glyphRange: NSRange
  ) -> Int {
    guard glyphRange.length > 0, !imageLines.entries.isEmpty else { return 0 }
    let first = characterIndexes[0]
    let span = NSRange(location: first, length: characterIndexes[glyphRange.length - 1] - first + 1)
    guard !imageLines.entries(intersecting: span).isEmpty else { return 0 }
    var changed = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
    for offset in 0..<glyphRange.length {
      guard let entry = imageLines.entry(containing: characterIndexes[offset]) else { continue }
      changed[offset] = characterIndexes[offset] == entry.range.location ? .controlCharacter : .null
    }
    layoutManager.setGlyphs(glyphs, properties: changed, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
    return glyphRange.length
  }

  func layoutManager(
    _ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
    forControlCharacterAt charIndex: Int
  ) -> NSLayoutManager.ControlCharacterAction {
    imageLines.entry(startingAt: charIndex) != nil ? .whitespace : action
  }

  func layoutManager(
    _ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer,
    proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint, characterIndex charIndex: Int
  ) -> NSRect {
    guard let entry = imageLines.entry(startingAt: charIndex) else { return .zero }
    return NSRect(origin: NSPoint(x: glyphPosition.x, y: 0), size: displaySize(of: entry.line))
  }

  func layoutManager(
    _ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
    lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
    in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange
  ) -> Bool {
    let first = characterIndexForGlyph(at: glyphRange.location)
    if let entry = imageLines.entry(startingAt: first) {
      let height = displaySize(of: entry.line).height + imagePadding * 2
      lineFragmentRect.pointee.size.height = height
      lineFragmentUsedRect.pointee.size.height = height
      baselineOffset.pointee = height - imagePadding
      return true
    }
    return BlankLineSpacing.adjust(
      self, lineFragmentRect: lineFragmentRect, lineFragmentUsedRect: lineFragmentUsedRect, forGlyphRange: glyphRange)
  }

  // MARK: - Drawing

  /// Where the picture of an image line sits, in text container coordinates.
  func imageRect(for entry: ImageLineIndex.Entry) -> NSRect {
    let glyph = glyphIndexForCharacter(at: entry.range.location)
    let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    let x = location(forGlyphAt: glyph).x
    return NSRect(origin: NSPoint(x: fragment.minX + x, y: fragment.minY + imagePadding), size: displaySize(of: entry.line))
  }

  nonisolated override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
    super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
    nonisolated(unsafe) let manager = self
    MainActor.assumeIsolated { manager.drawImages(forGlyphRange: glyphsToShow, at: origin) }
  }

  private func drawImages(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
    guard !imageLines.entries.isEmpty else { return }
    let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
    let selection = firstTextView?.selectedRanges.map(\.rangeValue) ?? []
    let scale = firstTextView?.window?.backingScaleFactor ?? 2
    for entry in imageLines.entries(intersecting: characters) {
      let rect = imageRect(for: entry).offsetBy(dx: origin.x, dy: origin.y)
      draw(entry, in: rect, scale: scale)
      if selection.contains(where: { NSIntersectionRange($0, entry.range).length == entry.range.length && $0.length > 0 }) {
        NSColor.selectionToken.setFill()
        rect.fill(using: .sourceOver)
      }
    }
  }

  private func draw(_ entry: ImageLineIndex.Entry, in rect: NSRect, scale: CGFloat) {
    switch (images.status(of: entry.line), entry.line.source) {
    case (.ready, .project(let name)):
      let maxPixel = Int((max(rect.width, rect.height) * scale).rounded(.up))
      if let image = images.thumbnail(fileName: name, maxPixel: maxPixel) {
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
      } else {
        NSColor.ruleToken.withAlphaComponent(0.35).setFill()
        rect.fill()
      }
    case (.missing, .project(let name)):
      drawBox(in: rect, title: "그림을 찾을 수 없어요", detail: name)
    case (.unreadable, .project(let name)):
      drawBox(in: rect, title: "그림을 읽지 못했어요", detail: "\(name) · iCloud에서 아직 내려받지 않았을 수 있어요")
    case (_, .outside(let path)):
      drawBox(in: rect, title: "작품 밖 그림", detail: path)
    default:
      drawBox(in: rect, title: "그림을 찾을 수 없어요", detail: "")
    }
  }

  /// Gray box for a picture that can't be shown (G1·G4·G17). The manuscript line stays; it is never removed automatically.
  private func drawBox(in rect: NSRect, title: String, detail: String) {
    let box = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
    NSColor.ruleToken.withAlphaComponent(0.25).setFill()
    box.fill()
    NSColor.ruleToken.setStroke()
    box.lineWidth = 1
    box.stroke()
    let center = NSMutableParagraphStyle()
    center.alignment = .center
    center.lineBreakMode = .byTruncatingMiddle
    let titleAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.inkMuted, .paragraphStyle: center,
    ]
    let detailAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.inkMuted, .paragraphStyle: center,
    ]
    let inner = rect.insetBy(dx: 16, dy: 0)
    (title as NSString).draw(in: NSRect(x: inner.minX, y: rect.midY - 19, width: inner.width, height: 18), withAttributes: titleAttributes)
    (detail as NSString).draw(in: NSRect(x: inner.minX, y: rect.midY + 3, width: inner.width, height: 16), withAttributes: detailAttributes)
  }
}
