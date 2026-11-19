import Foundation
import Testing
@testable import NovelCore

/// 작품 폴더에 저장하지 못한 원고를 사용자가 고른 다른 폴더로 내보낸다. 이미 있는 파일은 덮어쓰지 않는다.
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
}
