import Foundation

/// 앱 전체 설정(UserDefaults)의 키 이름. 설정 창(10단계)과 화면이 같은 이름을 쓰도록 여기 모은다.
enum AppSettingKey {
  /// 사이드바 뒤로 다른 앱·바탕화면이 흐릿하게 비치는 효과 (기본: 켬)
  static let sidebarSeesThroughWindow = "sidebarSeesThroughWindow"
  /// 상태 줄의 글자 수 표시 방식 `CharacterCountDisplay` (기본: 둘 다)
  static let characterCountDisplay = "characterCountDisplay"
  /// 목표 진행률과 사이드바 글자 수의 기준 `CharacterCountBasis` (기본: 공백 포함)
  static let characterCountGoalBasis = "characterCountGoalBasis"
  /// 상태 줄의 목표 진행률 모양 `GoalProgressStyle` (기본: 원형)
  static let goalProgressStyle = "goalProgressStyle"
}
