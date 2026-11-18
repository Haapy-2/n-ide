import AppKit
import NovelCore

/// 원고 편집용 NSTextView. TextKit 1을 명시적으로 쓴다(SPEC 3장).
/// 본문 폭을 고정하고 창이 넓으면 가운데 두며, 마지막 줄을 화면 가운데까지 올려 쓸 수 있게 아래 여백을 둔다.
final class ManuscriptTextView: NSTextView {
  var style = EditorStyle() {
    didSet { if style != oldValue { applyStyle() } }
  }
  /// 조합 중에 모양이 바뀌어 본문 전체에는 아직 못 입혔다. 조합이 끝나면 입힌다.
  private var needsRestyle = false

  /// 왼쪽 여백에 줄 번호(11f, `LineNumberGutter.swift`). 그림만 바뀌고 본문·선택은 건드리지 않아 조합 중에 바뀌어도 안전하다.
  var showsLineNumbers = false {
    didSet {
      guard showsLineNumbers != oldValue else { return }
      lineCountCache = nil
      needsDisplay = true
    }
  }
  /// 전체 줄 수. 본문 글자가 바뀌면 다시 센다(`storageEditedForLineNumbers`).
  private var lineCountCache: Int?

  var currentLineCount: Int {
    if let lineCountCache { return lineCountCache }
    let count = ParagraphLines.lineCount(in: textStorage?.mutableString ?? "")
    lineCountCache = count
    return count
  }

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
    isHorizontallyResizable = false
    autoresizingMask = [.width]
    drawsBackground = true
    backgroundColor = .paper
    insertionPointColor = .accentToken
    selectedTextAttributes = [.backgroundColor: NSColor.selectionToken]
    applyStyle()
    NotificationCenter.default.addObserver(
      self, selector: #selector(storageEditedForLineNumbers(_:)),
      name: NSTextStorage.didProcessEditingNotification, object: textStorage)
  }

  // MARK: - 줄 번호 다시 그리기

  /// 줄 수가 바뀌면(엔터·줄 지우기·붙여 넣기·회차 전환) 보이는 번호를 모두 다시 그린다.
  /// 줄 수가 같으면 아무것도 안 한다. 글자만 친 줄은 아래 `setNeedsDisplay`가 번호 칸까지 넓혀 다시 그린다.
  /// 읽기만 하므로 조합 중에도 안전하다.
  @objc private func storageEditedForLineNumbers(_ notification: Notification) {
    guard showsLineNumbers, let storage = textStorage, storage.editedMask.contains(.editedCharacters) else { return }
    let old = lineCountCache
    let count = ParagraphLines.lineCount(in: storage.mutableString)
    lineCountCache = count
    if old != count { setNeedsDisplay(visibleRect) }
  }

  override func drawBackground(in rect: NSRect) {
    super.drawBackground(in: rect)
    if showsLineNumbers { drawLineNumbers(in: rect) }
  }

  // 커서를 글자 크기의 1.2배로(`InsertionCaret.swift`). 끌 때(깜빡임)는 원래 칸 전체를 지워 흔적이 남지 않게 한다.
  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
    super.drawInsertionPoint(in: flag ? caretRect(in: rect) : widenedForCaret(rect), color: color, turnedOn: flag)
  }

  // 글자를 고치면 NSTextView는 본문 칸 안만 다시 그리게 한다. 번호 칸은 그 왼쪽 여백이라, 줄이 밀려 내려가도
  // 옛 번호가 남는다. 줄 번호를 켰을 때만 다시 그릴 곳을 왼쪽 끝까지 넓힌다(본문 칸은 그대로라 비용은 여백 조금).
  // 커서 자국을 막으려고 가는 칸은 커서 두께만큼 넓힌다(`InsertionCaret.swift`).
  override func setNeedsDisplay(_ invalidRect: NSRect) {
    let rect = widenedForCaret(invalidRect)
    super.setNeedsDisplay(showsLineNumbers ? widenedToGutter(rect) : rect)
  }

  override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
    let rect = widenedForCaret(rect)
    super.setNeedsDisplay(showsLineNumbers ? widenedToGutter(rect) : rect, avoidAdditionalLayout: flag)
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
    if hasMarkedText() { unmarkText() }
    textStorage?.setAttributedString(NSAttributedString(string: text, attributes: style.textAttributes))
    setSelectedRange(NSRange(location: 0, length: 0))
    episodeUndoManager.removeAllActions()
    scroll(.zero)
  }

  /// 스냅샷으로 되돌리기(11e): 본문 전체를 실행 취소 한 단위로 바꾼다. 회차 전환과 달리 기록을 비우지 않아 ⌘Z 한 번으로 돌아간다.
  /// 바꿨으면 true. 커서는 같은 자리(본문이 짧아졌으면 끝)에 둔다.
  func replaceAllUndoably(with text: String, actionName: String) -> Bool {
    finishComposition()
    let full = NSRange(location: 0, length: (string as NSString).length)
    guard string != text else { return false }
    let cursor = selectedRange().location
    let undo = episodeUndoManager
    undo.beginUndoGrouping()
    defer { undo.endUndoGrouping() }
    // shouldChangeText가 실행 취소 기록을 남기고, didChangeText가 바뀜 알림(자동 저장·글자 수)을 보낸다.
    guard shouldChangeText(in: full, replacementString: text) else { return false }
    textStorage?.replaceCharacters(in: full, with: NSAttributedString(string: text, attributes: style.textAttributes))
    didChangeText()
    undo.setActionName(actionName)
    setSelectedRange(NSRange(location: min(cursor, (text as NSString).length), length: 0))
    scrollRangeToVisible(selectedRange())
    return true
  }

  /// 앱 밖에서 바뀐 본문으로 갈아 끼운다(8단계). 회차 전환과 달리 커서와 스크롤 위치를 되도록 그대로 둔다.
  /// 실행 취소 기록은 비운다: 옛 본문 기준의 기록을 새 본문에 적용하면 엉뚱한 곳이 바뀐다.
  func reloadText(with text: String) {
    if hasMarkedText() { unmarkText() }
    let cursor = selectedRange().location
    let origin = enclosingScrollView?.contentView.bounds.origin ?? .zero
    textStorage?.setAttributedString(NSAttributedString(string: text, attributes: style.textAttributes))
    setSelectedRange(NSRange(location: min(cursor, (text as NSString).length), length: 0))
    episodeUndoManager.removeAllActions()
    scroll(origin)
  }

  override var undoManager: UndoManager? { episodeUndoManager }

  // 편집 메뉴의 실행 취소(⌘Z)·다시 실행(⇧⌘Z)은 처리하는 곳을 응답 사슬에서 찾는데, 편집기가 받지 않으면 창까지 올라가
  // 창의 기록(사이드바 회차 작업)을 쓴다. 입력은 회차 기록(`episodeUndoManager`)에 쌓이므로 여기서 직접 받는다(2026-11-12 사용자 지적).
  @objc func undo(_ sender: Any?) {
    finishComposition()
    episodeUndoManager.undo()
  }

  @objc func redo(_ sender: Any?) {
    finishComposition()
    episodeUndoManager.redo()
  }

  /// 되돌리기 단위를 한 글자로 한다(2026-11-12 사용자 요청). NSTextView는 이어서 친 글자를 한 묶음으로 합쳐
  /// ⌘Z 한 번에 문장째 지우므로, 고칠 때마다 묶음을 끊는다. 조합 중에는 끊지 않아 조합이 끝난 한 글자("한")가 한 단위가 된다.
  override func didChangeText() {
    super.didChangeText()
    guard !hasMarkedText() else { return }
    breakUndoCoalescing()
    if needsRestyle { applyStyle() }
  }

  /// 조합 중인 글자를 확정한다. 조합 중에 되돌리면 입력기와 텍스트 저장소가 서로 다른 글자를 가리켜 깨질 수 있다.
  private func finishComposition() {
    guard hasMarkedText() else { return }
    unmarkText()
    inputContext?.discardMarkedText()
  }

  /// 떠 있는 판(⇧⌘S)을 열기 전: 조합을 끝내고 키보드 초점을 내려놓는다. 커서·선택은 그대로 남는다.
  /// 판을 열 때 편집기가 초점을 갖고 있었는지 돌려준다(닫을 때 돌려줄지 정하려고).
  func yieldFocusForPanel() -> Bool {
    finishComposition()
    guard let window, window.firstResponder === self else { return false }
    window.makeFirstResponder(nil)
    return true
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

  // MARK: - 폭과 여백

  /// NSTextView는 텍스트 칸 오른쪽 끝보다 오른쪽 점을 자기 것으로 보지 않아, 오른쪽 여백 클릭이 뒤의 clip view로 가서
  /// 커서가 움직이지 않았다(2026-11-18 실제 클릭 기록으로 확인). 본문 폭을 고정해 오른쪽 여백이 넓으므로 편집기 안이면 직접 받는다.
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
