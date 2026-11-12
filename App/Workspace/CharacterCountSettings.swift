import NovelCore

/// 상태 줄에 글자 수를 어떻게 보일지 (PLAN 결정 사항 3). 설정 창에서 고른다.
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

  /// 상태 줄 왼쪽 글자. 예: `1,204자 · 공백 제외 987자`
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

/// 상태 줄 목표 진행률의 모양. 설정 창에서 고른다(2026-11-12 사용자 요청).
enum GoalProgressStyle: String, CaseIterable {
  /// 가운데가 뚫린 고리
  case ring
  /// 가운데까지 채워지는 원(파이 모양, 2026-11-12 사용자 요청)
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
