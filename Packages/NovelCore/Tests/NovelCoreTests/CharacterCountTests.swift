import Foundation
import Testing
@testable import NovelCore

struct CharacterCountTests {
  @Test func emptyText() {
    #expect(CharacterCount(counting: "") == .zero)
  }

  @Test func newlinesAreNeverCounted() {
    let count = CharacterCount(counting: "가나\n\n다\r\n라")
    #expect(count == CharacterCount(withSpaces: 4, withoutSpaces: 4))
  }

  @Test func spacesAndTabsCountOnlyWithSpaces() {
    let count = CharacterCount(counting: "그는 검을\t들었다.")
    #expect(count == CharacterCount(withSpaces: 10, withoutSpaces: 8))
  }

  @Test func fullWidthSpaceIsASpace() {
    let count = CharacterCount(counting: "가\u{3000}나")
    #expect(count == CharacterCount(withSpaces: 3, withoutSpaces: 2))
  }

  /// One visible character counts as one: decomposed Hangul (NFD), emoji, combining characters.
  @Test func countsVisibleCharacters() {
    let decomposed = "한글".decomposedStringWithCanonicalMapping
    #expect(decomposed.unicodeScalars.count == 6)
    #expect(CharacterCount(counting: decomposed).withSpaces == 2)
    #expect(CharacterCount(counting: "👨‍👩‍👧 é").withSpaces == 3)
  }

  @Test func dialogueParagraph() {
    let text = "\"여기서 뭐 해요?\"\n\n그녀가 물었다."
    #expect(CharacterCount(counting: text) == CharacterCount(withSpaces: 19, withoutSpaces: 16))
  }

  @Test func valueForBasis() {
    let count = CharacterCount(withSpaces: 120, withoutSpaces: 98)
    #expect(count.value(for: .withSpaces) == 120)
    #expect(count.value(for: .withoutSpaces) == 98)
  }

  /// Old project.json without counts still opens, and counted values survive a save and reload.
  @Test func storedWithEpisodeAndOptional() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "작품")
    var project = try store.loadProject()
    project.episodes = [
      EpisodeMeta(title: "센 회차", goal: 5_000, characterCount: CharacterCount(withSpaces: 10, withoutSpaces: 8)),
      EpisodeMeta(title: "안 센 회차", goal: 5_000),
    ]
    try store.saveProject(project)

    let loaded = try store.loadProject()
    #expect(loaded.episodes[0].characterCount == CharacterCount(withSpaces: 10, withoutSpaces: 8))
    #expect(loaded.episodes[1].characterCount == nil)
    let json = try String(contentsOf: store.layout.projectFile, encoding: .utf8)
    #expect(!json.contains("\"characterCount\" : null"))
  }
}
