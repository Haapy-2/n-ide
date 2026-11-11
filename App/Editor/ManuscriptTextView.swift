import AppKit

/// 원고 편집용 NSTextView. TextKit 1을 명시적으로 쓴다(SPEC 3장).
/// 본문 폭을 고정하고 창이 넓으면 가운데 두며, 마지막 줄을 화면 가운데까지 올려 쓸 수 있게 아래 여백을 둔다.
final class ManuscriptTextView: NSTextView {
  var style = EditorStyle() {
    didSet { if style != oldValue { applyStyle() } }
  }

  /// 회차마다 따로 쓰는 실행 취소 기록. 회차를 바꾸면 비운다(PLAN.md 세부 기준).
  let episodeUndoManager = UndoManager()

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
  }

  private func applyStyle() {
    let attributes = style.textAttributes
    typingAttributes = attributes
    defaultParagraphStyle = style.paragraphStyle
    // 조합 중에는 텍스트 저장소를 건드리지 않는다(한글 입력 보호). 조합이 끝난 뒤 다음 변경 때 다시 적용된다.
    if !hasMarkedText(), let storage = textStorage, storage.length > 0 {
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

  // MARK: - 폭과 여백

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
