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
  /// 비교 화면: 넣은 줄 바탕, 그 안의 바뀐 부분, 줄 왼쪽 막대 (PLAN 10장 5번)
  static let diffAdded = Color("diffAdded")
  static let diffAddedStrong = Color("diffAddedStrong")
  static let diffAddedMark = Color("diffAddedMark")
  /// 비교 화면: 지운 줄 바탕, 그 안의 바뀐 부분 (왼쪽 빗금은 error 색)
  static let diffRemoved = Color("diffRemoved")
  static let diffRemovedStrong = Color("diffRemovedStrong")
  /// 떠 있는 판 뒤를 어둡게 덮는 막
  static let scrim = Color("scrim")
  /// 커서 팔레트(설정 › 커서). 기본 파랑(accent)·먹색(ink) 말고 더 고를 수 있는 세 가지
  static let caretRed = Color("caretRed")
  static let caretGreen = Color("caretGreen")
  static let caretOrange = Color("caretOrange")
}
