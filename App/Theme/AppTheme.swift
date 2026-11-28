/// App theme. Order is the order in Settings.
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

  /// SF Symbols names for the Settings segments. Drawn uncolored in the system secondary text color.
  var symbolName: String {
    switch self {
    case .dark: "moon"
    case .system: "desktopcomputer"
    case .light: "sun.max"
    }
  }
}
