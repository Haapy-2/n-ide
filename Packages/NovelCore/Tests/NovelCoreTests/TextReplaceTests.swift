import Foundation
import Testing
@testable import NovelCore

struct TextReplaceTests {
  @Test func replacesEveryPlaceIncludingManyOnOneLine() {
    let result = TextReplace.replacing("민준", with: "도윤", in: "민준은 민준이다.\n\n민준!", caseSensitive: false)

    #expect(result?.text == "도윤은 도윤이다.\n\n도윤!")
    #expect(result?.count == 3)
  }

  /// 찾은 자리를 차례로 바꾸면 `replacing`과 같은 본문이 된다(편집기가 찾은 자리만 바꿀 때와 파일에 쓸 때가 같게).
  @Test func rangesMatchWhatReplacingChanges() {
    let text = "Sword 민준 " + "민준".decomposedStringWithCanonicalMapping + "\n민준👍"
    let ranges = TextReplace.ranges(of: "민준", in: text, caseSensitive: false)
    let edited = NSMutableString(string: text)
    for range in ranges.reversed() { edited.replaceCharacters(in: range, with: "도윤") }

    #expect(ranges.count == 3)
    #expect(edited as String == TextReplace.replacing("민준", with: "도윤", in: text, caseSensitive: false)?.text)
    #expect(TextReplace.ranges(of: "없음", in: text, caseSensitive: false).isEmpty)
  }

  @Test func emptyReplacementDeletes() {
    #expect(TextReplace.replacing("아주 ", with: "", in: "아주 아주 큰", caseSensitive: false)?.text == "큰")
  }

  @Test func noMatchGivesNil() {
    #expect(TextReplace.replacing("없음", with: "x", in: "본문", caseSensitive: false) == nil)
  }

  @Test func followsSearchCaseRule() {
    let text = "Sword sword SWORD"

    #expect(TextReplace.replacing("sword", with: "검", in: text, caseSensitive: false)?.text == "검 검 검")
    #expect(TextReplace.replacing("sword", with: "검", in: text, caseSensitive: true)?.text == "Sword 검 SWORD")
  }

  /// 자모를 따로 적은 한글(NFD)도 찾은 곳 통째로 바꾼다. 자모 일부가 남지 않는다.
  @Test func replacesDecomposedHangulWhole() {
    let text = "이름: " + "서윤".decomposedStringWithCanonicalMapping + "이"

    #expect(TextReplace.replacing("서윤", with: "도윤", in: text, caseSensitive: false)?.text == "이름: 도윤이")
  }

  @Test func keepsEmojiAroundIntact() {
    let text = "👩‍👩‍👧검👍검"

    #expect(TextReplace.replacing("검", with: "칼", in: text, caseSensitive: false)?.text == "👩‍👩‍👧칼👍칼")
  }

  @Test func doesNotCrossLinesAndKeepsCRLF() {
    let text = "끝에 검\r\n은 검은"

    #expect(TextReplace.replacing("검은", with: "x", in: text, caseSensitive: false)?.text == "끝에 검\r\n은 x")
  }

  /// 바꿀 말에 찾는 말이 들어 있어도 한 번만 바꾼다(바꾼 글을 다시 찾지 않는다).
  @Test func replacementContainingQueryIsNotReplacedAgain() {
    #expect(TextReplace.replacing("검", with: "검검", in: "검 검", caseSensitive: false)?.text == "검검 검검")
  }

  /// 같은 본문에서 찾기와 바꾸기가 같은 곳을 고른다.
  @Test func countMatchesSearch() {
    let text = "검은 검을 Sword\n검" + "검".decomposedStringWithCanonicalMapping
    for caseSensitive in [true, false] {
      let searched = TextSearch.matches(of: "검", in: text, caseSensitive: caseSensitive).count
      #expect(TextReplace.count(of: "검", in: text, caseSensitive: caseSensitive) == searched)
      #expect(TextReplace.replacing("검", with: "칼", in: text, caseSensitive: caseSensitive)?.count == searched)
    }
  }

  @Test func canReplaceRules() {
    #expect(TextReplace.canReplace("민준", with: "도윤"))
    #expect(TextReplace.canReplace("민준", with: ""))
    #expect(TextReplace.canReplace("Sword", with: "sword"))
    #expect(!TextReplace.canReplace("민준", with: "민준"))
    #expect(!TextReplace.canReplace("", with: "x"))
    #expect(!TextReplace.canReplace("민준", with: "도\n윤"))
  }

  @Test func planCountsEverythingWithoutLimit() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let many = EpisodeID.make(), none = EpisodeID.make(), open = EpisodeID.make(), missing = EpisodeID.make()
    try store.writeEpisode(String(repeating: "검 ", count: 1_500), id: many)
    try store.writeEpisode("없음", id: none)
    try store.writeEpisode("디스크의 검", id: open)

    let plan = try store.replacementPlan(
      "검", in: [many, none, open, missing], texts: [open: "편집기의 검 검"], caseSensitive: false)

    #expect(plan.episodes.map(\.id) == [many, open])
    #expect(plan.episodes.map(\.count) == [1_500, 2])
    #expect(plan.count == 1_502)
    #expect(plan.unreadable == [missing])
  }

  @Test func planStopsWhenCancelled() async throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let id = EpisodeID.make()
    try store.writeEpisode("검", id: id)

    let task = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      return try store.replacementPlan("검", in: [id], caseSensitive: false)
    }

    await #expect(throws: CancellationError.self) { try await task.value }
  }

  /// 장치 캐시를 비우지 않는 빠른 쓰기도 스냅샷·메모를 똑같이 남긴다(전체 바꾸기가 쓴다).
  @Test func snapshotWithoutFullSyncWritesTextAndMemo() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let id = EpisodeID.make()

    let snapshot = try #require(
      try store.writeSnapshot("바꾸기 전 글", episode: id, kind: .replace, memo: "메모", fullSync: false))

    #expect(try store.readSnapshot(snapshot) == "바꾸기 전 글")
    #expect(store.readMemo(snapshot) == "메모")
  }

  @Test func replaceSnapshotsAreNeverPruned() {
    #expect(!SnapshotKind.replace.isPrunable)
    #expect(!SnapshotKind.replaced.isPrunable)
    #expect(SnapshotKind(rawValue: "replace") == .replace)
    #expect(SnapshotKind(rawValue: "replaced") == .replaced)
  }
}
