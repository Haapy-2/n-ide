import AppKit
import NovelCore

/// 원고 편집용 NSTextView. TextKit 1을 명시적으로 쓴다(SPEC 3장).
/// 본문 폭을 고정하고 창이 넓으면 가운데 두며, 마지막 줄을 화면 가운데까지 올려 쓸 수 있게 아래 여백을 둔다.
final class ManuscriptTextView: NSTextView {
  var style = EditorStyle() {
    didSet { if style != oldValue { applyStyle() } }
  }
  /// 커서 두께·높이·색(설정 › 커서, `CaretSettings.swift`). 그림만 바뀌어 조합 중에 바뀌어도 안전하다.
  var caret = CaretStyle() {
    didSet {
      guard caret != oldValue else { return }
      insertionPointColor = caret.dynamicColor
      // 옛 두께·높이로 그린 커서를 지우고 새 모양으로 바로 다시 그린다.
      if let last = lastCaretRect { eraseCaret(last) }
      lastCaretRect = nil
      updateInsertionPointStateAndRestartTimer(true)
    }
  }
  /// 조합 중에 모양이 바뀌어 본문 전체에는 아직 못 입혔다. 조합이 끝나면 입힌다.
  private var needsRestyle = false
  /// 레이아웃 매니저의 delegate는 약한 참조라 여기서 붙잡아 둔다.
  private let blankLineSpacing = BlankLineSpacing()
  /// 빈 회차 안내 글을 마지막으로 그렸을 때 본문이 비어 있었는지(`EmptyEpisodePlaceholder.swift`)
  var placeholderShown = true

  /// 왼쪽 여백에 줄 번호(`LineNumberGutter.swift`). 그림만 바뀌고 본문·선택은 건드리지 않아 조합 중에 바뀌어도 안전하다.
  var showsLineNumbers = false {
    didSet {
      guard showsLineNumbers != oldValue else { return }
      lineCountCache = nil
      needsDisplay = true
    }
  }
  /// 줄 번호를 빈 줄에도 그릴지. 그림만 바뀐다.
  var numbersBlankLines = true {
    didSet { if numbersBlankLines != oldValue, showsLineNumbers { needsDisplay = true } }
  }
  /// 전체 줄 수. 본문 글자가 바뀌면 다시 센다(`storageEditedForLineNumbers`).
  private var lineCountCache: Int?

  /// 마지막으로 그린 커서 칸. macOS는 원래 굵기(1pt) 칸만 지우거나, 창이 비활성화될 때 지우는 요청을 따로 보내지 않을 수 있어서
  /// 굵은 커서가 남는다. 이 칸은 앱이 직접 지운다.
  private(set) var lastCaretRect: NSRect?

  var currentLineCount: Int {
    if let lineCountCache { return lineCountCache }
    let count = ParagraphLines.lineCount(in: textStorage?.mutableString ?? "")
    lineCountCache = count
    return count
  }

  private var isInsertingInput = false
  /// 입력기가 지금 만들고 있는 한 글자의 되돌리기 기록.
  private var currentInput: InputUndoUnit?

  /// 같은 말 여러 커서(⌘D, `MultiCursorEditing.swift`). nil이면 보통 편집기 그대로다.
  var multiCursor: MultiCursorSession? {
    didSet { currentInput = nil }
  }
  /// 여러 커서 코드가 본문·선택을 고치는 중. 이때 오는 선택·본문 바뀜은 여러 커서를 끝내지 않는다.
  var isApplyingMultiCursor = false
  /// 커서만 있던 자리에서 ⌘D로 고른 단어. 다음 ⌘D가 단어 전체로 찾을지 정한다.
  var wordFromCaret: NSRange?
  /// 맨 앞 커서가 지금 화면에 그려져 있나. 다른 자리 커서도 이 값대로 그린다(`MultiCursorEditing.swift`).
  var extraCaretsOn = false
  /// 설정 › 편집기 "같은 말 여러 커서". 끄면 ⌘D가 아무것도 하지 않고, 여러 커서 중이면 끝낸다.
  /// 메뉴만 흐리게 하면 메뉴를 거치지 않는 호출(`sendSelectNextOccurrence`)이 남아 여기서도 막는다.
  var multiCursorEnabled = true {
    didSet { if !multiCursorEnabled { endMultiCursor() } }
  }
  /// 커서 하나에서 여러 커서로 바뀌기 직전. 본문은 아직 그대로다(들어가기 전 스냅샷용).
  var onEnterMultiCursor: () -> Void = {}
  /// 작가에게 짧게 알릴 말(토스트).
  var onNotice: (String) -> Void = { _ in }

  /// 회차마다 따로 쓰는 실행 취소 기록. 회차를 바꾸면 비운다(PLAN.md 세부 기준).
  let episodeUndoManager = UndoManager()

  /// 창에 붙거나 다른 창으로 옮겨질 때마다. SwiftUI가 뷰를 창에 붙이는 시점은 정해져 있지 않아서
  /// "조금 뒤에 한 번" 하는 대신 AppKit이 알려 주는 이 순간에 초점과 창 감시를 건다.
  var onMoveToWindow: (NSWindow) -> Void = { _ in }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let window { onMoveToWindow(window) }
  }

  static func make() -> ManuscriptTextView {
    // TextKit 1: NSTextStorage → NSLayoutManager → NSTextContainer 를 직접 연결한다.
    let storage = NSTextStorage()
    let layoutManager = NSLayoutManager()
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
    // 높이 한도를 두지 않는다. 기본값이면 처음 잡힌 높이가 한도가 되어, 더 긴 회차로 바꾼 직후
    // 아직 배치가 안 된 아래쪽으로는 프로그램이 스크롤하지 못한다(검색 결과로 가기).
    maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    isHorizontallyResizable = false
    autoresizingMask = [.width]
    drawsBackground = true
    backgroundColor = .paper
    insertionPointColor = caret.dynamicColor
    selectedTextAttributes = [.backgroundColor: NSColor.selectionToken]
    layoutManager?.delegate = blankLineSpacing
    applyStyle()
    NotificationCenter.default.addObserver(
      self, selector: #selector(eraseCaretOnDeactivate(_:)), name: NSWindow.didResignKeyNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(eraseCaretOnDeactivate(_:)), name: NSApplication.didResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(storageEditedForLineNumbers(_:)),
      name: NSTextStorage.didProcessEditingNotification, object: textStorage)
  }

  // MARK: - 줄 번호 다시 그리기

  /// 줄 수가 바뀌면(엔터·줄 지우기·붙여 넣기·회차 전환) 보이는 번호를 모두 다시 그린다.
  /// 줄 수가 같으면 아무것도 안 한다. 글자만 친 줄은 아래 `setNeedsDisplay`가 번호 칸까지 넓혀 다시 그린다.
  /// 읽기만 하므로 조합 중에도 안전하다.
  @objc private func storageEditedForLineNumbers(_ notification: Notification) {
    // 여러 커서는 자리마다 따로 고쳐 이 알림이 커서 수만큼 온다. 그때는 다 고친 뒤 한 번만 센다.
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

  // 시스템은 커서를 끌 때 `drawInsertionPoint(turnedOn: false)`를 부르지 않고 그 칸을 다시 그리기만 한다.
  // 그래서 맨 앞 커서 칸을 다시 그리면 꺼진 것으로 본다. 켜진 때면 이 그리기 바로 뒤에 시스템이 다시 켠다.
  override func draw(_ dirtyRect: NSRect) {
    if multiCursor != nil, let last = lastCaretRect, needsToDraw(last) { extraCaretsOn = false }
    super.draw(dirtyRect)
    if multiCursor != nil { drawMultiCursorCarets(in: dirtyRect) }
  }

  // 커서 모양은 `InsertionCaret.swift`. 끌 때(깜빡임)는 원래 칸 전체를 지워 흔적이 남지 않게 한다.
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

  /// 창이 비활성화되거나 앱이 뒤로 가면 커서는 그려지지 않아야 한다. 남아 있는 칸을 지운다.
  @objc private func eraseCaretOnDeactivate(_ notification: Notification) {
    if let window = notification.object as? NSWindow, window !== self.window { return }
    if multiCursor != nil { turnOffExtraCarets() }
    guard let last = lastCaretRect else { return }
    eraseCaret(last)
    lastCaretRect = nil
  }

  private func eraseCaret(_ rect: NSRect) {
    // 반올림·안티에일리어싱으로 가장자리가 반 픽셀 남지 않게 1pt씩 넓혀 다시 그린다.
    setNeedsDisplay(rect.insetBy(dx: -1, dy: -1))
  }

  // 글자를 고치면 NSTextView는 본문 칸 안만 다시 그리게 한다. 번호 칸은 그 왼쪽 여백이라, 줄이 밀려 내려가도
  // 옛 번호가 남는다. 줄 번호를 켰을 때만 다시 그릴 곳을 왼쪽 끝까지 넓힌다(본문 칸은 그대로라 비용은 여백 조금).
  // 커서 자국을 막으려고 가는 칸은 커서 두께만큼 넓힌다(`InsertionCaret.swift`).
  // 맨 앞 커서 칸을 다시 그리라는 요청에는 다른 자리 커서 칸도 붙여, 깜빡임이 같은 그리기에서 같이 바뀌게 한다.
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

  private func applyStyle() {
    let attributes = style.textAttributes
    typingAttributes = attributes
    defaultParagraphStyle = style.paragraphStyle
    // 조합 중에는 텍스트 저장소를 건드리지 않는다(한글 입력 보호). 조합이 끝난 직후(`didChangeText`)에 입힌다.
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

  /// 본문 텍스트 전체를 바꾼다(회차 전환). 실행 취소 기록도 비운다.
  func replaceAllText(with text: String) {
    // 조합을 확정하고 입력기에도 끝났다고 알린다. unmarkText만 하면 입력기는 아직 조합 중이라 여겨,
    // 다음 키가 앞 회차의 자모와 합쳐져 새 본문에 들어갈 수 있다.
    finishComposition()
    forgetInputInProgress()
    dropMultiCursor()
    textStorage?.setAttributedString(NSAttributedString(string: text, attributes: style.textAttributes))
    updatePlaceholderIfNeeded()
    setSelectedRange(NSRange(location: 0, length: 0))
    episodeUndoManager.removeAllActions()
    scroll(.zero)
  }

  /// 스냅샷으로 되돌리기: 본문 전체를 실행 취소 한 단위로 바꾼다. 회차 전환과 달리 기록을 비우지 않아 ⌘Z 한 번으로 돌아간다.
  /// 바꿨으면 true. 커서는 같은 자리(본문이 짧아졌으면 끝)에 둔다.
  func replaceAllUndoably(with text: String, actionName: String) -> Bool {
    finishComposition()
    endMultiCursor()
    let full = NSRange(location: 0, length: (string as NSString).length)
    guard string != text else { return false }
    let cursor = selectedRange().location
    let undo = episodeUndoManager
    undo.beginUndoGrouping()
    defer { undo.endUndoGrouping() }
    // shouldChangeText가 실행 취소 기록을 남기고, didChangeText가 바뀜 알림(자동 저장·글자 수)을 보낸다.
    guard shouldChangeText(in: full, replacementString: text) else { return false }
    forgetInputInProgress()
    textStorage?.replaceCharacters(in: full, with: NSAttributedString(string: text, attributes: style.textAttributes))
    didChangeText()
    undo.setActionName(actionName)
    setSelectedRange(NSRange(location: min(cursor, (text as NSString).length), length: 0))
    scrollRangeToVisible(selectedRange())
    return true
  }

  /// 고칠 자리만 실행 취소 한 단위로 고친다(전체 바꾸기·되돌리기). 본문을 통째로 갈지 않아서 커서는 같은 글자 자리에 남고
  /// 화면 맨 위 글줄도 그대로다(위쪽에서 줄 수가 바뀌어도). 자리는 앞에서부터, 겹치지 않아야 한다. 고쳤으면 true.
  /// 조합 중이면 손대지 않고 false: 조합을 끊지 않으려는 것이라, 부르는 쪽이 조합이 끝난 뒤 다시 부른다.
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

    // 고친 자리 앞의 글자는 그대로, 뒤의 글자는 늘고 준 만큼 민다. 고친 자리 안이면 새 말 끝으로.
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

  /// 앱이 본문을 직접 고치기 전에: 입력기가 "표시된 글자 없이" 이어 가던 글자를 놓게 한다.
  /// 이 방식은 조합 중에도 `hasMarkedText`가 false라, 고친 뒤 입력기가 옛 자리를 `replacementRange`로 고쳐 쓰거나
  /// 한 글자 기록(`currentInput`)이 어긋난 범위로 늘어나 ⌘Z가 엉뚱한 글자를 지울 수 있다.
  private func forgetInputInProgress() {
    guard currentInput != nil else { return }
    currentInput = nil
    inputContext?.discardMarkedText()
  }

  /// 글자가 놓인 줄의 위 끝(편집기 좌표)
  private func lineTop(of index: Int) -> CGFloat {
    guard let layoutManager, layoutManager.numberOfGlyphs > 0 else { return 0 }
    let glyph = layoutManager.glyphIndexForCharacter(at: min(index, (string as NSString).length - 1))
    layoutManager.ensureLayout(forGlyphRange: NSRange(location: 0, length: glyph + 1))
    return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + textContainerOrigin.y
  }

  /// 앱 밖에서 바뀐 본문으로 갈아 끼운다. 회차 전환과 달리 커서와 스크롤 위치를 되도록 그대로 둔다.
  /// 실행 취소 기록은 비운다: 옛 본문 기준의 기록을 새 본문에 적용하면 엉뚱한 곳이 바뀐다.
  func reloadText(with text: String) {
    // 조합을 확정하고 입력기에도 끝났다고 알린다. unmarkText만 하면 입력기는 아직 조합 중이라 여겨,
    // 다음 키가 앞 회차의 자모와 합쳐져 새 본문에 들어갈 수 있다.
    finishComposition()
    forgetInputInProgress()
    dropMultiCursor()
    let cursor = selectedRange().location
    let origin = enclosingScrollView?.contentView.bounds.origin ?? .zero
    textStorage?.setAttributedString(NSAttributedString(string: text, attributes: style.textAttributes))
    setSelectedRange(NSRange(location: min(cursor, (text as NSString).length), length: 0))
    episodeUndoManager.removeAllActions()
    scroll(origin)
  }

  override var undoManager: UndoManager? { episodeUndoManager }

  // 편집 메뉴의 실행 취소(⌘Z)·다시 실행(⇧⌘Z)은 처리하는 곳을 응답 사슬에서 찾는데, 편집기가 받지 않으면 창까지 올라가
  // 창의 기록(사이드바 회차 작업)을 쓴다. 입력은 회차 기록(`episodeUndoManager`)에 쌓이므로 여기서 직접 받는다.
  @objc func undo(_ sender: Any?) {
    finishComposition()
    episodeUndoManager.undo()
  }

  @objc func redo(_ sender: Any?) {
    finishComposition()
    episodeUndoManager.redo()
  }

  /// 두벌식 입력기(macOS 27)는 표시된 글자 없이 "커서 앞 글자를 이 글로"(`replacementRange`)로 조합을 이어 가기도 한다
  /// (ㄱ → 가 → 각 → 가 + 가). 이때는 `hasMarkedText`가 늘 false이고, NSTextView는 이 바꾸기들을 한 묶음으로 합치지 않아
  /// ⌘Z가 조합 중간 글자("각")를 보여 준다. 그래서 입력기가 넣는 한 글자는 직접 한 단위로 기록하고, 입력기가 그 글자를
  /// 고치는 동안은 같은 기록의 범위만 늘린다. 되돌릴 때는 LIFO라 그 사이의 다른 변경이 먼저 되돌려져 범위가 맞는다.
  override func insertText(_ string: Any, replacementRange: NSRange) {
    let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    if multiCursor != nil, multiCursorInsertText(text, replacementRange: replacementRange) { return }
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

  /// 한 글자 기록 되돌리기(다시 실행도 같은 함수). 바꾼 뒤의 범위와 바뀌기 전 글로 반대 기록을 직접 남긴다.
  /// NSTextView가 `shouldChangeText`에서 스스로 남기는 기록은 끈다: 그 기록은 다시 실행 때 범위가 어긋나 앱을 죽였다.
  /// 범위가 본문 밖이면(있어서는 안 되는 상태) 아무것도 바꾸지 않는다.
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

  /// 되돌리기 단위를 한 글자로 한다. NSTextView는 이어서 친 글자를 한 묶음으로 합쳐
  /// ⌘Z 한 번에 문장째 지우므로, 고칠 때마다 묶음을 끊는다. 조합 중에는 끊지 않아 조합이 끝난 한 글자("한")가 한 단위가 된다.
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

  /// 조합 중인 글자를 확정한다. 조합 중에 되돌리면 입력기와 텍스트 저장소가 서로 다른 글자를 가리켜 깨질 수 있다.
  /// 여러 커서면 모든 자리의 조합을 확정한다(`unmarkText`).
  func finishComposition() {
    guard hasMarkedText() else { return }
    unmarkText()
    inputContext?.discardMarkedText()
  }

  // MARK: - 여러 커서일 때 입력기와의 약속 (`MultiCursorEditing.swift`)

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

  // 여러 커서의 조합 범위는 `NSTextView` 속 상태가 아니라 여기에 있다. 자동 저장·스타일 입히기 등이 이것으로 조합 중인지 본다.
  // 우리가 선택을 옮기는 동안에는 조합이 없다고 답한다: 있다고 하면 `NSTextView`가 선택을 옮기며 조합을 끊는다.
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
    super.paste(sender)
  }

  override func pasteAsPlainText(_ sender: Any?) {
    guard multiCursor == nil else { return multiCursorPaste(from: .general) }
    super.pasteAsPlainText(sender)
  }

  // 여러 커서 코드가 아닌 길(클릭, 전체 선택, 붙여 넣기, 다른 되돌리기 기록)이 선택이나 본문을 바꾸면 다른 자리는 낡는다.
  // 그 길이 바꾸기 전에 여러 커서를 버린다(PLAN 16장 D3). 본문·선택은 그 길이 정한다.
  override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
    if !isApplyingMultiCursor {
      dropMultiCursor()
      wordFromCaret = nil
    }
    super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
  }

  override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
    if !isApplyingMultiCursor { dropMultiCursor() }
    return super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
  }

  override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
    if !isApplyingMultiCursor { dropMultiCursor() }
    return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
  }

  /// 떠 있는 판(⇧⌘S)을 열기 전: 조합을 끝내고 키보드 초점을 내려놓는다. 커서·선택은 그대로 남는다.
  /// 판을 열 때 편집기가 초점을 갖고 있었는지 돌려준다(닫을 때 돌려줄지 정하려고).
  func yieldFocusForPanel() -> Bool {
    finishComposition()
    guard let window, window.firstResponder === self else { return false }
    window.makeFirstResponder(nil)
    return true
  }

  /// 검색 결과로 가기: 찾은 곳을 선택해 화면 가운데로 올리고 초점을 받는다.
  /// 검색 뒤 글이 바뀌어 그 자리에 문구가 없으면 가장 가까운 같은 문구로 간다. 문구가 아예 없으면 움직이지 않는다.
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
    // 회차를 막 바꿨으면 아직 본문 높이가 다 잡히지 않았다. 한 차례 뒤에 가운데로 옮기고 노란 표시를 띄운다.
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
    // 회차를 막 바꾸면 글자 배치가 앞부분까지만 되어 있어 본문 높이가 실제보다 작다. 그대로 두면 스크롤이 그 높이에서 막힌다.
    // 찾은 곳까지 배치를 끝내면 편집기 높이도 함께 늘어난다.
    layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: NSMaxRange(range)))
    sizeToFit()
    let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
    let midY = rect.midY + textContainerOrigin.y
    let maxY = max(0, frame.height - clip.bounds.height)
    clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: min(max(0, midY - clip.bounds.height / 2), maxY)))
    enclosingScrollView?.reflectScrolledClipView(clip)
  }

  /// 판을 닫은 뒤: 커서가 있던 자리로 초점을 돌려준다.
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
    default:
      return super.validateUserInterfaceItem(item)
    }
  }

  // MARK: - 회차 자리

  /// 지금 커서와 화면 맨 위 줄의 첫 글자.
  func viewState() -> EpisodeViewState {
    EpisodeViewState(caret: selectedRange().location, top: topVisibleCharacter(), openedAt: Date())
  }

  /// 커서와 화면을 기억한 자리로. 그사이 본문이 짧아졌으면 끝으로 맞춘다.
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

  /// 그 글자가 든 줄이 화면 맨 위에 오게. 그 앞까지는 배치를 끝내야 줄 위치를 알 수 있다
  /// (회차를 막 바꾼 직후는 아직 배치 전이다).
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

  // MARK: - 폭과 여백

  /// NSTextView는 텍스트 칸 오른쪽 끝보다 오른쪽 점을 자기 것으로 보지 않아, 오른쪽 여백 클릭이 뒤의 clip view로 가서
  /// 커서가 움직이지 않는다. 본문 폭을 고정해 오른쪽 여백이 넓으므로 편집기 안이면 직접 받는다.
  override func hitTest(_ point: NSPoint) -> NSView? {
    if let hit = super.hitTest(point) { return hit }
    guard !isHidden else { return nil }
    return frame.contains(point) ? self : nil
  }

  override func setFrameSize(_ newSize: NSSize) {
    var size = newSize
    // 마지막 줄을 화면 가운데까지 끌어올릴 수 있도록 보이는 높이의 절반만큼 아래에 여유를 둔다.
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

  /// 본문 폭은 창 너비와 상관없이 고정하고, 남는 폭은 좌우 여백으로 나눈다.
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

/// 입력기가 넣은 한 글자(음절)의 되돌리기 기록. 입력기가 그 글자를 고치는 동안 범위가 바뀌므로 참조형이다.
private final class InputUndoUnit {
  var range: NSRange
  let original: String

  init(range: NSRange, original: String) {
    self.range = range
    self.original = original
  }
}
