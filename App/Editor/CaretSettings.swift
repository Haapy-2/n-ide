import AppKit
import SwiftUI

/// 커서 팔레트: 미리 정한 색 다섯 개. 값은 Colors.xcassets에 라이트/다크 한 쌍씩.
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

/// 커서 색 하나: 팔레트 색이거나, 컬러 피커로 고른 sRGB 색.
enum CaretColor: Equatable {
  case palette(CaretPalette)
  case custom(red: Double, green: Double, blue: Double)

  static let standard = CaretColor.palette(.accent)

  /// UserDefaults에 넣는 글자: 팔레트는 이름, 고른 색은 "#RRGGBB". 빈 글자·알 수 없는 글자는 기본(accent).
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

  /// 컬러 피커에서 받은 색. sRGB로 바꿀 수 없는 색(무늬 등)은 nil.
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

  /// SwiftUI 색. 팔레트 색은 보는 모드(라이트/다크)에 따라 저절로 바뀐다.
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

/// 편집기 커서의 두께·높이·색. 색은 라이트/다크를 따로 고른다.
struct CaretStyle: Equatable {
  var width: CGFloat = EditorSetting.caretWidth.defaultValue
  var heightRatio: CGFloat = EditorSetting.caretHeightRatio.defaultValue
  var lightColor = CaretColor.standard
  var darkColor = CaretColor.standard

  /// 편집기에 넣는 색. 창의 모양(라이트/다크)에 따라 둘 중 하나로 그려진다.
  var dynamicColor: NSColor {
    let light = lightColor.nsColor(dark: false)
    let dark = darkColor.nsColor(dark: true)
    return NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    }
  }
}

/// 커서 설정(UserDefaults)을 한데 읽는다. 편집 영역과 설정 창이 같은 키·기본값을 쓰게 하려고 묶었다.
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

  /// "기본값으로": 커서 설정 네 개만 처음 값으로.
  func reset() {
    width = EditorSetting.caretWidth.defaultValue
    heightRatio = EditorSetting.caretHeightRatio.defaultValue
    lightColorText = ""
    darkColorText = ""
  }
}
