import Foundation

/// 사이드바에서 ⌘Z·⇧⌘Z로 회차 작업(새 회차, 이름 변경, 순서 변경, 휴지통, 목표 글자 수)을 되돌리기 전에 묻는 창(2026-11-12 사용자 요청).
/// 창의 "다시 묻지 않기"를 고르면 설정의 기간 동안 묻지 않고 바로 되돌린다.
enum UndoConfirmPause: String, CaseIterable {
  case day
  case threeDays
  case week
  case month
  case forever

  /// 설정 창 "확인 창 다시 띄우기"에 보이는 이름
  var title: String {
    switch self {
    case .day: "하루 뒤"
    case .threeDays: "3일 뒤"
    case .week: "일주일 뒤"
    case .month: "한 달 뒤"
    case .forever: "띄우지 않기"
    }
  }

  /// `now`부터 쉬는 끝 시각. 계속 쉬면 `.distantFuture`.
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

/// 확인 창이 쉬는지 판단하고 쉬게 하거나 다시 묻게 한다. 값은 UserDefaults(앱 전체 설정)에 둔다.
enum UndoConfirmation {
  static func isPaused(now: Date = .now, defaults: UserDefaults = .standard) -> Bool {
    let until = defaults.double(forKey: AppSettingKey.undoConfirmPausedUntil)
    return until > now.timeIntervalSince1970
  }

  /// "다시 묻지 않기"를 고르고 되돌렸을 때. 기간은 설정 값(기본 일주일).
  static func pause(now: Date = .now, defaults: UserDefaults = .standard) {
    let pause = defaults.string(forKey: AppSettingKey.undoConfirmPause).flatMap(UndoConfirmPause.init) ?? .week
    defaults.set(pause.end(from: now).timeIntervalSince1970, forKey: AppSettingKey.undoConfirmPausedUntil)
  }

  /// 설정 창의 "지금부터 다시 묻기"
  static func resume(defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: AppSettingKey.undoConfirmPausedUntil)
  }
}
