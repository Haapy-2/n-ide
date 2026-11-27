import Foundation

/// 앞말의 받침에 따라 조사를 고른다("검을", "도윤으로"). 받침을 알 수 없는 말(영문 등)은 "을(를)"처럼 둘 다 적는다.
public enum KoreanParticle {
  case objectMarker
  case subjectMarker
  case topicMarker
  case direction

  /// `word` 뒤에 조사를 붙인 문자열.
  public static func attach(_ particle: KoreanParticle, to word: String) -> String {
    word + particle.form(after: word)
  }

  public func form(after word: String) -> String {
    let (withFinal, withoutFinal) = pair
    switch Self.finalConsonant(of: word) {
    case nil: return withFinal == "으로" ? "(으)로" : "\(withFinal)(\(withoutFinal))"
    case .vowel: return withoutFinal
    // ㄹ 받침 뒤에는 "으로"가 아니라 "로"("길로").
    case .rieul where self == .direction: return withoutFinal
    case .rieul, .consonant: return withFinal
    }
  }

  private var pair: (String, String) {
    switch self {
    case .objectMarker: ("을", "를")
    case .subjectMarker: ("이", "가")
    case .topicMarker: ("은", "는")
    case .direction: ("으로", "로")
    }
  }

  enum Final { case vowel, rieul, consonant }

  /// 마지막 글자의 받침. 닫는 따옴표·괄호·공백은 건너뛴다. 알 수 없으면 nil.
  static func finalConsonant(of word: String) -> Final? {
    let skipped: Set<Character> = ["’", "'", "\"", "”", "」", "』", ")", "]", " ", "…", "."]
    // 자모를 따로 적은 한글(NFD)도 한 글자로 보려고 합친다.
    guard let last = word.precomposedStringWithCanonicalMapping.last(where: { !skipped.contains($0) }),
          let scalar = last.unicodeScalars.first else { return nil }
    switch scalar.value {
    case 0xAC00...0xD7A3:
      // 한글 음절 = 0xAC00 + (초성×21 + 중성)×28 + 종성. 종성 0은 받침 없음, 8은 ㄹ.
      let jong = (scalar.value - 0xAC00) % 28
      return jong == 0 ? .vowel : jong == 8 ? .rieul : .consonant
    case 0x30...0x39:
      // 숫자는 읽는 소리로: 영 일 이 삼 사 오 육 칠 팔 구
      let finals: [Final] = [.consonant, .rieul, .vowel, .consonant, .vowel, .vowel, .consonant, .rieul, .rieul, .vowel]
      return finals[Int(scalar.value - 0x30)]
    default:
      return nil
    }
  }
}
