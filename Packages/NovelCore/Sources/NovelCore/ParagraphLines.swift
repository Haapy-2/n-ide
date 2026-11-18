import Foundation

/// "줄"을 나누는 규칙 하나. 편집기 줄 번호와 비교 화면 줄 번호가 같은 줄을 가리키게 하려고 한곳에 둔다(11f).
///
/// 줄 = 문단. 엔터가 넣는 `\n`과, 다른 편집기에서 온 `\r\n`·`\r`, 유니코드 문단 구분(U+2029)에서 나눈다.
/// NSTextView(NSString 문단)와 같은 규칙이다. U+2028(줄 구분)은 화면에서만 줄을 넘기고 문단은 나누지 않고,
/// U+0085(NEL)는 NSString이 문단으로 보지 않아서 여기서도 나누지 않는다(테스트로 확인).
///
/// Swift `String`은 `\r\n`을 글자 하나로 묶어서 `split(separator: "\n")`로는 나뉘지 않는다.
/// 그래서 UTF-16 단위로 직접 센다.
public enum ParagraphLines {
  static let lineFeed: UInt16 = 0x0A
  static let carriageReturn: UInt16 = 0x0D
  static let paragraphSeparator: UInt16 = 0x2029

  /// 이 UTF-16 단위가 줄을 끝내는가. `\r\n`은 `\r` 쪽을 끝으로 보지 않고 `\n` 쪽에서 한 번만 센다.
  @inline(__always)
  static func endsLine(_ unit: UInt16, next: UInt16?) -> Bool {
    switch unit {
    case lineFeed, paragraphSeparator: true
    case carriageReturn: next != lineFeed
    default: false
    }
  }

  /// 줄로 나눈다. 줄 끝 문자는 빼고, 끝에 줄바꿈이 있으면 마지막에 빈 줄이 하나 붙는다.
  /// 빈 글은 줄이 없다(빈 글 → 새 글이면 모두 "넣은 줄").
  public static func split(_ text: String) -> [String] {
    if text.isEmpty { return [] }
    let units = Array(text.utf16)
    var lines: [String] = []
    var start = 0
    var index = 0
    while index < units.count {
      let unit = units[index]
      let next = index + 1 < units.count ? units[index + 1] : nil
      if unit == carriageReturn && next == lineFeed {
        lines.append(Self.string(units[start..<index]))
        index += 2
        start = index
        continue
      }
      if endsLine(unit, next: next) {
        lines.append(Self.string(units[start..<index]))
        start = index + 1
      }
      index += 1
    }
    lines.append(Self.string(units[start..<units.count]))
    return lines
  }

  /// `offset`(UTF-16 위치) 앞에 끝난 줄 수. 그 위치가 들어 있는 줄의 번호는 이 값 + 1.
  /// 편집기가 화면에 보이는 첫 문단의 번호를 구할 때 쓴다. 본문을 복사하지 않고 조각씩 읽는다.
  public static func lineBreaks(in text: NSString, before offset: Int) -> Int {
    let end = min(max(offset, 0), text.length)
    var count = 0
    var buffer = [UInt16](repeating: 0, count: 4096)
    var location = 0
    while location < end {
      let length = min(buffer.count, end - location)
      buffer.withUnsafeMutableBufferPointer { pointer in
        text.getCharacters(pointer.baseAddress!, range: NSRange(location: location, length: length))
      }
      for index in 0..<length {
        let unit = buffer[index]
        guard unit == lineFeed || unit == carriageReturn || unit == paragraphSeparator else { continue }
        if unit == carriageReturn {
          // 다음 단위가 \n이면 그쪽에서 센다. 다음 단위가 조각 밖이면 본문에서 직접 본다.
          let nextLocation = location + index + 1
          let next: UInt16? = index + 1 < length
            ? buffer[index + 1]
            : (nextLocation < text.length ? text.character(at: nextLocation) : nil)
          if next == lineFeed { continue }
        }
        count += 1
      }
      location += length
    }
    return count
  }

  /// 전체 줄 수. 빈 글도 편집기에서는 1번 줄이 보이므로 1. 끝이 줄바꿈이면 그 뒤 빈 줄까지 센다.
  public static func lineCount(in text: NSString) -> Int {
    lineBreaks(in: text, before: text.length) + 1
  }

  private static func string(_ units: ArraySlice<UInt16>) -> String {
    String(decoding: units, as: UTF16.self)
  }
}
