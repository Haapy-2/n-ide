import Foundation

/// Name used to refer to an episode in a sentence ("3화 ‘첫 만남’"). Shared by confirmations and panel titles.
public enum EpisodeLabel {
  /// - Parameters:
  ///   - number: position in the project (from 1)
  ///   - quoted: whether to wrap the title after the number in ‘ ’
  public static func text(number: Int, title: String, quoted: Bool = false) -> String {
    let numberLabel = "\(number)화"
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == numberLabel { return numberLabel }
    // If the title already starts with the same number ("3화 첫 만남"), don't add the number again.
    if trimmed.hasPrefix(numberLabel) || trimmed.hasPrefix("제\(numberLabel)") {
      return quoted ? "‘\(trimmed)’" : trimmed
    }
    return quoted ? "\(numberLabel) ‘\(trimmed)’" : "\(numberLabel) \(trimmed)"
  }
}
