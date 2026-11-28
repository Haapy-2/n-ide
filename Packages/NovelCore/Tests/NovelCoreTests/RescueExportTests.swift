import Foundation
import Testing
@testable import NovelCore

/// Export manuscripts that couldn't be saved to the project folder into a folder the user picks. Existing files aren't overwritten.
struct RescueExportTests {
  @Test func writesOneFilePerEpisodeWithoutOverwriting() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    try Data("원래 있던 파일".utf8).write(to: folder.url.appending(path: "1화.md"))

    let written = try RescueExport.write(
      [(title: "1화", text: "살릴 원고"), (title: "a/b:c", text: "둘"), (title: "  ", text: "셋")], to: folder.url)

    #expect(written.map(\.lastPathComponent) == ["1화 (2).md", "a-b-c.md", "제목 없음.md"])
    #expect(try String(contentsOf: folder.url.appending(path: "1화.md"), encoding: .utf8) == "원래 있던 파일")
    #expect(try String(contentsOf: written[0], encoding: .utf8) == "살릴 원고")
  }

  /// Long Hangul titles export too. When the temp file name (`.name.UUID.tmp`) pushed it past 255 bytes, the write failed entirely.
  @Test func longTitleIsShortenedToFitFileNameLimit() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let long = String(repeating: "가나다라마바사아자차", count: 20)

    let written = try RescueExport.write([(title: long, text: "하나"), (title: long, text: "둘")], to: folder.url)

    #expect(written.count == 2)
    #expect(written[0].lastPathComponent.hasPrefix("가나다라마바사아자차"))
    #expect(written[1].lastPathComponent.hasSuffix(" (2).md"))
    #expect(try String(contentsOf: written[1], encoding: .utf8) == "둘")
  }

  /// Shortening never cuts mid-character (including multi-byte, multi-code-point characters like emoji).
  @Test func shorteningKeepsWholeCharacters() {
    let name = RescueExport.fileName(for: String(repeating: "👨‍👩‍👧", count: 100))

    #expect(!name.isEmpty)
    #expect(Set(name) == ["👨‍👩‍👧"])
    #expect(name.utf8.count <= 200)
  }

  /// Names starting with a dot become hidden files in Finder.
  @Test func leadingDotsAreDropped() throws {
    let folder = try TestFolder()
    defer { folder.remove() }

    let written = try RescueExport.write([(title: ".숨은 제목", text: "하나"), (title: "...", text: "둘")], to: folder.url)

    #expect(written.map(\.lastPathComponent) == ["숨은 제목.md", "제목 없음.md"])
  }
}
