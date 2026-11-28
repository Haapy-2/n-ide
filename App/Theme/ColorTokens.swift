import SwiftUI

/// Color tokens (docs/DESIGN.md ch.1). Light/dark values live only in Resources/Colors.xcassets.
/// Code must not use color values directly, only these names.
extension Color {
  static let paper = Color("paper")
  static let ink = Color("ink")
  static let inkMuted = Color("inkMuted")
  static let sidebarFallback = Color("sidebar")
  static let rule = Color("rule")
  static let error = Color("error")
  static let accent = Color("accent")
  /// Diff view: inserted-line background, its changed part, the bar left of the line (PLAN ch.10 #5)
  static let diffAdded = Color("diffAdded")
  static let diffAddedStrong = Color("diffAddedStrong")
  static let diffAddedMark = Color("diffAddedMark")
  /// Diff view: deleted-line background, its changed part (left hatching uses the error color)
  static let diffRemoved = Color("diffRemoved")
  static let diffRemovedStrong = Color("diffRemovedStrong")
  /// Scrim dimming the area behind the floating panel
  static let scrim = Color("scrim")
  /// Caret palette (Settings › Caret). Three extra choices besides default blue (accent) and ink
  static let caretRed = Color("caretRed")
  static let caretGreen = Color("caretGreen")
  static let caretOrange = Color("caretOrange")
}
