import SwiftUI

/// Body font choices (SPEC ch.5). The two system fonts ship with macOS.
enum BodyFont: String, CaseIterable {
  case pretendard
  case appleSDGothicNeo
  case appleMyungjo

  var title: String {
    switch self {
    case .pretendard: "Pretendard"
    case .appleSDGothicNeo: "Apple SD 산돌고딕 Neo"
    case .appleMyungjo: "AppleMyungjo"
    }
  }

  var postScriptName: String {
    switch self {
    case .pretendard: "Pretendard-Regular"
    case .appleSDGothicNeo: "AppleSDGothicNeo-Regular"
    case .appleMyungjo: "AppleMyungjo"
    }
  }
}

/// Default, range and step of one numeric editor setting (DESIGN.md ch.3).
struct EditorSetting {
  let defaultValue: Double
  let range: ClosedRange<Double>
  let step: Double

  static let fontSize = EditorSetting(defaultValue: 17, range: 13...24, step: 1)
  static let lineSpacing = EditorSetting(defaultValue: 1.75, range: 1.4...2.2, step: 0.05)
  static let paragraphSpacing = EditorSetting(defaultValue: 0.6, range: 0...1.5, step: 0.1)
  static let lineWidthInCharacters = EditorSetting(defaultValue: 40, range: 30...55, step: 1)
  /// Character count refresh interval (s). 0 = live
  static let characterCountInterval = EditorSetting(defaultValue: 0.2, range: 0...0.3, step: 0.1)
  /// Caret width (pt) and height (multiple of font size). Width is a number field, so capped at 4.
  static let caretWidth = EditorSetting(defaultValue: 2, range: 1...4, step: 0.5)
  static let caretHeightRatio = EditorSetting(defaultValue: 1.2, range: 1...1.75, step: 0.05)
  /// How long a toast stays (s). Not an editor setting, but kept here to reuse the same slider/snapping rules.
  static let toastDuration = EditorSetting(defaultValue: 2, range: 0.5...5, step: 0.5)

  /// Snap a stored value to a usable one. Users can also change UserDefaults from Terminal (`defaults write`),
  /// so out-of-range or off-step values can arrive.
  /// Not a number → default; out of range → nearest end; otherwise snap to the nearest step.
  func clamped(_ value: Double) -> Double {
    guard value.isFinite else { return defaultValue }
    let bounded = min(max(value, range.lowerBound), range.upperBound)
    let steps = ((bounded - range.lowerBound) / step).rounded()
    // Rounded at two decimals so steps not exact in binary (like 0.05) don't leave values like 1.7500000001.
    let snapped = ((range.lowerBound + steps * step) * 100).rounded() / 100
    return min(snapped, range.upperBound)
  }
}

extension EditorStyle {
  /// Build the editor style from settings. Values are clamped into range once more here.
  init(font: BodyFont, fontSize: Double, lineSpacing: Double, paragraphSpacing: Double, lineWidthInCharacters: Double) {
    self.init()
    fontName = font.postScriptName
    self.fontSize = EditorSetting.fontSize.clamped(fontSize)
    self.lineSpacing = EditorSetting.lineSpacing.clamped(lineSpacing)
    self.paragraphSpacing = EditorSetting.paragraphSpacing.clamped(paragraphSpacing)
    self.lineWidthInCharacters = EditorSetting.lineWidthInCharacters.clamped(lineWidthInCharacters)
  }
}

/// Reads editor style settings (UserDefaults) together, so the editor and Settings window share keys and defaults.
/// Views holding this redraw when a value changes.
struct EditorStyleSettings: DynamicProperty {
  @AppStorage(AppSettingKey.bodyFont) var font: BodyFont = .pretendard
  @AppStorage(AppSettingKey.fontSize) var fontSize = EditorSetting.fontSize.defaultValue
  @AppStorage(AppSettingKey.lineSpacing) var lineSpacing = EditorSetting.lineSpacing.defaultValue
  @AppStorage(AppSettingKey.paragraphSpacing) var paragraphSpacing = EditorSetting.paragraphSpacing.defaultValue
  @AppStorage(AppSettingKey.lineWidthInCharacters) var lineWidthInCharacters = EditorSetting.lineWidthInCharacters.defaultValue

  var style: EditorStyle {
    EditorStyle(
      font: font, fontSize: fontSize, lineSpacing: lineSpacing,
      paragraphSpacing: paragraphSpacing, lineWidthInCharacters: lineWidthInCharacters)
  }
}
