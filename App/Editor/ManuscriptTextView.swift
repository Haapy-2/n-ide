import AppKit
import NovelCore

/// NSTextView for manuscript editing. Uses TextKit 1 explicitly (SPEC ch.3).
/// Fixes the body width, centers it in wide windows, and adds bottom padding so the last line can be raised to mid-screen.
final class ManuscriptTextView: NSTextView {
  var style = EditorStyle() {
    didSet { if style != oldValue { applyStyle() } }
  }
  /// Caret width, height, color (Settings › Caret, `CaretSettings.swift`). Only drawing changes, so safe to change during composition.
  var caret = CaretStyle() {
    didSet {
      guard caret != oldValue else { return }
      insertionPointColor = caret.dynamicColor
      // Erase the caret drawn with the old width/height and redraw in the new shape immediately.
      if let last = lastCaretRect { eraseCaret(last) }
      lastCaretRect = nil
      updateInsertionPointStateAndRestartTimer(true)
    }
  }
  /// The style changed during composition and isn't applied to the whole body yet. Applied when composition ends.
  private var needsRestyle = false
  /// Whether the body was empty when the empty-episode hint was last drawn (`EmptyEpisodePlaceholder.swift`)
  var placeholderShown = true

  /// Line numbers in the left margin (`LineNumberGutter.swift`). Only drawing changes, body/selection untouched, so safe during composition.
  var showsLineNumbers = false {
    didSet {
      guard showsLineNumbers != oldValue else { return }
      lineCountCache = nil
      needsDisplay = true
    }
  }
  /// Whether blank lines get numbers too. Only drawing changes.
  var numbersBlankLines = true {
    didSet { if numbersBlankLines != oldValue, showsLineNumbers { needsDisplay = true } }
  }
  /// Total line count. Recounted when body text changes (`storageEditedForLineNumbers`).
  private var lineCountCache: Int?

  /// Last drawn caret rect. macOS may erase only a default-width (1 pt) rect, or not send an erase request on window deactivation,
  /// leaving a thick caret behind. The app erases this rect itself.
  private(set) var lastCaretRect: NSRect?

  var currentLineCount: Int {
    if let lineCountCache { return lineCountCache }
    let count = ParagraphLines.lineCount(in: textStorage?.mutableString ?? "")
    lineCountCache = count
    return count
  }

  private var isInsertingInput = false
  /// Undo record for the single character the IME is currently building.
  private var currentInput: InputUndoUnit?

  /// Same-word multi-cursor (⌘D, `MultiCursorEditing.swift`). nil = plain editor.
  var multiCursor: MultiCursorSession? {
    didSet { currentInput = nil }
  }
  /// Multi-cursor code is editing body/selection. Selection/body changes arriving now don't end multi-cursor.
  var isApplyingMultiCursor = false
  /// Word chosen by ⌘D from a bare caret. Decides whether the next ⌘D matches whole words.
  var wordFromCaret: NSRange?
  /// Whether the leading caret is currently drawn. Other carets are drawn to match (`MultiCursorEditing.swift`).
  var extraCaretsOn = false
  /// Settings › Editor "same-word multi-cursor". When off, ⌘D does nothing and active multi-cursor ends.
  /// Only dimming the menu would leave calls that bypass it (`sendSelectNextOccurrence`), so blocked here too.
  var multiCursorEnabled = true {
    didSet { if !multiCursorEnabled { endMultiCursor() } }
  }
  /// Right before switching from one cursor to multi-cursor. Body is still unchanged (for the pre-entry snapshot).
  var onEnterMultiCursor: () -> Void = {}
  /// A short message for the writer (toast).
  var onNotice: (String) -> Void = { _ in }
  /// Names of picture files just written into the project (`project.json` `images`).
  var onImagesAdded: ([ImageMeta]) -> Void = { _ in }
  /// Bumped when the whole body is swapped (episode switch), so a picture finishing afterwards doesn't land in another episode.
  private(set) var textGeneration = 0

  /// Per-episode undo history. Cleared on episode switch (PLAN.md detailed criteria).
  let episodeUndoManager = UndoManager()

  /// On every attach to a window or move to another. When SwiftUI attaches a view to a window isn't defined, so
  /// instead of "once, a little later", focus and window observation are set at this moment AppKit reports.
  var onMoveToWindow: (NSWindow) -> Void = { _ in }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let window { onMoveToWindow(window) }
  }

  static func make() -> ManuscriptTextView {
    // TextKit 1: wire NSTextStorage → NSLayoutManager → NSTextContainer directly.
    let storage = NSTextStorage()
    let layoutManager = ManuscriptLayoutManager()
    storage.addLayoutManager(layoutManager)
    let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = false
    layoutManager.addTextContainer(container)
    let view = ManuscriptTextView(frame: .zero, textContainer: container)
    view.configure()
    return view
  }

  private func configure() {
    isRichText = false
    importsGraphics = false
    allowsUndo = true
    isAutomaticQuoteSubstitutionEnabled = false
    isAutomaticDashSubstitutionEnabled = false
    isAutomaticTextReplacementEnabled = false
    isAutomaticSpellingCorrectionEnabled = false
    isContinuousSpellCheckingEnabled = false
    isGrammarCheckingEnabled = false
    isVerticallyResizable = true
    // No height limit. By default the first height becomes the limit, so right after switching to a longer episode
    // the program can't scroll into the not-yet-laid-out lower part (search-result jump).
    maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    isHorizontallyResizable = false
    autoresizingMask = [.width]
    drawsBackground = true
    backgroundColor = .paper
    insertionPointColor = caret.dynamicColor
    selectedTextAttributes = [.backgroundColor: NSColor.selectionToken]
    applyStyle()
    NotificationCenter.default.addObserver(
      self, selector: #selector(eraseCaretOnDeactivate(_:)), name: NSWindow.didResignKeyNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(eraseCaretOnDeactivate(_:)), name: NSApplication.didResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(storageEditedForLineNumbers(_:)),
      name: NSTextStorage.didProcessEditingNotification, object: textStorage)
  }

  // MARK: - Line number redraw

  /// When the line count changes (Return, deleting lines, paste, episode switch), redraw all visible numbers.
  /// Same count → nothing. Lines where only characters were typed get redrawn by `setNeedsDisplay` below, widened to the number column.
  /// Read only, so safe during composition.
  @objc private func storageEditedForLineNumbers(_ notification: Notification) {
    // Multi-cursor edits each spot separately, so this notification arrives once per cursor. Count once after all edits then.
    guard !isApplyingMultiCursor, let storage = textStorage, storage.editedMask.contains(.editedCharacters) else { return }
    recountLines()
  }

  func recountLines() {
    guard showsLineNumbers, let storage = textStorage else { return }
    let old = lineCountCache
    let count = ParagraphLines.lineCount(in: storage.mutableString)
    lineCountCache = count
    if old != count { setNeedsDisplay(visibleRect) }
  }

  override func drawBackground(in rect: NSRect) {
    super.drawBackground(in: rect)
    drawPlaceholder()
    if showsLineNumbers { drawLineNumbers(in: rect) }
    if multiCursor != nil { drawMultiCursorSelections(in: rect) }
  }

  // When turning the caret off the system doesn't call `drawInsertionPoint(turnedOn: false)`; it just redraws that rect.
  // So redrawing the leading caret rect counts as off. If it should be on, the system turns it back on right after this draw.
  override func draw(_ dirtyRect: NSRect) {
    if multiCursor != nil, let last = lastCaretRect, needsToDraw(last) { extraCaretsOn = false }
    super.draw(dirtyRect)
    if multiCursor != nil { drawMultiCursorCarets(in: dirtyRect) }
  }

  // Caret shape: `InsertionCaret.swift`. When off (blink), erase the whole original rect so no trail remains.
  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
    if flag {
      let caret = caretRect(in: rect)
      if let last = lastCaretRect, last != caret { eraseCaret(last) }
      lastCaretRect = caret
      super.drawInsertionPoint(in: caret, color: color, turnedOn: true)
      if multiCursor != nil { drawExtraCaretsWithFirst() }
    } else {
      if multiCursor != nil { turnOffExtraCarets() }
      super.drawInsertionPoint(in: widenedForCaret(rect), color: color, turnedOn: false)
      if let last = lastCaretRect { eraseCaret(last) }
      lastCaretRect = nil
    }
  }

  /// The caret must not be drawn when the window deactivates or the app goes to the background. Erase the remaining rect.
  @objc private func eraseCaretOnDeactivate(_ notification: Notification) {
    if let window = notification.object as? NSWindow, window !== self.window { return }
    if multiCursor != nil { turnOffExtraCarets() }
    guard let last = lastCaretRect else { return }
    eraseCaret(last)
    lastCaretRect = nil
  }

  private func eraseCaret(_ rect: NSRect) {
    // Widen by 1 pt on each side so rounding/antialiasing doesn't leave a half-pixel edge.
    setNeedsDisplay(rect.insetBy(dx: -1, dy: -1))
  }

  // On text edits NSTextView redraws only inside the text container. The number column is in the left margin, so when lines shift down
  // old numbers remain. Only with line numbers on, widen the dirty rect to the left edge (container unchanged, so the cost is a bit of margin).
  // Thin rects are widened by the caret width to prevent caret trails (`InsertionCaret.swift`).
  // Requests to redraw the leading caret rect also include the other carets' rects so blinking changes together in the same draw.
  override func setNeedsDisplay(_ invalidRect: NSRect) {
    let rect = widenedForCaret(invalidRect)
    super.setNeedsDisplay(showsLineNumbers ? widenedToGutter(rect) : rect)
    if multiCursor != nil, isCaretSized(invalidRect) { invalidateExtraCarets() }
  }

  override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
    let wide = widenedForCaret(rect)
    super.setNeedsDisplay(showsLineNumbers ? widenedToGutter(wide) : wide, avoidAdditionalLayout: flag)
    if multiCursor != nil, isCaretSized(rect) { invalidateExtraCarets() }
  }

  private func widenedToGutter(_ rect: NSRect) -> NSRect {
    guard !rect.isEmpty, rect.minX > 0 else { return rect }
    return NSRect(x: 0, y: rect.minY, width: rect.maxX, height: rect.height)
  }

  /// The open project, for image files. Image lines show as boxes until set.
  var project: ProjectLayout? {
    get { manuscriptLayout?.images.project }
    set { manuscriptLayout?.images.project = newValue }
  }

  private func applyStyle() {
    manuscriptLayout?.imagePadding = (style.lineHeight / 2).rounded()
    let attributes = style.textAttributes
    typingAttributes = attributes
    defaultParagraphStyle = style.paragraphStyle
    // No text storage changes during composition (Hangul input protection). Applied right after composition ends (`didChangeText`).
    if hasMarkedText() {
      needsRestyle = true
    } else if let storage = textStorage, storage.length > 0 {
      needsRestyle = false
      storage.beginEditing()
      storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
      storage.endEditing()
    }
    updateInsets()
  }

  /// Replace the whole body text (episode switch). Also clears undo history.
  func replaceAllText(with text: String) {
    // Commit composition and tell the IME it ended. With only unmarkText the IME still thinks it's composing,
    // and the next key could merge with the previous episode's jamo into the new body.
    finishComposition()
    forgetInputInProgress()
    dropMultiCursor()
    manuscriptLayout?.images.clear()
    textGeneration += 1
    textStorage?.setAttributedString(NSAttributedString(string: text, attributes: style.textAttributes))
    updatePlaceholderIfNeeded()
    setSelectedRange(NSRange(location: 0, length: 0))
    episodeUndoManager.removeAllActions()
    scroll(.zero)
  }

  /// Restore from snapshot: replace the whole body as one undo unit. Unlike episode switch, history isn't cleared, so one ⌘Z goes back.
  /// True if changed. The caret stays at the same offset (or the end if the body got shorter).
  func replaceAllUndoably(with text: String, actionName: String) -> Bool {
    finishComposition()
    endMultiCursor()
    let full = NSRange(location: 0, length: (string as NSString).length)
    guard string != text else { return false }
    let cursor = selectedRange().location
    let undo = episodeUndoManager
    undo.beginUndoGrouping()
    defer { undo.endUndoGrouping() }
    // shouldChangeText records undo, and didChangeText sends the change notification (autosave, count).
    guard shouldChangeText(in: full, replacementString: text) else { return false }
    forgetInputInProgress()
    textStorage?.replaceCharacters(in: full, with: NSAttributedString(string: text, attributes: style.textAttributes))
    didChangeText()
    undo.setActionName(actionName)
    setSelectedRange(NSRange(location: min(cursor, (text as NSString).length), length: 0))
    scrollRangeToVisible(selectedRange())
    return true
  }

  /// Edit only the target spots as one undo unit (replace all / revert). The body isn't swapped wholesale, so the caret stays on the same character
  /// and the top line on screen stays too (even if line counts change above). Spots in order, non-overlapping. True if edited.
  /// During composition, don't touch it and return false: to avoid breaking composition, the caller retries after it ends.
  func replaceOccurrences(_ changes: [TextChange], actionName: String) -> Bool {
    guard !changes.isEmpty, !hasMarkedText(), let textStorage else { return false }
    endMultiCursor()
    let selection = selectedRange()
    let top = topVisibleCharacter()
    let topOffset = visibleRect.minY - lineTop(of: top)
    let undo = episodeUndoManager
    undo.beginUndoGrouping()
    defer { undo.endUndoGrouping() }
    let values = changes.map { NSValue(range: $0.range) }
    guard shouldChangeText(inRanges: values, replacementStrings: changes.map(\.text)) else { return false }
    forgetInputInProgress()
    textStorage.beginEditing()
    for change in changes.reversed() {
      textStorage.replaceCharacters(
        in: change.range, with: NSAttributedString(string: change.text, attributes: style.textAttributes))
    }
    textStorage.endEditing()
    didChangeText()
    undo.setActionName(actionName)

    // Characters before an edited spot stay; those after shift by the length change. Inside an edited spot → end of the new text.
    func moved(_ location: Int) -> Int {
      var shift = 0
      for change in changes {
        let length = (change.text as NSString).length
        if change.range.upperBound <= location {
          shift += length - change.range.length
        } else if change.range.location < location {
          return change.range.location + shift + length
        } else {
          break
        }
      }
      return location + shift
    }
    let start = moved(selection.location)
    setSelectedRange(NSRange(location: start, length: max(0, moved(selection.upperBound) - start)))
    if let clip = enclosingScrollView?.contentView {
      clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: max(0, lineTop(of: moved(top)) + topOffset)))
      enclosingScrollView?.reflectScrolledClipView(clip)
    }
    return true
  }

  /// Before the app edits the body directly: make the IME let go of a character it was continuing "without displayed text".
  /// In that mode `hasMarkedText` is false even while composing, so after the edit the IME may rewrite the old spot via `replacementRange`,
  /// or the single-character record (`currentInput`) may grow to a misaligned range and ⌘Z may delete the wrong characters.
  func forgetInputInProgress() {
    guard currentInput != nil else { return }
    currentInput = nil
    inputContext?.discardMarkedText()
  }

  /// Top edge of the line holding the character (editor coordinates)
  private func lineTop(of index: Int) -> CGFloat {
    guard let layoutManager, layoutManager.numberOfGlyphs > 0 else { return 0 }
    let glyph = layoutManager.glyphIndexForCharacter(at: min(index, (string as NSString).length - 1))
    layoutManager.ensureLayout(forGlyphRange: NSRange(location: 0, length: glyph + 1))
    return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + textContainerOrigin.y
  }

  /// Swap in a body changed outside the app. Unlike episode switch, keep caret and scroll position where possible.
  /// Undo history is cleared: applying records based on the old body to the new body would change the wrong places.
  func reloadText(with text: String) {
    // Commit composition and tell the IME it ended. With only unmarkText the IME still thinks it's composing,
    // and the next key could merge with the previous episode's jamo into the new body.
    finishComposition()
    forgetInputInProgress()
    dropMultiCursor()
    let cursor = selectedRange().location
    let origin = enclosingScrollView?.contentView.bounds.origin ?? .zero
    manuscriptLayout?.revalidateImages()
    textStorage?.setAttributedString(NSAttributedString(string: text, attributes: style.textAttributes))
    setSelectedRange(NSRange(location: min(cursor, (text as NSString).length), length: 0))
    episodeUndoManager.removeAllActions()
    scroll(origin)
  }

  override var undoManager: UndoManager? { episodeUndoManager }

  // Edit menu undo (⌘Z) / redo (⇧⌘Z) look for a handler along the responder chain; if the editor doesn't take it, it reaches the window
  // and uses the window's history (sidebar episode actions). Typing goes into the episode history (`episodeUndoManager`), so handle it here directly.
  @objc func undo(_ sender: Any?) {
    finishComposition()
    episodeUndoManager.undo()
  }

  @objc func redo(_ sender: Any?) {
    finishComposition()
    episodeUndoManager.redo()
  }

  /// The 2-set IME (macOS 27) sometimes continues composing without displayed text via "replace the character before the caret with this" (`replacementRange`)
  /// (ㄱ → 가 → 각 → 가 + 가). Then `hasMarkedText` is always false, and NSTextView doesn't coalesce these replacements,
  /// so ⌘Z shows a mid-composition character ("각"). So each character the IME inserts is recorded as one unit directly, and while the IME
  /// edits that character only the same record's range grows. Undo is LIFO, so other changes in between are undone first and ranges line up.
  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.intersection([.command, .control]).isEmpty, let scalar = event.characters?.unicodeScalars.first,
      scalar.value >= 0x20, scalar.value != 0x7F, !(0xF700...0xF8FF).contains(scalar.value)
    {
      openLineBesideImageLine(for: String(scalar))
    }
    super.keyDown(with: event)
  }

  override func deleteBackward(_ sender: Any?) {
    if deleteBackwardAroundImageLine() { return }
    super.deleteBackward(sender)
  }

  override func deleteForward(_ sender: Any?) {
    if deleteForwardAroundImageLine() { return }
    super.deleteForward(sender)
  }

  override func deleteWordBackward(_ sender: Any?) {
    if wordDeleteMeetsImageLine(backward: true) { return deleteBackward(sender) }
    super.deleteWordBackward(sender)
  }

  override func deleteWordForward(_ sender: Any?) {
    if wordDeleteMeetsImageLine(backward: false) { return deleteForward(sender) }
    super.deleteWordForward(sender)
  }

  // Tab doesn't reach `insertText`, and `keyDown` skips control characters, so a tab beside an image line would hide inside it.
  override func insertTab(_ sender: Any?) {
    openLineBesideImageLine(for: "\t")
    super.insertTab(sender)
  }

  override func insertTabIgnoringFieldEditor(_ sender: Any?) {
    openLineBesideImageLine(for: "\t")
    super.insertTabIgnoringFieldEditor(sender)
  }

  override func insertText(_ string: Any, replacementRange: NSRange) {
    let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    if multiCursor != nil, multiCursorInsertText(text, replacementRange: replacementRange) { return }
    if replacementRange.location == NSNotFound { openLineBesideImageLine(for: text) }
    guard !hasMarkedText() else {
      super.insertText(string, replacementRange: replacementRange)
      return
    }
    if replacementRange.location == NSNotFound {
      let range = selectedRange()
      let original = (self.string as NSString).substring(with: range)
      breakUndoCoalescing()
      insertWithoutUndo(string, replacementRange: replacementRange)
      let unit = InputUndoUnit(range: NSRange(location: range.location, length: (text as NSString).length), original: original)
      currentInput = unit
      episodeUndoManager.registerUndo(withTarget: self) { view in
        MainActor.assumeIsolated { view.revert(unit) }
      }
    } else if let unit = currentInput, NSIntersectionRange(unit.range, replacementRange) == replacementRange {
      insertWithoutUndo(string, replacementRange: replacementRange)
      unit.range.length += (text as NSString).length - replacementRange.length
    } else {
      currentInput = nil
      breakUndoCoalescing()
      super.insertText(string, replacementRange: replacementRange)
    }
  }

  private func insertWithoutUndo(_ string: Any, replacementRange: NSRange) {
    isInsertingInput = true
    episodeUndoManager.disableUndoRegistration()
    defer {
      episodeUndoManager.enableUndoRegistration()
      isInsertingInput = false
    }
    super.insertText(string, replacementRange: replacementRange)
  }

  /// Undo of a single-character record (redo uses the same function). Records the inverse directly from the post-change range and pre-change text.
  /// The record NSTextView leaves itself in `shouldChangeText` is disabled: its range went wrong on redo and crashed the app.
  /// If the range is outside the body (a state that must not happen), change nothing.
  private func revert(_ unit: InputUndoUnit) {
    currentInput = nil
    let range = unit.range
    let text = string as NSString
    guard NSMaxRange(range) <= text.length else { return }
    let replaced = text.substring(with: range)
    episodeUndoManager.disableUndoRegistration()
    let changed = shouldChangeText(in: range, replacementString: unit.original)
    if changed {
      textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: unit.original, attributes: typingAttributes))
      didChangeText()
    }
    episodeUndoManager.enableUndoRegistration()
    guard changed else { return }
    let inverse = InputUndoUnit(range: NSRange(location: range.location, length: (unit.original as NSString).length), original: replaced)
    episodeUndoManager.registerUndo(withTarget: self) { view in
      MainActor.assumeIsolated { view.revert(inverse) }
    }
    setSelectedRange(NSRange(location: NSMaxRange(inverse.range), length: 0))
  }

  /// Make the undo unit one character. NSTextView coalesces consecutive typing into one group,
  /// so one ⌘Z would delete a whole sentence; break the group on every edit. Not during composition, so a finished character ("한") is one unit.
  override func didChangeText() {
    super.didChangeText()
    updatePlaceholderIfNeeded()
    guard !hasMarkedText() else { return }
    if !isInsertingInput {
      currentInput = nil
      breakUndoCoalescing()
    }
    if needsRestyle { applyStyle() }
  }

  /// Commit the composing character. Undoing mid-composition could make the IME and text storage point at different characters and break.
  /// With multi-cursor, commit composition at every spot (`unmarkText`).
  func finishComposition() {
    guard hasMarkedText() else { return }
    unmarkText()
    inputContext?.discardMarkedText()
  }

  // MARK: - IME contract during multi-cursor (`MultiCursorEditing.swift`)

  override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    if multiCursor != nil, multiCursorSetMarkedText(text, selectedRange: selectedRange, replacementRange: replacementRange) {
      return
    }
    super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
  }

  override func unmarkText() {
    guard multiCursor == nil else { return multiCursorUnmark() }
    super.unmarkText()
  }

  // Multi-cursor composition ranges live here, not in `NSTextView`'s internal state. Autosave, styling etc. check this for composition.
  // While we move the selection, answer that there's no composition: otherwise `NSTextView` breaks composition when moving the selection.
  override func hasMarkedText() -> Bool {
    guard let session = multiCursor else { return super.hasMarkedText() }
    return !isApplyingMultiCursor && session.marked != nil
  }

  override func markedRange() -> NSRange {
    guard let session = multiCursor else { return super.markedRange() }
    return session.marked?.first ?? NSRange(location: NSNotFound, length: 0)
  }

  override func doCommand(by selector: Selector) {
    if multiCursor != nil, multiCursorDoCommand(selector) { return }
    super.doCommand(by: selector)
  }

  override func copy(_ sender: Any?) {
    guard multiCursor == nil else { return multiCursorCopy(to: .general) }
    super.copy(sender)
  }

  override func cut(_ sender: Any?) {
    guard multiCursor == nil else { return multiCursorCut(to: .general) }
    super.cut(sender)
  }

  override func paste(_ sender: Any?) {
    guard multiCursor == nil else { return multiCursorPaste(from: .general) }
    if project != nil, let sources = ImageImporter.sources(on: .general) { return insertImages(sources) }
    openLineBesideImageLine(for: NSPasteboard.general.string(forType: .string) ?? "")
    super.paste(sender)
  }

  override func pasteAsPlainText(_ sender: Any?) {
    guard multiCursor == nil else { return multiCursorPaste(from: .general) }
    openLineBesideImageLine(for: NSPasteboard.general.string(forType: .string) ?? "")
    super.pasteAsPlainText(sender)
  }

  // If a path other than multi-cursor code (click, select all, paste, another undo record) changes selection or body, other spots go stale.
  // Drop multi-cursor before that path makes its change (PLAN ch.16 D3). That path decides body and selection.
  override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
    var ranges = ranges
    if !isApplyingMultiCursor {
      dropMultiCursor()
      wordFromCaret = nil
      if ranges.count == 1, !hasMarkedText() {
        ranges = [NSValue(range: selectionKeepingImageLinesWhole(ranges[0].rangeValue, from: selectedRange()))]
      }
    }
    super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
  }

  override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
    if !isApplyingMultiCursor { dropMultiCursor() }
    guard editKeepsImageLinesWhole(affectedRanges.map(\.rangeValue)) else { return false }
    return super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
  }

  override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
    if !isApplyingMultiCursor { dropMultiCursor() }
    guard editKeepsImageLinesWhole([affectedCharRange]) else { return false }
    return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
  }

  // MARK: - Pictures (`ImageInsertion.swift`)

  override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
    super.acceptableDragTypes + ImageImporter.pictureTypes
  }

  // A plain-text view refuses picture data outright (it never asks `dragOperation(for:type:)` about types it can't read),
  // so the drag would be refused before it reaches the drop.
  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    acceptingImages(sender, super.draggingEntered(sender))
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    acceptingImages(sender, super.draggingUpdated(sender))
  }

  private func acceptingImages(_ sender: any NSDraggingInfo, _ operation: NSDragOperation) -> NSDragOperation {
    guard operation.isEmpty, project != nil, ImageImporter.sources(on: sender.draggingPasteboard) != nil else { return operation }
    return .copy
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    dropImages(sender) || super.performDragOperation(sender)
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = super.menu(for: event) ?? NSMenu()
    let items = brokenImageMenuItems(at: convert(event.locationInWindow, from: nil))
    guard !items.isEmpty else { return menu }
    menu.insertItem(.separator(), at: 0)
    for item in items.reversed() { menu.insertItem(item, at: 0) }
    return menu
  }

  /// Before opening the floating panel (⇧⌘S): end composition and release keyboard focus. Caret and selection stay.
  /// Returns whether the editor had focus when the panel opened (to decide whether to give it back on close).
  func yieldFocusForPanel() -> Bool {
    finishComposition()
    guard let window, window.firstResponder === self else { return false }
    window.makeFirstResponder(nil)
    return true
  }

  /// Go to a search result: select the match, scroll it to the middle, and take focus.
  /// If the text changed after searching and the phrase is gone from that spot, go to the nearest same phrase. If none at all, don't move.
  func reveal(_ target: TextReveal) {
    finishComposition()
    endMultiCursor()
    let text = string as NSString
    var range = NSRange(location: target.location, length: target.length)
    let options: NSString.CompareOptions = target.caseSensitive ? [] : [.caseInsensitive]
    let stillThere = NSMaxRange(range) <= text.length
      && text.substring(with: range).compare(target.query, options: options) == .orderedSame
    if !stillThere {
      let nearest = TextSearch.matches(of: target.query, in: string, caseSensitive: target.caseSensitive)
        .min { abs($0.location - target.location) < abs($1.location - target.location) }
      guard let nearest else { return }
      range = NSRange(location: nearest.location, length: nearest.length)
    }
    setSelectedRange(range)
    window?.makeFirstResponder(self)
    scrollRangeToVisible(range)
    // Right after an episode switch the body height isn't fully known. Center and show the yellow highlight one turn later.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.selectedRange() == range else { return }
      self.centerVertically(on: range)
      self.showFindIndicator(for: range)
    }
  }

  private func centerVertically(on range: NSRange) {
    guard let layoutManager, let textContainer, let clip = enclosingScrollView?.contentView else {
      scrollRangeToVisible(range)
      return
    }
    // Right after an episode switch, layout covers only the beginning, so the body height is smaller than real and scrolling stops there.
    // Completing layout up to the match grows the editor height too.
    layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: NSMaxRange(range)))
    sizeToFit()
    let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
    let midY = rect.midY + textContainerOrigin.y
    let maxY = max(0, frame.height - clip.bounds.height)
    clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: min(max(0, midY - clip.bounds.height / 2), maxY)))
    enclosingScrollView?.reflectScrolledClipView(clip)
  }

  /// After the panel closes: return focus to where the caret was.
  func regainFocusAfterPanel() {
    window?.makeFirstResponder(self)
  }

  override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(undo(_:)):
      (item as? NSMenuItem)?.title = episodeUndoManager.undoMenuItemTitle
      return episodeUndoManager.canUndo
    case #selector(redo(_:)):
      (item as? NSMenuItem)?.title = episodeUndoManager.redoMenuItemTitle
      return episodeUndoManager.canRedo
    case #selector(paste(_:)) where project != nil && ImageImporter.sources(on: .general) != nil:
      return true
    case #selector(insertImageFromPanel(_:)):
      return project != nil
    default:
      return super.validateUserInterfaceItem(item)
    }
  }

  // MARK: - Episode position

  /// Current caret and the first character of the top line on screen.
  func viewState() -> EpisodeViewState {
    EpisodeViewState(caret: selectedRange().location, top: topVisibleCharacter(), openedAt: Date())
  }

  /// Move caret and scroll to the remembered position. Clamp to the end if the body got shorter meanwhile.
  func restoreViewState(_ state: EpisodeViewState) {
    let length = (string as NSString).length
    setSelectedRange(NSRange(location: min(max(state.caret, 0), length), length: 0))
    scrollToCharacter(min(max(state.top, 0), length))
  }

  private func topVisibleCharacter() -> Int {
    guard let layoutManager, let textContainer, layoutManager.numberOfGlyphs > 0 else { return 0 }
    let point = NSPoint(x: 0, y: max(visibleRect.minY - textContainerOrigin.y, 0) + 1)
    let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
    return layoutManager.characterIndexForGlyph(at: glyph)
  }

  /// Put the line containing that character at the top of the screen. Layout must be complete up to it to know line positions
  /// (right after an episode switch it isn't yet).
  private func scrollToCharacter(_ index: Int) {
    guard let layoutManager, let clip = enclosingScrollView?.contentView, index > 0 else {
      scroll(.zero)
      return
    }
    let glyph = layoutManager.glyphIndexForCharacter(at: min(index, (string as NSString).length - 1))
    layoutManager.ensureLayout(forGlyphRange: NSRange(location: 0, length: glyph + 1))
    let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: max(0, line.minY + textContainerOrigin.y)))
    enclosingScrollView?.reflectScrolledClipView(clip)
  }

  // MARK: - Width and margins

  /// NSTextView doesn't treat points right of the text container's right edge as its own, so right-margin clicks go to the clip view behind
  /// and the caret doesn't move. With a fixed body width the right margin is wide, so take clicks inside the editor directly.
  override func hitTest(_ point: NSPoint) -> NSView? {
    if let hit = super.hitTest(point) { return hit }
    guard !isHidden else { return nil }
    return frame.contains(point) ? self : nil
  }

  /// After a resize the system pulls the caret to the screen center (`_centeredScrollRectToVisible`). The sidebar collapse/expand
  /// animation counts as a resize too, so with the caret at the end the body shifted and the first paragraph went off the top. Keep the viewed position.
  /// The body width is fixed, so lines usually don't rewrap. The system brings the caret back into view on the next keystroke.
  override func viewDidEndLiveResize() {
    guard let scrollView = enclosingScrollView else { return super.viewDidEndLiveResize() }
    let clip = scrollView.contentView
    let before = clip.bounds.origin
    super.viewDidEndLiveResize()
    guard clip.bounds.origin != before else { return }
    var bounds = clip.bounds
    bounds.origin = before
    clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
    scrollView.reflectScrolledClipView(clip)
  }

  override func setFrameSize(_ newSize: NSSize) {
    var size = newSize
    // Leave half the visible height as bottom slack so the last line can be pulled up to mid-screen.
    if let visible = enclosingScrollView?.contentView.bounds.height {
      size.height = max(size.height, usedTextHeight + Self.topAndBottom(visible: visible))
    }
    super.setFrameSize(size)
    updateInsets()
  }

  private var usedTextHeight: CGFloat {
    guard let layoutManager, let textContainer else { return 0 }
    return layoutManager.usedRect(for: textContainer).height
  }

  private static func topAndBottom(visible: CGFloat) -> CGFloat {
    EditorStyle.topInset + visible / 2
  }

  /// Body width is fixed regardless of window width; leftover width is split into left/right margins.
  private func updateInsets() {
    let available = bounds.width
    let width = min(style.textWidth, max(available - EditorStyle.minimumSideInset * 2, 100))
    let side = max((available - width) / 2, 0)
    if textContainer?.size.width != width {
      textContainer?.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    }
    let inset = NSSize(width: side, height: EditorStyle.topInset)
    if textContainerInset != inset { textContainerInset = inset }
  }
}

/// Undo record for one character (syllable) the IME inserted. A reference type because its range changes while the IME edits it.
private final class InputUndoUnit {
  var range: NSRange
  let original: String

  init(range: NSRange, original: String) {
    self.range = range
    self.original = original
  }
}
