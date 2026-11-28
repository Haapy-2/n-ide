import AppKit
import NovelCore

/// Arrow and delete keys with multi-cursor (PLAN ch.16 E5). Targets are computed per caret directly from text and layout:
/// calling editor movement commands per spot takes ~90 ms per key for 1,000 carets, over the 16 ms target (measured).
/// App tests compare the result against the single-cursor editor at every spot.
enum CursorMotion {
  case characterBackward, characterForward
  case wordBackward, wordForward
  case lineStart, lineEnd
  case paragraphStart, paragraphEnd
  /// ⇧⌥↑↓: paragraph start/end; if already there, the previous/next paragraph's start/end
  case paragraphBackward, paragraphForward
  case documentStart, documentEnd
  case lineUp, lineDown

  /// Moving without ⇧ while there's a selection starts backward commands at the selection start and forward ones at its end (same as the editor).
  var isBackward: Bool {
    switch self {
    case .characterBackward, .wordBackward, .lineStart, .paragraphStart, .paragraphBackward, .documentStart, .lineUp: true
    default: false
    }
  }

  var isVertical: Bool { self == .lineUp || self == .lineDown }
}

extension ManuscriptTextView {

  /// Key command → (motion, extend with ⇧)
  static let multiCursorMoves: [Selector: (CursorMotion, Bool)] = [
    #selector(moveLeft(_:)): (.characterBackward, false),
    #selector(moveBackward(_:)): (.characterBackward, false),
    #selector(moveRight(_:)): (.characterForward, false),
    #selector(moveForward(_:)): (.characterForward, false),
    #selector(moveWordLeft(_:)): (.wordBackward, false),
    #selector(moveWordBackward(_:)): (.wordBackward, false),
    #selector(moveWordRight(_:)): (.wordForward, false),
    #selector(moveWordForward(_:)): (.wordForward, false),
    #selector(moveToLeftEndOfLine(_:)): (.lineStart, false),
    #selector(moveToBeginningOfLine(_:)): (.lineStart, false),
    #selector(moveToRightEndOfLine(_:)): (.lineEnd, false),
    #selector(moveToEndOfLine(_:)): (.lineEnd, false),
    #selector(moveToBeginningOfParagraph(_:)): (.paragraphStart, false),
    #selector(moveToEndOfParagraph(_:)): (.paragraphEnd, false),
    #selector(moveToBeginningOfDocument(_:)): (.documentStart, false),
    #selector(moveToEndOfDocument(_:)): (.documentEnd, false),
    #selector(moveUp(_:)): (.lineUp, false),
    #selector(moveDown(_:)): (.lineDown, false),
    #selector(moveLeftAndModifySelection(_:)): (.characterBackward, true),
    #selector(moveBackwardAndModifySelection(_:)): (.characterBackward, true),
    #selector(moveRightAndModifySelection(_:)): (.characterForward, true),
    #selector(moveForwardAndModifySelection(_:)): (.characterForward, true),
    #selector(moveWordLeftAndModifySelection(_:)): (.wordBackward, true),
    #selector(moveWordBackwardAndModifySelection(_:)): (.wordBackward, true),
    #selector(moveWordRightAndModifySelection(_:)): (.wordForward, true),
    #selector(moveWordForwardAndModifySelection(_:)): (.wordForward, true),
    #selector(moveToLeftEndOfLineAndModifySelection(_:)): (.lineStart, true),
    #selector(moveToBeginningOfLineAndModifySelection(_:)): (.lineStart, true),
    #selector(moveToRightEndOfLineAndModifySelection(_:)): (.lineEnd, true),
    #selector(moveToEndOfLineAndModifySelection(_:)): (.lineEnd, true),
    #selector(moveToBeginningOfParagraphAndModifySelection(_:)): (.paragraphStart, true),
    #selector(moveToEndOfParagraphAndModifySelection(_:)): (.paragraphEnd, true),
    #selector(moveParagraphBackwardAndModifySelection(_:)): (.paragraphBackward, true),
    #selector(moveParagraphForwardAndModifySelection(_:)): (.paragraphForward, true),
    #selector(moveToBeginningOfDocumentAndModifySelection(_:)): (.documentStart, true),
    #selector(moveToEndOfDocumentAndModifySelection(_:)): (.documentEnd, true),
    #selector(moveUpAndModifySelection(_:)): (.lineUp, true),
    #selector(moveDownAndModifySelection(_:)): (.lineDown, true),
  ]

  /// Delete key → end to delete to with a bare caret
  static let multiCursorDeletions: [Selector: CursorMotion] = [
    #selector(deleteBackward(_:)): .characterBackward,
    #selector(deleteForward(_:)): .characterForward,
    #selector(deleteWordBackward(_:)): .wordBackward,
    #selector(deleteWordForward(_:)): .wordForward,
    #selector(deleteToBeginningOfLine(_:)): .lineStart,
    #selector(deleteToEndOfLine(_:)): .lineEnd,
  ]

  /// Commands that only scroll and leave carets alone. Passed to the editor with multi-cursor kept.
  static let multiCursorScrolls: Set<Selector> = [
    #selector(scrollPageUp(_:)), #selector(scrollPageDown(_:)), #selector(scrollLineUp(_:)), #selector(scrollLineDown(_:)),
    #selector(scrollToBeginningOfDocument(_:)), #selector(scrollToEndOfDocument(_:)),
    #selector(centerSelectionInVisibleArea(_:)),
  ]

  /// Move all spots together. End multi-cursor if they merge into one.
  func moveMultiCursor(_ motion: CursorMotion, extending: Bool) {
    guard let session = multiCursor else { return }
    if session.marked != nil { finishComposition() }
    let goals = motion.isVertical ? session.goalX : nil
    var heads: [Int] = []
    var newGoals: [CGFloat] = []
    for (index, selection) in session.cursor.selections.enumerated() {
      let range = selection.range
      if !extending, range.length > 0, motion == .characterBackward || motion == .characterForward {
        heads.append(motion.isBackward ? range.location : NSMaxRange(range))
        continue
      }
      let from = extending || range.length == 0 ? selection.head : (motion.isBackward ? range.location : NSMaxRange(range))
      let goal = goals.flatMap { $0.count == session.cursor.selections.count ? $0[index] : nil }
      let moved = cursorHead(motion, from: from, goalX: goal)
      heads.append(moved.head)
      newGoals.append(moved.goalX ?? 0)
    }
    let before = session.cursor.selections.count
    session.cursor.move(to: heads, extending: extending)
    session.goalX = motion.isVertical && session.cursor.selections.count == before ? newGoals : nil
    session.input = nil
    guard session.cursor.selections.count > 1 else {
      let only = session.cursor.selections[0]
      endMultiCursor()
      setSelectedRange(only.range)
      scrollRangeToVisible(NSRange(location: only.head, length: 0))
      return
    }
    selectPrimary()
    scrollRangeToVisible(NSRange(location: session.cursor.selections[0].head, length: 0))
    needsDisplay = true
  }

  /// Position after one move from caret `index`. Vertical moves also return the target horizontal position (text container coords).
  func cursorHead(_ motion: CursorMotion, from index: Int, goalX: CGFloat?) -> (head: Int, goalX: CGFloat?) {
    let text = string as NSString
    let length = text.length
    let index = min(max(index, 0), length)
    switch motion {
    case .characterBackward: return (MultiCursor.characterStart(before: index, in: text), nil)
    case .characterForward: return (MultiCursor.characterEnd(after: index, in: text), nil)
    case .wordBackward: return (index == 0 ? 0 : textStorage?.nextWord(from: index, forward: false) ?? index, nil)
    case .wordForward: return (index == length ? length : textStorage?.nextWord(from: index, forward: true) ?? index, nil)
    case .lineStart: return (visualLine(at: index).location, nil)
    case .lineEnd: return (lineContentEnd(visualLine(at: index)), nil)
    case .paragraphStart: return (MultiCursor.paragraphStart(at: index, in: text), nil)
    case .paragraphEnd: return (MultiCursor.paragraphEnd(at: index, in: text), nil)
    case .paragraphBackward:
      let start = MultiCursor.paragraphStart(at: index, in: text)
      return (start == index && index > 0 ? MultiCursor.paragraphStart(at: index - 1, in: text) : start, nil)
    case .paragraphForward:
      let end = MultiCursor.paragraphEnd(at: index, in: text)
      return (end == index && index < length ? MultiCursor.paragraphEnd(at: index + 1, in: text) : end, nil)
    case .documentStart: return (0, nil)
    case .documentEnd: return (length, nil)
    case .lineUp, .lineDown: return verticalHead(from: index, up: motion == .lineUp, goalX: goalX)
    }
  }

  /// End deleted by a delete key with a bare caret. Delete-to-line-end at the line end (⌘⌦) deletes the newline (same as the editor).
  func deletionStop(_ motion: CursorMotion, from index: Int) -> Int {
    let stop = cursorHead(motion, from: index, goalX: nil).head
    let text = string as NSString
    guard motion == .lineEnd, stop == index, index < text.length else { return stop }
    return MultiCursor.characterEnd(after: index, in: text)
  }

  /// Character range of the screen line holding the caret (including the newline). A wrap point counts as the next line.
  private func visualLine(at index: Int) -> NSRange {
    guard let layoutManager, let textContainer else { return NSRange(location: index, length: 0) }
    let length = (string as NSString).length
    if index == length { layoutManager.ensureLayout(for: textContainer) }
    if length == 0 || (index == length && layoutManager.extraLineFragmentTextContainer != nil) {
      return NSRange(location: length, length: 0)
    }
    var glyphs = NSRange()
    layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: min(index, length - 1)), effectiveRange: &glyphs)
    return layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
  }

  /// The furthest a caret can go on a screen line (before the newline)
  private func lineContentEnd(_ line: NSRange) -> Int {
    let text = string as NSString
    let end = NSMaxRange(line)
    guard end > line.location, end <= text.length else { return end }
    let last = text.character(at: end - 1)
    return last == 0x0A || last == 0x0D || last == 0x2029 ? end - 1 : end
  }

  private func verticalHead(from index: Int, up: Bool, goalX: CGFloat?) -> (head: Int, goalX: CGFloat?) {
    let length = (string as NSString).length
    guard let caret = caretLine(at: index) else { return (index, goalX) }
    let x = goalX ?? caret.minX
    let line = visualLine(at: index)
    let target: NSRange
    if up {
      guard line.location > 0 else { return (0, x) }
      target = visualLine(at: line.location - 1)
    } else {
      let next = NSMaxRange(line)
      guard next < length || (next == length && line.length > 0 && lineContentEnd(line) < next) else { return (length, x) }
      target = visualLine(at: next)
    }
    guard target.length > 0, let row = caretLine(at: target.location) else { return (target.location, x) }
    // `characterIndexForInsertion` (the click path) takes 33 ms for 1,000 carets (Debug measurement), so pick by glyph rects directly.
    // Don't land inside one character (e.g. decomposed Hangul); go to the nearer of its start/end.
    guard let layoutManager, let textContainer else { return (index, x) }
    var fraction: CGFloat = 0
    let glyph = layoutManager.glyphIndex(for: NSPoint(x: x, y: row.midY), in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
    let character = layoutManager.characterIndexForGlyph(at: glyph)
    let composed = (string as NSString).rangeOfComposedCharacterSequence(at: min(character, length - 1))
    let head = fraction > 0.5 ? NSMaxRange(composed) : composed.location
    return (min(max(head, target.location), lineContentEnd(target)), x)
  }
}
