import AppKit
import NovelCore

/// An image line edits as one block (PLAN ch.19 #2, G8): the caret sits only before or after it, edits that change part of it are
/// refused, and ⌫ right after it removes it whole. The hidden markdown characters never get a caret between them,
/// so nothing can be typed into the path.
extension ManuscriptTextView {
  var manuscriptLayout: ManuscriptLayoutManager? { layoutManager as? ManuscriptLayoutManager }

  private var imageLines: ImageLineIndex? {
    guard let index = manuscriptLayout?.imageLines, !index.entries.isEmpty else { return nil }
    return index
  }

  private func inside(_ index: ImageLineIndex, _ location: Int) -> ImageLineIndex.Entry? {
    guard let entry = index.entry(containing: location), location > entry.range.location else { return nil }
    return entry
  }

  /// Selection moved onto hidden characters → nearest edge (or the edge in the direction of a one-step move);
  /// a selection reaching into an image line grows to cover it.
  func selectionKeepingImageLinesWhole(_ proposed: NSRange, from old: NSRange) -> NSRange {
    guard let index = imageLines else { return proposed }
    if proposed.length == 0 {
      guard let entry = inside(index, proposed.location) else { return proposed }
      let start = entry.range.location
      let end = NSMaxRange(entry.range)
      if old.length == 0, proposed.location == old.location + 1 { return NSRange(location: end, length: 0) }
      if old.length == 0, proposed.location == old.location - 1 { return NSRange(location: start, length: 0) }
      return NSRange(location: proposed.location - start <= end - proposed.location ? start : end, length: 0)
    }
    var lower = proposed.location
    var upper = NSMaxRange(proposed)
    if let entry = inside(index, lower) { lower = entry.range.location }
    if let entry = index.entry(containing: upper - 1), upper < NSMaxRange(entry.range) { upper = NSMaxRange(entry.range) }
    return NSRange(location: lower, length: upper - lower)
  }

  /// False when an edit would change only part of an image line. Undo/redo and multi-cursor edits pass:
  /// undo restores states that existed, and ⌘D never matches inside an image line (NovelCore `TextSearch`).
  func editKeepsImageLinesWhole(_ ranges: [NSRange]) -> Bool {
    guard let index = imageLines, !isApplyingMultiCursor, !hasMarkedText(),
      !episodeUndoManager.isUndoing, !episodeUndoManager.isRedoing
    else { return true }
    for range in ranges {
      if range.length == 0 {
        if inside(index, range.location) != nil { return false }
        continue
      }
      for entry in index.entries(intersecting: range) where NSIntersectionRange(entry.range, range).length > 0 {
        if range.location > entry.range.location || NSMaxRange(range) < NSMaxRange(entry.range) { return false }
      }
    }
    return true
  }

  /// Typing right before or after an image line starts a new line first, so the text doesn't join the image line
  /// (which would turn it back into markdown text). Done in `keyDown`, before the key reaches the input method:
  /// once the input method has chosen where to insert, opening a line inside `setMarkedText`/`insertText` splits Hangul into loose jamo.
  func openLineBesideImageLine(for text: String) {
    guard !text.isEmpty, multiCursor == nil, !hasMarkedText(), let index = imageLines else { return }
    let selection = selectedRange()
    guard selection.length == 0 else { return }
    let location = selection.location
    if index.entry(startingAt: location) != nil, !text.hasSuffix("\n") {
      insertLineBreak(at: location, caretAfter: false)
    } else if index.entry(endingAt: location) != nil, !text.hasPrefix("\n") {
      insertLineBreak(at: location, caretAfter: true)
    }
  }

  private func insertLineBreak(at location: Int, caretAfter: Bool) {
    let range = NSRange(location: location, length: 0)
    guard shouldChangeText(in: range, replacementString: "\n") else { return }
    textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: "\n", attributes: style.textAttributes))
    didChangeText()
    setSelectedRange(NSRange(location: caretAfter ? location + 1 : location, length: 0))
  }

  /// True if handled. Right after an image line: select it so the delete removes it whole.
  /// Right before one: only move to the end of the previous line, so the image line doesn't join it.
  func deleteBackwardAroundImageLine() -> Bool {
    let selection = selectedRange()
    guard let index = imageLines, multiCursor == nil, !hasMarkedText(), selection.length == 0, selection.location > 0 else {
      return false
    }
    if let entry = index.entry(endingAt: selection.location) {
      setSelectedRange(entry.range)
      return false
    }
    guard index.entry(startingAt: selection.location) != nil else { return false }
    let text = string as NSString
    let previous = text.paragraphRange(for: NSRange(location: selection.location - 1, length: 0))
    guard previous.length > 1 else { return false }
    setSelectedRange(NSRange(location: selection.location - 1, length: 0))
    return true
  }

  /// Mirror of `deleteBackwardAroundImageLine` for ⌦.
  func deleteForwardAroundImageLine() -> Bool {
    let selection = selectedRange()
    guard let index = imageLines, multiCursor == nil, !hasMarkedText(), selection.length == 0 else { return false }
    if let entry = index.entry(startingAt: selection.location) {
      setSelectedRange(entry.range)
      return false
    }
    let text = string as NSString
    guard selection.location < text.length, ManuscriptTextView.isLineBreak(text.character(at: selection.location)) else {
      return false
    }
    let next = selection.location + 1
    if index.entry(endingAt: selection.location) != nil {
      // After an image line: delete the newline only if the next line is blank, else just step over.
      guard next < text.length, !ManuscriptTextView.isLineBreak(text.character(at: next)) else { return false }
      setSelectedRange(NSRange(location: next, length: 0))
      return true
    }
    guard index.entry(startingAt: next) != nil, selection.location > 0,
      !ManuscriptTextView.isLineBreak(text.character(at: selection.location - 1))
    else { return false }
    setSelectedRange(NSRange(location: next, length: 0))
    return true
  }
}
