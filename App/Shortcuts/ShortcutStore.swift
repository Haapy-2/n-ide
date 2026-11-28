import Foundation

/// App-wide shared shortcut settings. Changes go to UserDefaults and menus redraw immediately.
/// Menus, Settings and the snapshot panel read one value; writes are funneled here.
/// SwiftUI rebuilds menu items when a menu opens or a shortcut is pressed (not updating instantly is normal).
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
