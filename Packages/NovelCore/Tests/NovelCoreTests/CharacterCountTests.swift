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

  /// 화면에 보이는 한 글자는 한 글자: 자모를 풀어 쓴 한글(NFD), 이모지, 결합 문자.
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

  /// 글자 수가 없는 옛 project.json도 그대로 열리고, 센 값은 저장했다 다시 읽힌다.
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
