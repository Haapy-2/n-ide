import AppKit
import SwiftUI

/// Caret palette: five preset colors. Values live in Colors.xcassets as light/dark pairs.
enum CaretPalette: String, CaseIterable {
  case accent, ink, caretRed, caretGreen, caretOrange

  var title: String {
    switch self {
    case .accent: "기본 파랑"
    case .ink: "먹색"
    case .caretRed: "빨강"
    case .caretGreen: "초록"
    case .caretOrange: "주황"
    }
  }

  var color: Color {
    switch self {
    case .accent: .accent
    case .ink: .ink
    case .caretRed: .caretRed
    case .caretGreen: .caretGreen
    case .caretOrange: .caretOrange
    }
  }
}

/// One caret color: a palette color or an sRGB color picked in the color picker.
enum CaretColor: Equatable {
  case palette(CaretPalette)
  case custom(red: Double, green: Double, blue: Double)

  static let standard = CaretColor.palette(.accent)

  /// Text stored in UserDefaults: palette name, or "#RRGGBB" for picked colors. Empty/unknown text means default (accent).
  init(storageText: String) {
    if let palette = CaretPalette(rawValue: storageText) {
      self = .palette(palette)
    } else if storageText.count == 7, storageText.hasPrefix("#"), let value = Int(storageText.dropFirst(), radix: 16) {
      self = .custom(
        red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    } else {
      self = .standard
    }
  }

  /// Color from the color picker. nil for colors that can't convert to sRGB (patterns etc.).
  init?(picked color: Color) {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
    self = .custom(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
  }

  var storageText: String {
    switch self {
    case .palette(let palette):
      return palette == .accent ? "" : palette.rawValue
    case .custom(let red, let green, let blue):
      let byte = { (value: Double) in Int((min(max(value, 0), 1) * 255).rounded()) }
      return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
  }

  /// SwiftUI color. Palette colors follow the current appearance (light/dark) automatically.
  var color: Color {
    switch self {
    case .palette(let palette): palette.color
    case .custom(let red, let green, let blue): Color(.sRGB, red: red, green: green, blue: blue)
    }
  }

  func nsColor(dark: Bool) -> NSColor {
    switch self {
    case .palette(let palette):
      let named = NSColor(named: palette.rawValue) ?? .accentToken
      var resolved = named
      NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
        resolved = named.usingColorSpace(.sRGB) ?? named
      }
      return resolved
    case .custom(let red, let green, let blue):
      return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
  }
}

/// Editor caret width, height and color. Colors are chosen separately for light and dark.
struct CaretStyle: Equatable {
  var width: CGFloat = EditorSetting.caretWidth.defaultValue
  var heightRatio: CGFloat = EditorSetting.caretHeightRatio.defaultValue
  var lightColor = CaretColor.standard
  var darkColor = CaretColor.standard

  /// Color handed to the editor. Drawn as one of the two depending on the window's appearance.
  var dynamicColor: NSColor {
    let light = lightColor.nsColor(dark: false)
    let dark = darkColor.nsColor(dark: true)
    return NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    }
  }
}

/// Reads caret settings (UserDefaults) together, so the editor and Settings window share keys and defaults.
struct CaretStyleSettings: DynamicProperty {
  @AppStorage(AppSettingKey.caretWidth) var width = EditorSetting.caretWidth.defaultValue
  @AppStorage(AppSettingKey.caretHeightRatio) var heightRatio = EditorSetting.caretHeightRatio.defaultValue
  @AppStorage(AppSettingKey.caretColorLight) var lightColorText = ""
  @AppStorage(AppSettingKey.caretColorDark) var darkColorText = ""

  var style: CaretStyle {
    CaretStyle(
      width: EditorSetting.caretWidth.clamped(width),
      heightRatio: EditorSetting.caretHeightRatio.clamped(heightRatio),
      lightColor: CaretColor(storageText: lightColorText),
      darkColor: CaretColor(storageText: darkColorText))
  }

  /// "Restore defaults": resets only the four caret settings.
  func reset() {
    width = EditorSetting.caretWidth.defaultValue
    heightRatio = EditorSetting.caretHeightRatio.defaultValue
    lightColorText = ""
    darkColorText = ""
  }
}
