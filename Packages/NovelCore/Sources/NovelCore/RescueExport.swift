import Foundation

/// Export manuscripts that ultimately couldn't be saved to the project folder as one `.md` per episode into a folder the user picks.
/// Closing the window or quitting would lose memory-only manuscripts, so this offers a way to save them first.
public enum RescueExport {
  /// Existing files aren't overwritten; a number like ` (2)` is added. Returns written file locations in order.
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

  /// Replace `/` and `:` (not allowed in file names), drop a leading dot (would make a hidden file), and use "제목 없음" for empty titles.
  /// Long names are cut at a character boundary so that with the temp name (`.name.UUID.tmp`, 42 more bytes) and ` (number).md`
  /// it stays within the name limit (255). Some file systems count Hangul decomposed into jamo (가 → ㄱㅏ, 6 bytes), so measure the decomposed bytes.
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
