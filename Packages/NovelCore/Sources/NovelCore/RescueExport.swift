import Foundation

/// 작품 폴더에 끝내 저장하지 못한 원고를 사용자가 고른 다른 폴더에 회차마다 `.md`로 내보낸다.
/// 창을 닫거나 앱을 끄면 메모리에만 있던 원고가 사라지므로, 그 전에 살릴 길을 준다.
public enum RescueExport {
  /// 이미 있는 파일은 덮어쓰지 않고 ` (2)`처럼 번호를 붙인다. 쓴 파일 위치를 순서대로 돌려준다.
  public static func write(_ manuscripts: [(title: String, text: String)], to folder: URL) throws -> [URL] {
    var written: [URL] = []
    for manuscript in manuscripts {
      let base = fileName(for: manuscript.title)
      var number = 1
      while true {
        let name = number == 1 ? "\(base).md" : "\(base) (\(number)).md"
        let url = folder.appending(path: name)
        do {
          try AtomicFile.write(Data(manuscript.text.utf8), to: url, replacing: false)
          written.append(url)
          break
        } catch is AtomicFile.AlreadyExists {
          number += 1
        }
      }
    }
    return written
  }

  /// 파일 이름에 쓸 수 없는 `/`와 `:`를 바꾸고, 앞의 점(숨김 파일이 된다)을 떼고, 빈 제목은 "제목 없음"으로.
  /// 길면 글자 경계에서 자른다. 임시 파일 이름(`.이름.UUID.tmp`, 42바이트 더)과 ` (번호).md`를 붙여도
  /// 이름 한도(255)를 넘지 않게 한다. 파일 시스템에 따라 한글을 자모로 풀어(가 → ㄱㅏ, 6바이트) 세므로 푼 꼴의 바이트로 잰다.
  static func fileName(for title: String) -> String {
    let cleaned = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    var name = ""
    var bytes = 0
    for character in cleaned.drop(while: { $0 == "." }) {
      bytes += String(character).decomposedStringWithCanonicalMapping.utf8.count
      guard bytes <= nameLimit else { break }
      name.append(character)
    }
    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? "제목 없음" : name
  }

  static let nameLimit = 200
}
