import AppKit

/// 빈 회차 본문에 흐린 안내 글을 그린다. 텍스트 저장소에는 넣지 않아(본문이 원본) 글자 수·저장·조합과 상관없다.
/// 조합을 시작하면 조합 중인 글자가 저장소에 들어가 길이가 0이 아니게 되므로 그때 바로 사라진다.
extension ManuscriptTextView {
  static let placeholderText = "첫 문장을 써 주세요."

  func drawPlaceholder() {
    guard textStorage?.length == 0, let textContainer else { return }
    let origin = NSPoint(
      x: textContainerOrigin.x + textContainer.lineFragmentPadding,
      y: textContainerOrigin.y + emptyLineBaselineFromTop)
    let attributes: [NSAttributedString.Key: Any] = [.font: style.font, .foregroundColor: NSColor.inkMuted]
    // 줄 조각 기준을 빼면 origin이 기준선 자리가 된다(본문 첫 줄 글자와 같은 높이).
    (Self.placeholderText as NSString).draw(
      with: NSRect(origin: origin, size: NSSize(width: style.textWidth, height: style.lineHeight)),
      options: [], attributes: attributes)
  }

  /// 비었다 ↔ 글이 있다가 바뀔 때만 첫 줄을 다시 그린다.
  func updatePlaceholderIfNeeded() {
    let isEmpty = textStorage?.length == 0
    guard isEmpty != placeholderShown else { return }
    placeholderShown = isEmpty
    setNeedsDisplay(NSRect(
      x: 0, y: textContainerOrigin.y, width: bounds.width, height: style.lineHeight * 2))
  }
}
