import AppKit
import NovelCore

/// 여러 커서에서 화살표·지우기 키(PLAN 16장 E5). 목표 자리는 커서마다 글과 줄 배치에서 직접 계산한다:
/// 편집기 이동 명령을 자리마다 부르면 커서 1,000개에 키 하나 약 90ms라 목표(16ms)를 넘는다(측정).
/// 계산 결과가 커서 하나일 때의 편집기와 같은지는 앱 테스트가 모든 자리에서 비교한다.
enum CursorMotion {
  case characterBackward, characterForward
  case wordBackward, wordForward
  case lineStart, lineEnd
  case paragraphStart, paragraphEnd
  /// ⇧⌥↑↓: 문단 처음·끝, 이미 거기면 앞·뒤 문단의 처음·끝
  case paragraphBackward, paragraphForward
  case documentStart, documentEnd
  case lineUp, lineDown

  /// 선택이 있는데 ⇧ 없이 움직이면 앞쪽 명령은 선택 앞에서, 뒤쪽 명령은 선택 뒤에서 시작한다(편집기와 같다).
  var isBackward: Bool {
    switch self {
    case .characterBackward, .wordBackward, .lineStart, .paragraphStart, .paragraphBackward, .documentStart, .lineUp: true
    default: false
    }
  }

  var isVertical: Bool { self == .lineUp || self == .lineDown }
}

extension ManuscriptTextView {

  /// 키 명령 → (움직임, ⇧로 늘리기)
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

  /// 지우기 키 → 커서만 있을 때 지울 끝
  static let multiCursorDeletions: [Selector: CursorMotion] = [
    #selector(deleteBackward(_:)): .characterBackward,
    #selector(deleteForward(_:)): .characterForward,
    #selector(deleteWordBackward(_:)): .wordBackward,
    #selector(deleteWordForward(_:)): .wordForward,
    #selector(deleteToBeginningOfLine(_:)): .lineStart,
    #selector(deleteToEndOfLine(_:)): .lineEnd,
  ]

  /// 화면만 넘기고 커서는 그대로인 명령. 여러 커서를 둔 채 편집기에 넘긴다.
  static let multiCursorScrolls: Set<Selector> = [
    #selector(scrollPageUp(_:)), #selector(scrollPageDown(_:)), #selector(scrollLineUp(_:)), #selector(scrollLineDown(_:)),
    #selector(scrollToBeginningOfDocument(_:)), #selector(scrollToEndOfDocument(_:)),
    #selector(centerSelectionInVisibleArea(_:)),
  ]

  /// 모든 자리를 함께 움직인다. 만나서 하나가 되면 여러 커서를 끝낸다.
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

  /// 커서 `index`에서 한 번 움직인 자리. 위아래는 목표 가로 위치(글 상자 좌표)도 돌려준다.
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

  /// 커서만 있을 때 지우기 키가 지울 끝. 줄 끝에서 줄 끝까지 지우기(⌘⌦)는 줄바꿈을 지운다(편집기와 같다).
  func deletionStop(_ motion: CursorMotion, from index: Int) -> Int {
    let stop = cursorHead(motion, from: index, goalX: nil).head
    let text = string as NSString
    guard motion == .lineEnd, stop == index, index < text.length else { return stop }
    return MultiCursor.characterEnd(after: index, in: text)
  }

  /// 커서가 놓인 화면 줄의 글자 범위(줄바꿈 포함). 줄이 접히는 자리는 다음 줄로 본다.
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

  /// 화면 줄에서 커서가 갈 수 있는 끝(줄바꿈 앞)
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
    // `characterIndexForInsertion`(클릭과 같은 길)은 커서 1,000개에 33ms라(Debug 측정) 글자 칸으로 직접 고른다.
    // 한 글자 가운데(자모를 따로 적은 한글 등)에 서지 않게 그 글자 앞뒤 중 가까운 쪽으로.
    guard let layoutManager, let textContainer else { return (index, x) }
    var fraction: CGFloat = 0
    let glyph = layoutManager.glyphIndex(for: NSPoint(x: x, y: row.midY), in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
    let character = layoutManager.characterIndexForGlyph(at: glyph)
    let composed = (string as NSString).rangeOfComposedCharacterSequence(at: min(character, length - 1))
    let head = fraction > 0.5 ? NSMaxRange(composed) : composed.location
    return (min(max(head, target.location), lineContentEnd(target)), x)
  }
}
