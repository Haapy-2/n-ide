import Foundation
import NovelCore
import XCTest
@testable import NovelEditor

@MainActor
final class SnapshotPanelTests: XCTestCase {
  private var folder: URL!
  private var store: ProjectStore!
  private let episode = EpisodeID.make()

  override func setUp() async throws {
    let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    folder = repo.appending(path: "build/tmp/\(UUID().uuidString)")
    store = try ProjectStore.create(at: folder.appending(path: "작품.novel"), title: "x")
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: folder)
  }

  // MARK: - 접기

  private func lines(_ count: Int, changeAt changed: Set<Int>) -> (String, String) {
    let old = (0..<count).map { "줄 \($0)" }
    let new = old.enumerated().map { changed.contains($0.offset) ? "고친 줄 \($0.offset)" : $0.element }
    return (old.joined(separator: "\n"), new.joined(separator: "\n"))
  }

  private func shape(_ items: [DiffDisplay.Item]) -> [String] {
    items.map {
      switch $0 {
      case .row(let index, let row): row.isSame ? "=\(index)" : "*\(index)"
      case .folded(let range): "fold\(range.lowerBound)..<\(range.upperBound)"
      }
    }
  }

  func testFoldsLongSameRunsKeepingThreeLinesAroundChanges() throws {
    let (old, new) = lines(30, changeAt: [10, 20])
    let diff = try TextDiff(old: old, new: new)
    let items = DiffDisplay.items(diff.rows)
    // 앞 묶음(0~9)은 뒤 3줄만, 가운데(11~19)는 앞뒤 3줄, 끝(21~29)은 앞 3줄만.
    XCTAssertEqual(shape(items), [
      "fold0..<7", "=7", "=8", "=9", "*10",
      "=11", "=12", "=13", "fold14..<17", "=17", "=18", "=19", "*20",
      "=21", "=22", "=23", "fold24..<30",
    ])
  }

  func testDoesNotFoldSingleHiddenLine() throws {
    // 가운데 같은 줄 7개 = 앞 3 + 숨길 1 + 뒤 3 → 접지 않는다.
    let (old, new) = lines(9, changeAt: [0, 8])
    let items = DiffDisplay.items(try TextDiff(old: old, new: new).rows)
    XCTAssertFalse(items.contains { if case .folded = $0 { true } else { false } })
  }

  func testShortSameRunsBetweenChangesStayOpen() throws {
    // 바뀐 줄 사이의 같은 줄이 1~5개면 앞뒤 3줄이 겹친다. 접지도 죽지도 않아야 한다.
    for gap in 0...6 {
      let (old, new) = lines(gap + 2, changeAt: [0, gap + 1])
      let items = DiffDisplay.items(try TextDiff(old: old, new: new).rows)
      XCTAssertEqual(items.count, gap + 2, "gap \(gap)")
    }
  }

  func testExpandedFoldShowsAllLines() throws {
    let (old, new) = lines(30, changeAt: [10, 20])
    let rows = try TextDiff(old: old, new: new).rows
    let items = DiffDisplay.items(rows, expanded: [14])
    XCTAssertFalse(shape(items).contains("fold14..<17"))
    XCTAssertTrue(shape(items).contains("=15"))
    XCTAssertTrue(shape(items).contains("fold0..<7"))
  }

  func testNoChangesShowsEverythingUnfolded() throws {
    let (old, _) = lines(40, changeAt: [])
    let items = DiffDisplay.items(try TextDiff(old: old, new: old).rows)
    XCTAssertEqual(items.count, 40)
  }

  func testItemIDsAreUnique() throws {
    let (old, new) = lines(60, changeAt: [5, 30, 50])
    let items = DiffDisplay.items(try TextDiff(old: old, new: new).rows)
    XCTAssertEqual(Set(items.map(\.id)).count, items.count)
  }

  // MARK: - 목록과 비교

  private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertTrue(condition())
  }

  func testLoadsNewestFirstAndComparesIt() async throws {
    let now = Date()
    try store.writeSnapshot("첫 글", episode: episode, kind: .auto, at: now.addingTimeInterval(-120))
    try store.writeSnapshot("둘째 글", episode: episode, kind: .manual, memo: "남길 것", at: now.addingTimeInterval(-60))
    let browser = SnapshotBrowser(store: store, episodeID: episode, currentText: "지금 글")
    await browser.load()
    XCTAssertEqual(browser.items?.map(\.snapshot.kind), [.manual, .auto])
    XCTAssertEqual(browser.items?.first?.memo, "남길 것")
    XCTAssertEqual(browser.selectedID, browser.items?.first?.id)
    try await waitUntil { if case .ready = browser.comparison { true } else { false } }
    guard case .ready(let diff) = browser.comparison else { return }
    XCTAssertEqual(diff.oldLines, ["둘째 글"])
    XCTAssertEqual(diff.newLines, ["지금 글"])
  }

  func testSelectingAnotherSnapshotReplacesComparison() async throws {
    let now = Date()
    try store.writeSnapshot("옛 글", episode: episode, kind: .auto, at: now.addingTimeInterval(-120))
    try store.writeSnapshot("새 글", episode: episode, kind: .auto, at: now.addingTimeInterval(-60))
    let browser = SnapshotBrowser(store: store, episodeID: episode, currentText: "지금")
    await browser.load()
    browser.select(browser.items![1].id)
    try await waitUntil {
      if case .ready(let diff) = browser.comparison { diff.oldLines == ["옛 글"] } else { false }
    }
  }

  /// 바꾼 회차 목록에서 열면 `바꾸기 전`을 골라 둔 채 연다(가장 최근인 `바꾼 뒤`가 아니라).
  func testOpensWithPreferredSnapshotSelected() async throws {
    let now = Date()
    let before = try XCTUnwrap(try store.writeSnapshot("민준", episode: episode, kind: .replace, at: now))
    try store.writeSnapshot("도윤", episode: episode, kind: .replaced, at: now)
    let browser = SnapshotBrowser(store: store, episodeID: episode, currentText: "도윤", preferredID: before.id)
    await browser.load()
    XCTAssertEqual(browser.items?.first?.snapshot.kind, .replaced)
    XCTAssertEqual(browser.selectedID, before.id)
    try await waitUntil {
      if case .ready(let diff) = browser.comparison { diff.oldLines == ["민준"] } else { false }
    }
  }

  func testMissingPreferredSnapshotFallsBackToNewest() async throws {
    try store.writeSnapshot("글", episode: episode, kind: .auto)
    let browser = SnapshotBrowser(store: store, episodeID: episode, currentText: "글", preferredID: "없는.md")
    await browser.load()
    XCTAssertEqual(browser.selectedID, browser.items?.first?.id)
  }

  func testEmptyEpisodeHasEmptyList() async {
    let browser = SnapshotBrowser(store: store, episodeID: episode, currentText: "")
    await browser.load()
    XCTAssertEqual(browser.items, [])
    XCTAssertEqual(browser.comparison, .idle)
  }

  func testUpdateMemoWritesTrimsAndRemoves() async throws {
    try store.writeSnapshot("글", episode: episode, kind: .auto)
    let browser = SnapshotBrowser(store: store, episodeID: episode, currentText: "글")
    await browser.load()
    let id = try XCTUnwrap(browser.items?.first?.id)
    browser.updateMemo(id, to: "  다시 볼 것 \n")
    try await waitUntil { browser.items?.first?.memo == "다시 볼 것" }
    XCTAssertEqual(store.readMemo(try store.snapshots(of: episode)[0]), "다시 볼 것")
    browser.updateMemo(id, to: "   ")
    try await waitUntil { browser.items?.first?.memo == nil }
    XCTAssertNil(store.readMemo(try store.snapshots(of: episode)[0]))
    // 본문 스냅샷은 그대로
    XCTAssertEqual(try store.snapshots(of: episode).count, 1)
  }

  /// 이름 변경 스냅샷은 본문이 같아도 제목이 다르면 되돌릴 수 있고, 되돌리면 바뀌기 전 제목으로.
  func testRenameSnapshotRestoresTitle() async throws {
    try store.writeSnapshot("글", episode: episode, kind: .rename, memo: "'1화' → '프롤로그'", title: "1화")
    let browser = SnapshotBrowser(store: store, episodeID: episode, currentText: "글", currentTitle: "프롤로그")
    await browser.load()
    try await waitUntil { if case .ready = browser.comparison { true } else { false } }
    XCTAssertEqual(browser.restoredTitle, "1화")
    XCTAssertTrue(browser.canRestore)

    var renamed: [String] = []
    let restored = await browser.restoreSelected(with: EpisodeAutosaver(store: store)) { renamed.append($0) }

    XCTAssertTrue(restored)
    XCTAssertEqual(renamed, ["1화"])
  }

  func testSameTitleAndTextHasNothingToRestore() async throws {
    try store.writeSnapshot("글", episode: episode, kind: .rename, title: "프롤로그")
    let browser = SnapshotBrowser(store: store, episodeID: episode, currentText: "글", currentTitle: "프롤로그")
    await browser.load()
    try await waitUntil { if case .ready = browser.comparison { true } else { false } }
    XCTAssertNil(browser.restoredTitle)
    XCTAssertFalse(browser.canRestore)
  }

  /// 이름 변경 스냅샷의 메모를 고치면 지킬지 묻고, 지키면 보관 개수로 지우지 않는다. 다른 종류는 묻지 않는다.
  func testEditingRenameMemoAsksToKeep() async throws {
    try store.writeSnapshot("글", episode: episode, kind: .auto, at: Date().addingTimeInterval(-60))
    try store.writeSnapshot("글", episode: episode, kind: .rename, memo: "자동 메모", title: "1화")
    let browser = SnapshotBrowser(store: store, episodeID: episode, currentText: "글")
    await browser.load()
    let rename = try XCTUnwrap(browser.items?.first { $0.snapshot.kind == .rename })
    let auto = try XCTUnwrap(browser.items?.first { $0.snapshot.kind == .auto })

    browser.updateMemo(auto.id, to: "자동에 단 메모")
    try await waitUntil { browser.items?.first { $0.id == auto.id }?.memo == "자동에 단 메모" }
    XCTAssertNil(browser.askingToKeep)

    browser.updateMemo(rename.id, to: "이 이름은 남기기")
    try await waitUntil { browser.askingToKeep == rename.id }
    browser.keep(rename.id)
    try await waitUntil { browser.items?.first { $0.id == rename.id }?.isKept == true }
    XCTAssertTrue(store.isKept(rename.snapshot))
    try store.pruneSnapshots(of: episode, keeping: 1)
    XCTAssertTrue(try store.snapshots(of: episode).contains(rename.snapshot), "지킨 것은 정리하지 않는다")
  }

  // MARK: - 이름

  func testDayTitles() {
    let calendar = Calendar(identifier: .gregorian)
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 9))!
    XCTAssertEqual(SnapshotListView.dayTitle(now.addingTimeInterval(-3600), calendar: calendar, now: now), "오늘")
    XCTAssertEqual(SnapshotListView.dayTitle(now.addingTimeInterval(-86_400), calendar: calendar, now: now), "어제")
    XCTAssertNotEqual(SnapshotListView.dayTitle(now.addingTimeInterval(-3 * 86_400), calendar: calendar, now: now), "어제")
  }

  func testEveryKindHasShortName() {
    for kind in SnapshotKind.allCases {
      XCTAssertFalse(SnapshotListView.kindName(kind).isEmpty)
    }
  }

  func testTimeShowsSeconds() throws {
    let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 14, minute: 23, second: 5)))
    XCTAssertEqual(SnapshotListView.time(date), "14:23:05")
  }
}
