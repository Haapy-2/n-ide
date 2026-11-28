import Foundation

/// 원고 속 그림 줄 `![](../images/<ID>.png)` (PLAN 19장 1번, 결정 37·52).
/// 그림 줄인지 판단하는 곳은 여기 하나다. 글자 수·검색·바꾸기·⌘D·내보내기·그림 번호가 모두 이것을 써서
/// 서로 다른 줄을 그림으로 보는 일이 없게 한다.
///
/// 그림 줄: 한 줄을 혼자 차지하고(앞뒤 공백·탭만 허용) alt가 비어 있고 경로에 공백이 없다.
/// alt가 있는 줄, `"title"`이 붙은 줄, `<img>`, 문단 중간 그림은 글로 둔다. 모르는 모양을 글로 두면
/// 숨겨지는 글자가 없어 원고가 사라져 보이는 일이 없다.
public struct ImageLine: Equatable, Sendable {
  public enum Source: Equatable, Sendable {
    /// 작품의 `images/` 폴더 안 파일. 파일 이름만 든다(`../images/`·`images/` 둘 다 여기로).
    case project(fileName: String)
    /// 작품 밖을 가리키는 경로(`/Users/…`, `../../`, `https://` 등). 받지 않고 상자로 알린다(G4).
    case outside(path: String)
  }

  public let source: Source

  static let prefix = "![]("
  private static let folderPrefixes = ["../images/", "images/"]

  /// 한 줄(줄바꿈 없이)을 읽는다. 그림 줄이 아니면 nil.
  public static func parse<Line: StringProtocol>(_ line: Line) -> ImageLine? {
    let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(")") else { return nil }
    let raw = trimmed.dropFirst(prefix.count).dropLast()
    guard !raw.isEmpty, !raw.contains(where: { $0.isWhitespace || $0 == "(" || $0 == ")" || $0 == "\"" }) else {
      return nil
    }
    guard let path = String(raw).removingPercentEncoding else { return nil }
    return ImageLine(source: source(of: path))
  }

  private static func source(of path: String) -> Source {
    for folder in folderPrefixes where path.hasPrefix(folder) {
      let name = String(path.dropFirst(folder.count))
      if !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") {
        return .project(fileName: name)
      }
    }
    return .outside(path: path)
  }

  /// 앱이 넣는 그림 줄. 파일 이름은 앱이 만든 `<UUID>.<확장자>`라 인코딩할 글자가 없다.
  public static func markdown(fileName: String) -> String {
    "\(prefix)../images/\(fileName))"
  }

  /// 본문의 한 문단(줄바꿈 제외 범위)이 그림 줄인지. 검색처럼 문단마다 부르는 곳에서 쓴다:
  /// 첫 글자가 `!`가 아니면 문자열을 만들지 않고 바로 아니라고 답한다.
  public static func isImageLine(_ text: NSString, paragraph: NSRange) -> Bool {
    var index = paragraph.location
    let end = NSMaxRange(paragraph)
    while index < end {
      let unit = text.character(at: index)
      if unit == 0x20 || unit == 0x09 { index += 1; continue }
      guard unit == 0x21 else { return false }
      return parse(text.substring(with: paragraph)) != nil
    }
    return false
  }

  /// 본문 위에서 아래 순서의 그림 줄과 그 문단 범위(UTF-16, 줄바꿈 제외).
  /// 몇 번째인지(`그림 N`의 N)는 이 배열의 순서 + 1이다. 번호는 저장하지 않고 늘 여기서 센다(결정 36·52).
  public static func occurrences(in text: String) -> [(range: NSRange, line: ImageLine)] {
    let source = text as NSString
    var found: [(range: NSRange, line: ImageLine)] = []
    var start = 0
    while start < source.length {
      var end = 0
      var contentsEnd = 0
      source.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
      let paragraph = NSRange(location: start, length: contentsEnd - start)
      if isImageLine(source, paragraph: paragraph), let line = parse(source.substring(with: paragraph)) {
        found.append((paragraph, line))
      }
      guard end > start else { break }
      start = end
    }
    return found
  }

  /// 본문에 그림 줄이 있을 수도 있는지 빠르게 본다. 없으면 글자 수 세기가 줄을 나누지 않는다.
  static func mayContainImageLine(_ text: String) -> Bool {
    var first: UInt8 = 0
    var second: UInt8 = 0
    var third: UInt8 = 0
    for byte in text.utf8 {
      if byte == 0x28, first == 0x21, second == 0x5B, third == 0x5D { return true }
      (first, second, third) = (second, third, byte)
    }
    return false
  }
}
