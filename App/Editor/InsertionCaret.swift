import AppKit

/// 커서 높이를 글자 크기의 1.2배로(2026-11-18 사용자 요청, DESIGN 3장 "커서").
/// 줄 높이를 글자 크기 × 줄 간격(기본 1.75)으로 고정해서, 그대로 두면 커서가 줄 높이만큼 길어 글자보다 훨씬 컸다.
/// 위치는 글자 몸통(올림~내림) 한가운데. 두께는 2pt(시스템 1pt는 글자 획보다 가늘어 잘 안 보임, 같은 날 사용자 요청). 색은 accent.
extension ManuscriptTextView {
  static let caretHeightRatio: CGFloat = 1.2
  static let caretWidth: CGFloat = 2

  /// 시스템이 준 커서 칸(`lineRect`: 줄 위에서 시작하는 줄 높이 칸)에서 실제로 그릴 칸.
  /// 줄 높이를 고정해서 기준선은 모든 줄에서 줄 위로부터 같은 거리라, 그 거리로 글자 몸통 가운데를 구한다.
  func caretRect(in lineRect: NSRect) -> NSRect {
    let font = style.font
    let height = (style.fontSize * Self.caretHeightRatio).rounded()
    let baseline = lineRect.minY + emptyLineBaselineFromTop
    // 뒤집힌 좌표(아래로 갈수록 커짐). 글자 몸통 = 기준선 − 올림 ~ 기준선 − 내림(내림은 음수).
    let center = baseline - (font.ascender + font.descender) / 2
    var rect = lineRect
    rect.size.width = Self.caretWidth
    rect.size.height = min(height, lineRect.height)
    rect.origin.y = (center - rect.height / 2).rounded()
    // 줄 칸 밖으로는 나가지 않게(아주 큰 글자·좁은 줄 간격).
    rect.origin.y = min(max(rect.minY, lineRect.minY), lineRect.maxY - rect.height)
    return rect
  }

  /// 시스템은 커서를 옮기거나 깜빡일 때 원래 굵기(1pt) 칸만 지운다. 2pt로 그리면 오른쪽 1pt가 남아 자국이 생기므로
  /// 커서처럼 가는 칸을 다시 그리라는 요청은 커서 두께 + 1pt까지 넓힌다. 다른 다시 그리기는 그대로.
  func widenedForCaret(_ rect: NSRect) -> NSRect {
    guard !rect.isEmpty, rect.width < Self.caretWidth + 1 else { return rect }
    var wide = rect
    wide.size.width = Self.caretWidth + 1
    return wide
  }
}
