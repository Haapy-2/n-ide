/// 앱 화면 테마 (설정 창 "화면", 2026-11-12 사용자 요청). 순서는 설정 창에 놓이는 순서다.
enum AppTheme: String, CaseIterable {
  case dark
  case system
  case light

  var title: String {
    switch self {
    case .dark: "다크"
    case .system: "기기 설정"
    case .light: "라이트"
    }
  }

  /// 설정 창 세그먼트의 SF Symbols 이름. 색 없이 시스템 보조 글자색으로 그린다.
  var symbolName: String {
    switch self {
    case .dark: "moon"
    case .system: "desktopcomputer"
    case .light: "sun.max"
    }
  }
}
