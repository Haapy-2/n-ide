import Foundation

/// 여러 회차 이름을 한 번에 바꾸는 규칙(PLAN 15장). Finder의 여러 파일 이름 바꾸기와 같은 세 방식.
/// 창의 미리 보기와 적용이 이 함수 하나를 써서, 미리 본 이름과 실제로 바뀌는 이름이 어긋나지 않는다.
public enum EpisodeTitleBatch {
  public enum Rule: Equatable, Sendable {
    /// 찾는 곳은 작품 전체 검색과 같다(영문 대소문자 무시, 자모를 따로 적은 한글도). 찾을 말이 비면 그대로.
    case replace(find: String, with: String)
    case affix(prefix: String, suffix: String)
    /// 주어진 순서대로 `start`부터 번호를 붙인다. 이름이 비면 번호만.
    case numbered(name: String, start: Int, numberFirst: Bool)
  }

  /// 같은 순서의 새 제목. 앞뒤 공백은 자른다(한 회차 이름 변경과 같음).
  public static func titles(_ titles: [String], by rule: Rule) -> [String] {
    titles.enumerated().map { index, title in
      let raw: String
      switch rule {
      case .replace(let find, let replacement):
        raw = find.isEmpty
          ? title : TextReplace.replacing(find, with: replacement, in: title, caseSensitive: false)?.text ?? title
      case .affix(let prefix, let suffix):
        raw = prefix + title + suffix
      case .numbered(let name, let start, let numberFirst):
        let number = String(start + index)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = name.isEmpty ? number : numberFirst ? "\(number) \(name)" : "\(name) \(number)"
      }
      return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }
}
