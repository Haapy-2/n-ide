import AppKit

/// 편집기(AppKit)에서 쓰는 색 토큰. 값은 Resources/Colors.xcassets에 있다.
extension NSColor {
  static let paper = NSColor(named: "paper")!
  static let ink = NSColor(named: "ink")!
  static let accentToken = NSColor(named: "accent")!

  /// 선택 영역: accent를 라이트 18%, 다크 28%로 (DESIGN.md 1장).
  static let selectionToken = NSColor(name: nil) { appearance in
    let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    return NSColor(named: "accent")!.withAlphaComponent(dark ? 0.28 : 0.18)
  }
}
