import AppKit

/// 빈 줄(줄바꿈만 있는 문단)에는 문단 간격을 붙이지 않는다(DESIGN.md 3장).
/// 웹소설은 빈 줄로 문단을 나누는데, 빈 줄에도 붙이면 문단 사이가 "글 줄 뒤 간격 + 빈 줄 + 빈 줄 뒤 간격"으로 너무 벌어진다.
/// 저장소의 문단 속성은 그대로 두고 배치할 때 줄 칸만 줄여서, 한글 조합 중에도 저장소를 건드리지 않는다.
final class BlankLineSpacing: NSObject, NSLayoutManagerDelegate {
  func layoutManager(
    _ layoutManager: NSLayoutManager,
    shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
    lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
    baselineOffset: UnsafeMutablePointer<CGFloat>,
    in textContainer: NSTextContainer,
    forGlyphRange glyphRange: NSRange
  ) -> Bool {
    guard let storage = layoutManager.textStorage else { return false }
    let range = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    guard range.length == 1 else { return false }
    let text = storage.string as NSString
    let newline: unichar = 0x0A
    guard text.character(at: range.location) == newline,
      range.location == 0 || text.character(at: range.location - 1) == newline
    else { return false }
    // 쓴 칸(줄 높이)보다 긴 부분이 문단 간격이다.
    guard lineFragmentRect.pointee.height > lineFragmentUsedRect.pointee.height else { return false }
    lineFragmentRect.pointee.size.height = lineFragmentUsedRect.pointee.height
    return true
  }
}
