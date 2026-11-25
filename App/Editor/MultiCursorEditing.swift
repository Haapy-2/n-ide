import AppKit
import NovelCore

/// 같은 말 여러 커서의 편집기 쪽 상태(⌘D, PLAN 16장). 계산은 NovelCore `MultiCursor`.
final class MultiCursorSession {
  var cursor: MultiCursor
  /// 표시된 글자 방식(16장 5번 ⓑ)으로 조합 중일 때 자리마다 조합 중인 글 범위. 앞에서부터, 맨 앞이 입력기와 이어진 자리.
  var marked: [NSRange]?
  /// 지금 만들고 있는 한 글자의 되돌리기 기록. 입력기가 그 글자를 고치는 동안은 같은 기록의 범위만 늘린다.
  var input: MultiInputUnit?
  /// 위아래로 잇달아 움직이는 동안 자리마다 지킬 가로 위치(짧은 줄을 지나도 돌아오게). 다른 명령이 오면 잊는다.
  var goalX: [CGFloat]?

  init(cursor: MultiCursor) {
    self.cursor = cursor
  }
}

/// 자리마다 한 번에 고친 것의 되돌리기 기록. `ranges`는 지금 본문에서 고친 글이 놓인 자리, `originals`는 고치기 전 글.
final class MultiInputUnit {
  var ranges: [NSRange]
  let originals: [String]
  /// 되돌린 뒤 놓을 커서들(16장 U2)
  let cursorsBefore: [NSRange]

  init(ranges: [NSRange], originals: [String], cursorsBefore: [NSRange]) {
    self.ranges = ranges
    self.originals = originals
    self.cursorsBefore = cursorsBefore
  }

  /// 입력기가 이 기록의 글자들만 고치는가(자리마다 고칠 범위가 기록 범위 안).
  func covers(_ targets: [NSRange]) -> Bool {
    guard targets.count == ranges.count else { return false }
    return zip(ranges, targets).allSatisfy { unit, target in
      target.location >= unit.location && NSMaxRange(target) <= NSMaxRange(unit)
    }
  }
}

/// 여러 커서일 때 `ManuscriptTextView`가 입력기와의 약속(`NSTextInputClient`)을 직접 맡는다. 커서가 하나면 이 파일의 코드는 돌지 않는다.
/// 본문은 실제로 모든 자리에서 고치고(뒤에서부터, `shouldChangeText` → 고치기 → `didChangeText` 한 길),
/// `NSTextView`의 선택은 늘 맨 앞 자리다(입력기와 이어진 커서, 16장 5번). 나머지 자리는 직접 그린다.
/// 이 상태에서는 조합 중에도 텍스트 저장소를 고친다(CLAUDE.md 예외): 조합 범위를 `NSTextView`가 아니라 여기서 들고 있어서
/// 어긋날 속 상태가 없다. 계산이 맞지 않는 상황(낡은 범위, 맨 앞 커서 밖을 가리키는 입력기)이 오면 고치지 않고 여러 커서를 끝낸다.
extension ManuscriptTextView {

  var multiCursorRanges: [NSRange]? { multiCursor?.cursor.ranges }

  // MARK: - ⌘D

  /// 편집 메뉴 명령을 키보드 초점이 있는 편집기로 보낸다(초점이 사이드바·검색 칸이면 아무 일도 없다).
  static func sendSelectNextOccurrence() {
    NSApp.sendAction(#selector(selectNextOccurrence(_:)), to: nil, from: nil)
  }

  /// 커서만 있으면 커서 아래 단어를 고르고, 고른 말이 있으면 다음 같은 말을 하나 더 고른다(VS Code ⌘D).
  @objc func selectNextOccurrence(_ sender: Any?) {
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
        multiCursor = MultiCursorSession(cursor: cursor)
      }
      selectPrimary()
      scrollRangeToVisible(found)
      needsDisplay = true
    case .noMore, .notSearchable:
      break
    case .limitReached:
      NSSound.beep()
    }
  }

  /// 여러 커서를 끝내고 맨 앞 자리 하나로(Esc). 조합 중이면 먼저 확정한다.
  func endMultiCursor() {
    guard let session = multiCursor else { return }
    finishComposition()
    let primary = session.cursor.ranges[0]
    dropMultiCursor()
    if NSMaxRange(primary) <= (string as NSString).length { setSelectedRange(primary) }
  }

  /// 상태만 버린다. 본문·선택은 건드리지 않는다(다른 길이 본문이나 선택을 막 바꾸는 중일 때).
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

  // MARK: - 입력기

  /// 표시된 글자 방식. 처리했으면 true, 아니면 여러 커서를 끝냈으니 부르는 쪽이 보통 입력으로 넘긴다.
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

  /// 확정 글(표시된 글자 방식의 마지막) 또는 표시된 글자 없는 방식의 한 글자. 처리했으면 true.
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

  /// 입력기가 조합을 끝냄(한/영 전환 등, 16장 I5). 자리마다 지금 글 그대로 확정한다.
  func multiCursorUnmark() {
    guard let session = multiCursor, session.marked != nil else { return }
    session.marked = nil
    clearMarkedUnderline()
  }

  private func targets(for replacementRange: NSRange, around anchors: [NSRange]) -> [NSRange]? {
    guard replacementRange.location != NSNotFound else { return anchors }
    return MultiCursor.targets(forReplacement: replacementRange, around: anchors, textLength: (string as NSString).length)
  }

  /// 키 명령(화살표·지우기·엔터·탭·Esc). 처리했으면 true. 아직 여러 커서로 하지 않는 명령은 여러 커서를 끝내고 false.
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

  /// 지우기 키: 자리마다 선택이 있으면 그 선택, 커서만 있으면 커서에서 `motion`만큼. 모든 자리가 ⌘Z 한 단위.
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

  // MARK: - 복사와 붙여 넣기 (16장 E7)

  /// ⌘C: 고른 글을 줄바꿈으로 이어 복사(VS Code). 모두 빈 선택이면 아무것도 하지 않는다(커서 하나일 때와 같다).
  func multiCursorCopy(to pasteboard: NSPasteboard) {
    guard let session = multiCursor,
      let text = MultiCursor.copiedText(session.cursor.ranges, in: string as NSString)
    else { return }
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  /// ⌘X: 복사한 뒤 고른 글을 모든 자리에서 지운다(⌘Z 한 단위).
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

  /// ⌘V: 줄 수가 커서 수와 같으면 한 줄씩, 아니면 모든 자리에 같은 글(⌘Z 한 단위). 글이 아닌 것(그림)은 넣지 않는다.
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

  // MARK: - 고치기와 되돌리기

  /// 자리마다 한 번에 고친다. 메인 스레드에서 기다림 없이 끝난다(16장 D6). 고쳤으면 자리마다 새 글이 놓인 범위.
  /// 범위가 낡았으면(16장 D1) 아무것도 고치지 않고 nil.
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

  /// 뒤에서부터 자리마다 고친다. `beginEditing`으로 묶지 않는다: 묶으면 첫 자리~끝 자리 전체가 한 번 바뀐 것으로 잡혀
  /// 그만큼을 다시 처리한다(10만 자, 커서 2개라도 글 처음·끝이면 69ms). 자리마다면 고친 곳만(커서 100개 3.2ms, 측정).
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

  /// 한 번에 고친 것 되돌리기(다시 실행도 같은 함수). 자리가 본문 밖이면(있어서는 안 되는 상태) 아무것도 바꾸지 않는다.
  /// 되돌린 뒤에는 그때의 커서들로 다시 여러 커서가 된다.
  private func revertMultiInput(_ unit: MultiInputUnit) {
    finishComposition()
    dropMultiCursor()
    guard let storage = textStorage,
      let edit = MultiCursor.edit(unit.ranges, texts: unit.originals, textLength: storage.length)
    else { return }
    let text = string as NSString
    let replaced = unit.ranges.map { text.substring(with: $0) }
    let undo = episodeUndoManager
    undo.disableUndoRegistration()
    let changed = shouldChangeText(inRanges: unit.ranges.map { NSValue(range: $0) }, replacementStrings: unit.originals)
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

  // MARK: - 그리기

  /// 맨 앞 말고 다른 자리의 선택 바탕. 글자 아래에 그린다.
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

  /// 맨 앞 말고 다른 자리의 커서. 맨 앞 커서가 그려져 있을 때만(`extraCaretsOn`).
  func drawMultiCursorCarets(in rect: NSRect) {
    guard extraCaretsOn, let ranges = multiCursor?.cursor.ranges.dropFirst() else { return }
    insertionPointColor.setFill()
    for range in ranges where range.length == 0 {
      guard let caret = extraCaretRect(at: range.location), caret.intersects(rect) else { continue }
      caret.fill()
    }
  }

  /// 시스템이 맨 앞 커서를 켜는 그리기 안에서 다른 커서도 그린다. 그 칸들은 `invalidateExtraCarets`로
  /// 이 그리기에 들어와 있어, 다음 화면 갱신을 기다리지 않고 같은 순간에 켜진다.
  func drawExtraCaretsWithFirst() {
    extraCaretsOn = true
    drawMultiCursorCarets(in: visibleRect)
  }

  /// 창이 비활성화되는 등 시스템이 커서를 직접 끌 때.
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

  /// `index` 앞에 놓인 커서의 줄 칸(글 상자 좌표, 폭 1pt, x가 커서 자리). 줄이 접히는 자리는 다음 줄 처음.
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
    // 글자 상자(`boundingRect`)는 글자 모양이 그려지는 넓이라 커서 자리와 다르다(Pretendard에서 12pt쯤).
    // 커서 자리는 그 글자가 놓인 자리(`location`), 글 끝은 빈 범위의 선택 칸.
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
