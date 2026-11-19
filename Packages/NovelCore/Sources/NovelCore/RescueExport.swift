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

  /// 파일 이름에 쓸 수 없는 `/`와 `:`를 바꾸고, 빈 제목은 "제목 없음"으로.
  static func fileName(for title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "제목 없음" }
    return trimmed.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
  }
}
