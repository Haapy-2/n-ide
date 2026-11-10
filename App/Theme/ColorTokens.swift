import SwiftUI

/// 색 토큰 (docs/DESIGN.md 1장). 라이트/다크 값은 Resources/Colors.xcassets 한 곳에만 있다.
/// 코드에서는 색 값을 직접 쓰지 말고 이 이름만 쓴다.
extension Color {
  static let paper = Color("paper")
  static let ink = Color("ink")
  static let inkMuted = Color("inkMuted")
  static let sidebarFallback = Color("sidebar")
  static let rule = Color("rule")
  static let error = Color("error")
  static let accent = Color("accent")
}
