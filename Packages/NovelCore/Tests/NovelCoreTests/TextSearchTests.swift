import Foundation
import Testing
@testable import NovelCore

struct TextSearchTests {
  private func lines(_ matches: [SearchMatch]) -> [Int] { matches.map(\.line) }

  @Test func findsEveryPlaceWithLineNumbers() {
    let text = "그는 검을 들었다.\n\n검이 울었다. 검은 빛났다."
    let found = TextSearch.matches(of: "검", in: text, caseSensitive: false)

    #expect(lines(found) == [1, 3, 3])
    #expect(found.map(\.location) == [3, 12, 20])
    #expect(found.allSatisfy { $0.length == 1 })
  }

  @Test func ignoresEnglishCaseUnlessAsked() {
    let text = "Sword sword SWORD"

    #expect(TextSearch.matches(of: "sword", in: text, caseSensitive: false).count == 3)
    #expect(TextSearch.matches(of: "sword", in: text, caseSensitive: true).map(\.location) == [6])
  }

  /// 자모를 따로 적은 한글(NFD, 다른 편집기·맥 파일 이름에서 섞여 들어옴)도 같은 글자로 찾는다.
  @Test func findsDecomposedHangul() {
    let decomposed = "한서윤".decomposedStringWithCanonicalMapping
    let text = "이름: \(decomposed)"

    let found = TextSearch.matches(of: "서윤", in: text, caseSensitive: false)

    #expect(found.count == 1)
    let range = NSRange(location: found[0].location, length: found[0].length)
    #expect((text as NSString).substring(with: range).precomposedStringWithCanonicalMapping == "서윤")
  }

  /// 줄 번호는 편집기와 같다: `\r\n`도 줄바꿈 하나다.
  @Test func crlfCountsAsOneLineBreak() {
    let text = "첫 줄\r\n둘째 줄\r\n셋째 검"

    #expect(lines(TextSearch.matches(of: "검", in: text, caseSensitive: false)) == [3])
    #expect(ParagraphLines.lineCount(in: text as NSString) == 3)
  }

  @Test func doesNotCrossLines() {
    let text = "끝에 검\n은 빛났다"

    #expect(TextSearch.matches(of: "검은", in: text, caseSensitive: false).isEmpty)
    #expect(TextSearch.matches(of: "검\n은", in: text, caseSensitive: false).isEmpty)
    #expect(TextSearch.matches(of: "", in: text, caseSensitive: false).isEmpty)
  }

  @Test func longLinePreviewKeepsTheMatchAndMarksCuts() {
    let text = String(repeating: "가", count: 100) + "목표" + String(repeating: "나", count: 100)

    let match = TextSearch.matches(of: "목표", in: text, caseSensitive: false)[0]

    #expect(match.preview.hasPrefix("…"))
    #expect(match.preview.hasSuffix("…"))
    let preview = match.preview as NSString
    #expect(preview.substring(with: NSRange(location: match.previewMatch.lowerBound, length: 2)) == "목표")
    #expect(preview.length < 90)
  }

  @Test func shortLinePreviewIsTheWholeLine() {
    let match = TextSearch.matches(of: "검", in: "앞 줄\n그는 검을 들었다.\n뒷 줄", caseSensitive: false)[0]

    #expect(match.preview == "그는 검을 들었다.")
    #expect(match.previewMatch == 3..<4)
  }

  @Test func stopsAtLimit() {
    #expect(TextSearch.matches(of: "가", in: String(repeating: "가", count: 50), caseSensitive: false, limit: 7).count == 7)
  }

  // MARK: - 여러 회차

  @Test func searchesEpisodesInOrderAndPrefersGivenText() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let first = EpisodeID.make(), second = EpisodeID.make(), third = EpisodeID.make()
    try store.writeEpisode("검 하나", id: first)
    try store.writeEpisode("디스크에는 없음", id: second)
    try store.writeEpisode("검 셋 검", id: third)

    // 둘째 회차는 편집기에서 방금 고쳐 아직 저장 전인 글을 찾는다.
    let result = try store.search("검", in: [first, second, third], texts: [second: "막 쓴 검"], caseSensitive: false)

    #expect(result.episodes.map(\.id) == [first, second, third])
    #expect(result.matchCount == 4)
    #expect(!result.isTruncated)
  }

  @Test func reportsUnreadableEpisodesAndKeepsGoing() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let missing = EpisodeID.make(), present = EpisodeID.make()
    try store.writeEpisode("검", id: present)

    let result = try store.search("검", in: [missing, present], caseSensitive: false)

    #expect(result.unreadable == [missing])
    #expect(result.episodes.map(\.id) == [present])
  }

  @Test func truncatesAtLimitAcrossEpisodes() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let ids = (0..<3).map { _ in EpisodeID.make() }
    for id in ids { try store.writeEpisode("검 검 검", id: id) }

    let exact = try store.search("검", in: ids, caseSensitive: false, limit: 9)
    let cut = try store.search("검", in: ids, caseSensitive: false, limit: 4)

    #expect(exact.matchCount == 9 && !exact.isTruncated)
    #expect(cut.matchCount == 4 && cut.isTruncated)
    #expect(cut.episodes.map(\.matches.count) == [3, 1])
  }
}
