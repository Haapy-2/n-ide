import AppKit
import NovelCore

/// Editor-side state of same-word multi-cursor (⌘D, PLAN ch.16). Computation is NovelCore `MultiCursor`.
final class MultiCursorSession {
  var cursor: MultiCursor
  /// Per-spot composing range during displayed-text composition (ch.16 #5 ⓑ). In order; the first is the spot tied to the IME.
  var marked: [NSRange]?
  /// Undo record of the character being built. While the IME edits it, only that record's range grows.
  var input: MultiInputUnit?
  /// Per-spot horizontal position kept during consecutive up/down moves (so it returns after passing short lines). Forgotten on any other command.
  var goalX: [CGFloat]?

  init(cursor: MultiCursor) {
    self.cursor = cursor
  }
}

/// Undo record of one simultaneous edit across spots. `ranges` are where edited text sits in the current body, `originals` the pre-edit text.
final class MultiInputUnit {
  var ranges: [NSRange]
  let originals: [String]
  /// Carets to place after undo (ch.16 U2)
  let cursorsBefore: [NSRange]

  init(ranges: [NSRange], originals: [String], cursorsBefore: [NSRange]) {
    self.ranges = ranges
    self.originals = originals
    self.cursorsBefore = cursorsBefore
  }

  /// Whether the IME edits only this record's characters (each spot's edit range inside the record range).
  func covers(_ targets: [NSRange]) -> Bool {
    guard targets.count == ranges.count else { return false }
    return zip(ranges, targets).allSatisfy { unit, target in
      target.location >= unit.location && NSMaxRange(target) <= NSMaxRange(unit)
    }
  }
}

/// With multi-cursor, `ManuscriptTextView` handles the IME contract (`NSTextInputClient`) directly. With one cursor this file's code doesn't run.
/// The body is really edited at every spot (back to front, one path: `shouldChangeText` → edit → `didChangeText`),
/// and `NSTextView`'s selection is always the leading spot (the caret tied to the IME, ch.16 #5). Other spots are drawn directly.
/// In this state text storage is edited even during composition (CLAUDE.md exception): composition ranges are held here, not in `NSTextView`,
/// so there's no internal state to drift. When the math doesn't hold (stale ranges, IME pointing outside the leading caret), don't edit; end multi-cursor.
extension ManuscriptTextView {

  var multiCursorRanges: [NSRange]? { multiCursor?.cursor.ranges }

  // MARK: - ⌘D

  /// Send Edit menu commands to the editor with keyboard focus (nothing happens if focus is on the sidebar or a search field).
  static func sendSelectNextOccurrence() {
    NSApp.sendAction(#selector(selectNextOccurrence(_:)), to: nil, from: nil)
  }

  /// With a bare caret, select the word under it; with a selection, add the next occurrence (VS Code ⌘D).
  @objc func selectNextOccurrence(_ sender: Any?) {
    guard multiCursorEnabled else { return }
    finishComposition()
    if let session = multiCursor {
      guard session.cursor.ranges.allSatisfy({ $0.length > 0 }) else { return }
      var cursor = session.cursor
      let addition = cursor.addNext(in: string)
      handle(addition, cursor: cursor, session: session)
      return
    }
    let selection = selectedRange()
    if selection.length == 0 {
      let word = selectionRange(forProposedRange: selection, granularity: .selectByWord)
      let text = (string as NSString).substring(with: word)
      guard word.length > 0, text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil else { return }
      setSelectedRange(word)
      wordFromCaret = word
      return
    }
    guard var cursor = MultiCursor(selection: selection, wholeWord: wordFromCaret == selection) else { return }
    let addition = cursor.addNext(in: string)
    handle(addition, cursor: cursor, session: nil)
  }

  private func handle(_ addition: MultiCursor.Addition, cursor: MultiCursor, session: MultiCursorSession?) {
    switch addition {
    case .added(let found):
      if let session {
        session.cursor = cursor
      } else {
        onEnterMultiCursor()
        multiCursor = MultiCursorSession(cursor: cursor)
      }
      selectPrimary()
      scrollRangeToVisible(found)
      needsDisplay = true
    case .noMore, .notSearchable:
      break
    case .limitReached:
      onNotice("커서는 \(MultiCursor.limit.formatted())개까지 만들 수 있어요")
    }
  }

  /// End multi-cursor, keeping the leading spot only (Esc). Commit composition first if composing.
  func endMultiCursor() {
    guard let session = multiCursor else { return }
    finishComposition()
    let primary = session.cursor.ranges[0]
    dropMultiCursor()
    if NSMaxRange(primary) <= (string as NSString).length { setSelectedRange(primary) }
  }

  /// Drop the state only. Body and selection are untouched (another path is in the middle of changing them).
  func dropMultiCursor() {
    guard let session = multiCursor else { return }
    if session.marked != nil {
      session.marked = nil
      clearMarkedUnderline()
      inputContext?.discardMarkedText()
    }
    multiCursor = nil
    wordFromCaret = nil
    needsDisplay = true
  }

  func selectPrimary() {
    guard let primary = multiCursor?.cursor.ranges.first else { return }
    isApplyingMultiCursor = true
    defer { isApplyingMultiCursor = false }
    setSelectedRange(primary)
  }

  // MARK: - IME

  /// Displayed-text mode. True if handled; otherwise multi-cursor was ended and the caller falls back to normal input.
  func multiCursorSetMarkedText(_ text: String, selectedRange: NSRange, replacementRange: NSRange) -> Bool {
    guard let session = multiCursor else { return false }
    let anchors = session.marked ?? session.cursor.ranges
    let extending = session.marked != nil || replacementRange.location != NSNotFound
    guard let targets = targets(for: replacementRange, around: anchors),
      let inserted = applyMultiCursor(targets, texts: targets.map { _ in text }, extendingInput: extending)
    else {
      dropMultiCursor()
      return false
    }
    let length = (text as NSString).length
    let caret = min(max(selectedRange.location, 0), length)
    let selected = min(selectedRange.length, length - caret)
    session.marked = length > 0 ? inserted : nil
    session.cursor.place(inserted.map { NSRange(location: $0.location + caret, length: selected) })
    selectPrimary()
    updateMarkedUnderline()
    return true
  }

  /// Committed text (end of displayed-text mode) or one character in no-display mode. True if handled.
  func multiCursorInsertText(_ text: String, replacementRange: NSRange) -> Bool {
    guard let session = multiCursor else { return false }
    let anchors = session.marked ?? session.cursor.ranges
    let extending = session.marked != nil || replacementRange.location != NSNotFound
    guard let targets = targets(for: replacementRange, around: anchors),
      let inserted = applyMultiCursor(targets, texts: targets.map { _ in text }, extendingInput: extending)
    else {
      dropMultiCursor()
      return false
    }
    session.marked = nil
    clearMarkedUnderline()
    session.cursor.place(inserted.map { NSRange(location: NSMaxRange($0), length: 0) })
    selectPrimary()
    return true
  }

  /// The IME ended composition (input source switch etc., ch.16 I5). Commit the current text at every spot.
  func multiCursorUnmark() {
    guard let session = multiCursor, session.marked != nil else { return }
    session.marked = nil
    clearMarkedUnderline()
  }

  private func targets(for replacementRange: NSRange, around anchors: [NSRange]) -> [NSRange]? {
    guard replacementRange.location != NSNotFound else { return anchors }
    return MultiCursor.targets(forReplacement: replacementRange, around: anchors, textLength: (string as NSString).length)
  }

  /// Key commands (arrows, delete, Return, Tab, Esc). True if handled. Commands not yet supported in multi-cursor end it and return false.
  func multiCursorDoCommand(_ selector: Selector) -> Bool {
    guard let session = multiCursor else { return false }
    if let (motion, extending) = Self.multiCursorMoves[selector] {
      moveMultiCursor(motion, extending: extending)
      return true
    }
    if Self.multiCursorScrolls.contains(selector) { return false }
    session.goalX = nil
    if let motion = Self.multiCursorDeletions[selector] {
      deleteAtMultiCursor(motion)
      return true
    }
    switch selector {
    case #selector(insertNewline(_:)), #selector(insertParagraphSeparator(_:)):
      return multiCursorInsertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
    case #selector(insertTab(_:)):
      return multiCursorInsertText("\t", replacementRange: NSRange(location: NSNotFound, length: 0))
    case #selector(cancelOperation(_:)):
      endMultiCursor()
      return true
    default:
      endMultiCursor()
      return false
    }
  }

  /// Delete keys: each spot's selection if any, otherwise `motion` from the caret. All spots are one ⌘Z unit.
  private func deleteAtMultiCursor(_ motion: CursorMotion) {
    guard let session = multiCursor else { return }
    let ranges = session.cursor.ranges
    let stops = ranges.map { $0.length > 0 ? $0.location : deletionStop(motion, from: $0.location) }
    let targets = MultiCursor.deleteTargets(ranges, to: stops)
    guard targets.contains(where: { $0.length > 0 }),
      let inserted = applyMultiCursor(targets, texts: targets.map { _ in "" }, extendingInput: false)
    else { return }
    session.cursor.place(inserted)
    if session.cursor.ranges.count < 2 {
      endMultiCursor()
    } else {
      selectPrimary()
    }
  }

  // MARK: - Copy and paste (ch.16 E7)

  /// ⌘C: copy the selections joined by newlines (VS Code). If all are empty, do nothing (same as with one cursor).
  func multiCursorCopy(to pasteboard: NSPasteboard) {
    guard let session = multiCursor,
      let text = MultiCursor.copiedText(session.cursor.ranges, in: string as NSString)
    else { return }
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  /// ⌘X: copy, then delete the selections at every spot (one ⌘Z unit).
  func multiCursorCut(to pasteboard: NSPasteboard) {
    guard let session = multiCursor, session.cursor.ranges.contains(where: { $0.length > 0 }) else { return }
    finishComposition()
    multiCursorCopy(to: pasteboard)
    let ranges = session.cursor.ranges
    let targets = MultiCursor.deleteTargets(ranges, to: ranges.map(\.location))
    guard let inserted = applyMultiCursor(targets, texts: targets.map { _ in "" }, extendingInput: false) else { return }
    session.cursor.place(inserted)
    selectPrimary()
  }

  /// ⌘V: one line per cursor if the line count equals the cursor count, otherwise the same text at every spot (one ⌘Z unit). Non-text (images) isn't pasted.
  func multiCursorPaste(from pasteboard: NSPasteboard) {
    guard let session = multiCursor, let text = pasteboard.string(forType: .string) else { return }
    finishComposition()
    let ranges = session.cursor.ranges
    let texts = MultiCursor.pasteTexts(text, count: ranges.count)
    guard let inserted = applyMultiCursor(ranges, texts: texts, extendingInput: false) else { return }
    session.cursor.place(inserted.map { NSRange(location: NSMaxRange($0), length: 0) })
    selectPrimary()
    scrollRangeToVisible(session.cursor.ranges[0])
  }

  // MARK: - Editing and undo

  /// Edit all spots at once. Finishes on the main thread without waiting (ch.16 D6). Returns each spot's new-text range if edited.
  /// If ranges are stale (ch.16 D1), edit nothing and return nil.
  private func applyMultiCursor(_ targets: [NSRange], texts: [String], extendingInput: Bool) -> [NSRange]? {
    guard let session = multiCursor, let storage = textStorage,
      let edit = MultiCursor.edit(targets, texts: texts, textLength: storage.length)
    else { return nil }
    let text = string as NSString
    let originals = targets.map { text.substring(with: $0) }
    let cursorsBefore = session.cursor.ranges
    session.goalX = nil
    isApplyingMultiCursor = true
    defer { isApplyingMultiCursor = false }
    let undo = episodeUndoManager
    undo.disableUndoRegistration()
    guard shouldChangeText(inRanges: targets.map { NSValue(range: $0) }, replacementStrings: texts) else {
      undo.enableUndoRegistration()
      return nil
    }
    replaceEach(edit.changes, in: storage)
    recountLines()
    didChangeText()
    undo.enableUndoRegistration()

    if extendingInput, let unit = session.input, unit.covers(targets) {
      var shift = 0
      for index in unit.ranges.indices {
        let delta = edit.inserted[index].length - targets[index].length
        unit.ranges[index] = NSRange(
          location: unit.ranges[index].location + shift, length: unit.ranges[index].length + delta)
        shift += delta
      }
    } else {
      let unit = MultiInputUnit(ranges: edit.inserted, originals: originals, cursorsBefore: cursorsBefore)
      session.input = unit
      registerMultiUndo(unit)
    }
    needsDisplay = true
    return edit.inserted
  }

  /// Edit spot by spot from the back. Not wrapped in `beginEditing`: that would register first-to-last spot as one change
  /// and reprocess all of it (69 ms for 100k chars with just 2 cursors at start and end). Per spot, only edited parts (100 cursors 3.2 ms, measured).
  private func replaceEach(_ changes: [TextChange], in storage: NSTextStorage) {
    for change in changes.reversed() {
      storage.replaceCharacters(in: change.range, with: NSAttributedString(string: change.text, attributes: style.textAttributes))
    }
  }

  private func registerMultiUndo(_ unit: MultiInputUnit) {
    episodeUndoManager.registerUndo(withTarget: self) { view in
      MainActor.assumeIsolated { view.revertMultiInput(unit) }
    }
  }

  /// Undo of one simultaneous edit (redo uses the same function). If a spot is outside the body (must not happen), change nothing.
  /// After undo, multi-cursor resumes with the carets of that time.
  private func revertMultiInput(_ unit: MultiInputUnit) {
    finishComposition()
    dropMultiCursor()
    let (ranges, originals) = MultiCursor.joinedAtMeetingPoints(unit.ranges, texts: unit.originals)
    guard let storage = textStorage,
      let edit = MultiCursor.edit(ranges, texts: originals, textLength: storage.length)
    else { return }
    let text = string as NSString
    let replaced = ranges.map { text.substring(with: $0) }
    let undo = episodeUndoManager
    undo.disableUndoRegistration()
    let changed = shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: originals)
    if changed {
      replaceEach(edit.changes, in: storage)
      didChangeText()
    }
    undo.enableUndoRegistration()
    guard changed else { return }
    let inverse = MultiInputUnit(
      ranges: edit.inserted, originals: replaced,
      cursorsBefore: unit.ranges.map { NSRange(location: NSMaxRange($0), length: 0) })
    registerMultiUndo(inverse)
    if let cursor = MultiCursor(ranges: unit.cursorsBefore, wholeWord: false),
      cursor.ranges.allSatisfy({ NSMaxRange($0) <= storage.length }) {
      multiCursor = MultiCursorSession(cursor: cursor)
      selectPrimary()
    } else if let first = unit.cursorsBefore.first, NSMaxRange(first) <= storage.length {
      setSelectedRange(first)
    }
    needsDisplay = true
  }

  // MARK: - Drawing

  /// Selection background of non-leading spots. Drawn under the glyphs.
  func drawMultiCursorSelections(in rect: NSRect) {
    guard let ranges = multiCursor?.cursor.ranges.dropFirst(), let layoutManager, let textContainer else { return }
    NSColor.selectionToken.setFill()
    let origin = textContainerOrigin
    for range in ranges where range.length > 0 && NSMaxRange(range) <= (string as NSString).length {
      let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      layoutManager.enumerateEnclosingRects(
        forGlyphRange: glyphs, withinSelectedGlyphRange: glyphs, in: textContainer
      ) { box, _ in
        let shifted = box.offsetBy(dx: origin.x, dy: origin.y)
        if shifted.intersects(rect) { shifted.fill() }
      }
    }
  }

  /// Carets of non-leading spots. Only while the leading caret is drawn (`extraCaretsOn`).
  func drawMultiCursorCarets(in rect: NSRect) {
    guard extraCaretsOn, let ranges = multiCursor?.cursor.ranges.dropFirst() else { return }
    insertionPointColor.setFill()
    for range in ranges where range.length == 0 {
      guard let caret = extraCaretRect(at: range.location), caret.intersects(rect) else { continue }
      caret.fill()
    }
  }

  /// Other carets are drawn inside the system's draw that turns the leading caret on. Their rects were added to this draw
  /// via `invalidateExtraCarets`, so they turn on at the same moment without waiting for the next refresh.
  func drawExtraCaretsWithFirst() {
    extraCaretsOn = true
    drawMultiCursorCarets(in: visibleRect)
  }

  /// When the system turns the caret off directly, e.g. on window deactivation.
  func turnOffExtraCarets() {
    guard extraCaretsOn else { return }
    extraCaretsOn = false
    invalidateExtraCarets()
  }

  func invalidateExtraCarets() {
    guard let ranges = multiCursor?.cursor.ranges.dropFirst() else { return }
    for range in ranges where range.length == 0 {
      if let caret = extraCaretRect(at: range.location) { setNeedsDisplay(caret.insetBy(dx: -1, dy: -1)) }
    }
  }

  func extraCaretRect(at index: Int) -> NSRect? {
    guard let line = caretLine(at: index) else { return nil }
    return caretRect(in: line.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y))
  }

  /// Line rect of a caret placed before `index` (text container coords, 1 pt wide, x is the caret position). At a wrap point, the next line's start.
  func caretLine(at index: Int) -> NSRect? {
    guard let layoutManager, let textContainer else { return nil }
    let length = (string as NSString).length
    guard index <= length else { return nil }
    if index == length { layoutManager.ensureLayout(for: textContainer) }
    if length == 0 || (index == length && layoutManager.extraLineFragmentTextContainer != nil) {
      var line = layoutManager.extraLineFragmentRect
      line.origin.x += textContainer.lineFragmentPadding
      line.size.width = 1
      return line
    }
    // The glyph box (`boundingRect`) is where the glyph's shape is drawn, which differs from the caret position (about 12 pt in Pretendard).
    // The caret position is where the glyph is placed (`location`); at text end, the empty-range selection rect.
    let glyph = layoutManager.glyphIndexForCharacter(at: index)
    var line = layoutManager.lineFragmentRect(forGlyphAt: min(glyph, layoutManager.numberOfGlyphs - 1), effectiveRange: nil)
    if glyph < layoutManager.numberOfGlyphs {
      line.origin.x += layoutManager.location(forGlyphAt: glyph).x
    } else {
      let empty = NSRange(location: glyph, length: 0)
      layoutManager.enumerateEnclosingRects(forGlyphRange: empty, withinSelectedGlyphRange: empty, in: textContainer) { rect, stop in
        line.origin.x = rect.minX
        stop.pointee = true
      }
    }
    line.size.width = 1
    return line
  }

  private func updateMarkedUnderline() {
    clearMarkedUnderline()
    guard let marked = multiCursor?.marked, let layoutManager else { return }
    for range in marked where range.length > 0 {
      layoutManager.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: range)
    }
  }

  private func clearMarkedUnderline() {
    guard let layoutManager else { return }
    layoutManager.removeTemporaryAttribute(
      .underlineStyle, forCharacterRange: NSRange(location: 0, length: (string as NSString).length))
  }
}
