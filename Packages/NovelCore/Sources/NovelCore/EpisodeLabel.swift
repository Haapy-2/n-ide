import Foundation

/// 문장 안에서 회차를 부르는 이름("3화 ‘첫 만남’"). 확인 창·판 제목이 함께 쓴다.
public enum EpisodeLabel {
  /// - Parameters:
  ///   - number: 작품 안 순번(1부터)
  ///   - quoted: 번호 뒤에 붙는 제목을 ‘ ’로 감쌀지
  public static func text(number: Int, title: String, quoted: Bool = false) -> String {
    let numberLabel = "\(number)화"
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == numberLabel { return numberLabel }
    // 제목이 이미 같은 번호로 시작하면("3화 첫 만남") 번호를 또 붙이지 않는다.
    if trimmed.hasPrefix(numberLabel) || trimmed.hasPrefix("제\(numberLabel)") {
      return quoted ? "‘\(trimmed)’" : trimmed
    }
    return quoted ? "\(numberLabel) ‘\(trimmed)’" : "\(numberLabel) \(trimmed)"
  }
}
