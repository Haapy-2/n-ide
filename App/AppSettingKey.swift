import Foundation

/// 앱 전체 설정(UserDefaults)의 키 이름. 설정 창과 화면이 같은 이름을 쓰도록 여기 모은다.
enum AppSettingKey {
  /// 사이드바 뒤로 다른 앱·바탕화면이 흐릿하게 비치는 효과 (기본: 켬)
  static let sidebarSeesThroughWindow = "sidebarSeesThroughWindow"
  /// 상태 줄의 글자 수 표시 방식 `CharacterCountDisplay` (기본: 둘 다)
  static let characterCountDisplay = "characterCountDisplay"
  /// 목표 진행률과 사이드바 글자 수의 기준 `CharacterCountBasis` (기본: 공백 포함)
  static let characterCountGoalBasis = "characterCountGoalBasis"
  /// 상태 줄의 목표 진행률 모양 `GoalProgressStyle` (기본: 원형)
  static let goalProgressStyle = "goalProgressStyle"
  /// 글자 수를 다시 세기까지 기다리는 초. 0이면 실시간 (기본: 0.2)
  static let characterCountInterval = "characterCountInterval"
  /// 타이핑 중 상태 줄 숨기기 (기본: 끔 = 계속 보이기)
  static let statusBarHidesWhileTyping = "statusBarHidesWhileTyping"
  /// 쉬고 있을 때 10초 뒤 상태 줄 숨기기 (기본: 켬)
  static let statusBarHidesWhenIdle = "statusBarHidesWhenIdle"
  /// 사이드바 회차 줄의 글자 수 보이기 (기본: 켬)
  static let sidebarShowsCharacterCount = "sidebarShowsCharacterCount"
  /// 앱 화면 테마 `AppTheme` (기본: 기기 설정)
  static let appTheme = "appTheme"
  /// 사이드바 되돌리기 확인 창을 "다시 묻지 않기" 뒤 쉬게 하는 기간 `UndoConfirmPause` (기본: 일주일)
  static let undoConfirmPause = "undoConfirmPause"
  /// 사이드바 되돌리기 확인 창이 쉬는 끝 시각(1970 기준 초). 없으면 매번 묻는다.
  static let undoConfirmPausedUntil = "undoConfirmPausedUntil"
  /// 토스트(편집 영역 오른쪽 위 알림)가 머무는 초. 0.5~5, 0.5 단위 (기본: 2)
  static let toastDuration = "toastDuration"
  /// 자동 스냅샷 켜기 (기본: 켬). 꺼도 회차를 떠날 때와 직접 찍기는 그대로
  static let autoSnapshotEnabled = "autoSnapshotEnabled"
  /// 자동 스냅샷 간격, 분. 5·10·15·30·60 중 하나 (기본: 30)
  static let autoSnapshotMinutes = "autoSnapshotMinutes"
  /// 회차마다 남길 자동·떠날 때 스냅샷 개수. 10~100, 10 단위 (기본: 50)
  static let snapshotRetention = "snapshotRetention"
  /// 사용자가 바꾼 단축키 `ShortcutSettings.storageText` (기본: 빈 문자열 = 모두 기본값)
  static let shortcuts = "shortcuts"
  /// 본문 글꼴 `BodyFont` (기본: Pretendard)
  static let bodyFont = "bodyFont"
  /// 글자 크기 pt (기본: 17)
  static let fontSize = "fontSize"
  /// 줄 간격 배수 (기본: 1.75)
  static let lineSpacing = "lineSpacing"
  /// 문단 간격, 줄 단위 (기본: 0.6)
  static let paragraphSpacing = "paragraphSpacing"
  /// 본문 폭, 한 줄에 들어가는 한글 글자 수 (기본: 40)
  static let lineWidthInCharacters = "lineWidthInCharacters"
  /// 편집기 왼쪽 여백에 줄 번호 (기본: 끔, 11f)
  static let showsLineNumbers = "showsLineNumbers"
  /// 커서 두께 pt. 1~4, 0.5 단위 (기본: 2)
  static let caretWidth = "caretWidth"
  /// 커서 높이, 글자 크기의 배수. 1.0~1.75 (기본: 1.2)
  static let caretHeightRatio = "caretHeightRatio"
  /// 라이트 모드 커서 색 `CaretColor.storageText` (기본: 빈 문자열 = accent)
  static let caretColorLight = "caretColorLight"
  /// 다크 모드 커서 색 `CaretColor.storageText` (기본: 빈 문자열 = accent)
  static let caretColorDark = "caretColorDark"
  /// 사이드바에서 접어 둔 회차 묶음(GroupID를 쉼표로 이음). 이 맥에만 기억한다(2026-11-20 사용자 결정, project.json에 안 씀).
  static let collapsedEpisodeGroups = "collapsedEpisodeGroups"
}
