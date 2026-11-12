import SwiftUI

/// 본문 글꼴 선택지 (SPEC 5장). 시스템 글꼴 둘은 macOS에 기본으로 들어 있다.
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

/// 숫자로 고르는 편집기 설정 하나의 기본값·범위·단위 (DESIGN.md 3장).
struct EditorSetting {
  let defaultValue: Double
  let range: ClosedRange<Double>
  let step: Double

  static let fontSize = EditorSetting(defaultValue: 17, range: 13...24, step: 1)
  static let lineSpacing = EditorSetting(defaultValue: 1.75, range: 1.4...2.2, step: 0.05)
  static let paragraphSpacing = EditorSetting(defaultValue: 0.6, range: 0...1.5, step: 0.1)
  static let lineWidthInCharacters = EditorSetting(defaultValue: 40, range: 30...55, step: 1)

  /// 저장된 값을 쓸 수 있는 값으로 맞춘다. UserDefaults는 사용자가 터미널(`defaults write`)로도 바꿀 수 있어서
  /// 범위 밖이나 단위에 안 맞는 값이 들어올 수 있다.
  /// 숫자가 아니면 기본값, 범위 밖이면 가까운 끝값, 그 사이면 가까운 단위로 붙인다.
  func clamped(_ value: Double) -> Double {
    guard value.isFinite else { return defaultValue }
    let bounded = min(max(value, range.lowerBound), range.upperBound)
    let steps = ((bounded - range.lowerBound) / step).rounded()
    // 0.05처럼 2진수로 딱 떨어지지 않는 단위가 1.7500000001처럼 남지 않게 소수 둘째 자리에서 정리한다.
    let snapped = ((range.lowerBound + steps * step) * 100).rounded() / 100
    return min(snapped, range.upperBound)
  }
}

extension EditorStyle {
  /// 설정 값으로 편집 영역 모양을 만든다. 값은 여기서 한 번 더 범위 안으로 맞춘다.
  init(font: BodyFont, fontSize: Double, lineSpacing: Double, paragraphSpacing: Double, lineWidthInCharacters: Double) {
    self.init()
    fontName = font.postScriptName
    self.fontSize = EditorSetting.fontSize.clamped(fontSize)
    self.lineSpacing = EditorSetting.lineSpacing.clamped(lineSpacing)
    self.paragraphSpacing = EditorSetting.paragraphSpacing.clamped(paragraphSpacing)
    self.lineWidthInCharacters = EditorSetting.lineWidthInCharacters.clamped(lineWidthInCharacters)
  }
}

/// 편집기 모양 설정(UserDefaults)을 한데 읽는다. 편집 영역과 설정 창이 같은 키·기본값을 쓰게 하려고 묶었다.
/// 값이 바뀌면 이것을 가진 화면이 다시 그려진다.
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
