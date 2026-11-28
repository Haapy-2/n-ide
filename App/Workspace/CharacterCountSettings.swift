import NovelCore

/// How the status bar shows counts (PLAN decision 3). Chosen in Settings.
enum CharacterCountDisplay: String, CaseIterable {
  case both
  case withSpaces
  case withoutSpaces

  var title: String {
    switch self {
    case .both: "둘 다"
    case .withSpaces: "공백 포함"
    case .withoutSpaces: "공백 제외"
    }
  }

  /// Status bar left text. E.g. `1,204자 · 공백 제외 987자`
  func text(for count: CharacterCount) -> String {
    let with = "\(count.withSpaces.formatted())자"
    let without = "공백 제외 \(count.withoutSpaces.formatted())자"
    switch self {
    case .both: return "\(with) · \(without)"
    case .withSpaces: return with
    case .withoutSpaces: return without
    }
  }
}

/// Shape of the status bar goal progress. Chosen in Settings.
enum GoalProgressStyle: String, CaseIterable {
  /// Ring with a hollow center
  case ring
  /// Circle filling to the center
  case pie
  case bar

  var title: String {
    switch self {
    case .ring: "원(고리)"
    case .pie: "원(꽉 찬)"
    case .bar: "막대"
    }
  }
}

extension CharacterCountBasis {
  var title: String {
    switch self {
    case .withSpaces: "공백 포함"
    case .withoutSpaces: "공백 제외"
    }
  }
}
