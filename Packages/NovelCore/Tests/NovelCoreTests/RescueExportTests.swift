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

  /// 긴 한글 제목도 내보낸다. 임시 파일 이름(`.이름.UUID.tmp`)까지 255바이트를 넘으면 쓰기가 통째로 실패했다.
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

  /// 줄일 때 글자 가운데서 자르지 않는다(이모지처럼 여러 바이트·여러 코드 포인트인 글자도).
  @Test func shorteningKeepsWholeCharacters() {
    let name = RescueExport.fileName(for: String(repeating: "👨‍👩‍👧", count: 100))

    #expect(!name.isEmpty)
    #expect(Set(name) == ["👨‍👩‍👧"])
    #expect(name.utf8.count <= 200)
  }

  /// 점으로 시작하는 이름은 Finder에서 숨김 파일이 된다.
  @Test func leadingDotsAreDropped() throws {
    let folder = try TestFolder()
    defer { folder.remove() }

    let written = try RescueExport.write([(title: ".숨은 제목", text: "하나"), (title: "...", text: "둘")], to: folder.url)

    #expect(written.map(\.lastPathComponent) == ["숨은 제목.md", "제목 없음.md"])
  }
}
