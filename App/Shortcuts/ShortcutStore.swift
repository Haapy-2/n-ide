import Foundation

/// 앱 전체가 함께 보는 단축키 설정. 바꾸면 UserDefaults에 남기고 메뉴가 바로 다시 그려진다.
/// 메뉴·설정 창·스냅샷 판이 같은 값 하나를 읽고, 쓰기는 여기 한 곳으로 모은다.
/// 메뉴 항목은 메뉴를 열거나 단축키를 누를 때 SwiftUI가 다시 만든다(바로 바뀌지 않아도 정상).
@Observable
final class ShortcutStore {
  static let shared = ShortcutStore()

  private(set) var settings: ShortcutSettings
  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    settings = ShortcutSettings(storageText: defaults.string(forKey: AppSettingKey.shortcuts) ?? "")
  }

  func update(_ change: (inout ShortcutSettings) -> Void) {
    var copy = settings
    change(&copy)
    guard copy != settings else { return }
    settings = copy
    defaults.set(copy.storageText, forKey: AppSettingKey.shortcuts)
  }
}
