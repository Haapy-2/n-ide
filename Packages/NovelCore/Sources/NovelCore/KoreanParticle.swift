import Foundation

/// Choose a particle by the preceding word's final consonant ("검을", "도윤으로"). Words whose ending can't be known (Latin etc.) get both, like "을(를)".
public enum KoreanParticle {
  case objectMarker
  case subjectMarker
  case topicMarker
  case direction

  /// `word` followed by the particle.
  public static func attach(_ particle: KoreanParticle, to word: String) -> String {
    word + particle.form(after: word)
  }

  public func form(after word: String) -> String {
    let (withFinal, withoutFinal) = pair
    switch Self.finalConsonant(of: word) {
    case nil: return withFinal == "으로" ? "(으)로" : "\(withFinal)(\(withoutFinal))"
    case .vowel: return withoutFinal
    // After a ㄹ final consonant it's "로", not "으로" ("길로").
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

  /// Final consonant of the last character. Skips closing quotes, brackets and spaces. nil if unknown.
  static func finalConsonant(of word: String) -> Final? {
    let skipped: Set<Character> = ["’", "'", "\"", "”", "」", "』", ")", "]", " ", "…", "."]
    // Composed so decomposed Hangul (NFD) is treated as one character.
    guard let last = word.precomposedStringWithCanonicalMapping.last(where: { !skipped.contains($0) }),
          let scalar = last.unicodeScalars.first else { return nil }
    switch scalar.value {
    case 0xAC00...0xD7A3:
      // Hangul syllable = 0xAC00 + (initial×21 + medial)×28 + final. Final 0 = none, 8 = ㄹ.
      let jong = (scalar.value - 0xAC00) % 28
      return jong == 0 ? .vowel : jong == 8 ? .rieul : .consonant
    case 0x30...0x39:
      // Digits by their spoken sound: 영 일 이 삼 사 오 육 칠 팔 구
      let finals: [Final] = [.consonant, .rieul, .vowel, .consonant, .vowel, .vowel, .consonant, .rieul, .rieul, .vowel]
      return finals[Int(scalar.value - 0x30)]
    default:
      return nil
    }
  }
}
