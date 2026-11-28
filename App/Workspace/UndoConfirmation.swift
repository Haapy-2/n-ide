import Foundation

/// Dialog asking before ⌘Z/⇧⌘Z in the sidebar reverts episode actions (new episode, rename, reorder, trash, goal).
/// Choosing the dialog's "don't ask again" reverts immediately without asking for the configured period.
enum UndoConfirmPause: String, CaseIterable {
  case day
  case threeDays
  case week
  case month
  case forever

  /// Name shown in Settings "show confirmation again"
  var title: String {
    switch self {
    case .day: "하루 뒤"
    case .threeDays: "3일 뒤"
    case .week: "일주일 뒤"
    case .month: "한 달 뒤"
    case .forever: "띄우지 않기"
    }
  }

  /// End of the rest starting at `now`. `.distantFuture` for indefinitely.
  func end(from now: Date, calendar: Calendar = .current) -> Date {
    switch self {
    case .day: calendar.date(byAdding: .day, value: 1, to: now) ?? now
    case .threeDays: calendar.date(byAdding: .day, value: 3, to: now) ?? now
    case .week: calendar.date(byAdding: .day, value: 7, to: now) ?? now
    case .month: calendar.date(byAdding: .month, value: 1, to: now) ?? now
    case .forever: .distantFuture
    }
  }
}

/// Decides whether the confirmation is resting, and makes it rest or ask again. Stored in UserDefaults (app-wide setting).
enum UndoConfirmation {
  static func isPaused(now: Date = .now, defaults: UserDefaults = .standard) -> Bool {
    let until = defaults.double(forKey: AppSettingKey.undoConfirmPausedUntil)
    return until > now.timeIntervalSince1970
  }

  /// When reverting with "don't ask again" chosen. Duration is the setting value (default one week).
  static func pause(now: Date = .now, defaults: UserDefaults = .standard) {
    let pause = defaults.string(forKey: AppSettingKey.undoConfirmPause).flatMap(UndoConfirmPause.init) ?? .week
    defaults.set(pause.end(from: now).timeIntervalSince1970, forKey: AppSettingKey.undoConfirmPausedUntil)
  }

  /// Settings "ask again from now"
  static func resume(defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: AppSettingKey.undoConfirmPausedUntil)
  }
}
