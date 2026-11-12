import Foundation

/// 회차 하나의 글자 수 (SPEC 7장 3번). 글자는 `Character`(화면에 보이는 글자) 단위로 센다.
/// - 공백 포함: 줄바꿈만 빼고 모두.
/// - 공백 제외: 공백·탭·줄바꿈 등 빈칸 문자를 모두 뺀다(전각 공백도 뺀다).
public struct CharacterCount: Codable, Equatable, Hashable, Sendable {
  public var withSpaces: Int
  public var withoutSpaces: Int

  public init(withSpaces: Int, withoutSpaces: Int) {
    self.withSpaces = withSpaces
    self.withoutSpaces = withoutSpaces
  }

  public static let zero = CharacterCount(withSpaces: 0, withoutSpaces: 0)

  /// 본문 전체를 한 번 훑어 센다. 메인 스레드가 아닌 곳에서 부른다.
  public init(counting text: String) {
    // 편집기에서 꺼낸 문자열은 UTF-16 NSString을 감싼 것이라 글자 단위로 훑기가 느리다.
    // Swift 문자열로 한 번 바꾼 뒤 세면 10만 자 기준 20ms → 10ms (Swift 문자열이면 아무 일도 안 한다).
    var text = text
    text.makeContiguousUTF8()
    var withSpaces = 0
    var withoutSpaces = 0
    for character in text {
      if character.isNewline { continue }
      withSpaces += 1
      if !character.isWhitespace { withoutSpaces += 1 }
    }
    self.init(withSpaces: withSpaces, withoutSpaces: withoutSpaces)
  }

  /// 목표 진행률에 쓰는 값.
  public func value(for basis: CharacterCountBasis) -> Int {
    switch basis {
    case .withSpaces: withSpaces
    case .withoutSpaces: withoutSpaces
    }
  }
}

/// 목표 진행률과 사이드바 글자 수의 기준 (PLAN 결정 사항 3).
public enum CharacterCountBasis: String, CaseIterable, Sendable {
  case withSpaces
  case withoutSpaces
}
